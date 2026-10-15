`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_float_to_int_64
// DESCRIPTION:
// FP64 to signed 32-bit integer conversion helper. vrm_fpu_exp2_64 uses it
// to extract the integer component n = trunc(x) of its input operand.
//
// The conversion truncates toward zero. Inputs whose magnitude is below 1.0,
// including zero and subnormal values, produce 0. Inputs whose unbiased
// exponent exceeds 31 saturate to 32'h7FFFFFFF or 32'h80000000 according to
// the sign bit.
//
// FEATURES:
// - IEEE 754 binary64 input, two's-complement int32 output
// - Round-toward-zero (truncation) only
// - Sign-dependent saturation for exponents above 31
// - Single output register stage; valid_out follows valid_in
//
// NOTES:
// - The numerical result matches the D2I path (conv_op = 2'b10) of
//   vrm_fpu_conv_64. This module is kept separate because it has one output
//   register stage instead of two and a 32-bit result port, and
//   vrm_fpu_exp2_64 depends on that pipeline depth.
// - Reduced scope: this is not a full RISC-V FCVT.W.D implementation. There
//   is no rounding-mode input and no exception flag output.
// - NaN and infinity are not detected explicitly. Their exponent field (2047)
//   takes the saturation path, so the result follows the sign bit.
// - Magnitudes in [2^31, 2^32) have an unbiased exponent of 31 and are not
//   saturated; the two's-complement result wraps. Only -2^31 is exact in
//   that range.
// - Reset is synchronous and active-low. It clears int_out and valid_out.
// ============================================================================

module vrm_fpu_float_to_int_64 (
    // Clock, active-low synchronous reset, and input valid
    input  wire        clk, rstn, valid_in,

    // FP64 operand
    input  wire [63:0] float_in,

    // Signed int32 result and its valid flag
    output reg  [31:0] int_out,
    output reg         valid_out
);

    // ========================================================================
    // 1. FIELD EXTRACTION AND EXPONENT DECODE
    // ========================================================================

    wire        sign = float_in[63];
    wire [10:0] exp  = float_in[62:52];
    wire [51:0] frac = float_in[51:0];

    // Unbiased exponent, held as a signed value so that magnitudes below 1.0
    // decode to a negative exponent and select the zero path in section 3.
    wire signed [11:0] true_exp = {1'b0, exp} - 12'd1023;

    // ========================================================================
    // 2. MANTISSA ALIGNMENT
    // ========================================================================

    // Significand with the implicit leading one restored. Subnormal inputs are
    // not normalized; their negative exponent always selects the zero path.
    wire [52:0] mantissa = {1'b1, frac};

    // Right-shift distance that moves the binary point to bit 0. The value is
    // only meaningful for 0 <= true_exp <= 31; other exponents are resolved by
    // the range check in section 3.
    wire [5:0] shift = (true_exp >= 52) ? 6'd52 : (6'd52 - true_exp[5:0]);

    // Integer magnitude. For in-range exponents the shift is at least 21, so
    // shifted[52:32] is zero and is intentionally dropped.
    wire [52:0] shifted = mantissa >> shift;
    wire [31:0] abs_int = shifted[31:0];

    // ========================================================================
    // 3. RANGE CHECK AND SIGN APPLICATION
    // ========================================================================

    // Exponents above 31 mean a magnitude of at least 2^32, which int32
    // cannot hold.
    wire overflow = (true_exp > 31);

    // Priority: saturation, then the below-one zero path, then the
    // two's-complement magnitude.
    reg [31:0] result_comb;
    always @(*) begin
        if (overflow) begin
            result_comb = sign ? 32'h80000000 : 32'h7FFFFFFF;
        end else if (true_exp < 0) begin
            result_comb = 32'd0;
        end else begin
            result_comb = sign ? (~abs_int + 1) : abs_int;
        end
    end

    // ========================================================================
    // 4. OUTPUT REGISTER
    // ========================================================================

    // WARNING: vrm_fpu_exp2_64 drives float_in from its live op_a input and
    // samples int_out in the FSM state that immediately follows input
    // acceptance (S_IDLE -> S_F2I). Adding a register stage here, or replacing
    // this module with vrm_fpu_conv_64, misaligns that capture unless the
    // exp2 FSM is updated at the same time.
    always @(posedge clk) begin
        if (!rstn) begin
            int_out   <= 0;
            valid_out <= 0;
        end else begin
            valid_out <= valid_in;
            int_out   <= result_comb;
        end
    end
endmodule
