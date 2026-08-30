# Current Limitations

## Numerical Approximation

The transcendental and trigonometric functions are approximation-based. They are not currently documented as correctly rounded IEEE-754 implementations.

Exact bit matching is therefore appropriate for selected elementary test vectors, but not as a universal accuracy criterion for functions such as `log2`, `ln`, `exp2`, `exp`, `sin`, and `cos`.

## Special-Value Coverage

The current implementation contains handling for several FP64 special values, but the baseline testbench does not exhaustively verify:

- positive and negative zero;
- positive and negative infinity;
- quiet NaN;
- signaling NaN;
- subnormal values;
- invalid-operation cases;
- overflow and underflow behavior.

These cases should be added to a dedicated IEEE-754 compliance-oriented testbench.

## Rounding and Exception Behavior

The current baseline documentation does not claim complete implementation of IEEE-754 exception flags or all required rounding-mode behaviors.

If strict IEEE-754 compliance becomes a project requirement, the design should explicitly document and verify:

- rounding modes;
- invalid operation;
- divide-by-zero;
- overflow;
- underflow;
- inexact;
- exception flags.

## Conversion Range

Integer/FP64 conversion is currently centered around the datapath requirements of the project and the tested 32-bit integer cases. Boundary behavior for values outside the supported integer range requires additional verification.

## Trigonometric Range Reduction

The current sine and cosine implementations use polynomial evaluation. A comprehensive implementation for arbitrary large-magnitude arguments requires robust argument/range reduction before polynomial evaluation.

The current baseline tests only include zero-input cases for sine and cosine.

## Throughput

Several high-level functions are sequential FSM-based implementations that reuse arithmetic units. This reduces duplicated hardware but results in multi-cycle latency.

The current documentation does not claim a specific maximum throughput until the complete integrated design has been characterized.

## FPGA Validation

Simulation results should not be interpreted as FPGA validation.

Resource utilization, timing closure, maximum clock frequency, power, and actual FPGA behavior require synthesis, implementation, and hardware testing on the target device.

## Verification Scope

The current testbench is a functional baseline rather than a complete verification suite.

Recommended future extensions include:

1. randomized arithmetic testing;
2. directed corner-case testing;
3. IEEE-754 special-value testing;
4. numerical error measurement against a software reference;
5. latency verification;
6. back-to-back transaction testing;
7. AXI handshake stress testing;
8. FPGA implementation and hardware validation.
