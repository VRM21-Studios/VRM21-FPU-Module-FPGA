`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_packer_64
// DESCRIPTION:
// IEEE 754 double-precision result packing stage for the FPU datapath.
//
// The module applies round-to-nearest, ties-to-even using the guard, round,
// sticky, and least-significant mantissa bits, then packs the normalized
// floating-point components into a 64-bit IEEE 754 representation.
//
// Features:
// - Round-to-nearest, ties-to-even
// - Mantissa rounding with carry propagation
// - Exponent increment on mantissa overflow
// - Overflow detection and infinity generation
// - Basic zero/subnormal result handling
// - IEEE 754 sign, exponent, and fraction field packing
//
// Rounding Behavior:
// - The result is rounded up when the guard bit is set and either the round
//   bit, sticky bit, or current mantissa LSB is set.
// - If rounding generates a carry beyond the mantissa width, the mantissa is
//   shifted right and the exponent is incremented.
//
// Special Results:
// - Exponent overflow produces signed infinity.
// - Exponent zero produces a zero result.
//
// Notes:
// - This module performs the final packing step only.
// - Special-value classification and full IEEE 754 exception handling are
//   handled by the surrounding FPU datapath.
// ============================================================================

module vrm_fpu_packer_64 (
    input  wire        sign,
    input  wire [10:0] exp,
    input  wire [52:0] mant,
    input  wire        guard,
    input  wire        round,
    input  wire        sticky,
    output reg  [63:0] fp_out
);

    // =========================================================================
    // ROUNDING CONTROL
    // =========================================================================

    // Round-to-nearest, ties-to-even.
    //
    // A tie is rounded toward the even mantissa LSB through mant[0].
    wire round_up = guard && (round || sticky || mant[0]);

    // =========================================================================
    // INTERNAL PACKING REGISTERS
    // =========================================================================

    reg [53:0] mant_rounded;
    reg [10:0] final_exp;
    reg [51:0] final_frac;

    always @(*) begin

        // Apply the selected rounding increment to the extended mantissa.
        mant_rounded = mant + round_up;

        // =====================================================================
        // MANTISSA ROUNDING OVERFLOW
        // =====================================================================

        if (mant_rounded[53] == 1'b1) begin

            // Rounding generated a carry, requiring a one-bit normalization
            // shift and an exponent increment.
            final_exp  = exp + 11'd1;
            final_frac = mant_rounded[52:1];

        end else begin

            final_exp  = exp;
            final_frac = mant_rounded[51:0];

        end

        // =====================================================================
        // FINAL IEEE 754 RESULT
        // =====================================================================

        if (final_exp >= 11'h7FF) begin

            // Exponent overflow produces signed infinity.
            fp_out = {sign, 11'h7FF, 52'h0};

        end else if (final_exp == 11'h000) begin

            // Exponent zero is represented as a zero result.
            fp_out = {sign, 11'h000, 52'h0};

        end else begin

            // Pack sign, normalized exponent, and fraction fields.
            fp_out = {sign, final_exp, final_frac};

        end
    end

endmodule
