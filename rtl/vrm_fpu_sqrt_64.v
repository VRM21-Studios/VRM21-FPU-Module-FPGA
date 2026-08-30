`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: vrm_fpu_sqrt_64
 *
 * DESCRIPTION:
 * Fully pipelined IEEE 754 double-precision (FP64) square-root unit.
 *
 * The implementation uses a restoring square-root algorithm with 56
 * iterative stages. Each stage performs one digit-pair iteration, allowing
 * the unit to accept one new operand every clock cycle.
 *
 * Architecture:
 *   - FP64 unpacking
 *   - Exponent preprocessing
 *   - 56-stage restoring square-root pipeline
 *   - Guard / round / sticky generation
 *   - IEEE 754 result packing
 *   - Special-case output handling
 *
 * Latency:
 *   57 clock cycles from valid_in to valid_out.
 *
 * Throughput:
 *   1 result per clock cycle after the pipeline is filled.
 *
 * Special cases:
 *   - NaN input        -> Quiet NaN
 *   - Negative input   -> Quiet NaN
 *   - +Infinity        -> +Infinity
 *   - Zero             -> Zero with preserved sign
 *
 * [FIXED V2]&#58;  *   All pipeline registers are driven from a single always block.
 *   Generate blocks are used only for combinational next-state logic.
 *
 * ============================================================================
 */

module vrm_fpu_sqrt_64 (
    input  wire        clk,
    input  wire        rstn,

    input  wire        valid_in,
    input  wire [63:0] op_a,

    output wire [63:0] result_out,
    output wire        valid_out
);

    // =========================================================================
    // 1. UNPACK & PREPROCESSING
    // =========================================================================
    /*
     * Extract the IEEE 754 fields from the input operand.
     *
     * The unpacker also identifies special values such as zero, infinity,
     * and NaN. These flags are propagated through the pipeline so that
     * special cases can bypass the normal square-root datapath.
     */

    wire sign_a;
    wire [10:0] exp_a;
    wire [52:0] mant_a;
    wire is_zero_a, is_nan_a, is_inf_a;

    vrm_fpu_unpacker_64 unpack_a (
        .fp_in(op_a),
        .sign(sign_a),
        .exp(exp_a),
        .mantissa(mant_a),
        .is_zero(is_zero_a),
        .is_nan(is_nan_a),
        .is_inf(is_inf_a),
        .is_subnormal(),
        .is_snan(),
        .is_qnan()
    );

    /*
     * Convert the biased exponent into a signed/unbiased representation.
     *
     * For square root:
     *
     *              E_real
     * E_result =  ---------
     *                 2
     *
     * When the exponent is odd, the mantissa is adjusted accordingly so
     * that the restoring square-root operation always works on a normalized
     * radicand.
     */

    wire [11:0] e_real = {1'b0, exp_a} - 12'd1023;
    wire exp_is_odd = e_real[0];

    /*
     * Construct the initial radicand.
     *
     * Two different alignments are required depending on whether the
     * unbiased exponent is even or odd.
     *
     * The extended width provides sufficient room for all restoring
     * square-root iterations and precision bits.
     */

    wire [109:0] d_init =
        exp_is_odd ? {mant_a, 57'd0} :
                     {1'b0, mant_a, 56'd0};

    /*
     * Calculate the exponent of the final square-root result.
     *
     * The exponent is approximately:
     *
     *     1023 + floor(E_real / 2)
     *
     * The arithmetic shift preserves the sign for negative unbiased
     * exponents.
     */

    wire [10:0] exp_final_init = 11'd1023 + (e_real >>> 1);

    // =========================================================================
    // 2. PIPELINE PARAMETERS
    // =========================================================================

    /*
     * 56 restoring iterations are required to generate the required
     * precision for an FP64 result.
     *
     * Stage 0 is the input latch.
     * Stages 1 through 56 perform the iterative square-root operation.
     *
     * Therefore the complete pipeline contains 57 registered stages.
     */

    localparam STAGES = 56;
    localparam TOTAL_STAGES = STAGES + 1; // Stages 0..56 = 57 stages

    // =========================================================================
    // PIPELINE REGISTERS
    // =========================================================================

    /*
     * Radicand shift register.
     *
     * Two bits are consumed during every restoring square-root iteration.
     */

    reg [109:0] pipe_rad [0:TOTAL_STAGES-1];

    /*
     * Partial remainder used by the restoring square-root algorithm.
     */

    reg [57:0] pipe_rem [0:TOTAL_STAGES-1];

    /*
     * Partial square-root result.
     *
     * Additional bits are retained to generate guard, round, and sticky
     * information during final rounding.
     */

    reg [56:0] pipe_root [0:TOTAL_STAGES-1];

    /*
     * Propagated result exponent.
     */

    reg [10:0] pipe_exp [0:TOTAL_STAGES-1];

    /*
     * Pipeline control and special-case flags.
     */

    reg pipe_vld  [0:TOTAL_STAGES-1];
    reg pipe_sign [0:TOTAL_STAGES-1];
    reg pipe_inv  [0:TOTAL_STAGES-1];
    reg pipe_inf  [0:TOTAL_STAGES-1];
    reg pipe_zero [0:TOTAL_STAGES-1];

    // =========================================================================
    // 3. COMBINATIONAL NEXT-STATE LOGIC
    // =========================================================================
    /*
     * The generate block contains only combinational logic.
     *
     * Every generated stage calculates the next state of the restoring
     * square-root operation from the corresponding registered stage.
     *
     * No pipeline register is declared or driven inside this generate block.
     * This ensures that all sequential state is controlled by the single
     * always block below.
     */

    wire [109:0] next_rad  [0:STAGES-1];
    wire [57:0]  next_rem  [0:STAGES-1];
    wire [56:0]  next_root [0:STAGES-1];

    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : SQRT_COMB

            /*
             * Append the next two radicand bits to the partial remainder.
             *
             * The restoring square-root algorithm processes two input bits
             * per iteration.
             */

            wire [57:0] R_appended =
                {pipe_rem[i][55:0], pipe_rad[i][109:108]};

            /*
             * Trial subtraction value:
             *
             *     (root << 2) | 01
             *
             * This represents the trial divisor used by the restoring
             * square-root iteration.
             */

            wire [57:0] test_val =
                {pipe_root[i][55:0], 2'b01};

            /*
             * Perform the trial subtraction with one additional sign bit.
             */

            wire [58:0] sub_res =
                {1'b0, R_appended} - {1'b0, test_val};

            /*
             * If the subtraction does not underflow, the trial digit is 1.
             * Otherwise, the trial digit is 0 and the original remainder
             * is retained.
             */

            wire can_sub = !sub_res[58];

            /*
             * Shift the radicand by two bits for the next iteration.
             */

            assign next_rad[i] = pipe_rad[i] << 2;

            /*
             * Update the partial remainder.
             */

            assign next_rem[i] =
                can_sub ? sub_res[57:0] :
                          R_appended;

            /*
             * Append the next root digit.
             */

            assign next_root[i] =
                can_sub ? {pipe_root[i][55:0], 1'b1} :
                          {pipe_root[i][55:0], 1'b0};

        end
    endgenerate

    // =========================================================================
    // 4. SINGLE SEQUENTIAL PIPELINE BLOCK
    // =========================================================================
    /*
     * This is the only always block that drives the pipeline registers.
     *
     * Keeping all sequential assignments in one block prevents multiple
     * drivers on the generated pipeline registers and keeps the pipeline
     * structure explicit.
     */

    integer j;

    always @(posedge clk) begin
        if (!rstn) begin

            // -----------------------------------------------------------------
            // Reset all pipeline stages.
            // -----------------------------------------------------------------

            for (j = 0; j < TOTAL_STAGES; j = j + 1) begin
                pipe_vld[j]  <= 1'b0;
                pipe_rad[j]  <= 110'd0;
                pipe_rem[j]  <= 58'd0;
                pipe_root[j] <= 57'd0;
                pipe_exp[j]  <= 11'd0;
                pipe_sign[j] <= 1'b0;
                pipe_inv[j]  <= 1'b0;
                pipe_inf[j]  <= 1'b0;
                pipe_zero[j] <= 1'b0;
            end

        end else begin

            // ================================================================
            // STAGE 0: INPUT LATCH
            // ================================================================

            pipe_vld[0] <= valid_in;

            if (valid_in) begin
                pipe_rad[0]  <= d_init;
                pipe_rem[0]  <= 58'd0;
                pipe_root[0] <= 57'd0;
                pipe_exp[0]  <= exp_final_init;
                pipe_sign[0] <= sign_a;
                pipe_inf[0]  <= is_inf_a;
                pipe_zero[0] <= is_zero_a;

                /*
                 * Invalid-result flag.
                 *
                 * The square root of a NaN or a negative non-zero value
                 * produces NaN.
                 */

                pipe_inv[0] <= is_nan_a || (sign_a && !is_zero_a);
            end

            // ================================================================
            // STAGES 1..56: RESTORING SQUARE-ROOT ITERATIONS
            // ================================================================
            /*
             * Each stage performs one restoring square-root iteration.
             *
             * The combinational next-state signals are generated above,
             * while the registers themselves are updated here.
             *
             * The explicit stage-by-stage structure keeps the pipeline
             * deterministic and synthesizable.
             */

            // -----------------------------------------------------------------
            // Stage 1
            // -----------------------------------------------------------------

            pipe_vld[1]  <= pipe_vld[0];
            pipe_rad[1]  <= next_rad[0];
            pipe_rem[1]  <= next_rem[0];
            pipe_root[1] <= next_root[0];
            pipe_exp[1]  <= pipe_exp[0];
            pipe_sign[1] <= pipe_sign[0];
            pipe_inv[1]  <= pipe_inv[0];
            pipe_inf[1]  <= pipe_inf[0];
            pipe_zero[1] <= pipe_zero[0];

            // -----------------------------------------------------------------
            // Stage 2
            // -----------------------------------------------------------------

            pipe_vld[2]  <= pipe_vld[1];
            pipe_rad[2]  <= next_rad[1];
            pipe_rem[2]  <= next_rem[1];
            pipe_root[2] <= next_root[1];
            pipe_exp[2]  <= pipe_exp[1];
            pipe_sign[2] <= pipe_sign[1];
            pipe_inv[2]  <= pipe_inv[1];
            pipe_inf[2]  <= pipe_inf[1];
            pipe_zero[2] <= pipe_zero[1];

            // -----------------------------------------------------------------
            // Stage 3
            // -----------------------------------------------------------------

            pipe_vld[3]  <= pipe_vld[2];
            pipe_rad[3]  <= next_rad[2];
            pipe_rem[3]  <= next_rem[2];
            pipe_root[3] <= next_root[2];
            pipe_exp[3]  <= pipe_exp[2];
            pipe_sign[3] <= pipe_sign[2];
            pipe_inv[3]  <= pipe_inv[2];
            pipe_inf[3]  <= pipe_inf[2];
            pipe_zero[3] <= pipe_zero[2];

            // -----------------------------------------------------------------
            // Stage 4
            // -----------------------------------------------------------------

            pipe_vld[4]  <= pipe_vld[3];
            pipe_rad[4]  <= next_rad[3];
            pipe_rem[4]  <= next_rem[3];
            pipe_root[4] <= next_root[3];
            pipe_exp[4]  <= pipe_exp[3];
            pipe_sign[4] <= pipe_sign[3];
            pipe_inv[4]  <= pipe_inv[3];
            pipe_inf[4]  <= pipe_inf[3];
            pipe_zero[4] <= pipe_zero[3];

            // -----------------------------------------------------------------
            // Stage 5
            // -----------------------------------------------------------------

            pipe_vld[5]  <= pipe_vld[4];
            pipe_rad[5]  <= next_rad[4];
            pipe_rem[5]  <= next_rem[4];
            pipe_root[5] <= next_root[4];
            pipe_exp[5]  <= pipe_exp[4];
            pipe_sign[5] <= pipe_sign[4];
            pipe_inv[5]  <= pipe_inv[4];
            pipe_inf[5]  <= pipe_inf[4];
            pipe_zero[5] <= pipe_zero[4];

            // -----------------------------------------------------------------
            // Stage 6
            // -----------------------------------------------------------------

            pipe_vld[6]  <= pipe_vld[5];
            pipe_rad[6]  <= next_rad[5];
            pipe_rem[6]  <= next_rem[5];
            pipe_root[6] <= next_root[5];
            pipe_exp[6]  <= pipe_exp[5];
            pipe_sign[6] <= pipe_sign[5];
            pipe_inv[6]  <= pipe_inv[5];
            pipe_inf[6]  <= pipe_inf[5];
            pipe_zero[6] <= pipe_zero[5];

            // -----------------------------------------------------------------
            // Stage 7
            // -----------------------------------------------------------------

            pipe_vld[7]  <= pipe_vld[6];
            pipe_rad[7]  <= next_rad[6];
            pipe_rem[7]  <= next_rem[6];
            pipe_root[7] <= next_root[6];
            pipe_exp[7]  <= pipe_exp[6];
            pipe_sign[7] <= pipe_sign[6];
            pipe_inv[7]  <= pipe_inv[6];
            pipe_inf[7]  <= pipe_inf[6];
            pipe_zero[7] <= pipe_zero[6];

            // -----------------------------------------------------------------
            // Stage 8
            // -----------------------------------------------------------------

            pipe_vld[8]  <= pipe_vld[7];
            pipe_rad[8]  <= next_rad[7];
            pipe_rem[8]  <= next_rem[7];
            pipe_root[8] <= next_root[7];
            pipe_exp[8]  <= pipe_exp[7];
            pipe_sign[8] <= pipe_sign[7];
            pipe_inv[8]  <= pipe_inv[7];
            pipe_inf[8]  <= pipe_inf[7];
            pipe_zero[8] <= pipe_zero[7];

            // -----------------------------------------------------------------
            // Stage 9
            // -----------------------------------------------------------------

            pipe_vld[9]  <= pipe_vld[8];
            pipe_rad[9]  <= next_rad[8];
            pipe_rem[9]  <= next_rem[8];
            pipe_root[9] <= next_root[8];
            pipe_exp[9]  <= pipe_exp[8];
            pipe_sign[9] <= pipe_sign[8];
            pipe_inv[9]  <= pipe_inv[8];
            pipe_inf[9]  <= pipe_inf[8];
            pipe_zero[9] <= pipe_zero[8];

            // -----------------------------------------------------------------
            // Stage 10
            // -----------------------------------------------------------------

            pipe_vld[10]  <= pipe_vld[9];
            pipe_rad[10]  <= next_rad[9];
            pipe_rem[10]  <= next_rem[9];
            pipe_root[10] <= next_root[9];
            pipe_exp[10]  <= pipe_exp[9];
            pipe_sign[10] <= pipe_sign[9];
            pipe_inv[10]  <= pipe_inv[9];
            pipe_inf[10]  <= pipe_inf[9];
            pipe_zero[10] <= pipe_zero[9];

            // -----------------------------------------------------------------
            // Stage 11
            // -----------------------------------------------------------------

            pipe_vld[11]  <= pipe_vld[10];
            pipe_rad[11]  <= next_rad[10];
            pipe_rem[11]  <= next_rem[10];
            pipe_root[11] <= next_root[10];
            pipe_exp[11]  <= pipe_exp[10];
            pipe_sign[11] <= pipe_sign[10];
            pipe_inv[11]  <= pipe_inv[10];
            pipe_inf[11]  <= pipe_inf[10];
            pipe_zero[11] <= pipe_zero[10];

            // -----------------------------------------------------------------
            // Stage 12
            // -----------------------------------------------------------------

            pipe_vld[12]  <= pipe_vld[11];
            pipe_rad[12]  <= next_rad[11];
            pipe_rem[12]  <= next_rem[11];
            pipe_root[12] <= next_root[11];
            pipe_exp[12]  <= pipe_exp[11];
            pipe_sign[12] <= pipe_sign[11];
            pipe_inv[12]  <= pipe_inv[11];
            pipe_inf[12]  <= pipe_inf[11];
            pipe_zero[12] <= pipe_zero[11];

            // -----------------------------------------------------------------
            // Stage 13
            // -----------------------------------------------------------------

            pipe_vld[13]  <= pipe_vld[12];
            pipe_rad[13]  <= next_rad[12];
            pipe_rem[13]  <= next_rem[12];
            pipe_root[13] <= next_root[12];
            pipe_exp[13]  <= pipe_exp[12];
            pipe_sign[13] <= pipe_sign[12];
            pipe_inv[13]  <= pipe_inv[12];
            pipe_inf[13]  <= pipe_inf[12];
            pipe_zero[13] <= pipe_zero[12];

            // -----------------------------------------------------------------
            // Stage 14
            // -----------------------------------------------------------------

            pipe_vld[14]  <= pipe_vld[13];
            pipe_rad[14]  <= next_rad[13];
            pipe_rem[14]  <= next_rem[13];
            pipe_root[14] <= next_root[13];
            pipe_exp[14]  <= pipe_exp[13];
            pipe_sign[14] <= pipe_sign[13];
            pipe_inv[14]  <= pipe_inv[13];
            pipe_inf[14]  <= pipe_inf[13];
            pipe_zero[14] <= pipe_zero[13];

            // -----------------------------------------------------------------
            // Stage 15
            // -----------------------------------------------------------------

            pipe_vld[15]  <= pipe_vld[14];
            pipe_rad[15]  <= next_rad[14];
            pipe_rem[15]  <= next_rem[14];
            pipe_root[15] <= next_root[14];
            pipe_exp[15]  <= pipe_exp[14];
            pipe_sign[15] <= pipe_sign[14];
            pipe_inv[15]  <= pipe_inv[14];
            pipe_inf[15]  <= pipe_inf[14];
            pipe_zero[15] <= pipe_zero[14];

            // -----------------------------------------------------------------
            // Stage 16
            // -----------------------------------------------------------------

            pipe_vld[16]  <= pipe_vld[15];
            pipe_rad[16]  <= next_rad[15];
            pipe_rem[16]  <= next_rem[15];
            pipe_root[16] <= next_root[15];
            pipe_exp[16]  <= pipe_exp[15];
            pipe_sign[16] <= pipe_sign[15];
            pipe_inv[16]  <= pipe_inv[15];
            pipe_inf[16]  <= pipe_inf[15];
            pipe_zero[16] <= pipe_zero[15];

            // -----------------------------------------------------------------
            // Stage 17
            // -----------------------------------------------------------------

            pipe_vld[17]  <= pipe_vld[16];
            pipe_rad[17]  <= next_rad[16];
            pipe_rem[17]  <= next_rem[16];
            pipe_root[17] <= next_root[16];
            pipe_exp[17]  <= pipe_exp[16];
            pipe_sign[17] <= pipe_sign[16];
            pipe_inv[17]  <= pipe_inv[16];
            pipe_inf[17]  <= pipe_inf[16];
            pipe_zero[17] <= pipe_zero[16];

            // -----------------------------------------------------------------
            // Stage 18
            // -----------------------------------------------------------------

            pipe_vld[18]  <= pipe_vld[17];
            pipe_rad[18]  <= next_rad[17];
            pipe_rem[18]  <= next_rem[17];
            pipe_root[18] <= next_root[17];
            pipe_exp[18]  <= pipe_exp[17];
            pipe_sign[18] <= pipe_sign[17];
            pipe_inv[18]  <= pipe_inv[17];
            pipe_inf[18]  <= pipe_inf[17];
            pipe_zero[18] <= pipe_zero[17];

            // -----------------------------------------------------------------
            // Stage 19
            // -----------------------------------------------------------------

            pipe_vld[19]  <= pipe_vld[18];
            pipe_rad[19]  <= next_rad[18];
            pipe_rem[19]  <= next_rem[18];
            pipe_root[19] <= next_root[18];
            pipe_exp[19]  <= pipe_exp[18];
            pipe_sign[19] <= pipe_sign[18];
            pipe_inv[19]  <= pipe_inv[18];
            pipe_inf[19]  <= pipe_inf[18];
            pipe_zero[19] <= pipe_zero[18];

            // -----------------------------------------------------------------
            // Stage 20
            // -----------------------------------------------------------------

            pipe_vld[20]  <= pipe_vld[19];
            pipe_rad[20]  <= next_rad[19];
            pipe_rem[20]  <= next_rem[19];
            pipe_root[20] <= next_root[19];
            pipe_exp[20]  <= pipe_exp[19];
            pipe_sign[20] <= pipe_sign[19];
            pipe_inv[20]  <= pipe_inv[19];
            pipe_inf[20]  <= pipe_inf[19];
            pipe_zero[20] <= pipe_zero[19];

            // -----------------------------------------------------------------
            // Stage 21
            // -----------------------------------------------------------------

            pipe_vld[21]  <= pipe_vld[20];
            pipe_rad[21]  <= next_rad[20];
            pipe_rem[21]  <= next_rem[20];
            pipe_root[21] <= next_root[20];
            pipe_exp[21]  <= pipe_exp[20];
            pipe_sign[21] <= pipe_sign[20];
            pipe_inv[21]  <= pipe_inv[20];
            pipe_inf[21]  <= pipe_inf[20];
            pipe_zero[21] <= pipe_zero[20];

            // -----------------------------------------------------------------
            // Stage 22
            // -----------------------------------------------------------------

            pipe_vld[22]  <= pipe_vld[21];
            pipe_rad[22]  <= next_rad[21];
            pipe_rem[22]  <= next_rem[21];
            pipe_root[22] <= next_root[21];
            pipe_exp[22]  <= pipe_exp[21];
            pipe_sign[22] <= pipe_sign[21];
            pipe_inv[22]  <= pipe_inv[21];
            pipe_inf[22]  <= pipe_inf[21];
            pipe_zero[22] <= pipe_zero[21];

            // -----------------------------------------------------------------
            // Stage 23
            // -----------------------------------------------------------------

            pipe_vld[23]  <= pipe_vld[22];
            pipe_rad[23]  <= next_rad[22];
            pipe_rem[23]  <= next_rem[22];
            pipe_root[23] <= next_root[22];
            pipe_exp[23]  <= pipe_exp[22];
            pipe_sign[23] <= pipe_sign[22];
            pipe_inv[23]  <= pipe_inv[22];
            pipe_inf[23]  <= pipe_inf[22];
            pipe_zero[23] <= pipe_zero[22];

            // -----------------------------------------------------------------
            // Stage 24
            // -----------------------------------------------------------------

            pipe_vld[24]  <= pipe_vld[23];
            pipe_rad[24]  <= next_rad[23];
            pipe_rem[24]  <= next_rem[23];
            pipe_root[24] <= next_root[23];
            pipe_exp[24]  <= pipe_exp[23];
            pipe_sign[24] <= pipe_sign[23];
            pipe_inv[24]  <= pipe_inv[23];
            pipe_inf[24]  <= pipe_inf[23];
            pipe_zero[24] <= pipe_zero[23];

            // -----------------------------------------------------------------
            // Stage 25
            // -----------------------------------------------------------------

            pipe_vld[25]  <= pipe_vld[24];
            pipe_rad[25]  <= next_rad[24];
            pipe_rem[25]  <= next_rem[24];
            pipe_root[25] <= next_root[24];
            pipe_exp[25]  <= pipe_exp[24];
            pipe_sign[25] <= pipe_sign[24];
            pipe_inv[25]  <= pipe_inv[24];
            pipe_inf[25]  <= pipe_inf[24];
            pipe_zero[25] <= pipe_zero[24];

            // -----------------------------------------------------------------
            // Stage 26
            // -----------------------------------------------------------------

            pipe_vld[26]  <= pipe_vld[25];
            pipe_rad[26]  <= next_rad[25];
            pipe_rem[26]  <= next_rem[25];
            pipe_root[26] <= next_root[25];
            pipe_exp[26]  <= pipe_exp[25];
            pipe_sign[26] <= pipe_sign[25];
            pipe_inv[26]  <= pipe_inv[25];
            pipe_inf[26]  <= pipe_inf[25];
            pipe_zero[26] <= pipe_zero[25];

            // -----------------------------------------------------------------
            // Stage 27
            // -----------------------------------------------------------------

            pipe_vld[27]  <= pipe_vld[26];
            pipe_rad[27]  <= next_rad[26];
            pipe_rem[27]  <= next_rem[26];
            pipe_root[27] <= next_root[26];
            pipe_exp[27]  <= pipe_exp[26];
            pipe_sign[27] <= pipe_sign[26];
            pipe_inv[27]  <= pipe_inv[26];
            pipe_inf[27]  <= pipe_inf[26];
            pipe_zero[27] <= pipe_zero[26];

            // -----------------------------------------------------------------
            // Stage 28
            // -----------------------------------------------------------------

            pipe_vld[28]  <= pipe_vld[27];
            pipe_rad[28]  <= next_rad[27];
            pipe_rem[28]  <= next_rem[27];
            pipe_root[28] <= next_root[27];
            pipe_exp[28]  <= pipe_exp[27];
            pipe_sign[28] <= pipe_sign[27];
            pipe_inv[28]  <= pipe_inv[27];
            pipe_inf[28]  <= pipe_inf[27];
            pipe_zero[28] <= pipe_zero[27];

            // -----------------------------------------------------------------
            // Stage 29
            // -----------------------------------------------------------------

            pipe_vld[29]  <= pipe_vld[28];
            pipe_rad[29]  <= next_rad[28];
            pipe_rem[29]  <= next_rem[28];
            pipe_root[29] <= next_root[28];
            pipe_exp[29]  <= pipe_exp[28];
            pipe_sign[29] <= pipe_sign[28];
            pipe_inv[29]  <= pipe_inv[28];
            pipe_inf[29]  <= pipe_inf[28];
            pipe_zero[29] <= pipe_zero[28];

            // -----------------------------------------------------------------
            // Stage 30
            // -----------------------------------------------------------------

            pipe_vld[30]  <= pipe_vld[29];
            pipe_rad[30]  <= next_rad[29];
            pipe_rem[30]  <= next_rem[29];
            pipe_root[30] <= next_root[29];
            pipe_exp[30]  <= pipe_exp[29];
            pipe_sign[30] <= pipe_sign[29];
            pipe_inv[30]  <= pipe_inv[29];
            pipe_inf[30]  <= pipe_inf[29];
            pipe_zero[30] <= pipe_zero[29];

            // -----------------------------------------------------------------
            // Stage 31
            // -----------------------------------------------------------------

            pipe_vld[31]  <= pipe_vld[30];
            pipe_rad[31]  <= next_rad[30];
            pipe_rem[31]  <= next_rem[30];
            pipe_root[31] <= next_root[30];
            pipe_exp[31]  <= pipe_exp[30];
            pipe_sign[31] <= pipe_sign[30];
            pipe_inv[31]  <= pipe_inv[30];
            pipe_inf[31]  <= pipe_inf[30];
            pipe_zero[31] <= pipe_zero[30];

            // -----------------------------------------------------------------
            // Stage 32
            // -----------------------------------------------------------------

            pipe_vld[32]  <= pipe_vld[31];
            pipe_rad[32]  <= next_rad[31];
            pipe_rem[32]  <= next_rem[31];
            pipe_root[32] <= next_root[31];
            pipe_exp[32]  <= pipe_exp[31];
            pipe_sign[32] <= pipe_sign[31];
            pipe_inv[32]  <= pipe_inv[31];
            pipe_inf[32]  <= pipe_inf[31];
            pipe_zero[32] <= pipe_zero[31];

            // -----------------------------------------------------------------
            // Stage 33
            // -----------------------------------------------------------------

            pipe_vld[33]  <= pipe_vld[32];
            pipe_rad[33]  <= next_rad[32];
            pipe_rem[33]  <= next_rem[32];
            pipe_root[33] <= next_root[32];
            pipe_exp[33]  <= pipe_exp[32];
            pipe_sign[33] <= pipe_sign[32];
            pipe_inv[33]  <= pipe_inv[32];
            pipe_inf[33]  <= pipe_inf[32];
            pipe_zero[33] <= pipe_zero[32];

            // -----------------------------------------------------------------
            // Stage 34
            // -----------------------------------------------------------------

            pipe_vld[34]  <= pipe_vld[33];
            pipe_rad[34]  <= next_rad[33];
            pipe_rem[34]  <= next_rem[33];
            pipe_root[34] <= next_root[33];
            pipe_exp[34]  <= pipe_exp[33];
            pipe_sign[34] <= pipe_sign[33];
            pipe_inv[34]  <= pipe_inv[33];
            pipe_inf[34]  <= pipe_inf[33];
            pipe_zero[34] <= pipe_zero[33];

            // -----------------------------------------------------------------
            // Stage 35
            // -----------------------------------------------------------------

            pipe_vld[35]  <= pipe_vld[34];
            pipe_rad[35]  <= next_rad[34];
            pipe_rem[35]  <= next_rem[34];
            pipe_root[35] <= next_root[34];
            pipe_exp[35]  <= pipe_exp[34];
            pipe_sign[35] <= pipe_sign[34];
            pipe_inv[35]  <= pipe_inv[34];
            pipe_inf[35]  <= pipe_inf[34];
            pipe_zero[35] <= pipe_zero[34];

            // -----------------------------------------------------------------
            // Stage 36
            // -----------------------------------------------------------------

            pipe_vld[36]  <= pipe_vld[35];
            pipe_rad[36]  <= next_rad[35];
            pipe_rem[36]  <= next_rem[35];
            pipe_root[36] <= next_root[35];
            pipe_exp[36]  <= pipe_exp[35];
            pipe_sign[36] <= pipe_sign[35];
            pipe_inv[36]  <= pipe_inv[35];
            pipe_inf[36]  <= pipe_inf[35];
            pipe_zero[36] <= pipe_zero[35];

            // -----------------------------------------------------------------
            // Stage 37
            // -----------------------------------------------------------------

            pipe_vld[37]  <= pipe_vld[36];
            pipe_rad[37]  <= next_rad[36];
            pipe_rem[37]  <= next_rem[36];
            pipe_root[37] <= next_root[36];
            pipe_exp[37]  <= pipe_exp[36];
            pipe_sign[37] <= pipe_sign[36];
            pipe_inv[37]  <= pipe_inv[36];
            pipe_inf[37]  <= pipe_inf[36];
            pipe_zero[37] <= pipe_zero[36];

            // -----------------------------------------------------------------
            // Stage 38
            // -----------------------------------------------------------------

            pipe_vld[38]  <= pipe_vld[37];
            pipe_rad[38]  <= next_rad[37];
            pipe_rem[38]  <= next_rem[37];
            pipe_root[38] <= next_root[37];
            pipe_exp[38]  <= pipe_exp[37];
            pipe_sign[38] <= pipe_sign[37];
            pipe_inv[38]  <= pipe_inv[37];
            pipe_inf[38]  <= pipe_inf[37];
            pipe_zero[38] <= pipe_zero[37];

            // -----------------------------------------------------------------
            // Stage 39
            // -----------------------------------------------------------------

            pipe_vld[39]  <= pipe_vld[38];
            pipe_rad[39]  <= next_rad[38];
            pipe_rem[39]  <= next_rem[38];
            pipe_root[39] <= next_root[38];
            pipe_exp[39]  <= pipe_exp[38];
            pipe_sign[39] <= pipe_sign[38];
            pipe_inv[39]  <= pipe_inv[38];
            pipe_inf[39]  <= pipe_inf[38];
            pipe_zero[39] <= pipe_zero[38];

            // -----------------------------------------------------------------
            // Stage 40
            // -----------------------------------------------------------------

            pipe_vld[40]  <= pipe_vld[39];
            pipe_rad[40]  <= next_rad[39];
            pipe_rem[40]  <= next_rem[39];
            pipe_root[40] <= next_root[39];
            pipe_exp[40]  <= pipe_exp[39];
            pipe_sign[40] <= pipe_sign[39];
            pipe_inv[40]  <= pipe_inv[39];
            pipe_inf[40]  <= pipe_inf[39];
            pipe_zero[40] <= pipe_zero[39];

            // -----------------------------------------------------------------
            // Stage 41
            // -----------------------------------------------------------------

            pipe_vld[41]  <= pipe_vld[40];
            pipe_rad[41]  <= next_rad[40];
            pipe_rem[41]  <= next_rem[40];
            pipe_root[41] <= next_root[40];
            pipe_exp[41]  <= pipe_exp[40];
            pipe_sign[41] <= pipe_sign[40];
            pipe_inv[41]  <= pipe_inv[40];
            pipe_inf[41]  <= pipe_inf[40];
            pipe_zero[41] <= pipe_zero[40];

            // -----------------------------------------------------------------
            // Stage 42
            // -----------------------------------------------------------------

            pipe_vld[42]  <= pipe_vld[41];
            pipe_rad[42]  <= next_rad[41];
            pipe_rem[42]  <= next_rem[41];
            pipe_root[42] <= next_root[41];
            pipe_exp[42]  <= pipe_exp[41];
            pipe_sign[42] <= pipe_sign[41];
            pipe_inv[42]  <= pipe_inv[41];
            pipe_inf[42]  <= pipe_inf[41];
            pipe_zero[42] <= pipe_zero[41];

            // -----------------------------------------------------------------
            // Stage 43
            // -----------------------------------------------------------------

            pipe_vld[43]  <= pipe_vld[42];
            pipe_rad[43]  <= next_rad[42];
            pipe_rem[43]  <= next_rem[42];
            pipe_root[43] <= next_root[42];
            pipe_exp[43]  <= pipe_exp[42];
            pipe_sign[43] <= pipe_sign[42];
            pipe_inv[43]  <= pipe_inv[42];
            pipe_inf[43]  <= pipe_inf[42];
            pipe_zero[43] <= pipe_zero[42];

            // -----------------------------------------------------------------
            // Stage 44
            // -----------------------------------------------------------------

            pipe_vld[44]  <= pipe_vld[43];
            pipe_rad[44]  <= next_rad[43];
            pipe_rem[44]  <= next_rem[43];
            pipe_root[44] <= next_root[43];
            pipe_exp[44]  <= pipe_exp[43];
            pipe_sign[44] <= pipe_sign[43];
            pipe_inv[44]  <= pipe_inv[43];
            pipe_inf[44]  <= pipe_inf[43];
            pipe_zero[44] <= pipe_zero[43];

            // -----------------------------------------------------------------
            // Stage 45
            // -----------------------------------------------------------------

            pipe_vld[45]  <= pipe_vld[44];
            pipe_rad[45]  <= next_rad[44];
            pipe_rem[45]  <= next_rem[44];
            pipe_root[45] <= next_root[44];
            pipe_exp[45]  <= pipe_exp[44];
            pipe_sign[45] <= pipe_sign[44];
            pipe_inv[45]  <= pipe_inv[44];
            pipe_inf[45]  <= pipe_inf[44];
            pipe_zero[45] <= pipe_zero[44];

            // -----------------------------------------------------------------
            // Stage 46
            // -----------------------------------------------------------------

            pipe_vld[46]  <= pipe_vld[45];
            pipe_rad[46]  <= next_rad[45];
            pipe_rem[46]  <= next_rem[45];
            pipe_root[46] <= next_root[45];
            pipe_exp[46]  <= pipe_exp[45];
            pipe_sign[46] <= pipe_sign[45];
            pipe_inv[46]  <= pipe_inv[45];
            pipe_inf[46]  <= pipe_inf[45];
            pipe_zero[46] <= pipe_zero[45];

            // -----------------------------------------------------------------
            // Stage 47
            // -----------------------------------------------------------------

            pipe_vld[47]  <= pipe_vld[46];
            pipe_rad[47]  <= next_rad[46];
            pipe_rem[47]  <= next_rem[46];
            pipe_root[47] <= next_root[46];
            pipe_exp[47]  <= pipe_exp[46];
            pipe_sign[47] <= pipe_sign[46];
            pipe_inv[47]  <= pipe_inv[46];
            pipe_inf[47]  <= pipe_inf[46];
            pipe_zero[47] <= pipe_zero[46];

            // -----------------------------------------------------------------
            // Stage 48
            // -----------------------------------------------------------------

            pipe_vld[48]  <= pipe_vld[47];
            pipe_rad[48]  <= next_rad[47];
            pipe_rem[48]  <= next_rem[47];
            pipe_root[48] <= next_root[47];
            pipe_exp[48]  <= pipe_exp[47];
            pipe_sign[48] <= pipe_sign[47];
            pipe_inv[48]  <= pipe_inv[47];
            pipe_inf[48]  <= pipe_inf[47];
            pipe_zero[48] <= pipe_zero[47];

            // -----------------------------------------------------------------
            // Stage 49
            // -----------------------------------------------------------------

            pipe_vld[49]  <= pipe_vld[48];
            pipe_rad[49]  <= next_rad[48];
            pipe_rem[49]  <= next_rem[48];
            pipe_root[49] <= next_root[48];
            pipe_exp[49]  <= pipe_exp[48];
            pipe_sign[49] <= pipe_sign[48];
            pipe_inv[49]  <= pipe_inv[48];
            pipe_inf[49]  <= pipe_inf[48];
            pipe_zero[49] <= pipe_zero[48];

            // -----------------------------------------------------------------
            // Stage 50
            // -----------------------------------------------------------------

            pipe_vld[50]  <= pipe_vld[49];
            pipe_rad[50]  <= next_rad[49];
            pipe_rem[50]  <= next_rem[49];
            pipe_root[50] <= next_root[49];
            pipe_exp[50]  <= pipe_exp[49];
            pipe_sign[50] <= pipe_sign[49];
            pipe_inv[50]  <= pipe_inv[49];
            pipe_inf[50]  <= pipe_inf[49];
            pipe_zero[50] <= pipe_zero[49];

            // -----------------------------------------------------------------
            // Stage 51
            // -----------------------------------------------------------------

            pipe_vld[51]  <= pipe_vld[50];
            pipe_rad[51]  <= next_rad[50];
            pipe_rem[51]  <= next_rem[50];
            pipe_root[51] <= next_root[50];
            pipe_exp[51]  <= pipe_exp[50];
            pipe_sign[51] <= pipe_sign[50];
            pipe_inv[51]  <= pipe_inv[50];
            pipe_inf[51]  <= pipe_inf[50];
            pipe_zero[51] <= pipe_zero[50];

            // -----------------------------------------------------------------
            // Stage 52
            // -----------------------------------------------------------------

            pipe_vld[52]  <= pipe_vld[51];
            pipe_rad[52]  <= next_rad[51];
            pipe_rem[52]  <= next_rem[51];
            pipe_root[52] <= next_root[51];
            pipe_exp[52]  <= pipe_exp[51];
            pipe_sign[52] <= pipe_sign[51];
            pipe_inv[52]  <= pipe_inv[51];
            pipe_inf[52]  <= pipe_inf[51];
            pipe_zero[52] <= pipe_zero[51];

            // -----------------------------------------------------------------
            // Stage 53
            // -----------------------------------------------------------------

            pipe_vld[53]  <= pipe_vld[52];
            pipe_rad[53]  <= next_rad[52];
            pipe_rem[53]  <= next_rem[52];
            pipe_root[53] <= next_root[52];
            pipe_exp[53]  <= pipe_exp[52];
            pipe_sign[53] <= pipe_sign[52];
            pipe_inv[53]  <= pipe_inv[52];
            pipe_inf[53]  <= pipe_inf[52];
            pipe_zero[53] <= pipe_zero[52];

            // -----------------------------------------------------------------
            // Stage 54
            // -----------------------------------------------------------------

            pipe_vld[54]  <= pipe_vld[53];
            pipe_rad[54]  <= next_rad[53];
            pipe_rem[54]  <= next_rem[53];
            pipe_root[54] <= next_root[53];
            pipe_exp[54]  <= pipe_exp[53];
            pipe_sign[54] <= pipe_sign[53];
            pipe_inv[54]  <= pipe_inv[53];
            pipe_inf[54]  <= pipe_inf[53];
            pipe_zero[54] <= pipe_zero[53];

            // -----------------------------------------------------------------
            // Stage 55
            // -----------------------------------------------------------------

            pipe_vld[55]  <= pipe_vld[54];
            pipe_rad[55]  <= next_rad[54];
            pipe_rem[55]  <= next_rem[54];
            pipe_root[55] <= next_root[54];
            pipe_exp[55]  <= pipe_exp[54];
            pipe_sign[55] <= pipe_sign[54];
            pipe_inv[55]  <= pipe_inv[54];
            pipe_inf[55]  <= pipe_inf[54];
            pipe_zero[55] <= pipe_zero[54];

            // -----------------------------------------------------------------
            // Stage 56
            // -----------------------------------------------------------------

            pipe_vld[56]  <= pipe_vld[55];
            pipe_rad[56]  <= next_rad[55];
            pipe_rem[56]  <= next_rem[55];
            pipe_root[56] <= next_root[55];
            pipe_exp[56]  <= pipe_exp[55];
            pipe_sign[56] <= pipe_sign[55];
            pipe_inv[56]  <= pipe_inv[55];
            pipe_inf[56]  <= pipe_inf[55];
            pipe_zero[56] <= pipe_zero[55];

        end
    end

    // =========================================================================
    // 5. POST-PROCESSING & ROUNDING
    // =========================================================================
    /*
     * Extract the final mantissa and the additional precision bits required
     * by the IEEE 754 round-to-nearest-even operation implemented by the
     * common FP64 packer.
     */

    wire [52:0] final_mant =
        pipe_root[STAGES][55:3];

    wire final_guard =
        pipe_root[STAGES][2];

    wire final_round =
        pipe_root[STAGES][1];

    /*
     * Sticky is asserted whenever:
     *
     *   1. The final restoring remainder is non-zero, or
     *   2. An additional quotient bit was discarded.
     */

    wire sticky =
        (pipe_rem[STAGES] != 0) ||
        pipe_root[STAGES][0];

    // =========================================================================
    // FP64 PACKER
    // =========================================================================
    /*
     * The common packer performs the final IEEE 754 field construction and
     * round-to-nearest-even operation.
     */

    wire [63:0] final_fp;

    vrm_fpu_packer_64 packer (
        .sign(pipe_sign[STAGES]),
        .exp(pipe_exp[STAGES]),
        .mant(final_mant),
        .guard(final_guard),
        .round(final_round),
        .sticky(sticky),
        .fp_out(final_fp)
    );

    // =========================================================================
    // 6. FINAL OUTPUT SELECTION
    // =========================================================================
    /*
     * The valid flag corresponds directly to the final pipeline stage.
     */

    assign valid_out = pipe_vld[STAGES];

    /*
     * Special-case priority:
     *
     *   1. Invalid input / negative operand -> NaN
     *   2. Infinity                         -> Infinity
     *   3. Zero                             -> Zero
     *   4. Normal operand                   -> Computed square root
     */

    assign result_out =
        pipe_inv[STAGES]  ? 64'h7FF8000000000000 :
        pipe_inf[STAGES]  ? {pipe_sign[STAGES], 11'h7FF, 52'h0} :
        pipe_zero[STAGES] ? {pipe_sign[STAGES], 63'd0} :
                            final_fp;

endmodule
