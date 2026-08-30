`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_cos_64
 * DESCRIPTION:
 *   Double-precision cosine function unit for the RV32D/RV64D FPU.
 *
 *   The cosine function is approximated using an even polynomial:
 *
 *       cos(x) = C0 + C2*x^2 + C4*x^4 + ... + C28*x^28
 *
 *   The polynomial is evaluated using Horner's method:
 *
 *       cos(x) = C0 + x^2(C2 + x^2(C4 + ... + x^2*C28))
 *
 *   The implementation reuses a single floating-point multiplier and
 *   floating-point adder/subtractor. This reduces hardware resources at the
 *   cost of increased execution latency.
 *
 * OPERATION:
 *   1. Capture the input operand.
 *   2. Calculate x^2.
 *   3. Initialize the Horner polynomial with the highest-order coefficient.
 *   4. Iteratively multiply by x^2 and add the next coefficient.
 *   5. The final accumulated value is the cosine result.
 *
 * LATENCY:
 *   Variable / multi-cycle.
 *   The exact latency depends on the latency of vrm_fpu_mul_64 and
 *   vrm_fpu_add_sub_64.
 *
 * INTERFACE:
 *   valid_in  : Input transaction request.
 *   valid_out : Indicates that result_out contains a valid result.
 *
 * NOTES:
 *   - Input and output use IEEE-754 double-precision (64-bit) format.
 *   - Polynomial coefficients are provided by vrm_fpu_constants.vh.
 *   - No explicit argument reduction is performed in this module.
 *   - The multiplier and adder are time-shared across all polynomial stages.
 * ============================================================================ */

module vrm_fpu_cos_64 (
    input  wire        clk,
    input  wire        rstn,
    input  wire        valid_in,
    input  wire [63:0] op_a,

    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // STATE MACHINE
    // =========================================================================
    //
    // The FSM controls the sequential Horner evaluation:
    //
    //   IDLE
    //     |
    //     v
    //   x^2 calculation
    //     |
    //     v
    //   Horner initialization
    //     |
    //     v
    //   multiply by x^2
    //     |
    //     v
    //   add next coefficient
    //     |
    //     +---- repeat until coefficient C0
    //     |
    //     v
    //   output result
    //
    localparam S_IDLE        = 4'd0;
    localparam S_MUL_X2      = 4'd1;
    localparam S_WAIT_X2     = 4'd2;
    localparam S_HORNER_INIT = 4'd3;
    localparam S_HORNER_MUL  = 4'd4;
    localparam S_WAIT_HMUL   = 4'd5;
    localparam S_HORNER_ADD  = 4'd6;
    localparam S_WAIT_HADD   = 4'd7;

    reg [3:0] state;

    // =========================================================================
    // INTERNAL DATA REGISTERS
    // =========================================================================

    // Original input operand.
    reg [63:0] x_in;

    // Squared input: x^2.
    reg [63:0] x2;

    // Current Horner accumulator.
    reg [63:0] p;

    // Current polynomial coefficient index.
    //
    // C[14] corresponds to the highest-order term C28.
    // The index decreases toward C[0], which corresponds to C0.
    reg [3:0] idx;

    // =========================================================================
    // COSINE POLYNOMIAL COEFFICIENTS
    // =========================================================================
    //
    // The coefficient table maps:
    //
    //   C[0]  -> C0
    //   C[1]  -> C2
    //   C[2]  -> C4
    //   ...
    //   C[14] -> C28
    //
    // The coefficients are defined in vrm_fpu_constants.vh.
    //
    wire [63:0] C [0:14];

    assign C[0]  = `COS_C0;
    assign C[1]  = `COS_C2;
    assign C[2]  = `COS_C4;
    assign C[3]  = `COS_C6;
    assign C[4]  = `COS_C8;
    assign C[5]  = `COS_C10;
    assign C[6]  = `COS_C12;
    assign C[7]  = `COS_C14;
    assign C[8]  = `COS_C16;
    assign C[9]  = `COS_C18;
    assign C[10] = `COS_C20;
    assign C[11] = `COS_C22;
    assign C[12] = `COS_C24;
    assign C[13] = `COS_C26;
    assign C[14] = `COS_C28;

    // =========================================================================
    // SHARED FLOATING-POINT MULTIPLIER
    // =========================================================================
    //
    // The same multiplier is reused for:
    //
    //   1. x * x
    //   2. x^2 * p
    //
    // This saves hardware resources compared with instantiating separate
    // multipliers for each operation.
    //
    reg        mul_valid;
    reg [63:0] mul_a;
    reg [63:0] mul_b;

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
    // SHARED FLOATING-POINT ADDER
    // =========================================================================
    //
    // Used to add each polynomial coefficient to the current Horner product.
    //
    // Since only addition is required here, add_sub is always driven low
    // when a transaction is issued.
    //
    reg        add_valid;
    reg        add_sub;
    reg [63:0] add_a;
    reg [63:0] add_b;

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
        if (!rstn) begin

            // -----------------------------------------------------------------
            // Reset state and control signals.
            // -----------------------------------------------------------------
            state     <= S_IDLE;
            valid_out <= 1'b0;
            mul_valid <= 1'b0;
            add_valid <= 1'b0;

        end else begin

            // -----------------------------------------------------------------
            // Pulse-based request signals.
            //
            // Each operation is asserted for one cycle only. The FSM then
            // waits for the corresponding valid_out signal from the
            // arithmetic unit.
            // -----------------------------------------------------------------
            valid_out <= 1'b0;
            mul_valid <= 1'b0;
            add_valid <= 1'b0;

            case (state)

                // =============================================================
                // IDLE
                // =============================================================
                //
                // Accept a new input transaction.
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
                // First multiplication:
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
                // WAIT FOR x^2 RESULT
                // =============================================================
                //
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
                // Start from the highest-order coefficient:
                //
                //     p = C28
                //
                // The next iteration will process C26.
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
                // Evaluate:
                //
                //     p = x^2 * p
                //
                // This is the multiplication stage of Horner's method.
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
                //
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
                // Add the current coefficient:
                //
                //     p = p + C[idx]
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
                //
                // The adder result is used directly as the accumulator for
                // the next Horner iteration.
                //
                // This avoids waiting for another clock cycle just to copy
                // add_res into p before issuing the next multiplication.
                //
                S_WAIT_HADD: begin
                    if (add_ready) begin
                        p <= add_res;

                        if (idx == 0) begin

                            // -------------------------------------------------
                            // Final coefficient C0 has been added.
                            //
                            // The result of the addition is already the final
                            // cosine value, so no additional multiplication
                            // is required.
                            // -------------------------------------------------
                            result_out <= add_res;
                            valid_out  <= 1'b1;

                            state <= S_IDLE;

                        end else begin

                            // -------------------------------------------------
                            // Continue Horner evaluation.
                            //
                            // Use add_res directly as the next multiplier
                            // operand rather than waiting for p to update.
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
                // DEFAULT
                // =============================================================
                //
                // Recover to a known state if the FSM ever enters an invalid
                // state.
                //
                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
