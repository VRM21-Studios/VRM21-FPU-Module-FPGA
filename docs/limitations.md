# Current Limitations

## Characterization Basis

The current VRM-FPU V1 baseline has been characterized on an AMD/Xilinx Kria KR260 FPGA using the `FPU2.bit` bitstream, the `vrm_fpu_axi_0` control interface, and an AXI DMA data path through PYNQ.

The current characterization uses the following verified AXI operation map:

| Operation | Opcode | funct3 |
| --------- | -----: | -----: |
| `ADD`     |    `0` |    `0` |
| `SUB`     |    `1` |    `0` |
| `MUL`     |    `2` |    `0` |
| `DIV`     |    `3` |    `0` |
| `SQRT`    |    `4` |    `0` |
| `FEQ`     |    `7` |    `0` |
| `FLT`     |    `7` |    `1` |
| `FLE`     |    `7` |    `2` |
| `FMIN`    |    `7` |    `3` |
| `FMAX`    |    `7` |    `4` |
| `LOG2`    |    `8` |    `0` |
| `LN`      |    `8` |    `1` |
| `EXP2`    |    `8` |    `2` |
| `EXP`     |    `8` |    `3` |
| `SIGM`    |    `8` |    `4` |
| `TANH`    |    `8` |    `5` |
| `SIN`     |    `8` |    `6` |
| `COS`     |    `8` |    `7` |

The characterization includes directed vectors, IEEE-754 special-value probes, exponent/subnormal boundary probes, 1000 randomized finite cases for each of `ADD`, `SUB`, `MUL`, `DIV`, and `SQRT`, transcendental point tests, 301-point wide sweeps, a 401-point local trigonometric sweep, composite-function demonstrations, and end-to-end PYNQ/DMA timing measurements.

The randomized tests use seed `0x21F0`.

## Numerical Approximation

The transcendental and trigonometric functions are approximation-based. They are not currently documented as correctly rounded IEEE-754 mathematical-library implementations.

The latest hardware characterization shows input-dependent approximation error:

| Function  | Sweep             | Maximum Absolute Error | Maximum Relative Error |
| --------- | ----------------- | ---------------------: | ---------------------: |
| `log2`    | `1e-10` to `1e10` |            `5.6750e-2` |            `2.6132e-2` |
| `ln`      | `1e-10` to `1e10` |            `3.9336e-2` |            `2.6132e-2` |
| `exp2`    | `-10` to `10`     |            `6.6498e-3` |            `1.5726e-5` |
| `exp`     | `-10` to `10`     |            `1.1609e-1` |            `2.1939e-5` |
| `sigmoid` | `-10` to `10`     |            `4.2547e-6` |            `9.2456e-6` |
| `tanh`    | `-10` to `10`     |            `8.5094e-6` |            `2.6467e-5` |

These measurements demonstrate that the numerical quality of the transcendental functions depends on the input domain. Exact bit matching is therefore appropriate for selected elementary vectors, but not as a universal criterion for `log2`, `ln`, `exp2`, `exp`, `sigmoid`, `tanh`, `sin`, or `cos`.

ULP is retained as a secondary diagnostic. For large approximation errors, absolute and relative error are more informative.

## Finite Arithmetic Characterization

The core arithmetic datapaths show substantially stronger behavior than the approximation-based transcendental functions for the tested finite domain.

The directed finite test vectors matched the Python/NumPy FP64 reference bit-for-bit for all `ADD`, `SUB`, `MUL`, `DIV`, and `SQRT` cases.

The randomized characterization used 1000 finite cases per operation:

| Operation | Exact Matches | Notes                                                                                                                                   |
| --------- | ------------: | --------------------------------------------------------------------------------------------------------------------------------------- |
| `ADD`     |  `986 / 1000` | Remaining 14 cases differ by at most 1 ULP                                                                                              |
| `SUB`     |  `995 / 1000` | Remaining 5 cases differ by at most 1 ULP                                                                                               |
| `MUL`     |  `975 / 1000` | All 108 overflow cases matched `+/-Inf`; the 25 finite mismatches produced subnormal reference results and were returned as signed zero |
| `DIV`     |  `714 / 1000` | Finite underflow/overflow and subnormal-result cases are not handled correctly                                                          |
| `SQRT`    |  `997 / 1000` | The 3 mismatches correspond to subnormal inputs and show large relative error                                                           |

These measurements should not be interpreted as an exhaustive correctness or IEEE-754 compliance proof. They establish the behavior of the tested V1 implementation and identify specific numerical edge-domain limitations.

## Special-Value Coverage

