# Testbench Results

## Verification Overview

The current baseline verification uses `tb_vrm_fpu_axi`, which exercises the FPU through its AXI-Lite control interface and 64-bit AXI-Stream datapath.

The simulation covers:

- basic arithmetic;
- integer/FP64 conversion;
- comparison;
- transcendental functions;
- trigonometric functions;
- activation functions.

The results below are the captured simulation outputs.

## Simulation Output

```text
=================================================
=== VRM FPU AXI HARDWARE VERIFICATION (FP64) ===
=================================================

[1] BASIC ARITHMETIC
ADD  (1.5 + 2.5) : 4010000000000000
SUB  (5.0 - 3.0) : 4000000000000000
MUL  (2.0 * 3.0) : 4018000000000000
DIV  (6.0 / 2.0) : 4008000000000000
SQRT (sqrt(4.0)) : 4000000000000000

[2] CONVERSION AND COMPARISON
I2F  (Integer 3)     : 4008000000000000
F2I  (Double 3.0)    : 0000000000000003
FEQ  (2.0 == 2.0)   : 0000000000000001 (Expected: 1)
FLT  (2.0 < 3.0)    : 0000000000000001 (Expected: 1)
FMIN (2.0, 3.0)     : 4000000000000000

[3] TRANSCENDENTAL FUNCTIONS - INTEGER TEST CASES
LOG2 (8.0)          : 4008000000000000 (Expected: 4008000000000000 = 3.0)
EXP2 (3.0)          : 4020000000000000 (Expected: 4020000000000000 = 8.0)

[4] TRANSCENDENTAL FUNCTIONS - FRACTIONAL TEST CASES
LOG2 (5.0)          : 40029351b5fca815 (Expected: approximately 40029311...)
EXP2 (1.5)          : 4006a09ea6e2bc12 (Expected: approximately 4006A09E...)
LN   (e)            : 3ff0000d3b63d778 (Expected: 3FF0000000000000 = 1.0)
EXP  (1.0)          : 4005bf0aa8aa0c77 (Expected: 4005BF0A8B145769 = e)

[5] FOLDED ARCHITECTURE TEST - SIN AND COS
SIN  (0.0)          : 0000000000000000 (Expected: 0000000000000000 = 0.0)
COS  (0.0)          : 3ff0000000000000 (Expected: 3FF0000000000000 = 1.0)

[6] ACTIVATION FUNCTION TEST - SIGMOID AND TANH
SIGMOID (0.0)      : 3fe0000000000000 (Expected: 3FE0000000000000 = 0.5)
TANH    (0.0)      : 0000000000000000 (Expected: 0000000000000000 = 0.0)

=================================================
=== SIMULATION FINISHED =========================
=================================================
```

## Result Summary

| Function | Test Input | Result | Status |
|---|---:|---|---|
| ADD | 1.5 + 2.5 | 4.0 | PASS |
| SUB | 5.0 - 3.0 | 2.0 | PASS |
| MUL | 2.0 × 3.0 | 6.0 | PASS |
| DIV | 6.0 / 2.0 | 3.0 | PASS |
| SQRT | sqrt(4.0) | 2.0 | PASS |
| I2F | integer 3 | 3.0 | PASS |
| F2I | 3.0 | integer 3 | PASS |
| FEQ | 2.0 == 2.0 | 1 | PASS |
| FLT | 2.0 < 3.0 | 1 | PASS |
| FMIN | min(2.0, 3.0) | 2.0 | PASS |
| LOG2 | 8.0 | 3.0 | PASS |
| EXP2 | 3.0 | 8.0 | PASS |
| LOG2 | 5.0 | Approximate | APPROX. |
| EXP2 | 1.5 | Approximate | APPROX. |
| LN | e | Approximate to 1.0 | APPROX. |
| EXP | 1.0 | Approximate to e | APPROX. |
| SIN | 0.0 | 0.0 | PASS |
| COS | 0.0 | 1.0 | PASS |
| SIGMOID | 0.0 | 0.5 | PASS |
| TANH | 0.0 | 0.0 | PASS |

## Interpretation

The baseline simulation demonstrates that the integrated AXI-connected FPU produces the expected results for the tested elementary cases.

The fractional transcendental tests intentionally show approximate outputs. These functions use polynomial approximations and therefore should not be evaluated using exact bit-for-bit comparison against mathematical reference values.

The current result is suitable as a functional baseline. A more extensive verification campaign should add randomized vectors and quantitative numerical-error analysis.
