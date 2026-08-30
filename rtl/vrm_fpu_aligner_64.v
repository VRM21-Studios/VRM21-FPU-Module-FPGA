`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_aligner_64
// DESCRIPTION:
// Exponent alignment stage for the 64-bit IEEE-754 floating-point
// addition/subtraction datapath.
//
// The module compares the magnitudes of two unpacked operands, selects the
// larger operand as Large (L), and right-shifts the smaller operand as Small
// (S) so both operands use a common exponent.
//
// Features:
// - Operand magnitude comparison using exponent and mantissa
// - Large/Small operand selection
// - Common exponent generation
// - Mantissa alignment through right shifting
// - Extended mantissa representation for additional precision
// - Sticky-bit generation from discarded mantissa bits
// - Handling of exponent differences larger than the alignment range
//
// Notes:
// - Operand magnitude is determined primarily by the exponent and then by
//   the mantissa when both exponents are equal.
// - The larger operand is always assigned to the Large path.
// - Mantissas are extended by one bit before alignment.
// - The sticky bit records whether any non-zero information was discarded
//   during the right shift.
// ============================================================================

module vrm_fpu_aligner_64 (
    // =========================================================================
    // Operand A
    // =========================================================================
    input  wire        sign_a,
    input  wire [10:0] exp_a,
    input  wire [52:0] mant_a,
    
    // =========================================================================
    // Operand B
    // =========================================================================
    input  wire        sign_b,
    input  wire [10:0] exp_b,
    input  wire [52:0] mant_b,

    // =========================================================================
    // Aligned Operand Outputs
    // =========================================================================
    output reg         sign_L,
    output reg         sign_S,
    output reg  [10:0] exp_common,
    output reg  [53:0] mant_L,
    output reg  [53:0] mant_S_align,
    output reg         sticky
);

    // =========================================================================
    // 1. OPERAND MAGNITUDE COMPARISON
    // =========================================================================

    // Select operand A as the Large operand when its exponent is greater,
    // or when the exponents are equal and its mantissa is greater or equal.
    wire a_is_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));
    
    // Calculate the absolute exponent difference between the two operands.
    wire [10:0] exp_diff =
        a_is_larger ? (exp_a - exp_b) : (exp_b - exp_a);
    
    // Select the Large and Small mantissas according to the magnitude
    // comparison above.
    wire [52:0] mant_large = a_is_larger ? mant_a : mant_b;
    wire [52:0] mant_small = a_is_larger ? mant_b : mant_a;
    
    // =========================================================================
    // 2. MANTISSA EXTENSION
    // =========================================================================

    // Append one zero bit to preserve an additional bit position during
    // alignment and subsequent rounding operations.
    wire [53:0] mant_L_padded = {mant_large, 1'b0};
    wire [53:0] mant_S_padded = {mant_small, 1'b0};

    // =========================================================================
    // 3. STICKY-BIT PREPARATION
    // =========================================================================

    // Generate a mask for mantissa bits that are discarded during the
    // alignment shift. Shifts beyond the supported mantissa range are handled
    // separately below.
    wire [107:0] sticky_mask =
        (108'hFFFFFFFFFFFFFFFFFFFFFFFFFFF >> (108 - exp_diff));

    wire [53:0] discarded_bits =
        mant_S_padded & sticky_mask[53:0];

    // =========================================================================
    // 4. MANTISSA ALIGNMENT
    // =========================================================================

    always @(*) begin

        // Propagate the sign and exponent belonging to the Large operand.
        sign_L     = a_is_larger ? sign_a : sign_b;
        sign_S     = a_is_larger ? sign_b : sign_a;
        exp_common = a_is_larger ? exp_a  : exp_b;

        // The Large mantissa does not require alignment.
        mant_L = mant_L_padded;
        
        // Shift the Small mantissa toward the least-significant bits so both
        // operands share the same exponent.
        //
        // If the exponent difference exceeds the available mantissa range,
        // the Small mantissa is completely shifted out and only its non-zero
        // state is retained through the sticky bit.
        if (exp_diff > 11'd54) begin
            mant_S_align = 54'd0;
            sticky       = (mant_small != 53'd0);
        end else begin
            mant_S_align = mant_S_padded >> exp_diff;
            sticky       = (discarded_bits != 54'd0);
        end
    end

endmodule