The implementation provides partial special-value handling, but it does not currently provide complete IEEE-754 semantic coverage.

The latest special-value characterization passed 13 of 25 selected arithmetic special-value probes. Correct behavior was observed for several cases including:

* `+Inf + finite`
* `-Inf + finite`
* finite divided by signed zero
* `SQRT(+0)`
* `SQRT(-0)`
* `SQRT(+Inf)`
* selected NaN comparison cases

Failures were observed for several invalid or exceptional combinations, including:

* `+Inf + -Inf`
* `+Inf - +Inf`
* NaN propagation through arithmetic
* `Inf * 0`
* `0 / 0`
* `Inf / Inf`
* finite divided by `Inf`
* `-Inf` divided by a finite operand

The comparison probes were more complete: the selected `FEQ`, `FLT`, and `FLE` special-value cases all matched the expected semantic results.

NaN payload and canonicalization are not treated as bit-exact requirements in this characterization.

## Subnormal and Underflow Behavior

Subnormal handling is a significant V1 limitation.

Direct boundary tests show correct behavior beginning at the minimum normal FP64 value, while values below the normal/subnormal boundary are not preserved consistently.

Observed behavior includes:

* minimum subnormal multiplied by `1.0` returning `+0`;
* minimum and maximum subnormal values returning `+0` for selected `ADD`, `SUB`, and `MUL` tests;
* subnormal division cases producing incorrect results, including `+Inf`;
* `min_normal / 2` returning zero instead of the corresponding positive subnormal;
* `min_subnormal + min_subnormal` returning zero instead of `2 * min_subnormal`;
* `min_normal - max_subnormal` returning zero instead of the minimum subnormal.

This indicates that the V1 arithmetic datapaths should not be treated as fully gradual-underflow IEEE-754 implementations.

By contrast, the boundary tests at the normal range were successful, including:

* minimum normal values;
* twice the minimum normal value;
* values immediately below the maximum finite value;
* maximum finite operands;
* overflow cases where `max_finite + max_finite` and `max_finite * 2` correctly produced infinity.

## Division Range Limitation

Division shows a stronger range limitation than the other elementary arithmetic datapaths.

In the 1000-case randomized division test:

* `714 / 866` finite-reference cases matched exactly;
* `134` cases were expected to overflow to infinity, but did not match the expected infinity result;
* cases whose mathematical result underflowed to zero or became subnormal also produced incorrect finite results.

One extreme example produced an expected negative subnormal result near `-1.03e-309` while the hardware returned a large finite value near `-3.34e307`.

Therefore, V1 division should be considered reliable only within the characterized operating range. Extreme exponent differences, underflow, subnormal results, and overflow behavior remain outside the demonstrated correctness envelope.

## Square-Root Subnormal Limitation

The randomized square-root test matched 997 of 1000 positive finite cases exactly.

The three mismatches occurred for subnormal inputs. The largest observed error was approximately:

* absolute error: `7.18e-155`;
* relative error: `7.55`;
* ULP distance: `1.38e16`.

This indicates that the square-root datapath is accurate for the tested normal-range values but does not provide equivalent accuracy for subnormal inputs.

## Trigonometric Range Reduction

The `sin` and `cos` implementations use direct polynomial evaluation. They do not perform complete internal argument/range reduction.

The measured characterization demonstrates a clear domain limitation:

| Operation | Sweep                 | Maximum Absolute Error |
| --------- | --------------------- | ---------------------: |
| `sin`     | `-10` to `10`         |             `3.6611e5` |
| `cos`     | `-10` to `10`         |             `1.4418e5` |
| `sin`     | local `[-pi/2, pi/2]` |            `6.8706e-5` |
| `cos`     | local `[-pi/2, pi/2]` |            `1.2257e-3` |

The wide-domain results diverge dramatically because the polynomial is evaluated without comprehensive argument reduction.

Within the local trigonometric interval, the approximation remains bounded but still exhibits measurable error, especially for `cos` near its zero crossing. Relative error is not a useful primary metric at values close to zero; absolute error is preferred there.

## Composite and Software-Orchestrated Functions

Higher-level functions are constructed from multiple primitive FPU transactions rather than single dedicated hardware instructions.

Examples include:

```text
x^y    = exp2(y * log2(x))
tan(x) = sin(x) / cos(x)
log10  = ln(x) / ln(10)
GELU   = 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715*x^3)))
```

Measured examples show that errors from the primitive approximation stages propagate into the composite result.

For the tested cases:

