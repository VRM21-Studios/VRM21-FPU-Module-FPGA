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

## FPGA Hardware Validation

The VRM FPU Series has been validated on an AMD/Xilinx Kria KV260 FPGA platform using a PYNQ-based software interface and AXI DMA data path.

The validation setup loads the FPU bitstream onto the FPGA and communicates with the `vrm_fpu_axi` hardware block through AXI-Lite control registers and AXI4-Stream data transfer. FP64 operands are transferred using a DMA engine, while the selected FPU operation is configured through the AXI-Lite interface.

The hardware validation has been demonstrated for:

* Basic FP64 arithmetic:

  * Addition
  * Subtraction
  * Multiplication
  * Division
  * Square root
* Integer/FP64 conversion:

  * Integer-to-FP64
  * FP64-to-integer
* FP64 comparison operations:

  * Equal
  * Less-than
  * Minimum
* Transcendental functions:

  * `log2`
  * `ln`
  * `exp2`
  * `exp`
  * `sin`
  * `cos`
  * `sigmoid`
  * `tanh`
* Higher-level functions implemented as software-orchestrated micro-operations:

  * Power: `x^y`
  * Tangent: `tan(x)`
  * Base-10 logarithm: `log10(x)`
  * GELU

The FPGA validation confirms that the integrated FPU datapath, AXI-Lite control interface, AXI4-Stream interface, and DMA-based data movement operate correctly on physical FPGA hardware.

However, the validation should not be interpreted as an exhaustive numerical characterization of the FPU. The current tests use a limited set of representative input values and do not constitute a complete IEEE-754 compliance test suite.

## Known Limitations

### 1. Numerical Approximation

Several transcendental functions are implemented using polynomial/Taylor or related approximations rather than fully accurate mathematical implementations. Consequently, the output may contain a numerical error relative to a software reference implementation.

For example, the current simulation results demonstrate small deviations for fractional transcendental inputs:

| Function | Test Input |    Hardware Result |                    Expected |
| -------- | ---------: | -----------------: | --------------------------: |
| `log2`   |        5.0 | `40029351B5FCA815` | approximately `40029311...` |
| `exp2`   |        1.5 | `4006A09EA6E2BC12` | approximately `4006A09E...` |
| `ln`     |          e | `3FF0000D3B63D778` |          `3FF0000000000000` |
| `exp`    |        1.0 | `4005BF0AA8AA0C77` |          `4005BF0A8B145769` |

These results are consistent with the current approximation-based implementation and should be considered when the FPU is used in numerical workloads requiring high precision.

### 2. Limited Input-Domain Characterization

The current verification does not exhaustively cover:

* Very large and very small operands
* Subnormal values
* Overflow and underflow boundaries
* All NaN representations
* Signaling NaNs
* Signed zero corner cases
* Infinity combinations
* Rounding-mode variations
* Full exponent-range stress testing

The presence of hardware validation therefore confirms functional operation of the tested datapaths, but does not establish complete IEEE-754 conformance.

### 3. Transcendental Range Reduction

The current `sin` and `cos` implementations rely on polynomial approximation. Accurate evaluation over a wide input range therefore requires appropriate range reduction.

The higher-level `tan` demonstration performs range reduction in the PYNQ software layer before sending the reduced argument to the FPGA.

### 4. Software-Orchestrated Composite Functions

Functions such as `x^y`, `tan`, `log10`, and GELU are currently constructed from multiple primitive FPU operations through software micro-operation sequences.

For example:

```text
x^y    = exp2(y × log2(x))
tan(x) = sin(x) / cos(x)
log10  = ln(x) / ln(10)
```

These operations therefore incur multiple hardware transactions and are not currently implemented as single dedicated hardware instructions.

### 5. Verification Scope

The repository currently contains both RTL simulation results and physical FPGA validation results. The existing testbench is intended as a functional verification baseline rather than a comprehensive compliance framework.

Future verification work may include:

* Randomized FP64 testing
* Reference comparison against IEEE-754 software implementations
* ULP-based error analysis
* Boundary and corner-case testing
* Extended transcendental-function characterization
* Resource utilization and timing analysis across FPGA configurations
* Throughput and latency benchmarking

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
