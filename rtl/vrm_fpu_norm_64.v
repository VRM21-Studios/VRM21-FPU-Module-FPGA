`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_norm_64
// DESCRIPTION:
// Normalization stage for the IEEE 754 double-precision floating-point
// datapath.
//
// The module normalizes the mantissa produced by the add/subtract stage and
// extracts the rounding information required by the subsequent packing stage.
//
// Features:
// - Leading-zero detection for cancellation results
// - Right normalization when the mantissa overflows
// - Left normalization for non-normalized results
// - Basic handling of exponent underflow toward the subnormal range
// - Guard, round, and sticky bit generation
// - Sign and exponent propagation
//
// Normalization Behavior:
// - A zero mantissa produces a zero exponent and mantissa.
// - A carry into bit 54 shifts the mantissa right by one position and
//   increments the exponent.
// - Otherwise, the mantissa is shifted left according to the leading-zero
//   count while reducing the exponent accordingly.
// - When the exponent cannot support the required normalization shift, the
//   result is represented with exponent zero.
//
// Notes:
// - The module operates on an extended 55-bit mantissa representation.
// - Rounding itself is not performed here; guard, round, and sticky bits are
//   forwarded to the packing stage.
// ============================================================================

module vrm_fpu_norm_64 (
    input  wire         sign_in,
    input  wire  [10:0] exp_in,
    input  wire  [54:0] mant_in,
    input  wire         sticky_in,
    output reg          sign_out,
    output reg   [10:0] exp_out,
    output reg   [52:0] mant_out,
    output reg          guard_out,
    output reg          round_out,
    output reg          sticky_out
);

    // =========================================================================
    // LEADING-ZERO DETECTION
    // =========================================================================

    reg [5:0] lzc;
    integer j;

    always @(*) begin

        // Default to the maximum possible leading-zero count.
        lzc = 6'd54;

        // Search for the most-significant set bit in the mantissa.
        for (j = 0; j <= 53; j = j + 1)
            if (mant_in[j] == 1'b1)
                lzc = 6'd53 - j[5:0];

        // Preserve the operand sign through normalization.
        sign_out = sign_in;

        // =====================================================================
        // ZERO RESULT
        // =====================================================================

        if (mant_in == 55'd0) begin

            // An exact cancellation produces +0.
            exp_out    = 11'd0;
            mant_out   = 53'd0;
            guard_out  = 1'b0;
            round_out  = 1'b0;
            sticky_out = 1'b0;

        // =====================================================================
        // RIGHT NORMALIZATION
        // =====================================================================

        end else if (mant_in[54] == 1'b1) begin

            // Mantissa overflow requires a one-bit right shift.
            exp_out    = exp_in + 11'd1;
            mant_out   = mant_in[54:2];
            guard_out  = mant_in[1];
            round_out  = mant_in[0];
            sticky_out = sticky_in;

        // =====================================================================
        // LEFT NORMALIZATION
        // =====================================================================

        end else begin

            if (exp_in > {5'b0, lzc}) begin

                // Shift the mantissa left until the leading one reaches
                // the normalized position and reduce the exponent accordingly.
                exp_out = exp_in - {5'b0, lzc};

                {mant_out, guard_out, round_out} =
                    {mant_in[53:0], 1'b0} << lzc;

                sticky_out = sticky_in;

            end else begin

                // Exponent cannot support the complete normalization shift.
                // Clamp the exponent to zero and retain the remaining
                // mantissa shift as a subnormal result.
                exp_out = 11'd0;

                {mant_out, guard_out, round_out} =
                    {mant_in[53:0], 1'b0} <<
                    (exp_in > 11'd0 ?
                     (exp_in - 11'd1) :
                     11'd0);

                sticky_out = sticky_in;

            end
        end
    end

endmodule
