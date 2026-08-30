# VRM21-FPU-Series

**64-bit IEEE 754 Floating-Point Hardware Accelerator for FPGA**

`VRM21-FPU-Series` is a modular double-precision floating-point unit (FPU) implemented in Verilog/SystemVerilog and designed for FPGA-based hardware acceleration.

The project provides a reusable FP64 computation architecture covering basic arithmetic, conversion, comparison, transcendental functions, and activation functions. The FPU is exposed through an AXI-based hardware interface and can be controlled from an embedded processor through AXI-Lite and AXI-Stream/DMA.

The design has been verified through both **RTL simulation** and **FPGA hardware validation on a Kria KV260 platform**.

---

## Features

* 64-bit IEEE 754 double-precision datapath
* Modular FPU architecture
* AXI-Lite control interface
* AXI-Stream data interface
* AXI DMA integration
* FPGA hardware acceleration
* Parameterized internal arithmetic modules
* Support for basic floating-point operations
* Integer ↔ FP64 conversion
* Floating-point comparison and classification
* Transcendental function approximation
* Activation functions
* Micro-operation based function composition

---

## Supported Operations

### Basic Arithmetic

| Operation | Function |
| --------- | -------- |
| ADD       | `A + B`  |
| SUB       | `A - B`  |
| MUL       | `A × B`  |
| DIV       | `A / B`  |
| SQRT      | `√A`     |

### Conversion and Comparison

| Operation | Function                               |
| --------- | -------------------------------------- |
| I2F       | 32-bit signed integer → FP64           |
| F2I       | FP64 → 32-bit signed integer           |
| FEQ       | Floating-point equality                |
| FLT       | Floating-point less-than               |
| FLE       | Floating-point less-than-or-equal      |
| FMIN      | Floating-point minimum                 |
| FMAX      | Floating-point maximum                 |
| FCLASS    | IEEE 754 floating-point classification |

### Transcendental Functions

| Operation | Function  |
| --------- | --------- |
| LOG2      | `log₂(x)` |
| LN        | `ln(x)`   |
| EXP2      | `2ˣ`      |
| EXP       | `eˣ`      |
| SIN       | `sin(x)`  |
| COS       | `cos(x)`  |

### Activation Functions

| Operation | Function        |
| --------- | --------------- |
| SIGMOID   | `1 / (1 + e⁻ˣ)` |
| TANH      | `tanh(x)`       |

The transcendental and activation units use hardware-oriented numerical approximations rather than software library implementations.

---

## Higher-Level Hardware Micro-Operations

The FPU primitives can also be orchestrated into more complex mathematical functions.

The current FPGA demonstration includes:

```text
POWER
x^y = 2^(y × log2(x))

TAN
tan(x) = sin(x) / cos(x)

LOG10
log10(x) = ln(x) / ln(10)

GELU
GELU(x) ≈ 0.5 × x × (1 + tanh(√(2/π) × (x + 0.044715x³)))
```

These higher-level functions demonstrate that the individual FPU blocks can be composed into larger computational pipelines without requiring a dedicated hardware block for every mathematical operation.

---

## Architecture

The design is organized as a collection of independent computational units.

```text
                         ┌──────────────────────┐
                         │      AXI-Lite        │
                         │   Control Registers  │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │     VRM FPU AXI      │
                         │     Control Core     │
                         └──────────┬───────────┘
                                    │
                              AXI-Stream
                                    │
                                    ▼
                    ┌──────────────────────────────┐
                    │          FPU Core            │
                    │                              │
                    │  ┌────────┐  ┌────────────┐  │
                    │  │  ADD   │  │    MUL     │  │
                    │  └────────┘  └────────────┘  │
                    │                              │
                    │  ┌────────┐  ┌────────────┐  │
                    │  │  DIV   │  │    SQRT    │  │
                    │  └────────┘  └────────────┘  │
                    │                              │
                    │  ┌────────┐  ┌────────────┐  │
                    │  │ CONV   │  │   MISC     │  │
                    │  └────────┘  └────────────┘  │
                    │                              │
                    │  ┌────────────────────────┐  │
                    │  │   Transcendental Unit  │  │
                    │  │ LOG2 / LN / EXP2 / EXP │  │
                    │  │ SIN / COS              │  │
                    │  └────────────────────────┘  │
                    │                              │
                    │  ┌────────────────────────┐  │
                    │  │   Activation Functions │  │
                    │  │ SIGMOID / TANH         │  │
                    │  └────────────────────────┘  │
                    └──────────────┬───────────────┘
                                   │
                              AXI-Stream
                                   │
                                   ▼
                              AXI DMA / PS
```

