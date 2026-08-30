`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_tanh_64
 * DESCRIPTION:
 *   Double-precision floating-point hyperbolic tangent function unit.
 *
 *   Computes:
 *
 *       tanh(x) = (exp(2x) - 1) / (exp(2x) + 1)
 *
 *   The implementation is constructed from existing FPU arithmetic units:
 *
 *       1. Multiply by two:
 *            2x = x + x
 *
 *       2. Exponential:
 *            exp_val = exp(2x)
 *
 *       3. Numerator:
 *            num = exp(2x) - 1
 *
 *       4. Denominator:
 *            den = exp(2x) + 1
 *
 *       5. Division:
 *            tanh(x) = num / den
 *
 *   The numerator and denominator are calculated in parallel after the
 *   exponential result becomes available.
 *
 * MATHEMATICAL FORM:
 *
 *              exp(2x) - 1
 *       tanh(x) = -----------
 *              exp(2x) + 1
 *
 * INTERFACE:
 *
 *   clk        : System clock.
 *   rstn       : Active-low synchronous reset.
 *   valid_in   : Input transaction valid.
 *   op_a       : IEEE-754 double-precision input operand.
 *   result_out : IEEE-754 double-precision tanh result.
 *   valid_out  : Output result valid.
 *
 * LATENCY:
 *
 *   Variable total latency determined by the instantiated ADD/SUB, EXP,
 *   and DIV units.
 *
 * ============================================================================
 */

module vrm_fpu_tanh_64 (
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
    // STAGE 1: CALCULATE 2x
    // =========================================================================
    //
    // Compute:
    //
    //     2x = x + x
    //
    // The existing floating-point adder/subtractor is used to perform the
    // operation.
    //

    wire [63:0] two_x;
    wire        two_x_done;

    vrm_fpu_add_sub_64 u_add2x (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (valid_in),
        .is_sub    (1'b0),
        .op_a      (op_a),
        .op_b      (op_a),
        .result_out(two_x),
        .valid_out (two_x_done)
    );


    // =========================================================================
    // STAGE 2: EXPONENTIAL
    // =========================================================================
    //
    // Compute:
    //
    //     exp_val = exp(2x)
    //
    // The exponential unit starts after the 2x calculation has completed.
    //

    wire [63:0] exp_val;
    wire        exp_done;

    vrm_fpu_exp_64 u_exp (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (two_x_done),
        .op_a      (two_x),
        .result_out(exp_val),
        .valid_out (exp_done)
    );


    // =========================================================================
    // STAGE 3: REGISTER EXPONENTIAL RESULT
    // =========================================================================
    //
    // The exponential result is registered before being distributed to the
    // numerator and denominator arithmetic units.
    //
    // This ensures that both paths operate on the same exp(2x) value.
    //

    reg [63:0] exp_reg;
    reg        exp_ready;

    always @(posedge clk) begin
        if (exp_done)
            exp_reg <= exp_val;
    end

    always @(posedge clk) begin
        exp_ready <= exp_done;
    end


    // =========================================================================
    // STAGE 4: NUMERATOR AND DENOMINATOR
    // =========================================================================
    //
    // Calculate both terms in parallel:
    //
    //     num = exp(2x) - 1
    //
    //     den = exp(2x) + 1
    //
    // Both operations use the same registered exponential value.
    //

    wire [63:0] num;
    wire [63:0] den;

    wire        num_done;
    wire        den_done;


    // -------------------------------------------------------------------------
    // Numerator: exp(2x) - 1
    // -------------------------------------------------------------------------

    vrm_fpu_add_sub_64 u_sub1 (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (exp_ready),
        .is_sub    (1'b1),
        .op_a      (exp_reg),
        .op_b      (FP_ONE),
        .result_out(num),
        .valid_out (num_done)
    );


    // -------------------------------------------------------------------------
    // Denominator: exp(2x) + 1
    // -------------------------------------------------------------------------

    vrm_fpu_add_sub_64 u_add1 (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (exp_ready),
        .is_sub    (1'b0),
        .op_a      (exp_reg),
        .op_b      (FP_ONE),
        .result_out(den),
        .valid_out (den_done)
    );


    // =========================================================================
    // STAGE 5: DIVISION
    // =========================================================================
    //
    // Start the division only after both numerator and denominator are valid.
    //
    //     result = num / den
    //
    // Therefore:
    //
    //              exp(2x) - 1
    //     tanh(x) = -----------
    //              exp(2x) + 1
    //
    // The two completion signals are ANDed because the divider requires both
    // operands to be ready from the same transaction.
    //

    wire div_start;

    assign div_start = num_done & den_done;

    wire [63:0] div_res;
    wire        div_done;

    vrm_fpu_div_64 u_div (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (div_start),
        .op_a      (num),
        .op_b      (den),
        .result_out(div_res),
        .valid_out (div_done)
    );


    // =========================================================================
    // OUTPUT REGISTER
    // =========================================================================
    //
    // Register the final division result and propagate its valid signal.
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
