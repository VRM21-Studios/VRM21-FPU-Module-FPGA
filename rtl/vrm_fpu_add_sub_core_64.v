`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_add_sub_core_64
// DESCRIPTION:
// Mantissa arithmetic stage for the 64-bit IEEE-754 floating-point
// addition/subtraction datapath.
//
// The module performs the actual mantissa addition or subtraction after the
// operands have been unpacked and aligned to a common exponent.
//
// Features:
// - Mantissa addition for operands with equal effective signs
// - Mantissa subtraction for operands with different effective signs
// - Explicit 55-bit arithmetic width
// - Result sign generation
// - Zero-result sign handling
// - Common exponent propagation
// - Sticky-bit propagation to the normalization stage
//
// Notes:
// - The Large and Small operand ordering is established by the preceding
//   alignment stage.
// - Subtraction is selected when the operand signs differ.
// - A zero result is assigned a positive sign.
// - Mantissa normalization is performed by the downstream normalization stage.
// ============================================================================

module vrm_fpu_add_sub_core_64 (
    input  wire        sign_L,
    input  wire        sign_S,
    input  wire [10:0] exp_common,
    input  wire [53:0] mant_L,       
    input  wire [53:0] mant_S_align,
    input  wire        sticky_in,
    output reg         final_sign,
    output reg  [10:0] exp_out,
    output reg  [54:0] mant_res,     
    output reg         sticky_out
);

    // =========================================================================
    // 1. OPERATION SELECTION
    // =========================================================================

    // Different operand signs require subtraction; equal signs require
    // addition of the aligned mantissas.
    wire eff_sub = (sign_L ^ sign_S); 

    // =========================================================================
    // 2. MANTISSA ARITHMETIC AND RESULT SIGN
    // =========================================================================

    always @(*) begin

        // Perform the mantissa arithmetic using an explicit 55-bit extension
        // to preserve the carry/borrow position of the operation.
        if (eff_sub)
            mant_res = {1'b0, mant_L} - {1'b0, mant_S_align};
        else
            mant_res = {1'b0, mant_L} + {1'b0, mant_S_align};

        // A cancellation result is assigned a positive sign. Otherwise,
        // preserve the sign of the Large operand.
        if (eff_sub && (mant_res == 55'd0))
            final_sign = 1'b0;
        else
            final_sign = sign_L;

        // Propagate the common exponent and sticky information to the
        // normalization stage.
        exp_out    = exp_common;
        sticky_out = sticky_in;
    end

endmodule
