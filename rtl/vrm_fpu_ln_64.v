`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_ln_64
 * DESCRIPTION:
 * Fully synchronous FP64 natural logarithm unit for RV32D/RV64D FPU support.
 *
 * The natural logarithm is computed using the identity:
 *
 *     ln(x) = log2(x) * ln(2)
 *
 * The module uses vrm_fpu_log2_64 as the first computational stage, followed
 * by an FP64 multiplication with the constant ln(2).
 *
 * OPERATION:
 *     Input  -> FP64 log2 -> FP64 multiply by ln(2) -> Output
 *
 * LATENCY:
 *     Determined by the latency of vrm_fpu_log2_64 plus the latency of
 *     vrm_fpu_mul_64 and the control sequencing between both units.
 *
 * INTERFACE:
 *     valid_in   : Input transaction valid
 *     op_a       : FP64 input operand
 *     result_out : FP64 natural logarithm result
 *     valid_out  : Output transaction valid
 *
 * DEPENDENCIES:
 *     - vrm_fpu_constants.vh
 *     - vrm_fpu_log2_64
 *     - vrm_fpu_mul_64
 *
 * NOTES:
 *     - The module is fully synchronous.
 *     - Internal arithmetic is performed using FP64 datapaths.
 *     - The ln(2) constant is provided through vrm_fpu_constants.vh.
 * ============================================================================ */

module vrm_fpu_ln_64 (
    input  wire        clk, rstn, valid_in,
    input  wire [63:0] op_a,
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // Natural Logarithm Constant
    // =========================================================================
    // ln(x) = log2(x) * ln(2)
    localparam FP_LN2 = `FP64_LN2;

    // =========================================================================
    // Stage 1: Base-2 Logarithm
    // =========================================================================
    // The input is first processed by the FP64 log2 unit.
    wire [63:0] log2_res;
    wire        log2_done;

    vrm_fpu_log2_64 u_log2 (
        .clk(clk), .rstn(rstn), .valid_in(valid_in),
        .op_a(op_a), .result_out(log2_res), .valid_out(log2_done)
    );

    // =========================================================================
    // Stage 2: Multiply by ln(2)
    // =========================================================================
    // Convert log2(x) into ln(x) using:
    //     ln(x) = log2(x) * ln(2)
    reg         mul_start;
    wire [63:0] mul_res;
    wire        mul_done;

    vrm_fpu_mul_64 u_mul (
        .clk(clk), .rstn(rstn), .valid_in(mul_start),
        .op_a(log2_res), .op_b(FP_LN2), .result_out(mul_res), .valid_out(mul_done)
    );

    // =========================================================================
    // Control State Machine
    // =========================================================================
    reg [1:0] state;

    localparam S_IDLE      = 0;
    localparam S_WAIT_LOG2 = 1;
    localparam S_MUL       = 2;

    // =========================================================================
    // Sequential Control Logic
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
            valid_out <= 0;
            mul_start <= 0;
        end else begin
            valid_out <= 0;
            mul_start <= 0;

            case (state)

                // -----------------------------------------------------------------
                // S_IDLE:
                // Wait for a new input transaction.
                // -----------------------------------------------------------------
                S_IDLE:
                    if (valid_in)
                        state <= S_WAIT_LOG2;

                // -----------------------------------------------------------------
                // S_WAIT_LOG2:
                // Wait for the FP64 log2 unit to complete.
                // Once the result is available, start the multiplication
                // with ln(2).
                // -----------------------------------------------------------------
                S_WAIT_LOG2:
                    if (log2_done) begin
                        mul_start <= 1;
                        state <= S_MUL;
                    end

                // -----------------------------------------------------------------
                // S_MUL:
                // Wait for the final FP64 multiplication result.
                // -----------------------------------------------------------------
                S_MUL:
                    if (mul_done) begin
                        result_out <= mul_res;
                        valid_out <= 1;
                        state <= S_IDLE;
                    end

                // -----------------------------------------------------------------
                // Default recovery state.
                // -----------------------------------------------------------------
                default:
                    state <= S_IDLE;

            endcase
        end
    end

endmodule
