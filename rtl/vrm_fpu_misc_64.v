`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: vrm_fpu_misc_64 (LANE F: COMPARISON & CLASSIFICATION)
 * DESCRIPTION:
 *   Implements miscellaneous IEEE 754 / RISC-V RV32D floating-point
 *   operations:
 *     - FEQ : Floating-Point Equal
 *     - FLT : Floating-Point Less Than
 *     - FLE : Floating-Point Less Than or Equal
 *     - FMIN: Floating-Point Minimum
 *     - FMAX: Floating-Point Maximum
 *     - FCLASS: Floating-Point Classification
 *
 * LATENCY:
 *   1 cycle
 *
 * OPERATION SELECT:
 *   3'b000 : FEQ
 *   3'b001 : FLT
 *   3'b010 : FLE
 *   3'b011 : FMIN
 *   3'b100 : FMAX
 *   3'b101 : FCLASS
 * ============================================================================ */

module vrm_fpu_misc_64 (
    input  wire        clk,
    input  wire        rstn,
    
    input  wire        valid_in,
    input  wire [2:0]  misc_op,
    input  wire [63:0] op_a,
    input  wire [63:0] op_b,
    
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // 1. UNPACK & SPECIAL-VALUE DETECTION
    // =========================================================================
    // Decode both FP64 operands and extract their sign, exponent,
    // mantissa, and IEEE 754 classification flags.

    wire s_a, s_b;
    wire [10:0] e_a, e_b;
    wire [52:0] m_a, m_b;
    wire z_a, z_b, nan_a, nan_b, inf_a, inf_b, sub_a, sub_b;

    vrm_fpu_unpacker_64 unpack_a (
        .fp_in(op_a), .sign(s_a), .exp(e_a), .mantissa(m_a), .is_snan(), .is_qnan(),
        .is_zero(z_a), .is_nan(nan_a), .is_inf(inf_a), .is_subnormal(sub_a)
    );

    vrm_fpu_unpacker_64 unpack_b (
        .fp_in(op_b), .sign(s_b), .exp(e_b), .mantissa(m_b), .is_snan(), .is_qnan(),
        .is_zero(z_b), .is_nan(nan_b), .is_inf(inf_b), .is_subnormal(sub_b)
    );

    // =========================================================================
    // 2. CORE COMPARISON LOGIC
    // =========================================================================
    // Compare the operands according to their IEEE 754 numerical ordering.
    //
    // The sign bit is handled separately from the magnitude field.
    // For operands with identical signs:
    //   - Positive values use normal magnitude ordering.
    //   - Negative values use reversed magnitude ordering.
    //
    // Both +0.0 and -0.0 are considered equal.

    wire both_zero = z_a && z_b;
    wire mag_a_gt_b = (op_a[62:0] > op_b[62:0]);
    wire mag_a_eq_b = (op_a[62:0] == op_b[62:0]);

    reg lt, eq;

    always @(*) begin
        if (nan_a || nan_b) begin
            // IEEE 754: Ordered comparisons involving NaN are false.
            lt = 0;
            eq = 0;
        end else if (both_zero) begin
            // +0.0 and -0.0 compare as equal.
            lt = 0;
            eq = 1;
        end else if (s_a != s_b) begin
            // A negative value is always less than a positive value.
            lt = s_a;
            eq = 0;
        end else begin
            // Both operands have the same sign.
            if (!s_a) begin
                // Both operands are positive.
                lt = mag_a_gt_b ? 0 : (mag_a_eq_b ? 0 : 1);
                eq = mag_a_eq_b;
            end else begin
                // Both operands are negative.
                // Magnitude ordering is reversed for negative values.
                lt = mag_a_gt_b ? 1 : 0;
                eq = mag_a_eq_b;
            end
        end
    end

    wire le = lt || eq;

    // =========================================================================
    // 3. FCLASS LOGIC
    // =========================================================================
    // Generate the IEEE 754 10-bit classification mask.
    //
    // Bit mapping follows the RISC-V FCLASS encoding:
    //   Bit 9 : Signaling NaN
    //   Bit 8 : Quiet NaN
    //   Bit 7 : +Infinity
    //   Bit 6 : +Normal
    //   Bit 5 : +Subnormal
    //   Bit 4 : +Zero
    //   Bit 3 : -Zero
    //   Bit 2 : -Subnormal
    //   Bit 1 : -Normal
    //   Bit 0 : -Infinity

    wire [9:0] class_mask_a = {
        nan_a && (op_a[51]),                         // Quiet NaN
        nan_a && (!op_a[51]),                        // Signaling NaN
        !s_a && inf_a,                               // +Infinity
        !s_a && !inf_a && !sub_a && !z_a,            // +Normal
        !s_a && sub_a,                               // +Subnormal
        !s_a && z_a,                                 // +Zero
        s_a && z_a,                                  // -Zero
        s_a && sub_a,                                // -Subnormal
        s_a && !inf_a && !sub_a && !z_a,             // -Normal
        s_a && inf_a                                 // -Infinity
    };

    // =========================================================================
    // 4. OUTPUT MULTIPLEXER & OUTPUT REGISTER
    // =========================================================================
    // All miscellaneous operations have a one-cycle registered output.
    // Comparison results are returned in the least-significant bit.
    // FCLASS returns its 10-bit classification mask in bits [9:0].

    always @(posedge clk) begin
        if (!rstn) begin
            valid_out  <= 1'b0;
            result_out <= 64'd0;
        end else begin
            valid_out <= valid_in;

            case (misc_op)
                3'b000: result_out <= {63'd0, eq};                                  // FEQ
                3'b001: result_out <= {63'd0, lt};                                  // FLT
                3'b010: result_out <= {63'd0, le};                                  // FLE
                3'b011: result_out <= (lt || (z_a && z_b && s_a)) ? op_a : op_b;    // FMIN
                3'b100: result_out <= (lt || (z_a && z_b && s_a)) ? op_b : op_a;    // FMAX
                3'b101: result_out <= {54'd0, class_mask_a};                        // FCLASS
                default: result_out <= 64'd0;
            endcase
        end
    end

endmodule
