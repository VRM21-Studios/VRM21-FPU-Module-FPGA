`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_unpacker_64
// DESCRIPTION:
// IEEE-754 double-precision operand unpacker and classification unit.
//
// The module decomposes a 64-bit floating-point operand into its constituent
// IEEE-754 fields and identifies special-value classes.
//
// Features:
// - 64-bit IEEE-754 double-precision input
// - Sign, exponent, and mantissa extraction
// - Zero detection
// - Subnormal detection
// - Infinity detection
// - NaN detection
// - Signaling NaN and Quiet NaN classification
// - Hidden-bit generation for normalized operands
//
// Notes:
// - The mantissa output contains the 52-bit fraction field plus one hidden bit.
// - Normalized numbers receive an implicit leading 1.
// - Subnormal numbers do not contain an implicit leading 1.
// - Zero is represented by an all-zero mantissa output.
// - NaN classification uses the most-significant fraction bit to distinguish
//   Signaling NaN from Quiet NaN.
// ============================================================================

module vrm_fpu_unpacker_64 (
    input  wire [63:0] fp_in,
    
    // =========================================================================
    // Extracted IEEE-754 Components
    // =========================================================================
    output wire        sign,
    output wire [10:0] exp,
    output wire [52:0] mantissa, // 52-bit fraction + 1-bit hidden (implicit)
    
    // =========================================================================
    // IEEE-754 Special-Value Classification
    // =========================================================================
    output wire        is_zero,
    output wire        is_subnormal,
    output wire        is_inf,
    output wire        is_nan,
    output wire        is_snan,
    output wire        is_qnan
);

    // =========================================================================
    // 1. RAW IEEE-754 FIELD EXTRACTION
    // =========================================================================

    // Extract the sign, exponent, and fraction fields directly from the
    // 64-bit IEEE-754 double-precision representation.
    wire        raw_sign = fp_in[63];
    wire [10:0] raw_exp  = fp_in[62:52];
    wire [51:0] raw_frac = fp_in[51:0];

    // =========================================================================
    // 2. SPECIAL-VALUE CLASSIFICATION
    // =========================================================================

    // Detect the two exponent boundary cases used by IEEE-754 for zero,
    // subnormal numbers, infinity, and NaN.
    wire exp_all_zeros = (raw_exp == 11'h000);
    wire exp_all_ones  = (raw_exp == 11'h7FF);
    wire frac_is_zero  = (raw_frac == 52'h0);

    // Classify the input according to its exponent and fraction fields.
    assign is_zero      = exp_all_zeros && frac_is_zero;
    assign is_subnormal = exp_all_zeros && !frac_is_zero;
    assign is_inf       = exp_all_ones  && frac_is_zero;
    assign is_nan       = exp_all_ones  && !frac_is_zero;
    
    // -------------------------------------------------------------------------
    // NaN Classification
    // -------------------------------------------------------------------------

    // For a NaN operand, the most-significant fraction bit distinguishes
    // Signaling NaN from Quiet NaN in this implementation.
    assign is_snan      = is_nan && (raw_frac[51] == 1'b0);
    assign is_qnan      = is_nan && (raw_frac[51] == 1'b1);

    // =========================================================================
    // 3. FIELD OUTPUT AND HIDDEN-BIT GENERATION
    // =========================================================================

    assign sign = raw_sign;
    assign exp  = raw_exp;
    
    // Generate the 53-bit mantissa representation used by the downstream FPU
    // datapath. Normalized values receive an implicit leading 1, while
    // subnormal values use a leading 0.
    assign mantissa = is_subnormal ? {1'b0, raw_frac} : 
                      is_zero      ? 53'h0 : 
                                     {1'b1, raw_frac};

endmodule
