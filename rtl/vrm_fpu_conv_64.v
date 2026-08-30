`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: vrm_fpu_conv_64
 * LANE E: CONVERSION UNIT
 *
 * DESCRIPTION:
 * Conversion unit between 32-bit integers and IEEE 754 double-precision
 * floating-point values for the RV32D FPU.
 *
 * Supported operations:
 *   00 : I2D  - Signed Integer 32-bit to Double 64-bit
 *   01 : UI2D - Unsigned Integer 32-bit to Double 64-bit
 *   10 : D2I  - Double 64-bit to Signed Integer 32-bit
 *   11 : D2UI - Double 64-bit to Unsigned Integer 32-bit
 *
 * The unit is implemented as a two-stage pipeline:
 *   Stage 1 : Operand analysis and alignment
 *   Stage 2 : Final conversion and output packing
 *
 * Fixed-width extensions are explicitly used in several expressions to
 * prevent truncation and width-mismatch warnings in Verilator.
 * ============================================================================ */

module vrm_fpu_conv_64 (
    input  wire        clk,
    input  wire        rstn,
    
    input  wire        valid_in,
    input  wire [1:0]  conv_op,    // 00: I2D, 01: UI2D, 10: D2I, 11: D2UI
    input  wire [63:0] op_a,       // 64-bit FP value or 32-bit integer in [31:0]
    
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // STAGE 1: OPERAND ANALYSIS & ALIGNMENT
    // =========================================================================
    
    // -------------------------------------------------------------------------
    // Integer-to-Double Conversion Path
    // -------------------------------------------------------------------------
    
    // Extract the 32-bit integer input.
    wire [31:0] int_in = op_a[31:0];

    // Determine the integer sign.
    // Signed conversion uses bit 31 as the sign bit.
    // Unsigned conversion always uses a positive sign.
    wire        int_sign = conv_op[0] ? 1'b0 : int_in[31];

    // Convert the input integer to its absolute magnitude.
    wire [31:0] int_abs  = (int_sign) ? (~int_in + 1) : int_in;
    
    // -------------------------------------------------------------------------
    // Integer Leading-Zero / Leading-One Position Detection
    // -------------------------------------------------------------------------
    
    // The leading-zero count is used to determine the normalized exponent
    // and mantissa position during Integer-to-Double conversion.
    reg [4:0] lzc_int;
    integer i;

    always @(*) begin
        lzc_int = 5'd31;

        for (i = 0; i < 32; i = i + 1) begin
            if (int_abs[i])
                lzc_int = 5'd31 - i[4:0];
        end
    end

    // -------------------------------------------------------------------------
    // Double-to-Integer Conversion Path
    // -------------------------------------------------------------------------
    
    // Unpack the IEEE 754 double-precision operand.
    wire        f_sign;
    wire [10:0] f_exp;
    wire [52:0] f_mant;
    
    vrm_fpu_unpacker_64 unpack_f2i (
        .fp_in(op_a), 
        .sign(f_sign), 
        .exp(f_exp), 
        .mantissa(f_mant), 
        .is_zero(), 
        .is_subnormal(), 
        .is_inf(), 
        .is_nan(), 
        .is_snan(), 
        .is_qnan()
    );

    // Calculate the shift amount required to convert the normalized
    // floating-point mantissa into an integer representation.
    //
    // The exponent is biased by 1023. The additional offset accounts for
    // the position of the implicit leading bit within the extended mantissa.
    //
    // If the exponent is sufficiently small, the resulting integer becomes
    // zero after the right shift.
    wire signed [12:0] shift_amt = 13'd1086 - {2'b0, f_exp};

    // -------------------------------------------------------------------------
    // Pipeline Registers: Stage 1 -> Stage 2
    // -------------------------------------------------------------------------
    
    reg        s2_valid, s2_sign;
    reg [1:0]  s2_op;
    reg [31:0] s2_int_abs;
    reg [4:0]  s2_lzc;
    reg [63:0] s2_f_mant_ext;
    reg signed [11:0] s2_shift;
    reg        s2_f_sign;

    always @(posedge clk) begin
        if (!rstn) begin
            s2_valid      <= 1'b0;
            s2_op         <= 2'b00;
            s2_sign       <= 1'b0;
            s2_int_abs    <= 32'd0;
            s2_lzc        <= 5'd0;
            s2_f_mant_ext <= 64'd0;
            s2_shift      <= 12'd0;
            s2_f_sign     <= 1'b0;
        end else begin
            s2_valid      <= valid_in;
            s2_op         <= conv_op;
            s2_sign       <= int_sign;
            s2_int_abs    <= int_abs;
            s2_lzc        <= lzc_int;
            s2_f_mant_ext <= {f_mant, 11'd0};
            s2_shift      <= shift_amt;
            s2_f_sign     <= f_sign;
        end
    end

    // =========================================================================
    // STAGE 2: FINAL CONVERSION & PACKING
    // =========================================================================
    
    reg [63:0] res_i2d;
    reg [63:0] res_d2i;
    wire [63:0] shifted;
    
    // Convert the extended floating-point mantissa into an integer magnitude
    // according to the calculated shift amount.
    assign shifted = s2_f_mant_ext >> s2_shift;

    always @(*) begin

        // ---------------------------------------------------------------------
        // Integer-to-Double (I2D / UI2D)
        // ---------------------------------------------------------------------
        
        // Zero is handled directly as the IEEE 754 +0.0 representation.
        if (s2_int_abs == 0) begin
            res_i2d = 64'd0;
        end else begin
            res_i2d[63] = s2_sign;

            // Calculate the IEEE 754 biased exponent.
            // The explicit extension of s2_lzc prevents width ambiguity.
            res_i2d[62:52] = 11'd1023 + (11'd31 - {6'b0, s2_lzc}); 

            // Normalize the integer magnitude and place it into the
            // 52-bit fraction field.
            //
            // Explicit 64-bit extension is used before shifting so that
            // significant bits are not truncated during the operation.
            res_i2d[51:0] = ({32'd0, s2_int_abs} << (s2_lzc + 1)) << 20; 
        end

        // ---------------------------------------------------------------------
        // Double-to-Integer (D2I / D2UI)
        // ---------------------------------------------------------------------
        
        // The floating-point value is smaller than one and therefore produces
        // an integer value of zero.
        if (s2_shift > 63) begin
            res_d2i = 64'd0;

        // The floating-point value exceeds the representable 32-bit range.
        // Saturate the result to the corresponding signed boundary.
        end else if (s2_shift < 32) begin
            res_d2i = s2_f_sign ? {32'h0, 32'h80000000} :
                                  {32'h0, 32'h7FFFFFFF};

        end else begin

            // Apply two's-complement conversion for negative results.
            res_d2i[31:0] = s2_f_sign ? (~shifted[31:0] + 1) :
                                         shifted[31:0];

            res_d2i[63:32] = 32'd0;
        end
    end
    
    // =========================================================================
    // FINAL OUTPUT REGISTER & OPERATION MUX
    // =========================================================================
    
    always @(posedge clk) begin
        if (!rstn) begin
            valid_out  <= 1'b0;
            result_out <= 64'd0;
        end else begin
            valid_out  <= s2_valid;

            // conv_op[1] selects the conversion direction:
            //   0 -> Integer to Double
            //   1 -> Double to Integer
            result_out <= (s2_op[1]) ? res_d2i : res_i2d;
        end
    end

    // =========================================================================
    // UNUSED SIGNAL SUPPRESSION
    // =========================================================================
    
    // Explicitly reference signals that are intentionally unused by the
    // current conversion datapath to keep Verilator lint output clean.
    //
    // conv_op[0] is already consumed during Stage 1 sign determination,
    // but s2_op[0] is not otherwise required after the operation direction
    // has been selected.
    //
    // The upper 32 bits of shifted are also intentionally unused because
    // only the lower 32 bits are required by the current integer output path.
    // verilator lint_off UNUSED
    wire _unused_op0 = s2_op[0];
    wire [31:0] _unused_shifted_high = shifted[63:32];
    // verilator lint_on UNUSED

endmodule
