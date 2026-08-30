`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: vrm_fpu_math_64
 * DESCRIPTION:
 *   Top-level mathematical function dispatcher for the RV32D floating-point
 *   math extension.
 *
 *   This module routes each input operation to its corresponding dedicated
 *   mathematical function unit and multiplexes the returned result.
 *
 * FUNCTION SELECT:
 *   3'd0 : LOG2
 *   3'd1 : LN
 *   3'd2 : EXP2
 *   3'd3 : EXP
 *   3'd4 : SIGMOID
 *   3'd5 : TANH
 *   3'd6 : SIN
 *   3'd7 : COS
 *
 * ARCHITECTURE:
 *   - Eight independent mathematical function units.
 *   - Only the selected function unit receives a valid input pulse.
 *   - Each function unit operates independently according to its own
 *     internal latency.
 *   - The returned valid signal is used to select the corresponding result.
 * ============================================================================ */

module vrm_fpu_math_64 (
    input  wire        clk, rstn,
    input  wire [2:0]  func,
    input  wire        valid_in,
    input  wire [63:0] op_a,
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // FUNCTION UNIT OUTPUTS
    // =========================================================================
    // Each mathematical function unit provides an independent result and
    // valid signal.

    wire [63:0] res[0:7];
    wire        vld[0:7];

    // =========================================================================
    // FUNCTION ENABLE / DISPATCH LOGIC
    // =========================================================================
    // Generate a one-cycle enable for the function selected by 'func'.
    // Only the selected function unit receives valid_in.

    wire en0 = valid_in && (func == 3'd0);
    wire en1 = valid_in && (func == 3'd1);
    wire en2 = valid_in && (func == 3'd2);
    wire en3 = valid_in && (func == 3'd3);
    wire en4 = valid_in && (func == 3'd4);
    wire en5 = valid_in && (func == 3'd5);
    wire en6 = valid_in && (func == 3'd6);
    wire en7 = valid_in && (func == 3'd7);

    // =========================================================================
    // MATHEMATICAL FUNCTION UNITS
    // =========================================================================
    // Each function is implemented as a dedicated lower-level FPU module.

    vrm_fpu_log2_64    u0 (.clk(clk),.rstn(rstn),.valid_in(en0),.op_a(op_a),.result_out(res[0]),.valid_out(vld[0]));
    vrm_fpu_ln_64      u1 (.clk(clk),.rstn(rstn),.valid_in(en1),.op_a(op_a),.result_out(res[1]),.valid_out(vld[1]));
    vrm_fpu_exp2_64    u2 (.clk(clk),.rstn(rstn),.valid_in(en2),.op_a(op_a),.result_out(res[2]),.valid_out(vld[2]));
    vrm_fpu_exp_64     u3 (.clk(clk),.rstn(rstn),.valid_in(en3),.op_a(op_a),.result_out(res[3]),.valid_out(vld[3]));
    vrm_fpu_sigmoid_64 u4 (.clk(clk),.rstn(rstn),.valid_in(en4),.op_a(op_a),.result_out(res[4]),.valid_out(vld[4]));
    vrm_fpu_tanh_64    u5 (.clk(clk),.rstn(rstn),.valid_in(en5),.op_a(op_a),.result_out(res[5]),.valid_out(vld[5]));
    vrm_fpu_sin_64     u6 (.clk(clk),.rstn(rstn),.valid_in(en6),.op_a(op_a),.result_out(res[6]),.valid_out(vld[6]));
    vrm_fpu_cos_64     u7 (.clk(clk),.rstn(rstn),.valid_in(en7),.op_a(op_a),.result_out(res[7]),.valid_out(vld[7]));

    // =========================================================================
    // OUTPUT RESULT MULTIPLEXER
    // =========================================================================
    // Combine the valid signals from all function units.
    // The first active valid signal determines which result is forwarded.
    //
    // Since only one function unit is enabled for each input transaction,
    // normally only one vld signal is active at a time.

    always @(posedge clk) begin
        if (!rstn) begin
            valid_out <= 0;
            result_out <= 0;
        end else begin
            valid_out <= vld[0] | vld[1] | vld[2] | vld[3] | vld[4] | vld[5] | vld[6] | vld[7];

            if      (vld[0]) result_out <= res[0];
            else if (vld[1]) result_out <= res[1];
            else if (vld[2]) result_out <= res[2];
            else if (vld[3]) result_out <= res[3];
            else if (vld[4]) result_out <= res[4];
            else if (vld[5]) result_out <= res[5];
            else if (vld[6]) result_out <= res[6];
            else if (vld[7]) result_out <= res[7];
            else             result_out <= 64'd0;
        end
    end

endmodule
