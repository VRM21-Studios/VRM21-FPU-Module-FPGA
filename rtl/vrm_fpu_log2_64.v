`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: vrm_fpu_log2_64
 * DESCRIPTION:
 *   Double-precision floating-point base-2 logarithm unit for RV32D.
 *
 *   Computes:
 *       log2(x)
 *
 *   The implementation uses:
 *     - IEEE 754 FP64 unpacking
 *     - Integer exponent extraction
 *     - Integer-to-double conversion
 *     - Mantissa reduction to the form 1 + y
 *     - Taylor polynomial approximation of log2(1 + y)
 *     - Pipelined FP64 multiplication and addition/subtraction units
 *
 * SPECIAL CASES:
 *   NaN       -> NaN
 *   +0.0      -> -Infinity
 *   +Infinity -> +Infinity
 *   Negative  -> NaN
 *
 * POLYNOMIAL:
 *   log2(1 + y) is approximated using a 14th-order Taylor polynomial.
 *
 *   The polynomial is evaluated using Horner's method:
 *
 *       P(y) = C0 + y(C1 + y(C2 + ... + y*C14))
 *
 * ============================================================================ */

module vrm_fpu_log2_64 (
    input  wire        clk, rstn, valid_in,
    input  wire [63:0] op_a,
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // LOCAL CONSTANTS
    // =========================================================================
    // FP_ONE represents the IEEE 754 double-precision value 1.0.
    //
    // These constants are intentionally hard-coded in this module so that
    // the implementation does not depend on values defined in the header.

    localparam FP_ONE = 64'h3FF0_0000_0000_0000;

    // =========================================================================
    // TAYLOR POLYNOMIAL COEFFICIENTS
    // =========================================================================
    // Coefficients for the approximation of:
    //
    //     log2(1 + y)
    //
    // using a 14th-order Taylor polynomial.
    //
    // The coefficients are represented directly as IEEE 754 FP64 constants.

    localparam C0  = 64'h0000_0000_0000_0000;   //  0
    localparam C1  = 64'h3FF7_1547_652B_82FE;   // +1.4426950408889634
    localparam C2  = 64'hBFE7_1547_652B_82FE;   // -0.7213475204444817
    localparam C3  = 64'h3FDE_CA5B_4387_588B;   // +0.4808983469629878
    localparam C4  = 64'hBFD7_1547_652B_82FE;   // -0.36067376022224085
    localparam C5  = 64'h3FD2_A14D_112E_0B02;   // +0.2885390081777927
    localparam C6  = 64'hBFCE_CA5B_4387_588B;   // -0.2404491734814939
    localparam C7  = 64'h3FC8_E38E_E38E_38E4;   // +0.20609929155528038
    localparam C8  = 64'hBFC5_1547_652B_82FE;   // -0.18033688011112042
    localparam C9  = 64'h3FC1_DE7A_3D73_6BD3;   // +0.1602994489876626
    localparam C10 = 64'hBFBE_CA5B_4387_588B;   // -0.14426950408889635
    localparam C11 = 64'h3FBA_5E03_827C_2C7B;   // +0.1311540946262694
    localparam C12 = 64'hBFBC_CA5B_4387_588B;   // -0.12022458674074695
    localparam C13 = 64'h3FB4_9F1B_53C5_A5E3;   // +0.11097654160684334
    localparam C14 = 64'hBFB2_502B_502B_502C;   // -0.10304964577764019

    // =========================================================================
    // COEFFICIENT ARRAY
    // =========================================================================
    // Coefficients are arranged using indices 0 through 14 so they can be
    // accessed sequentially by the polynomial evaluation state machine.

    wire [63:0] coeff [0:14];

    assign coeff[0]  = C0;
    assign coeff[1]  = C1;
    assign coeff[2]  = C2;
    assign coeff[3]  = C3;
    assign coeff[4]  = C4;
    assign coeff[5]  = C5;
    assign coeff[6]  = C6;
    assign coeff[7]  = C7;
    assign coeff[8]  = C8;
    assign coeff[9]  = C9;
    assign coeff[10] = C10;
    assign coeff[11] = C11;
    assign coeff[12] = C12;
    assign coeff[13] = C13;
    assign coeff[14] = C14;

    // =========================================================================
    // STATE MACHINE
    // =========================================================================
    // The FSM sequences the conversion, mantissa reduction, polynomial
    // evaluation, and final exponent addition.

    localparam S_IDLE        = 5'd0;
    localparam S_UNPACK      = 5'd1;
    localparam S_I2F_START   = 5'd2;
    localparam S_WAIT_I2F    = 5'd3;
    localparam S_BUILD_Y     = 5'd4;
    localparam S_WAIT_SUB_Y  = 5'd5;
    localparam S_POLY_INIT   = 5'd6;
    localparam S_POLY_MUL    = 5'd7;
    localparam S_WAIT_MUL    = 5'd8;
    localparam S_POLY_ADD    = 5'd9;
    localparam S_WAIT_ADD    = 5'd10;
    localparam S_FINAL_ADD   = 5'd11;
    localparam S_WAIT_FINAL  = 5'd12;

    reg [4:0] state;

    // =========================================================================
    // INPUT UNPACKING
    // =========================================================================
    // Extract the sign, exponent, mantissa, and special-value indicators
    // from the input FP64 operand.

    wire sign_a, zero_a, inf_a, nan_a;
    wire [10:0] exp_a;
    wire [52:0] mant_a;

    vrm_fpu_unpacker_64 unpack (
        .fp_in(op_a), .sign(sign_a), .exp(exp_a), .mantissa(mant_a),
        .is_zero(zero_a), .is_inf(inf_a), .is_nan(nan_a),
        .is_subnormal(), .is_snan(), .is_qnan()
    );

    // =========================================================================
    // EXPONENT EXTRACTION
    // =========================================================================
    // Convert the biased FP64 exponent into a signed integer exponent:
    //
    //     e_int = exp_a - 1023
    //
    // The 32-bit sign-extended version is used by the integer-to-double
    // conversion unit.

    wire signed [11:0] e_int = {1'b0, exp_a} - 12'd1023;
    wire [31:0] e_int_32 = {{20{e_int[11]}}, e_int};

    // =========================================================================
    // FP64 MULTIPLIER INTERFACE
    // =========================================================================
    // Shared multiplier used during Horner polynomial evaluation.

    reg         mul_valid;
    reg  [63:0] mul_a, mul_b;
    wire [63:0] mul_res;
    wire        mul_ready;

    vrm_fpu_mul_64 u_mul (
        .clk(clk), .rstn(rstn), .valid_in(mul_valid),
        .op_a(mul_a), .op_b(mul_b), .result_out(mul_res), .valid_out(mul_ready)
    );

    // =========================================================================
    // FP64 ADDER / SUBTRACTOR INTERFACE
    // =========================================================================
    // Shared adder/subtractor used to construct y, accumulate polynomial
    // coefficients, and combine the final exponent term.

    reg         add_valid, add_sub;
    reg  [63:0] add_a, add_b;
    wire [63:0] add_res;
    wire        add_ready;

    vrm_fpu_add_sub_64 u_add (
        .clk(clk), .rstn(rstn), .valid_in(add_valid), .is_sub(add_sub),
        .op_a(add_a), .op_b(add_b), .result_out(add_res), .valid_out(add_ready)
    );

    // =========================================================================
    // INTERNAL REGISTERS
    // =========================================================================
    // x_reg stores the original input.
    // e_float stores the converted integer exponent as FP64.
    // y represents the reduced mantissa term:
    //
    //     y = mantissa - 1
    //
    // p stores the current Horner polynomial result.

    reg [63:0] x_reg, e_float, y, p;

    // Polynomial index runs from coefficient C13 down to C0 after
    // initialization with C14.

    reg [3:0] poly_idx;

    // =========================================================================
    // INTEGER-TO-DOUBLE CONVERSION INTERFACE
    // =========================================================================
    // Convert the extracted signed integer exponent into FP64.

    reg         conv_start;
    wire [63:0] conv_res;
    wire        conv_done;

    vrm_fpu_conv_64 i_conv (
        .clk(clk), .rstn(rstn), .valid_in(conv_start),
        .conv_op(2'b00),
        .op_a({32'd0, e_int_32}),
        .result_out(conv_res), .valid_out(conv_done)
    );

    // =========================================================================
    // MAIN CONTROL FSM
    // =========================================================================

    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
            valid_out <= 0;
            mul_valid <= 0;
            add_valid <= 0;
            conv_start <= 0;
        end else begin

            // Default handshake signals are deasserted every cycle.
            // Individual states assert them only when a new operation
            // needs to be launched.

            valid_out <= 0;
            mul_valid <= 0;
            add_valid <= 0;
            conv_start <= 0;

            case (state)

                // =================================================================
                // IDLE
                // =================================================================
                // Wait for a valid input transaction.

                S_IDLE:
                    if (valid_in) begin
                        x_reg <= op_a;
                        state <= S_UNPACK;
                    end

                // =================================================================
                // INPUT VALIDATION
                // =================================================================
                // Handle IEEE 754 special cases before starting the normal
                // logarithm calculation.

                S_UNPACK: begin
                    if (nan_a) begin
                        // log2(NaN) = NaN
                        result_out <= 64'h7FF8000000000000;
                        valid_out <= 1;
                        state <= S_IDLE;
                    end else if (zero_a) begin
                        // log2(+0) = -Infinity
                        result_out <= 64'hFFF0000000000000;
                        valid_out <= 1;
                        state <= S_IDLE;
                    end else if (inf_a && !sign_a) begin
                        // log2(+Infinity) = +Infinity
                        result_out <= 64'h7FF0000000000000;
                        valid_out <= 1;
                        state <= S_IDLE;
                    end else if (sign_a) begin
                        // log2(negative) = NaN
                        result_out <= 64'h7FF8000000000000;
                        valid_out <= 1;
                        state <= S_IDLE;
                    end else begin
                        state <= S_I2F_START;
                    end
                end

                // =================================================================
                // START INTEGER-TO-FLOAT CONVERSION
                // =================================================================

                S_I2F_START: begin
                    conv_start <= 1;
                    state <= S_WAIT_I2F;
                end

                // =================================================================
                // WAIT FOR INTEGER-TO-FLOAT CONVERSION
                // =================================================================

                S_WAIT_I2F:
                    if (conv_done) begin
                        e_float <= conv_res;
                        state <= S_BUILD_Y;
                    end

                // =================================================================
                // BUILD REDUCED MANTISSA TERM
                // =================================================================
                // Construct:
                //
                //     y = mantissa - 1
                //
                // The mantissa is represented as a normalized FP64 value
                // in the range [1, 2).

                S_BUILD_Y: begin
                    add_a <= {1'b0, 11'd1023, mant_a[51:0]};
                    add_b <= FP_ONE;
                    add_sub <= 1;
                    add_valid <= 1;
                    state <= S_WAIT_SUB_Y;
                end

                // =================================================================
                // WAIT FOR y = M - 1
                // =================================================================

                S_WAIT_SUB_Y:
                    if (add_ready) begin
                        y <= add_res;
                        state <= S_POLY_INIT;
                    end

                // =================================================================
                // INITIALIZE HORNER EVALUATION
                // =================================================================
                // Start with the highest-order coefficient C14.
                //
                // The polynomial is subsequently evaluated by repeatedly
                // performing:
                //
                //     p = y * p
                //     p = p + C[n]

                S_POLY_INIT: begin
                    p <= coeff[14];
                    poly_idx <= 13;
                    state <= S_POLY_MUL;
                end

                // =================================================================
                // POLYNOMIAL MULTIPLICATION
                // =================================================================
                // Multiply the current polynomial accumulator by y.

                S_POLY_MUL: begin
                    mul_a <= y;
                    mul_b <= p;
                    mul_valid <= 1;
                    state <= S_WAIT_MUL;
                end

                // =================================================================
                // WAIT FOR POLYNOMIAL MULTIPLICATION
                // =================================================================

                S_WAIT_MUL:
                    if (mul_ready) begin
                        p <= mul_res;
                        state <= S_POLY_ADD;
                    end

                // =================================================================
                // POLYNOMIAL COEFFICIENT ADDITION
                // =================================================================
                // Add the next Taylor coefficient to the accumulated product.

                S_POLY_ADD: begin
                    add_a <= coeff[poly_idx];
                    add_b <= p;
                    add_sub <= 0;
                    add_valid <= 1;
                    state <= S_WAIT_ADD;
                end

                // =================================================================
                // WAIT FOR POLYNOMIAL ADDITION
                // =================================================================
                // The adder result is used directly for the next multiplication
                // when another polynomial coefficient remains.

                S_WAIT_ADD: begin
                    if (add_ready) begin
                        p <= add_res;

                        if (poly_idx == 0)
                            state <= S_FINAL_ADD;
                        else begin
                            // Use the adder result directly as the next
                            // polynomial accumulator input.
                            mul_a <= y;
                            mul_b <= add_res;
                            mul_valid <= 1;
                            poly_idx <= poly_idx - 1;
                            state <= S_WAIT_MUL;
                        end
                    end
                end

                // =================================================================
                // FINAL EXPONENT ADDITION
                // =================================================================
                // Combine the integer exponent term with the polynomial:
                //
                //     log2(x) = e + log2(1 + y)

                S_FINAL_ADD: begin
                    add_a <= e_float;
                    add_b <= p;
                    add_sub <= 0;
                    add_valid <= 1;
                    state <= S_WAIT_FINAL;
                end

                // =================================================================
                // WAIT FOR FINAL RESULT
                // =================================================================

                S_WAIT_FINAL:
                    if (add_ready) begin
                        result_out <= add_res;
                        valid_out <= 1;
                        state <= S_IDLE;
                    end

                // =================================================================
                // DEFAULT STATE RECOVERY
                // =================================================================

                default:
                    state <= S_IDLE;

            endcase
        end
    end

endmodule
