`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_mul_64
// DESCRIPTION:
// Six-stage pipelined IEEE 754 double-precision floating-point multiplier.
//
// The module performs floating-point multiplication using a deeply pipelined
// mantissa multiplier and dedicated normalization and packing stages.
//
// Features:
// - IEEE 754 double-precision datapath
// - 64-bit floating-point operands
// - Six-stage pipelined operation
// - DSP-oriented mantissa multiplication
// - Sign calculation using operand sign XOR
// - Exponent addition with IEEE 754 bias correction
// - Mantissa normalization
// - Guard, round, and sticky bit generation
// - IEEE 754 result packing
//
// Pipeline Stages:
// - STAGE 0 : Operand unpacking and exponent preparation
// - STAGE 1 : Input registers for the multiplier datapath
// - STAGE 2-4 : Deeply pipelined mantissa multiplication
// - STAGE 5 : Product normalization and sticky-bit reduction
// - STAGE 6 : Final packing and output register
//
// DSP Inference:
// - Mantissa multiplication is explicitly marked for DSP utilization.
// - Retiming attributes are applied to the multiplication pipeline registers
//   to allow synthesis tools to move registers toward the multiplier logic.
// - This structure is intended to allow Vivado to map the multiplication
//   pipeline into the available DSP48E2 pipeline registers.
//
// Notes:
// - The module assumes the surrounding FPU datapath provides the required
//   floating-point special-case handling.
// - The output valid signal is pipelined together with the arithmetic data.
// ============================================================================

module vrm_fpu_mul_64 (
    input  wire        clk,
    input  wire        rstn,

    input  wire        valid_in,
    input  wire [63:0] op_a,
    input  wire [63:0] op_b,

    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // STAGE 0: OPERAND UNPACKING
    // =========================================================================

    wire sign_a, sign_b;
    wire [10:0] exp_a, exp_b;
    wire [52:0] mant_a, mant_b;

    // Extract sign, exponent, and mantissa fields from both operands.
    vrm_fpu_unpacker_64 unpack_a (
        .fp_in      (op_a),
        .sign       (sign_a),
        .exp        (exp_a),
        .mantissa   (mant_a),
        .is_zero    (),
        .is_subnormal(),
        .is_inf     (),
        .is_nan     (),
        .is_snan    (),
        .is_qnan    ()
    );

    vrm_fpu_unpacker_64 unpack_b (
        .fp_in      (op_b),
        .sign       (sign_b),
        .exp        (exp_b),
        .mantissa   (mant_b),
        .is_zero    (),
        .is_subnormal(),
        .is_inf     (),
        .is_nan     (),
        .is_snan    (),
        .is_qnan    ()
    );

    // The result sign is the XOR of the operand signs.
    wire sign_res = sign_a ^ sign_b;

    // Add operand exponents and remove the IEEE 754 double-precision bias.
    wire signed [12:0] exp_sum =
        {2'b0, exp_a} + {2'b0, exp_b} - 13'd1023;

    // =========================================================================
    // STAGE 1: INPUT LATCH
    // =========================================================================

    reg        stg1_valid, stg1_sign;
    reg [12:0] stg1_exp;

    // Request DSP-oriented implementation for the mantissa operands.
    (* use_dsp = "yes" *) reg [52:0] stg1_mant_a, stg1_mant_b;

    always @(posedge clk) begin
        if (!rstn) begin
            stg1_valid  <= 0;
            stg1_sign   <= 0;
            stg1_exp    <= 0;
            stg1_mant_a <= 0;
            stg1_mant_b <= 0;
        end else begin
            stg1_valid  <= valid_in;
            stg1_sign   <= sign_res;
            stg1_exp    <= exp_sum;
            stg1_mant_a <= mant_a;
            stg1_mant_b <= mant_b;
        end
    end

    // =========================================================================
    // STAGES 2-4: PIPELINED MANTISSA MULTIPLICATION
    // =========================================================================

    reg [2:0] pipe_valid, pipe_sign;
    reg [12:0] pipe_exp [0:2];

    // Retiming allows synthesis tools to move these registers toward the
    // multiplier datapath and make use of internal DSP pipeline registers.
    (* use_dsp = "yes" *)
    (* retiming_backward = 1 *) reg [105:0] mult_pipe_0;

    (* retiming_backward = 1 *) reg [105:0] mult_pipe_1;
    (* retiming_backward = 1 *) reg [105:0] mult_pipe_2;

    always @(posedge clk) begin
        if (!rstn) begin
            pipe_valid   <= 3'd0;
            pipe_sign    <= 3'd0;

            pipe_exp[0]  <= 0;
            pipe_exp[1]  <= 0;
            pipe_exp[2]  <= 0;

            mult_pipe_0  <= 0;
            mult_pipe_1  <= 0;
            mult_pipe_2  <= 0;
        end else begin

            // Propagate valid and sign information through the multiplier
            // pipeline.
            pipe_valid <= {pipe_valid[1:0], stg1_valid};
            pipe_sign  <= {pipe_sign[1:0], stg1_sign};

            // Propagate the calculated exponent alongside the product.
            pipe_exp[0] <= stg1_exp;
            pipe_exp[1] <= pipe_exp[0];
            pipe_exp[2] <= pipe_exp[1];

            // Pipeline the 106-bit mantissa product.
            mult_pipe_0 <= stg1_mant_a * stg1_mant_b;
            mult_pipe_1 <= mult_pipe_0;
            mult_pipe_2 <= mult_pipe_1;
        end
    end

    // =========================================================================
    // STAGE 5: PRODUCT NORMALIZATION
    // =========================================================================

    // A set MSB indicates that the product requires a one-bit right shift.
    wire overflow = mult_pipe_2[105];

    // Adjust the exponent when the product is already above the normalized
    // mantissa range.
    wire signed [12:0] norm_exp_wire =
        overflow ? (pipe_exp[2] + 13'd1) : pipe_exp[2];

    // Select the normalized mantissa and rounding bits according to the
    // product normalization state.
    wire [52:0] norm_mant_wire =
        overflow ? mult_pipe_2[105:53] : mult_pipe_2[104:52];

    wire guard_bit_wire =
        overflow ? mult_pipe_2[52] : mult_pipe_2[51];

    wire round_bit_wire =
        overflow ? mult_pipe_2[51] : mult_pipe_2[50];

    // Reduce all discarded lower product bits into a single sticky bit.
    wire sticky_bit_wire =
        overflow ? (|mult_pipe_2[50:0]) :
                    (|mult_pipe_2[49:0]);

    // -------------------------------------------------------------------------
    // STAGE 5 -> STAGE 6 PIPELINE REGISTER
    // -------------------------------------------------------------------------

    reg        stg5_valid, stg5_sign;
    reg [10:0] stg5_final_exp;
    reg [52:0] stg5_mant;
    reg        stg5_guard, stg5_round, stg5_sticky;

    always @(posedge clk) begin
        if (!rstn) begin
            stg5_valid     <= 0;
            stg5_sign      <= 0;
            stg5_final_exp <= 0;
            stg5_mant      <= 0;
            stg5_guard     <= 0;
            stg5_round     <= 0;
            stg5_sticky    <= 0;
        end else begin
            stg5_valid <= pipe_valid[2];
            stg5_sign  <= pipe_sign[2];

            // Clamp the exponent to the representable IEEE 754 range.
            stg5_final_exp <=
                (norm_exp_wire <= 0) ? 11'd0 :
                (norm_exp_wire >= 13'd2047) ? 11'h7FF :
                norm_exp_wire[10:0];

            stg5_mant   <= norm_mant_wire;
            stg5_guard  <= guard_bit_wire;
            stg5_round  <= round_bit_wire;
            stg5_sticky <= sticky_bit_wire;
        end
    end

    // =========================================================================
    // STAGE 6: RESULT PACKING
    // =========================================================================

    wire [63:0] final_fp_data;

    // Convert the normalized components and rounding information back into
    // the 64-bit IEEE 754 representation.
    vrm_fpu_packer_64 packer (
        .sign   (stg5_sign),
        .exp    (stg5_final_exp),
        .mant   (stg5_mant),
        .guard  (stg5_guard),
        .round  (stg5_round),
        .sticky (stg5_sticky),
        .fp_out (final_fp_data)
    );

    // =========================================================================
    // OUTPUT REGISTER
    // =========================================================================

    always @(posedge clk) begin
        if (!rstn) begin
            valid_out  <= 0;
            result_out <= 0;
        end else begin
            valid_out  <= stg5_valid;
            result_out <= final_fp_data;
        end
    end

endmodule