The transcendental functions are implemented by composing lower-level floating-point primitives such as multiplication and addition with polynomial approximation.

For more details, see:

* [`docs/architecture.md`](docs/architecture.md)
* [`docs/module_overview.md`](docs/module_overview.md)
* [`docs/interface.md`](docs/interface.md)
* [`docs/numerical_implementation.md`](docs/numerical_implementation.md)

---

## Numerical Implementation

Several transcendental functions use polynomial approximation and Horner-form evaluation.

For example, the sine implementation follows the general structure:

```text
x²
 │
 ▼
Polynomial evaluation
 │
 ▼
x × P(x²)
 │
 ▼
sin(x)
```

This structure allows the computation to be mapped onto reusable floating-point multiplier and adder units.

The same architectural concept is used for other transcendental functions.

Because these functions are approximations, their numerical accuracy depends on the approximation order, input range, floating-point implementation, and range-reduction strategy.

Detailed implementation notes are available in:

[`docs/numerical_implementation.md`](docs/numerical_implementation.md)

---

# Verification

The project has two levels of validation:

```text
                 VRM21-FPU-Series
                        │
             ┌──────────┴──────────┐
             │                     │
             ▼                     ▼
      RTL Simulation         FPGA Validation
             │                     │
             ▼                     ▼
       Verilog Testbench      Kria KV260
             │                     │
             ▼                     ▼
       Functional Check      PYNQ + AXI DMA
```

## RTL Simulation

The AXI testbench validates the major FPU operation groups.

The simulation baseline includes:

* Basic arithmetic
* Integer/FP64 conversion
* Comparison
* `LOG2`
* `EXP2`
* `LN`
* `EXP`
* `SIN`
* `COS`
* `SIGMOID`
* `TANH`

Example exact results include:

```text
ADD  (1.5 + 2.5) : 4010000000000000
SUB  (5.0 - 3.0) : 4000000000000000
MUL  (2.0 * 3.0) : 4018000000000000
DIV  (6.0 / 2.0) : 4008000000000000
SQRT (sqrt(4.0)) : 4000000000000000

I2F  (Integer 3) : 4008000000000000
F2I  (Double 3.0): 0000000000000003

FEQ  (2.0 == 2.0): 0000000000000001
FLT  (2.0 < 3.0) : 0000000000000001

LOG2 (8.0)       : 4008000000000000
EXP2 (3.0)       : 4020000000000000

SIN  (0.0)       : 0000000000000000
COS  (0.0)       : 3ff0000000000000

SIGMOID (0.0)    : 3fe0000000000000
TANH    (0.0)    : 0000000000000000
```

Fractional transcendental cases have also been evaluated. Their results demonstrate functional behavior, although some remain approximate due to the current polynomial implementations.

See the complete simulation output in:

[`docs/tb_result.md`](docs/tb_result.md)

---

# FPGA Hardware Validation

The FPU has additionally been validated on actual FPGA hardware using a **Kria KV260** platform.

The FPGA system uses:

```text
Python / PYNQ
      │
      ▼
AXI-Lite
      │
      ├── FPU operation
      └── function selector
      │
      ▼
VRM FPU AXI Core
      │
      │ AXI-Stream
      ▼
AXI DMA
      │
      ▼
FP64 FPU Hardware
      │
      ▼
FPGA Result
```

The host-side validation program uses PYNQ to load the FPGA bitstream, configure the FPU through AXI-Lite registers, and transfer FP64 operands through AXI DMA.

The hardware interface is exercised through a single-operation function:

