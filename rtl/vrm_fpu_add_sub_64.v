`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_add_sub_64
// DESCRIPTION:
// IEEE-754 double-precision floating-point addition/subtraction datapath.
//
// The datapath is organized as a multi-stage pipeline:
// - Stage 1 : Operand unpacking and mantissa alignment
// - Stage 2 : Mantissa add/subtract and normalization
// - Stage 3 : Result packing
// - Output  : Registered result and valid signal
//
// Features:
// - 64-bit IEEE-754 double-precision operands
// - Floating-point addition and subtraction through sign manipulation
// - Exponent comparison and mantissa alignment
// - Sticky-bit propagation during alignment and normalization
// - Guard, round, and sticky bits for final result packing
// - Pipelined datapath with registered stage boundaries
//
// Notes:
// - Subtraction is implemented by inverting the effective sign of operand B.
// - Special-value detection is delegated to the unpacker and downstream
//   datapath components.
// - Rounding and final IEEE-754 field construction are handled by the packer.
// ============================================================================

module vrm_fpu_add_sub_64 (
    input  wire        clk,
    input  wire        rstn,
    input  wire        valid_in,
    input  wire        is_sub,
    input  wire [63:0] op_a,
    input  wire [63:0] op_b,
    output reg  [63:0] result_out,
    output reg         valid_out
);

    // =========================================================================
    // 1. OPERAND UNPACKING AND ALIGNMENT
    // =========================================================================

    // Decompose both IEEE-754 operands into sign, exponent, and mantissa.
    wire sign_a, sign_b;
    wire [10:0] exp_a, exp_b;
    wire [52:0] mant_a, mant_b;

    vrm_fpu_unpacker_64 unpack_a (
        .fp_in(op_a), .sign(sign_a), .exp(exp_a), .mantissa(mant_a),
        .is_zero(), .is_subnormal(), .is_inf(), .is_nan(), .is_snan(), .is_qnan()
    );

    vrm_fpu_unpacker_64 unpack_b (
        .fp_in(op_b), .sign(sign_b), .exp(exp_b), .mantissa(mant_b),
        .is_zero(), .is_subnormal(), .is_inf(), .is_nan(), .is_snan(), .is_qnan()
    );

    // For subtraction, invert the effective sign of operand B.
    wire effective_sign_b = sign_b ^ is_sub;

    // -------------------------------------------------------------------------
    // Mantissa Alignment
    // -------------------------------------------------------------------------

    // The aligner determines the operand with the larger magnitude, aligns
    // the smaller mantissa to the common exponent, and generates the sticky bit.
    wire sign_L_s1, sign_S_s1, sticky_s1;
    wire [10:0] exp_common_s1;
    wire [53:0] mant_L_s1, mant_S_align_s1;

    vrm_fpu_aligner_64 aligner (
        .sign_a(sign_a), .exp_a(exp_a), .mant_a(mant_a),
        .sign_b(effective_sign_b), .exp_b(exp_b), .mant_b(mant_b),
        .sign_L(sign_L_s1), .sign_S(sign_S_s1), .exp_common(exp_common_s1),
        .mant_L(mant_L_s1), .mant_S_align(mant_S_align_s1), .sticky(sticky_s1)
    );

    // =========================================================================
    // 2. STAGE 1 -> STAGE 2 PIPELINE REGISTER
    // =========================================================================

    // Register the aligned operands and associated control information before
    // entering the add/subtract and normalization stage.
    reg valid_s2, sign_L_s2, sign_S_s2, sticky_s2;
    reg [10:0] exp_common_s2;
    reg [53:0] mant_L_s2, mant_S_align_s2;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_s2 <= 0; sign_L_s2 <= 0; sign_S_s2 <= 0; sticky_s2 <= 0;
            exp_common_s2 <= 0; mant_L_s2 <= 0; mant_S_align_s2 <= 0;
        end else begin
            valid_s2        <= valid_in;
            sign_L_s2       <= sign_L_s1;
            sign_S_s2       <= sign_S_s1;
            exp_common_s2   <= exp_common_s1;
            mant_L_s2       <= mant_L_s1;
            mant_S_align_s2 <= mant_S_align_s1;
            sticky_s2       <= sticky_s1;
        end
    end

    // =========================================================================
    // 3. ADD/SUBTRACT AND NORMALIZATION
    // =========================================================================

    // Perform signed mantissa addition/subtraction using the aligned operands.
    wire sign_res_s2, sticky_norm_s2;
    wire [10:0] exp_res_s2;
    wire [54:0] mant_res_s2;

    vrm_fpu_add_sub_core_64 adder (
        .sign_L(sign_L_s2), .sign_S(sign_S_s2), .exp_common(exp_common_s2),
        .mant_L(mant_L_s2), .mant_S_align(mant_S_align_s2), .sticky_in(sticky_s2),
        .final_sign(sign_res_s2), .exp_out(exp_res_s2), .mant_res(mant_res_s2), .sticky_out(sticky_norm_s2)
    );

    // Normalize the intermediate mantissa and extract the rounding fields.
    wire sign_norm_s2, guard_s2, round_bit_s2, sticky_final_s2;
    wire [10:0] exp_norm_s2;
    wire [52:0] mant_norm_s2;

    vrm_fpu_norm_64 normalizer (
        .sign_in(sign_res_s2), .exp_in(exp_res_s2), .mant_in(mant_res_s2), .sticky_in(sticky_norm_s2),
        .sign_out(sign_norm_s2), .exp_out(exp_norm_s2), .mant_out(mant_norm_s2),
        .guard_out(guard_s2), .round_out(round_bit_s2), .sticky_out(sticky_final_s2)
    );

    // =========================================================================
    // 4. STAGE 2 -> STAGE 3 PIPELINE REGISTER
    // =========================================================================

    // Register the normalized floating-point fields and rounding information
    // before final IEEE-754 result packing.
    reg valid_s3, sign_s3, guard_s3, round_s3, sticky_s3;
    reg [10:0] exp_s3;
    reg [52:0] mant_s3;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_s3 <= 0; sign_s3 <= 0; guard_s3 <= 0; round_s3 <= 0; sticky_s3 <= 0;
            exp_s3 <= 0; mant_s3 <= 0;
        end else begin
            valid_s3  <= valid_s2;
            sign_s3   <= sign_norm_s2;
            exp_s3    <= exp_norm_s2;
            mant_s3   <= mant_norm_s2;
            guard_s3  <= guard_s2;
            round_s3  <= round_bit_s2;
            sticky_s3 <= sticky_final_s2;
        end
    end

    // =========================================================================
    // 5. RESULT PACKING
    // =========================================================================

    // Reconstruct the final 64-bit IEEE-754 floating-point representation.
    wire [63:0] final_fp_data;

    vrm_fpu_packer_64 packer (
        .sign(sign_s3), .exp(exp_s3), .mant(mant_s3),
        .guard(guard_s3), .round(round_s3), .sticky(sticky_s3),
        .fp_out(final_fp_data)
    );

    // =========================================================================
    // 6. OUTPUT REGISTER
    // =========================================================================

    // Register the packed result and propagate the pipeline valid signal.
    always @(posedge clk) begin
        if (!rstn) begin
            valid_out  <= 0;
            result_out <= 64'h0;
        end else begin
            valid_out  <= valid_s3;
            result_out <= final_fp_data;
        end
    end

endmodule
