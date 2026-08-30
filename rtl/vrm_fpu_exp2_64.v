`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_exp2_64
 * DESCRIPTION:
 * FP64 base-2 exponential unit for RV32D/RV64D FPU support.
 *
 * The function computes:
 *
 *     2^x = 2^n * 2^f
 *
 * where:
 *
 *     n = trunc(x)
 *     f = x - n
 *
 * The fractional component is evaluated using a polynomial approximation,
 * while the integer component is converted into an FP64 power-of-two value.
 *
 * OPERATION:
 *     Input
 *       |
 *       +--> Float-to-Integer --> n
 *       |
 *       +--> Integer-to-Float --> n_float
 *       |
 *       +--> f = x - n_float
 *       |
 *       +--> Polynomial Approximation of 2^f
 *       |
 *       +--> 2^n * Polynomial Result
 *       |
 *     Output
 *
 * PIPELINE / CONTROL:
 *     The unit is controlled by a sequential FSM and uses the shared
 *     FP64 multiplication, addition/subtraction, and conversion units.
 *
 * STREAMING SAFETY:
 *     The integer component n_r is captured internally before subsequent
 *     arithmetic stages. This prevents the integer portion of a transaction
 *     from being overwritten by a later transaction while the polynomial
 *     computation is still in progress.
 *
 * DEPENDENCIES:
 *     - vrm_fpu_constants.vh
 *     - vrm_fpu_mul_64
 *     - vrm_fpu_add_sub_64
 *     - vrm_fpu_float_to_int_64
 *     - vrm_fpu_conv_64
 *
 * NOTES:
 *     - Input and output operands use IEEE-754 FP64 representation.
 *     - Polynomial coefficients are provided through vrm_fpu_constants.vh.
 *     - The implementation uses a sequential FSM rather than a fully
 *       combinational datapath.
 * ============================================================================ */

module vrm_fpu_exp2_64 (
    input  wire        clk, rstn, valid_in,
    input  wire [63:0] op_a,
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // FP64 Constants
    // =========================================================================
    localparam FP_ONE = `FP64_ONE;

    // =========================================================================
    // Control State Definitions
    // =========================================================================
    localparam S_IDLE        = 5'd0;
    localparam S_F2I         = 5'd1;
    localparam S_I2F_START   = 5'd2;
    localparam S_WAIT_I2F    = 5'd3;
    localparam S_SUB_F       = 5'd4;
    localparam S_WAIT_SUB    = 5'd5;
    localparam S_POLY_INIT   = 5'd6;
    localparam S_POLY_MUL    = 5'd7;
    localparam S_WAIT_MUL    = 5'd8;
    localparam S_POLY_ADD    = 5'd9;
    localparam S_WAIT_ADD    = 5'd10;
    localparam S_MUL_2N      = 5'd11;
    localparam S_WAIT_MUL2N  = 5'd12;

    reg [4:0] state;

    // =========================================================================
    // FP64 Multiplication Unit
    // =========================================================================
    reg         mul_valid;
    reg  [63:0] mul_a, mul_b;
    wire [63:0] mul_res;
    wire        mul_ready;

    vrm_fpu_mul_64 u_mul (
        .clk(clk), .rstn(rstn), .valid_in(mul_valid),
        .op_a(mul_a), .op_b(mul_b), .result_out(mul_res), .valid_out(mul_ready)
    );

    // =========================================================================
    // FP64 Addition / Subtraction Unit
    // =========================================================================
    reg         add_valid, add_sub;
    reg  [63:0] add_a, add_b;
    wire [63:0] add_res;
    wire        add_ready;

    vrm_fpu_add_sub_64 u_add (
        .clk(clk), .rstn(rstn), .valid_in(add_valid), .is_sub(add_sub),
        .op_a(add_a), .op_b(add_b), .result_out(add_res), .valid_out(add_ready)
    );

    // =========================================================================
    // Float-to-Integer Conversion
    // =========================================================================
    // Extract the integer component n from the input x.
    wire [31:0] n_int;

    vrm_fpu_float_to_int_64 f2i (
        .clk(clk), .rstn(rstn), .valid_in(1'b1),
        .float_in(op_a), .int_out(n_int), .valid_out()
    );

    // =========================================================================
    // Internal Data Registers
    // =========================================================================
    // n_r      : Captured integer component of x.
    // x_reg    : Original FP64 input.
    // n_float  : FP64 representation of n_r.
    // f        : Fractional component, f = x - n.
    // p        : Polynomial accumulator.
    reg [31:0] n_r;
    reg [63:0] x_reg, n_float, f, p;
    reg [3:0]  poly_idx;

    // =========================================================================
    // Polynomial Coefficient Table
    // =========================================================================
    // Coefficients for the approximation of 2^f.
    wire [63:0] coeff [0:14];

    assign coeff[0]  = `EXP2_C0;
    assign coeff[1]  = `EXP2_C1;
    assign coeff[2]  = `EXP2_C2;
    assign coeff[3]  = `EXP2_C3;
    assign coeff[4]  = `EXP2_C4;
    assign coeff[5]  = `EXP2_C5;
    assign coeff[6]  = `EXP2_C6;
    assign coeff[7]  = `EXP2_C7;
    assign coeff[8]  = `EXP2_C8;
    assign coeff[9]  = `EXP2_C9;
    assign coeff[10] = `EXP2_C10;
    assign coeff[11] = `EXP2_C11;
    assign coeff[12] = `EXP2_C12;
    assign coeff[13] = `EXP2_C13;
    assign coeff[14] = `EXP2_C14;

    // =========================================================================
    // Integer-to-FP64 Conversion
    // =========================================================================
    // Convert the captured integer component n_r into FP64 format.
    reg         conv_start;
    wire [63:0] conv_res;
    wire        conv_done;

    vrm_fpu_conv_64 i_conv (
        .clk(clk), .rstn(rstn), .valid_in(conv_start),
        .conv_op(2'b00),
        .op_a({32'd0, n_r}),
        .result_out(conv_res), .valid_out(conv_done)
    );

    // =========================================================================
    // Main Control FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
            valid_out <= 0;
            mul_valid <= 0;
            add_valid <= 0;
            conv_start <= 0;
        end else begin
            // Default pulse signals are deasserted every cycle.
            valid_out <= 0;
            mul_valid <= 0;
            add_valid <= 0;
            conv_start <= 0;

            case (state)

                // -----------------------------------------------------------------
                // Wait for a new input transaction.
                // -----------------------------------------------------------------
                S_IDLE:
                    if (valid_in) begin
                        x_reg <= op_a;
                        state <= S_F2I;
                    end

                // -----------------------------------------------------------------
                // Capture the integer component of the input.
                // -----------------------------------------------------------------
                S_F2I: begin
                    n_r <= n_int;
                    state <= S_I2F_START;
                end

                // -----------------------------------------------------------------
                // Start conversion of n_r from integer to FP64.
                // -----------------------------------------------------------------
                S_I2F_START: begin
                    conv_start <= 1;
                    state <= S_WAIT_I2F;
                end

                // -----------------------------------------------------------------
                // Wait for the integer-to-FP64 conversion result.
                // -----------------------------------------------------------------
                S_WAIT_I2F:
                    if (conv_done) begin
                        n_float <= conv_res;
                        state <= S_SUB_F;
                    end

                // -----------------------------------------------------------------
                // Calculate the fractional component:
                //
                //     f = x - n
                // -----------------------------------------------------------------
                S_SUB_F: begin
                    add_a <= x_reg;
                    add_b <= n_float;
                    add_sub <= 1;
                    add_valid <= 1;
                    state <= S_WAIT_SUB;
                end

                // -----------------------------------------------------------------
                // Wait for the fractional component calculation.
                // -----------------------------------------------------------------
                S_WAIT_SUB:
                    if (add_ready) begin
                        f <= add_res;
                        state <= S_POLY_INIT;
                    end

                // -----------------------------------------------------------------
                // Initialize the polynomial using the highest-order
                // coefficient.
                // -----------------------------------------------------------------
                S_POLY_INIT: begin
                    p <= coeff[14];
                    poly_idx <= 13;
                    state <= S_POLY_MUL;
                end

                // -----------------------------------------------------------------
                // Polynomial multiplication:
                //
                //     p = f * p
                // -----------------------------------------------------------------
                S_POLY_MUL: begin
                    mul_a <= f;
                    mul_b <= p;
                    mul_valid <= 1;
                    state <= S_WAIT_MUL;
                end

                // -----------------------------------------------------------------
                // Wait for the polynomial multiplication result.
                // -----------------------------------------------------------------
                S_WAIT_MUL:
                    if (mul_ready) begin
                        p <= mul_res;
                        state <= S_POLY_ADD;
                    end

                // -----------------------------------------------------------------
                // Add the next polynomial coefficient:
                //
                //     p = coefficient + p
                // -----------------------------------------------------------------
                S_POLY_ADD: begin
                    add_a <= coeff[poly_idx];
                    add_b <= p;
                    add_sub <= 0;
                    add_valid <= 1;
                    state <= S_WAIT_ADD;
                end

                // -----------------------------------------------------------------
                // Wait for the polynomial addition result.
                // -----------------------------------------------------------------
                S_WAIT_ADD:
                    if (add_ready) begin
                        p <= add_res;

                        if (poly_idx == 0)
                            state <= S_MUL_2N;
                        else begin
                            // Use the addition result directly for the next
                            // polynomial multiplication.
                            mul_a <= f;
                            mul_b <= add_res;
                            mul_valid <= 1;
                            poly_idx <= poly_idx - 1;
                            state <= S_WAIT_MUL;
                        end
                    end

                // -----------------------------------------------------------------
                // Multiply the fractional polynomial result by 2^n.
                // The exponent field is constructed directly from n_r.
                // -----------------------------------------------------------------
                S_MUL_2N: begin
                    mul_a <= {1'b0, 11'd1023 + n_r[10:0], 52'd0};
                    mul_b <= p;
                    mul_valid <= 1;
                    state <= S_WAIT_MUL2N;
                end

                // -----------------------------------------------------------------
                // Wait for the final multiplication result and present it
                // at the output.
                // -----------------------------------------------------------------
                S_WAIT_MUL2N:
                    if (mul_ready) begin
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