```python
fpu_calc(op_a, op_b, fpu_op, funct3)
```

This provides a simple software-to-hardware interface for issuing individual FPU operations.

---

## FPGA Demonstration

The hardware validation was extended beyond individual primitives into multi-pass mathematical functions.

Validated hardware demonstrations include:

### Basic Operations

```text
ADD
SUB
MUL
DIV
SQRT
```

### Transcendental Operations

```text
EXP
LN
LOG2
SIN
COS
```

### Micro-Operation Composition

```text
x^y
tan(x)
log10(x)
GELU(x)
```

For example:

```text
x^y
 │
 ├── LOG2(x)
 │
 ├── y × LOG2(x)
 │
 └── EXP2(...)
          │
          ▼
         x^y
```

And:

```text
GELU(x)
 │
 ├── x²
 ├── x³
 ├── 0.044715 × x³
 ├── x + term
 ├── √(2/π) × term
 ├── TANH(...)
 ├── 1 + TANH(...)
 ├── 0.5 × x
 └── final multiplication
          │
          ▼
       GELU(x)
```

This demonstrates the FPU as a reusable hardware mathematical engine rather than merely a collection of isolated operators.

---

# FPGA Platform

The current hardware validation environment is based on:

| Component             | Platform              |
| --------------------- | --------------------- |
| FPGA Board            | AMD/Xilinx Kria KV260 |
| Host Framework        | PYNQ                  |
| Control               | AXI-Lite              |
| Data Transfer         | AXI DMA               |
| Floating-Point Format | IEEE 754 FP64         |
| HDL                   | Verilog/SystemVerilog |

The Python application runs on the Kria processing system and communicates with the programmable logic containing the FPU accelerator.

---

# Repository Structure

```text
VRM21-FPU-Series/
│
├── rtl/
│   ├── vrm_fpu_axi.v
│   ├── vrm_fpu_add_sub_64.v
│   ├── vrm_fpu_mul_64.v
│   ├── vrm_fpu_div_64.v
│   ├── vrm_fpu_sqrt_64.v
│   ├── vrm_fpu_conv_64.v
│   ├── vrm_fpu_misc_64.v
│   ├── vrm_fpu_log2_64.v
│   ├── vrm_fpu_ln_64.v
│   ├── vrm_fpu_exp2_64.v
│   ├── vrm_fpu_exp_64.v
│   ├── vrm_fpu_sigmoid_64.v
│   ├── vrm_fpu_tanh_64.v
│   ├── vrm_fpu_sin_64.v
│   ├── vrm_fpu_cos_64.v
│   └── ...
│
├── tb/
│   └── tb_vrm_fpu_axi.v
│
├── docs/
│   ├── architecture.md
│   ├── module_overview.md
│   ├── interface.md
│   ├── numerical_implementation.md
│   ├── tb_result.md
│   └── limitations.md
│
└── README.md
```

The exact repository structure may evolve as additional FPU modules are integrated.

---

# Interface Overview

The primary accelerator interface consists of:

### AXI-Lite

Used for configuring the operation:

```text
Register 0x08
    FPU operation selector

Register 0x0C
    Function selector / funct3
```

### AXI-Stream

Used for transferring floating-point operands and results.

For binary operations:

```text
Input Stream:

    Operand A
       │
       ▼
    Operand B
       │
      TLAST
       │
       ▼
    FPU Core
       │
       ▼
    Result Stream
```

AXI DMA can be used to transfer operand and result buffers between the processing system and programmable logic.

More details:

[`docs/interface.md`](docs/interface.md)

---

# Design Philosophy

The project is structured around several principles:

### Modular

Each mathematical operation is implemented as an independent hardware block whenever practical.

### Reusable

Lower-level arithmetic units can be reused by higher-level mathematical functions.

### Hardware-Oriented

The implementations prioritize synthesizable RTL structures and FPGA-compatible datapaths.

### Composable

Complex functions can be constructed from simpler FPU operations.

### Verifiable

The same hardware interface can be exercised from both RTL simulation and an embedded FPGA software environment.

---

# Current Verification Status