| Function           | Maximum Absolute Error | Maximum Relative Error* |
| ------------------ | ---------------------: | ----------------------: |
| `x^y`              |              `4.58e-4` |               `1.45e-5` |
| `tan`              |              `5.04e-2` |               `6.10e-2` |
| `log10`            |              `7.30e-6` |               `5.66e-6` |
| GELU approximation |              `1.29e-8` |               `2.33e-6` |

* Relative error for `tan` is quoted away from the zero-crossing cases where the reference result is extremely close to zero. At `180°`, for example, the absolute error is about `5.04e-2`, while a relative-error calculation becomes numerically uninformative.

The `tan` demonstration performs software-side angle conversion and range reduction before invoking the FPGA `sin`, `cos`, and `div` primitives. This reduces polynomial divergence but does not remove the underlying approximation error.

Composite functions should therefore be documented as software-orchestrated micro-operation sequences, not as single dedicated FPU instructions.

## Conversion Coverage

Integer/FP64 conversion is not characterized by the current hardware test script because the verified AXI opcode/funct3 map used for this characterization does not include a confirmed conversion encoding.

The current numerical characterization does not establish conversion boundary behavior because the conversion instruction encoding was not verified for this test harness.

Before making new claims about conversion accuracy, the exact conversion instruction encoding and interface behavior should be verified from the RTL and tested explicitly.

## Rounding and Exception Behavior

The current implementation should not be documented as a complete IEEE-754 execution environment.

This characterization does not establish:

* all IEEE-754 rounding modes;
* correctly rounded results for every operation;
* complete exception flag behavior;
* complete signaling-NaN behavior;
* exhaustive invalid-operation semantics;
* exhaustive overflow and underflow flag semantics.

The measured arithmetic results demonstrate that many finite normal-range operations are highly accurate, but this is different from establishing complete IEEE-754 compliance.

If strict IEEE-754 compliance becomes a future project requirement, rounding modes, exception flags, special-value semantics, and boundary behavior must be defined and verified explicitly.

## Throughput and Timing

End-to-end PYNQ/DMA measurements on the KR260 showed approximately 0.212–0.214 ms median transaction latency for the tested primitive operations:

| Operation |     Median |        P95 |    Maximum |
| --------- | ---------: | ---------: | ---------: |
| `ADD`     | `0.214 ms` | `0.224 ms` | `0.253 ms` |
| `MUL`     | `0.213 ms` | `0.228 ms` | `0.283 ms` |
| `DIV`     | `0.213 ms` | `0.222 ms` | `0.250 ms` |
| `SQRT`    | `0.214 ms` | `0.221 ms` | `0.248 ms` |
| `LOG2`    | `0.214 ms` | `0.232 ms` | `0.268 ms` |
| `SIN`     | `0.213 ms` | `0.217 ms` | `0.234 ms` |

These are end-to-end host/PYNQ/AXI-DMA transaction measurements. They include software and transfer overhead and must not be interpreted as intrinsic RTL pipeline latency.

The current characterization also does not establish maximum sustained throughput under back-to-back streaming operation.

## FPGA Hardware Validation

The current V1 numerical characterization has been performed on physical AMD/Xilinx Kria KR260 hardware using:

* the `FPU2.bit` bitstream;
* the `vrm_fpu_axi_0` AXI-Lite control interface;
* `axi_dma_0` for operand/result movement;
* PYNQ software running on the Kria platform.

The hardware tests confirm that the integrated AXI control/data path and the characterized FPU operations can be exercised successfully on real FPGA hardware.

The results should not be interpreted as an exhaustive IEEE-754 compliance suite. They provide a measured V1 numerical baseline and expose specific limitations in special-value semantics, subnormal handling, extreme division ranges, and transcendental approximation domains.

## Verification Scope

The current characterization is intentionally a V1 functional and numerical baseline rather than a complete compliance framework.

Covered by the latest hardware characterization:

* directed finite arithmetic;
* randomized finite arithmetic;
* selected special values;
* signed-zero behavior;
* subnormal and exponent boundaries;
* transcendental point measurements;
* transcendental wide/local sweeps;
* software-orchestrated composite functions;
* end-to-end PYNQ/DMA timing.

Not established by this baseline:

* exhaustive IEEE-754 compliance;
* all rounding modes;
* complete exception-flag verification;
* exhaustive NaN payload/signaling behavior;
* complete integer/FP64 conversion characterization;
* maximum sustained hardware throughput;
* formal proof or exhaustive randomized coverage over the complete FP64 state space.

The current results are therefore the numerical characterization baseline for VRM-FPU V1. Further expansion is optional and should be treated as a separate verification/compliance effort rather than as a prerequisite for using the current V1 implementation as a hardware research platform.
