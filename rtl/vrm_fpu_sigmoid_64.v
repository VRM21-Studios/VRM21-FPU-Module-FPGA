`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_sigmoid_64
 * ============================================================================
 * DESCRIPTION:
 *   Double-precision floating-point sigmoid function unit for RV32D/RV64D
 *   floating-point datapaths.
 *
 *   Computes:
 *
 *       sigmoid(x) = 1 / (1 + exp(-x))
 *
 *   The implementation is constructed from existing FPU arithmetic blocks:
 *
 *       1. Negation:
 *            -x
 *
 *       2. Exponential:
 *            exp(-x)
 *
 *       3. Addition:
 *            1 + exp(-x)
 *
 *       4. Division:
 *            1 / (1 + exp(-x))
 *
 *   The unit is fully pipelined through the underlying arithmetic modules.
 *   Each stage propagates its valid signal to the next stage.
 *
 * ============================================================================
 * INTERFACE:
 *   valid_in    : Input transaction valid.
 *   op_a        : IEEE-754 double-precision input operand.
 *   result_out  : IEEE-754 double-precision sigmoid result.
 *   valid_out   : Output result valid.
 *
 * ============================================================================
 * LATENCY:
 *   Variable total latency determined by the instantiated FPU arithmetic
 *   units (ADD/SUB, EXP, ADD, and DIV).
 *
 * ============================================================================
 */

module vrm_fpu_sigmoid_64 (
    input  wire        clk,
    input  wire        rstn,
    input  wire        valid_in,
    input  wire [63:0] op_a,

    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    // IEEE-754 double-precision representation of +1.0.
    localparam FP_ONE = `FP64_ONE;


    // =========================================================================
    // STAGE 1: NEGATE INPUT
    // =========================================================================
    //
    // Computes:
    //
    //     neg_x = 0 - x
    //
    // The subtraction unit is used instead of directly toggling the sign bit
    // so that the operation remains within the common FPU arithmetic pipeline.
    //

    wire [63:0] neg_x;
    wire        neg_done;

    vrm_fpu_add_sub_64 u_neg (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (valid_in),
        .is_sub    (1'b1),
        .op_a      (64'd0),
        .op_b      (op_a),
        .result_out(neg_x),
        .valid_out (neg_done)
    );


    // =========================================================================
    // STAGE 2: EXPONENTIAL
    // =========================================================================
    //
    // Computes:
    //
    //     exp_val = exp(-x)
    //
    // The exponential unit receives its transaction only after the negation
    // stage has produced a valid result.
    //

    wire [63:0] exp_val;
    wire        exp_done;

    vrm_fpu_exp_64 u_exp (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (neg_done),
        .op_a      (neg_x),
        .result_out(exp_val),
        .valid_out (exp_done)
    );


    // =========================================================================
    // STAGE 3: ADD ONE
    // =========================================================================
    //
    // Computes the denominator:
    //
    //     den = 1 + exp(-x)
    //
    // This forms the denominator of the sigmoid equation.
    //

    wire [63:0] den;
    wire        den_done;

    vrm_fpu_add_sub_64 u_add (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (exp_done),
        .is_sub    (1'b0),
        .op_a      (FP_ONE),
        .op_b      (exp_val),
        .result_out(den),
        .valid_out (den_done)
    );


    // =========================================================================
    // STAGE 4: RECIPROCAL / DIVISION
    // =========================================================================
    //
    // Computes:
    //
    //     result = 1 / den
    //
    // Therefore:
    //
    //     result = 1 / (1 + exp(-x))
    //
    // which is the sigmoid function.
    //

    wire [63:0] div_res;
    wire        div_done;

    vrm_fpu_div_64 u_div (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (den_done),
        .op_a      (FP_ONE),
        .op_b      (den),
        .result_out(div_res),
        .valid_out (div_done)
    );


    // =========================================================================
    // OUTPUT REGISTER
    // =========================================================================
    //
    // Register the final result and propagate the completion signal.
    //

    always @(posedge clk) begin
        if (!rstn) begin
            valid_out  <= 1'b0;
            result_out <= 64'd0;
        end else begin
            valid_out  <= div_done;
            result_out <= div_res;
        end
    end

endmodule
