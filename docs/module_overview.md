# FPU Module Overview

## Core Arithmetic

| Module | Function | Format |
|---|---|---|
| `vrm_fpu_add_sub_64` | Floating-point addition/subtraction | FP64 |
| `vrm_fpu_mul_64` | Floating-point multiplication | FP64 |
| `vrm_fpu_div_64` | Floating-point division | FP64 |
| `vrm_fpu_sqrt_64` | Floating-point square root | FP64 |

## Conversion and Classification

| Module | Function |
|---|---|
| `vrm_fpu_conv_64` | Integer/FP64 conversion |
| `vrm_fpu_misc_64` | Comparison and classification |
| `vrm_fpu_unpacker_64` | FP64 field extraction and special-value detection |

The conversion unit currently supports the integer/double operations required by the surrounding FPU datapath, while the miscellaneous unit provides comparison and `FCLASS` functionality.

## Transcendental Functions

| Module | Function | Implementation |
|---|---|---|
| `vrm_fpu_log2_64` | `log2(x)` | Polynomial/Horner approximation |
| `vrm_fpu_ln_64` | `ln(x)` | `log2(x) * ln(2)` |
| `vrm_fpu_exp2_64` | `2^x` | Integer/fraction decomposition + polynomial |
| `vrm_fpu_exp_64` | `exp(x)` | `exp2(x * log2(e))` |

## Activation Functions

| Module | Function |
|---|---|
| `vrm_fpu_sigmoid_64` | `1 / (1 + exp(-x))` |
| `vrm_fpu_tanh_64` | `(exp(2x)-1)/(exp(2x)+1)` |

These functions are constructed from reusable arithmetic and exponential blocks.

## Trigonometric Functions

| Module | Function |
|---|---|
| `vrm_fpu_sin_64` | Sine approximation |
| `vrm_fpu_cos_64` | Cosine approximation |

Both functions use polynomial evaluation with Horner's method. The squared input is computed once and reused during polynomial evaluation.

## Function Dispatcher

`vrm_fpu_math_64` provides a common interface for the higher-level mathematical functions. It selects the requested function and forwards the input to the corresponding implementation.

Current function mapping:

| `func` | Operation |
|---:|---|
| `0` | `log2` |
| `1` | `ln` |
| `2` | `exp2` |
| `3` | `exp` |
| `4` | sigmoid |
| `5` | tanh |
| `6` | sin |
| `7` | cos |

## AXI Integration

`vrm_fpu_axi` provides the external AXI-Lite and AXI-Stream interface used by the verification testbench.

The AXI-Lite registers select the FPU operation and function code, while the AXI-Stream channel transports 64-bit operands and results.
