`ifndef VRM_FPU_CONSTANTS_VH
`define VRM_FPU_CONSTANTS_VH

// =====================================================================
//  IEEE-754 double-precision constants
//
//  All constants are represented as 64-bit IEEE-754 binary64 values.
// =====================================================================
`define FP64_ZERO          64'h0000_0000_0000_0000
`define FP64_ONE           64'h3FF0_0000_0000_0000
`define FP64_TWO           64'h4000_0000_0000_0000
`define FP64_HALF          64'h3FE0_0000_0000_0000
`define FP64_LN2           64'h3FE6_2E42_FEFA_39EF
`define FP64_LOG2E         64'h3FF7_1547_652B_82FE
`define FP64_ONE_OVER_LN2  64'h3FF7_1547_652B_82FE

// =====================================================================
//  LOG2(1 + y) Taylor-series coefficients
//
//  Coefficient definition:
//      c(n) = (-1)^(n+1) / (n * ln(2))
//
//  The series is provided through order 14.
// =====================================================================
`define LOG2_C0            64'h0000_0000_0000_0000   // 0
`define LOG2_C1            64'h3FF7_1547_652B_82FE   // +1.4426950408889634
`define LOG2_C2            64'hBFE7_1547_652B_82FE   // -0.7213475204444817
`define LOG2_C3            64'h3FDE_CA5B_4387_588B   // +0.4808983469629878
`define LOG2_C4            64'hBFD7_1547_652B_82FE   // -0.36067376022224085
`define LOG2_C5            64'h3FD2_A14D_112E_0B02   // +0.2885390081777927
`define LOG2_C6            64'hBFCE_CA5B_4387_588B   // -0.2404491734814939
`define LOG2_C7            64'h3FC8_E38E_E38E_38E4   // +0.20609929155528038
`define LOG2_C8            64'hBFC5_1547_652B_82FE   // -0.18033688011112042
`define LOG2_C9            64'h3FC1_DE7A_3D73_6BD3   // +0.1602994489876626
`define LOG2_C10           64'hBFBE_CA5B_4387_588B   // -0.14426950408889635
`define LOG2_C11           64'h3FBA_5E03_827C_2C7B   // +0.1311540946262694
`define LOG2_C12           64'hBFB7_1547_652B_82FE   // -0.12022458674074695
`define LOG2_C13           64'h3FB4_9F1B_53C5_A5E3   // +0.11097654160684334
`define LOG2_C14           64'hBFB2_502B_502B_502C   // -0.10304964577764019

// =====================================================================
//  EXP2(f) Taylor-series coefficients
//
//  Coefficient definition:
//      c(n) = ln(2)^n / n!
//
//  The series is provided through order 14.
// =====================================================================
`define EXP2_C0            64'h3FF0_0000_0000_0000   // 1.0
`define EXP2_C1            64'h3FE6_2E42_FEFA_39EF   // 0.6931471805599453
`define EXP2_C2            64'h3FCE_BFBD_FF82_C58F   // 0.24022650695910073
`define EXP2_C3            64'h3FAC_6B08_D704_A0C0   // 0.05550410866482158
`define EXP2_C4            64'h3F83_B2AB_6FBF_C17E   // 0.00961812910762807
`define EXP2_C5            64'h3F55_D2E4_72F6_0C9F   // 0.0013340862833401
`define EXP2_C6            64'h3F26_2C1F_9D4A_622B   // 0.000154035303933
`define EXP2_C7            64'h3EF5_7A3F_8128_D56B   // 1.5252733804e-5
`define EXP2_C8            64'h3EC3_CFA0_C7D6_C0C5   // 1.321548679e-6
`define EXP2_C9            64'h3E92_B6CE_9D4A_39E5   // 1.01778366e-7
`define EXP2_C10           64'h3E61_E8B8_BD13_AE05   // 6.9494998e-9
`define EXP2_C11           64'h3E30_A2E6_1F21_1F21   // 4.335795e-10
`define EXP2_C12           64'h3E00_2A2A_2A2A_2A2B   // 2.5155e-11
`define EXP2_C13           64'h3DCF_41B7_405D_1745   // 1.362e-12
`define EXP2_C14           64'h3D9E_2F96_F7D5_6B34   // 6.97e-14

// =====================================================================
//  SIN(x) polynomial coefficients
//
//  Polynomial form:
//      sin(x) = x * P(x^2)
//
//  Odd-order Taylor coefficients are provided from order 1 through 29.
// =====================================================================
`define SIN_C1             64'h3FF0_0000_0000_0000   // 1
`define SIN_C3             64'hBFC5_5555_5555_5555   // -1/6
`define SIN_C5             64'h3F81_1111_1110_F30C   // 1/120
`define SIN_C7             64'hBF2A_01A0_19C1_61D5   // -1/5040
`define SIN_C9             64'h3ED0_38EF_1D24_8C5A   // 1/362880
`define SIN_C11            64'hBE73_9C7_64F5_B0E0    // -1/39916800
`define SIN_C13            64'h3E15_56B8_AA4E_D11E   // 1/6227020800
`define SIN_C15            64'hBDB6_A7E5_F1D3_9A0B   // -1/1307674368000
`define SIN_C17            64'h3D57_320_CA40_5F2D    // 1/355687428096000
`define SIN_C19            64'hBCF7_D3E4_3B1A_9A3E   // -1/121645100408832000
`define SIN_C21            64'h3C97_A4F9_DA63_7A4B   // 1/5.1090942e19
`define SIN_C23            64'hBC37_3B4_44C3_E2D5    // -1/2.5852017e22
`define SIN_C25            64'h3BD6_CDA5_98B3_2A6B   // 1/1.551121e25
`define SIN_C27            64'hBB76_46D1_8D91_B9D4   // -1/1.0888869e28
`define SIN_C29            64'h3B15_7C06_E912_AE5E   // 1/8.8417619e30

// =====================================================================
//  COS(x) polynomial coefficients
//
//  Polynomial form:
//      cos(x) = P(x^2)
//
//  Even-order Taylor coefficients are provided from order 0 through 28.
// =====================================================================
`define COS_C0             64'h3FF0_0000_0000_0000   // 1
`define COS_C2             64'hBFE0_0000_0000_0000   // -1/2
`define COS_C4             64'h3FA5_5555_5555_5555   // 1/24
`define COS_C6             64'hBF56_0F01_9B40_3EF5   // -1/720
`define COS_C8             64'h3F06_6D06_6D06_6D07   // 1/40320
`define COS_C10            64'hBEB4_4A04_4A04_4A04   // -1/3628800
`define COS_C12            64'h3E60_6A85_2A85_2A85   // 1/479001600
`define COS_C14            64'hBE0C_672_672_672_672  // -1/87178291200
`define COS_C16            64'h3DB6_8C06_8C06_8C07   // 1/20922789888000
`define COS_C18            64'hBD60_DEB_DEB_DEB_DF   // -1/6402373705728000
`define COS_C20            64'h3D0A_A5A_5A5A_5A5B    // 1/2432902008176640000
`define COS_C22            64'hBCB3_F3F_3F3F_3F40    // -1/1.1240007e21
`define COS_C24            64'h3C5D_4D4_D4D4_D4D5    // 1/6.204484e23
`define COS_C26            64'hBC06_9B3_3B33_B340    // -1/4.0329146e26
`define COS_C28            64'h3BAF_BF1_4E9A_27F9    // 1/3.0488834e29

`endif
