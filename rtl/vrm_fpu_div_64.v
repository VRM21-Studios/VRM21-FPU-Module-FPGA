`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_div_64
// DESCRIPTION:
// IEEE 754 Double-Precision Floating-Point Divider.
// Implements a fully pipelined restoring-division architecture with one
// division stage per pipeline cycle.
//
// Architecture:
// - Input unpacking and initialization
// - 56-stage unrolled restoring division
// - Quotient normalization and rounding-bit extraction
// - IEEE 754 result packing
// - Special-case bypass for division by zero and zero dividend
//
// Performance:
// - Throughput : 1 result/cycle
// - Latency    : 56 cycles
//
// Notes:
// - A 57-bit quotient pipeline is used to preserve the required quotient
//   range and prevent truncation during the iterative division process.
// - All pipeline stages use synchronous reset to prevent invalid state
//   propagation.
// - Zero-divisor and zero-dividend flags are propagated through the pipeline
//   for special-case result generation at the output.
// ============================================================================

module vrm_fpu_div_64 (
    input  wire        clk,
    input  wire        rstn,
    
    input  wire        valid_in,
    input  wire [63:0] op_a,
    input  wire [63:0] op_b,
    
    output wire [63:0] result_out,
    output wire        valid_out
);

    // =========================================================================
    // 1. INPUT UNPACKING
    // =========================================================================

    wire sign_a, sign_b;
    wire [10:0] exp_a, exp_b;
    wire [52:0] mant_a, mant_b;
    wire is_zero_a, is_zero_b;

    vrm_fpu_unpacker_64 unpack_a (
        .fp_in(op_a),
        .sign(sign_a),
        .exp(exp_a),
        .mantissa(mant_a),
        .is_zero(is_zero_a),
        .is_subnormal(),
        .is_inf(),
        .is_nan(),
        .is_snan(),
        .is_qnan()
    );

    vrm_fpu_unpacker_64 unpack_b (
        .fp_in(op_b),
        .sign(sign_b),
        .exp(exp_b),
        .mantissa(mant_b),
        .is_zero(is_zero_b),
        .is_subnormal(),
        .is_inf(),
        .is_nan(),
        .is_snan(),
        .is_qnan()
    );

    // =========================================================================
    // 2. DIVISION PIPELINE
    // =========================================================================

    localparam STAGES = 56;

    // Pipeline state:
    // - stg_rem  : Partial remainder
    // - stg_quo  : Generated quotient
    // - stg_div  : Divisor
    // - stg_exp  : Bias-adjusted exponent
    // - stg_sign : Result sign
    // - stg_vld  : Pipeline valid flag
    // - stg_dz   : Division-by-zero flag
    // - stg_za   : Zero-dividend flag
    reg [53:0] stg_rem  [0:STAGES];
    reg [56:0] stg_quo  [0:STAGES];
    reg [52:0] stg_div  [0:STAGES];
    reg [12:0] stg_exp  [0:STAGES];
    reg        stg_sign [0:STAGES];
    reg        stg_vld  [0:STAGES];
    reg        stg_dz   [0:STAGES];
    reg        stg_za   [0:STAGES];

    // -------------------------------------------------------------------------
    // Stage 0: Input Initialization
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (!rstn) begin
            stg_vld[0]  <= 0;
            stg_rem[0]  <= 54'd0;
            stg_quo[0]  <= 57'd0;
            stg_div[0]  <= 53'd0;
            stg_exp[0]  <= 13'd0;
            stg_sign[0] <= 0;
            stg_dz[0]   <= 0;
            stg_za[0]   <= 0;
        end else begin
            stg_vld[0] <= valid_in;

            if (valid_in) begin
                stg_rem[0]  <= {1'b0, mant_a};
                stg_quo[0]  <= 57'd0;
                stg_div[0]  <= mant_b;
                stg_sign[0] <= sign_a ^ sign_b;

                // Preserve special-case information through the pipeline.
                stg_dz[0]   <= is_zero_b;
                stg_za[0]   <= is_zero_a;

                // Bias-adjusted exponent:
                // ExpA - ExpB + 1023.
                stg_exp[0]  <= {2'b0, exp_a} - {2'b0, exp_b} + 13'd1023;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stages 1 to 56: Restoring Division
    // -------------------------------------------------------------------------

    genvar i;

    generate
        for (i = 0; i < STAGES; i = i + 1) begin : DIV_PIPE
            
            // Combinational restoring-division step.
            // The divisor is subtracted first and the partial remainder is
            // shifted left after the subtraction decision.
            wire [54:0] sub_val =
                {1'b0, stg_rem[i]} - {2'b0, stg_div[i]};

            // A zero MSB indicates that the subtraction result is positive
            // and the current quotient bit can be set.
            wire can_sub = !sub_val[54];

            always @(posedge clk) begin
                if (!rstn) begin
                    stg_vld[i+1]  <= 0;
                    stg_rem[i+1]  <= 54'd0;
                    stg_quo[i+1]  <= 57'd0;
                    stg_div[i+1]  <= 53'd0;
                    stg_exp[i+1]  <= 13'd0;
                    stg_sign[i+1] <= 0;
                    stg_dz[i+1]   <= 0;
                    stg_za[i+1]   <= 0;
                end else begin
                    stg_vld[i+1] <= stg_vld[i];

                    if (stg_vld[i]) begin
                        // Propagate operands and control information.
                        stg_div[i+1]  <= stg_div[i];
                        stg_sign[i+1] <= stg_sign[i];
                        stg_exp[i+1]  <= stg_exp[i];
                        stg_dz[i+1]   <= stg_dz[i];
                        stg_za[i+1]   <= stg_za[i];

                        // Restoring division step:
                        // 1. Evaluate the subtraction.
                        // 2. Select the new remainder.
                        // 3. Shift the quotient and append the generated bit.
                        if (can_sub) begin
                            stg_rem[i+1] <= {sub_val[52:0], 1'b0};
                            stg_quo[i+1] <= {stg_quo[i][55:0], 1'b1};
                        end else begin
                            stg_rem[i+1] <= {stg_rem[i][52:0], 1'b0};
                            stg_quo[i+1] <= {stg_quo[i][55:0], 1'b0};
                        end
                    end
                end
            end
        end
    endgenerate

    // =========================================================================
    // 3. POST-PROCESSING AND NORMALIZATION
    // =========================================================================

    // The normalized quotient can be either:
    // - 1.xxx : quotient overflow bit is set
    // - 0.1xxx: quotient requires one exponent decrement
    wire overflow = stg_quo[STAGES][55];

    // Adjust the final exponent according to the quotient normalization.
    wire [10:0] final_exp =
        overflow ?
        stg_exp[STAGES][10:0] :
        (stg_exp[STAGES][10:0] - 11'd1);

    // Select the normalized mantissa and rounding bits.
    wire [52:0] final_mant =
        overflow ?
        stg_quo[STAGES][55:3] :
        stg_quo[STAGES][54:2];

    wire final_guard =
        overflow ?
        stg_quo[STAGES][2] :
        stg_quo[STAGES][1];

    wire final_round =
        overflow ?
        stg_quo[STAGES][1] :
        stg_quo[STAGES][0];

    // Sticky bit combines the final remainder with the discarded quotient
    // bit when the quotient is normalized without overflow.
    wire sticky =
        (stg_rem[STAGES] != 0) ||
        (overflow ? stg_quo[STAGES][0] : 1'b0);

    // =========================================================================
    // 4. IEEE 754 RESULT PACKING
    // =========================================================================

    wire [63:0] final_fp;

    vrm_fpu_packer_64 packer (
        .sign(stg_sign[STAGES]),
        .exp(final_exp),
        .mant(final_mant),
        .guard(final_guard),
        .round(final_round),
        .sticky(sticky),
        .fp_out(final_fp)
    );

    // =========================================================================
    // 5. OUTPUT AND SPECIAL-CASE HANDLING
    // =========================================================================

    assign valid_out = stg_vld[STAGES];

    // Special-case result priority:
    // 1. Division by zero -> Infinity
    // 2. Zero dividend    -> Zero
    // 3. Normal division  -> Packed IEEE 754 result
    assign result_out =
        stg_dz[STAGES] ? {stg_sign[STAGES], 11'h7FF, 52'h0} :
        stg_za[STAGES] ? {stg_sign[STAGES], 63'd0} :
                         final_fp;

endmodule
