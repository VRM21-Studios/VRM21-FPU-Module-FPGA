`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

// ============================================================================
// MODULE: vrm_fpu
// DESCRIPTION:
// Top-level floating-point processing unit for the VRM FPU.
//
// The module receives two 64-bit operands together with an operation selector
// and dispatches each operation to the corresponding functional lane.
//
// Pipeline structure:
// - Stage 0 : Input registration and operation dispatch
// - Functional lanes : Parallel operation processing
// - Output stage : Result selection and registration
//
// Functional lanes:
// - Lane A    : Floating-point addition and subtraction
// - Lane B    : Floating-point multiplication
// - Lane C    : Floating-point division
// - Lane D    : Floating-point square root
// - Lane E    : Floating-point conversion
// - Lane F    : Miscellaneous floating-point operations
// - Lane MATH : Transcendental mathematical functions
//
// The functional lanes operate independently and are enabled according to
// the operation code captured in Stage 0.
//
// INPUT:
// - valid_in : Input transaction valid
// - fpu_op   : Functional operation selector
// - funct3   : Sub-operation selector for applicable functional lanes
// - op_a     : Primary 64-bit operand
// - op_b     : Secondary 64-bit operand
//
// OUTPUT:
// - result_out : 64-bit operation result
// - valid_out  : Result valid indication
// ============================================================================

module vrm_fpu (
    input  wire        clk,
    input  wire        rstn,
    input  wire        valid_in,
    input  wire [3:0]  fpu_op,
    input  wire [2:0]  funct3,
    input  wire [63:0] op_a,
    input  wire [63:0] op_b,
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // 1. INPUT PIPELINE REGISTER
    // =========================================================================

    // Stage 0 registers capture the input transaction before operation
    // dispatch to the functional lanes.
    reg        s0_valid;
    reg [3:0]  s0_op;
    reg [2:0]  s0_f3;
    reg [63:0] s0_a, s0_b;

    always @(posedge clk) begin
        if (!rstn) begin
            s0_valid <= 1'b0;
            s0_op    <= 4'd0;
            s0_f3    <= 3'd0;
            s0_a     <= 64'd0;
            s0_b     <= 64'd0;
        end else begin
            s0_valid <= valid_in;
            s0_op    <= fpu_op;
            s0_f3    <= funct3;
            s0_a     <= op_a;
            s0_b     <= op_b;
        end
    end

    // =========================================================================
    // 2. FUNCTIONAL LANE ENABLE
    // =========================================================================

    // Each enable signal activates the functional lane associated with the
    // selected operation code.
    wire en_a = s0_valid && (s0_op == 4'd0 || s0_op == 4'd1);
    wire en_b = s0_valid && (s0_op == 4'd2);
    wire en_c = s0_valid && (s0_op == 4'd3);
    wire en_d = s0_valid && (s0_op == 4'd4);
    wire en_e = s0_valid && (s0_op == 4'd5 || s0_op == 4'd6);
    wire en_f = s0_valid && (s0_op == 4'd7);
    wire en_math = s0_valid && (s0_op == 4'd8);

    // =========================================================================
    // 3. FUNCTIONAL LANE OUTPUTS
    // =========================================================================

    // Each functional lane provides an independent result and valid signal.
    wire [63:0] res_a, res_b, res_c, res_d, res_e, res_f, res_math;
    wire        vld_a, vld_b, vld_c, vld_d, vld_e, vld_f, vld_math;

    // =========================================================================
    // 4. FUNCTIONAL LANES
    // =========================================================================

    // -------------------------------------------------------------------------
    // Lane A: Floating-Point Addition / Subtraction
    // -------------------------------------------------------------------------
    vrm_fpu_add_sub_64 lane_a (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_a),
        .is_sub     (s0_op[0]),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_a),
        .valid_out  (vld_a)
    );

    // -------------------------------------------------------------------------
    // Lane B: Floating-Point Multiplication
    // -------------------------------------------------------------------------
    vrm_fpu_mul_64 lane_b (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_b),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_b),
        .valid_out  (vld_b)
    );

    // -------------------------------------------------------------------------
    // Lane C: Floating-Point Division
    // -------------------------------------------------------------------------
    vrm_fpu_div_64 lane_c (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_c),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_c),
        .valid_out  (vld_c)
    );

    // -------------------------------------------------------------------------
    // Lane D: Floating-Point Square Root
    // -------------------------------------------------------------------------
    vrm_fpu_sqrt_64 lane_d (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_d),
        .op_a       (s0_a),
        .result_out (res_d),
        .valid_out  (vld_d)
    );

    // -------------------------------------------------------------------------
    // Lane E: Floating-Point Conversion
    // -------------------------------------------------------------------------
    wire [1:0] conv_mode = (s0_op == 4'd6) ? 2'b10 : 2'b00;

    vrm_fpu_conv_64 lane_e (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_e),
        .conv_op    (conv_mode),
        .op_a       (s0_a),
        .result_out (res_e),
        .valid_out  (vld_e)
    );

    // -------------------------------------------------------------------------
    // Lane F: Miscellaneous Floating-Point Operations
    // -------------------------------------------------------------------------
    vrm_fpu_misc_64 lane_f (
        .clk        (clk),
        .rstn       (rstn),
        .valid_in   (en_f),
        .misc_op    (s0_f3),
        .op_a       (s0_a),
        .op_b       (s0_b),
        .result_out (res_f),
        .valid_out  (vld_f)
    );

    // -------------------------------------------------------------------------
    // Lane MATH: Transcendental Mathematical Functions
    // -------------------------------------------------------------------------
    vrm_fpu_math_64 lane_math (
        .clk        (clk),
        .rstn       (rstn),
        .func       (s0_f3),
        .valid_in   (en_math),
        .op_a       (s0_a),
        .result_out (res_math),
        .valid_out  (vld_math)
    );

    // =========================================================================
    // 5. OUTPUT RESULT SELECTION
    // =========================================================================

    // The functional lane valid signals are combined to generate the output
    // valid indication. When multiple lanes are valid simultaneously, the
    // selection priority follows the lane order defined below.
    always @(posedge clk) begin
        if (!rstn) begin
            valid_out  <= 1'b0;
            result_out <= 64'd0;
        end else begin
            valid_out <= vld_a || vld_b || vld_c || vld_d || vld_e || vld_f || vld_math;

            if (vld_a)      result_out <= res_a;
            else if (vld_b) result_out <= res_b;
            else if (vld_c) result_out <= res_c;
            else if (vld_d) result_out <= res_d;
            else if (vld_e) result_out <= res_e;
            else if (vld_f) result_out <= res_f;
            else if (vld_math) result_out <= res_math;
            else            result_out <= 64'd0;
        end
    end

endmodule
