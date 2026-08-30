`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_sin_64
 * DESCRIPTION:
 *   Double-precision floating-point sine function unit.
 *
 *   Computes:
 *
 *       sin(x)
 *
 *   using a polynomial approximation evaluated with Horner's method.
 *
 *   The implementation first calculates:
 *
 *       x2 = x * x
 *
 *   and then evaluates an odd polynomial:
 *
 *       sin(x) ≈ x * P(x2)
 *
 *   where:
 *
 *       P(x2) = C1 + x2(C3 + x2(C5 + ... + x2(C29)))
 *
 *   The polynomial coefficients are provided by vrm_fpu_constants.vh.
 *
 *   The computation is implemented as a sequential FSM and reuses the
 *   instantiated floating-point multiplier and adder/subtractor units.
 *
 * POLYNOMIAL:
 *
 *   sin(x) ≈ x * (
 *       C1  + x2 * (
 *       C3  + x2 * (
 *       C5  + ...
 *       C27 + x2 * C29
 *       )))
 *
 *   The coefficients correspond to the odd-order terms:
 *
 *       C1, C3, C5, ..., C29
 *
 *   The polynomial is evaluated from the highest-order coefficient toward
 *   the lowest-order coefficient using Horner's method.
 *
 * OPERATION FLOW:
 *
 *   1. Capture input x.
 *   2. Calculate x2 = x * x.
 *   3. Initialize Horner accumulator with C29.
 *   4. Repeatedly calculate:
 *
 *          p = x2 * p + Cn
 *
 *      for n = 27, 25, ..., 1.
 *
 *   5. Calculate:
 *
 *          result = x * p
 *
 *   6. Assert valid_out when the final result is available.
 *
 * INTERFACE:
 *
 *   clk        : System clock.
 *   rstn       : Active-low synchronous reset.
 *   valid_in   : Input transaction valid.
 *   op_a       : IEEE-754 double-precision input operand.
 *   result_out : IEEE-754 double-precision sine result.
 *   valid_out  : Output result valid.
 *
 * LATENCY:
 *
 *   Variable latency determined by the latency of the instantiated
 *   vrm_fpu_mul_64 and vrm_fpu_add_sub_64 units and the number of polynomial
 *   iterations.
 *
 * ============================================================================
 */

module vrm_fpu_sin_64 (
    input  wire        clk,
    input  wire        rstn,
    input  wire        valid_in,
    input  wire [63:0] op_a,

    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // FSM STATE DEFINITIONS
    // =========================================================================
    //
    // The FSM controls the sequential calculation of x^2, polynomial
    // evaluation, and the final multiplication by x.
    //

    localparam S_IDLE        = 4'd0;
    localparam S_MUL_X2      = 4'd1;
    localparam S_WAIT_X2     = 4'd2;
    localparam S_HORNER_INIT = 4'd3;
    localparam S_HORNER_MUL  = 4'd4;
    localparam S_WAIT_HMUL   = 4'd5;
    localparam S_HORNER_ADD  = 4'd6;
    localparam S_WAIT_HADD   = 4'd7;
    localparam S_FINAL_MUL   = 4'd8;
    localparam S_WAIT_FMUL   = 4'd9;

    reg [3:0] state;


    // =========================================================================
    // INTERNAL DATA REGISTERS
    // =========================================================================

    // Original input value.
    reg [63:0] x_in;

    // Squared input value:
    //
    //     x2 = x * x
    //
    reg [63:0] x2;

    // Horner polynomial accumulator.
    reg [63:0] p;

    // Polynomial coefficient index.
    //
    // The evaluation starts at C29 (index 14) and proceeds downward to
    // C1 (index 0).
    //
    reg [3:0] idx;


    // =========================================================================
    // SINE POLYNOMIAL COEFFICIENTS
    // =========================================================================
    //
    // The coefficients represent the odd-order terms of the sine polynomial:
    //
    //     C1, C3, C5, ..., C29
    //
    // They are defined in vrm_fpu_constants.vh.
    //

    wire [63:0] C [0:14];

    assign C[0]  = `SIN_C1;
    assign C[1]  = `SIN_C3;
    assign C[2]  = `SIN_C5;
    assign C[3]  = `SIN_C7;
    assign C[4]  = `SIN_C9;
    assign C[5]  = `SIN_C11;
    assign C[6]  = `SIN_C13;
    assign C[7]  = `SIN_C15;
    assign C[8]  = `SIN_C17;
    assign C[9]  = `SIN_C19;
    assign C[10] = `SIN_C21;
    assign C[11] = `SIN_C23;
    assign C[12] = `SIN_C25;
    assign C[13] = `SIN_C27;
    assign C[14] = `SIN_C29`;


    // =========================================================================
    // FLOATING-POINT MULTIPLIER
    // =========================================================================
    //
    // Shared multiplier used for:
    //
    //   1. x * x
    //   2. x2 * p during Horner evaluation
    //   3. x * p for the final result
    //
    // The multiplier is controlled through mul_valid.
    //

    reg         mul_valid;
    reg  [63:0] mul_a;
    reg  [63:0] mul_b;

    wire [63:0] mul_res;
    wire        mul_ready;

    vrm_fpu_mul_64 u_mul (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (mul_valid),
        .op_a      (mul_a),
        .op_b      (mul_b),
        .result_out(mul_res),
        .valid_out (mul_ready)
    );


    // =========================================================================
    // FLOATING-POINT ADDER / SUBTRACTOR
    // =========================================================================
    //
    // Used to add each polynomial coefficient during Horner evaluation:
    //
    //     p = x2 * p + Cn
    //
    // Only addition is used by this implementation.
    //

    reg         add_valid;
    reg         add_sub;
    reg  [63:0] add_a;
    reg  [63:0] add_b;

    wire [63:0] add_res;
    wire        add_ready;

    vrm_fpu_add_sub_64 u_add (
        .clk       (clk),
        .rstn      (rstn),
        .valid_in  (add_valid),
        .is_sub    (add_sub),
        .op_a      (add_a),
        .op_b      (add_b),
        .result_out(add_res),
        .valid_out (add_ready)
    );


    // =========================================================================
    // MAIN CONTROL FSM
    // =========================================================================

    always @(posedge clk) begin

        // ---------------------------------------------------------------------
        // Synchronous active-low reset
        // ---------------------------------------------------------------------

        if (!rstn) begin
            state     <= S_IDLE;
            valid_out <= 1'b0;
            mul_valid <= 1'b0;
            add_valid <= 1'b0;

        end else begin

            // -----------------------------------------------------------------
            // Default handshake values
            //
            // These signals are asserted for one cycle when a new operation is
            // submitted to the corresponding arithmetic unit.
            // -----------------------------------------------------------------

            valid_out <= 1'b0;
            mul_valid <= 1'b0;
            add_valid <= 1'b0;

            case (state)

                // =============================================================
                // IDLE
                // =============================================================
                //
                // Capture a new input transaction.
                //

                S_IDLE: begin
                    if (valid_in) begin
                        x_in <= op_a;
                        state <= S_MUL_X2;
                    end
                end


                // =============================================================
                // CALCULATE x^2
                // =============================================================
                //
                // Calculate:
                //
                //     x2 = x * x
                //

                S_MUL_X2: begin
                    mul_a     <= x_in;
                    mul_b     <= x_in;
                    mul_valid <= 1'b1;

                    state <= S_WAIT_X2;
                end


                // =============================================================
                // WAIT FOR x^2
                // =============================================================

                S_WAIT_X2: begin
                    if (mul_ready) begin
                        x2    <= mul_res;
                        state <= S_HORNER_INIT;
                    end
                end


                // =============================================================
                // INITIALIZE HORNER EVALUATION
                // =============================================================
                //
                // Start the polynomial from the highest-order coefficient:
                //
                //     p = C29
                //
                // The next coefficient is C27, corresponding to index 13.
                //

                S_HORNER_INIT: begin
                    p     <= C[14];
                    idx   <= 4'd13;
                    state <= S_HORNER_MUL;
                end


                // =============================================================
                // HORNER MULTIPLICATION
                // =============================================================
                //
                // Calculate:
                //
                //     p = x2 * p
                //

                S_HORNER_MUL: begin
                    mul_a     <= x2;
                    mul_b     <= p;
                    mul_valid <= 1'b1;

                    state <= S_WAIT_HMUL;
                end


                // =============================================================
                // WAIT FOR HORNER MULTIPLICATION
                // =============================================================

                S_WAIT_HMUL: begin
                    if (mul_ready) begin
                        p     <= mul_res;
                        state <= S_HORNER_ADD;
                    end
                end


                // =============================================================
                // HORNER ADDITION
                // =============================================================
                //
                // Add the current polynomial coefficient:
                //
                //     p = x2 * p + C[idx]
                //
                // The result is then either used for the next Horner iteration
                // or sent to the final multiplication stage.
                //

                S_HORNER_ADD: begin
                    add_a     <= C[idx];
                    add_b     <= p;
                    add_sub   <= 1'b0;
                    add_valid <= 1'b1;

                    state <= S_WAIT_HADD;
                end


                // =============================================================
                // WAIT FOR HORNER ADDITION
                // =============================================================

                S_WAIT_HADD: begin
                    if (add_ready) begin

                        // Preserve the latest polynomial result.
                        p <= add_res;

                        if (idx == 0) begin

                            // All polynomial coefficients have been processed.
                            state <= S_FINAL_MUL;

                        end else begin

                            // -------------------------------------------------
                            // Start the next Horner iteration immediately
                            // using the adder result directly.
                            //
                            // This avoids an unnecessary extra cycle between
                            // the addition and the next multiplication.
                            // -------------------------------------------------

                            mul_a     <= x2;
                            mul_b     <= add_res;
                            mul_valid <= 1'b1;

                            idx   <= idx - 1'b1;
                            state <= S_WAIT_HMUL;
                        end
                    end
                end


                // =============================================================
                // FINAL MULTIPLICATION
                // =============================================================
                //
                // After Horner evaluation:
                //
                //     p ≈ sin(x) / x
                //
                // Therefore:
                //
                //     result = x * p
                //

                S_FINAL_MUL: begin
                    mul_a     <= x_in;
                    mul_b     <= p;
                    mul_valid <= 1'b1;

                    state <= S_WAIT_FMUL;
                end


                // =============================================================
                // WAIT FOR FINAL RESULT
                // =============================================================

                S_WAIT_FMUL: begin
                    if (mul_ready) begin
                        result_out <= mul_res;
                        valid_out  <= 1'b1;

                        state <= S_IDLE;
                    end
                end


                // =============================================================
                // DEFAULT RECOVERY
                // =============================================================

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
