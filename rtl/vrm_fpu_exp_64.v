`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_exp_64
 * DESCRIPTION:
 * FP64 natural exponential unit for RV32D/RV64D FPU support.
 *
 * The natural exponential function is computed using the identity:
 *
 *     exp(x) = 2^(x * log2(e))
 *
 * The input is first scaled by log2(e), then processed by the FP64
 * base-2 exponential unit.
 *
 * OPERATION:
 *     Input
 *       |
 *       +--> Multiply by log2(e)
 *       |
 *       +--> FP64 exp2
 *       |
 *     Output
 *
 * DEPENDENCIES:
 *     - vrm_fpu_constants.vh
 *     - vrm_fpu_mul_64
 *     - vrm_fpu_exp2_64
 *
 * NOTES:
 *     - Input and output operands use IEEE-754 FP64 representation.
 *     - The logarithm base conversion uses the constant log2(e).
 *     - The final exponential calculation is delegated to vrm_fpu_exp2_64.
 *     - valid_out follows the completion signal of the exp2 computation.
 * ============================================================================ */

module vrm_fpu_exp_64 (
    input  wire        clk, rstn, valid_in,
    input  wire [63:0] op_a,
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // Mathematical Constant
    // =========================================================================
    // log2(e) is used to convert the natural exponential into a base-2
    // exponential:
    //
    //     exp(x) = 2^(x * log2(e))
    localparam FP_LOG2E = `FP64_LOG2E;

    // =========================================================================
    // Stage 1: Input Scaling
    // =========================================================================
    // Calculate:
    //
    //     scaled = x * log2(e)
    //
    // The result is the exponent passed to the exp2 unit.
    wire [63:0] scaled;
    wire        scaled_done;

    vrm_fpu_mul_64 u_mul (
        .clk(clk), .rstn(rstn), .valid_in(valid_in),
        .op_a(op_a), .op_b(FP_LOG2E), .result_out(scaled), .valid_out(scaled_done)
    );

    // =========================================================================
    // Stage 2: Base-2 Exponential
    // =========================================================================
    // Calculate:
    //
    //     result = 2^scaled
    wire [63:0] exp2_res;
    wire        exp2_done;

    vrm_fpu_exp2_64 u_exp2 (
        .clk(clk), .rstn(rstn), .valid_in(scaled_done),
        .op_a(scaled), .result_out(exp2_res), .valid_out(exp2_done)
    );

    // =========================================================================
    // Output Register
    // =========================================================================
    // Register the result and propagate the completion signal from the
    // exp2 computation.
    always @(posedge clk) begin
        if (!rstn) begin
            valid_out <= 0;
            result_out <= 0;
        end else begin
            valid_out <= exp2_done;
            result_out <= exp2_res;
        end
    end

endmodule