| Function | RTL Simulation | FPGA Validation |
| -------- | :------------: | :-------------: |
| ADD      |        ✓       |        ✓        |
| SUB      |        ✓       |        ✓        |
| MUL      |        ✓       |        ✓        |
| DIV      |        ✓       |        ✓        |
| SQRT     |        ✓       |        ✓        |
| I2F      |        ✓       |        —        |
| F2I      |        ✓       |        —        |
| FEQ      |        ✓       |        —        |
| FLT      |        ✓       |        —        |
| FLE      |   Implemented  |        —        |
| FMIN     |        ✓       |        —        |
| FMAX     |   Implemented  |        —        |
| FCLASS   |   Implemented  |        —        |
| LOG2     |        ✓       |        ✓        |
| LN       |        ✓       |        ✓        |
| EXP2     |        ✓       |        ✓        |
| EXP      |        ✓       |        ✓        |
| SIN      |        ✓       |        ✓        |
| COS      |        ✓       |        ✓        |
| SIGMOID  |        ✓       |   Implemented   |
| TANH     |        ✓       |        ✓        |
| POW      |        —       |        ✓        |
| TAN      |        —       |        ✓        |
| LOG10    |        —       |        ✓        |
| GELU     |        —       |        ✓        |

A check mark in the FPGA column indicates that the function has been exercised through the hardware accelerator environment. It does not imply exhaustive numerical validation across the complete IEEE 754 input space.

---

# Limitations

The current implementation should be considered a hardware research/development implementation rather than a fully IEEE 754-compliant commercial FPU.

Known limitations include:

* Transcendental functions use numerical approximations.
* Numerical accuracy varies with the input range.
* Some functions require range reduction performed by the software layer.
* Exceptional IEEE 754 cases are not necessarily handled identically to a commercial CPU FPU.
* FPGA validation currently covers selected functional cases rather than exhaustive testing.
* Resource utilization and timing characteristics are FPGA-device dependent.
* Higher-level functions such as `pow`, `tan`, `log10`, and `GELU` are currently demonstrated through composition of existing hardware primitives.

Further details:

[`docs/limitations.md`](docs/limitations.md)

---

# Documentation

| Document                                                          | Description                              |
| ----------------------------------------------------------------- | ---------------------------------------- |
| [`architecture.md`](docs/architecture.md)                         | Overall FPU architecture                 |
| [`module_overview.md`](docs/module_overview.md)                   | Module and function overview             |
| [`interface.md`](docs/interface.md)                               | AXI and module interfaces                |
| [`numerical_implementation.md`](docs/numerical_implementation.md) | Numerical approximation techniques       |
| [`tb_result.md`](docs/tb_result.md)                               | RTL simulation results                   |
| [`limitations.md`](docs/limitations.md)                           | Known limitations and verification scope |

---

# Example Software Flow

A typical FPGA application follows:

```text
1. Load FPGA bitstream
        │
        ▼
2. Access VRM FPU AXI peripheral
        │
        ▼
3. Configure FPU operation
        │
        ▼
4. Prepare FP64 operands
        │
        ▼
5. Transfer operands using AXI DMA
        │
        ▼
6. Execute hardware operation
        │
        ▼
7. Receive FP64 result
        │
        ▼
8. Process / display result
```

The current PYNQ demonstration additionally provides a command-line calculator capable of exposing the hardware accelerator through common mathematical operations.

---

# Project Status

**Status: Active Development**

The current release represents a functional FP64 FPGA FPU platform with:

* RTL implementation
* AXI-based hardware interface
* RTL simulation baseline
* FPGA hardware validation
* Transcendental function support
* Activation function support
* Higher-level mathematical function composition

Future development may focus on improving numerical accuracy, expanding IEEE 754 special-case handling, optimizing FPGA resource utilization, improving throughput/latency, and extending the supported mathematical function set.

---

## License

Licensed under the MIT License.
Provided as-is, without warranty.

---

## Author

**VRM21-Studios**

Hardware architecture, RTL implementation, verification, and FPGA integration developed as part of the VRM21 hardware acceleration projects.
