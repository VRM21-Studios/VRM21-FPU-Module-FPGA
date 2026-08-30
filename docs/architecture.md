# VRM21 FPU Architecture

## Overview

The `VRM21-FPU-Series` is a Verilog-based floating-point processing unit targeting 64-bit IEEE-754 double-precision datapaths. The current architecture is organized as a collection of reusable arithmetic, conversion, comparison, transcendental, trigonometric, and activation-function units.

The design uses a modular architecture in which complex functions are constructed from reusable primitive FPU blocks such as floating-point addition/subtraction, multiplication, and division.

## Architectural Structure

At the system level, the FPU is accessed through an AXI-Lite control interface and an AXI-Stream data interface.

```text
                 +----------------------+
                 |      AXI-Lite        |
                 |   Control Registers  |
                 +----------+-----------+
                            |
                            v
+-------------+      +------+-------+      +----------------+
| AXI-Stream  | ---> |   FPU AXI    | ---> |  AXI-Stream    |
| Input       |      |    Wrapper   |      |  Output        |
+-------------+      +------+-------+      +----------------+
                            |
                            v
                 +----------------------+
                 |    FPU Function      |
                 |       Units          |
                 +----------------------+
                   |   |   |   |   |
                   v   v   v   v   v
                 ADD MUL DIV SQRT CONV
                   |   |   |   |   |
                   +---+---+---+---+
                           |
                           v
                    Transcendental /
                    Trigonometric /
                    Activation Units
```

## Functional Groups

The implementation is divided into several functional groups:

- Basic arithmetic: addition/subtraction, multiplication, division, and square root.
- Conversion: integer-to-double and double-to-integer conversion.
- Comparison and classification: equality, less-than, less-or-equal, minimum, maximum, and floating-point classification.
- Transcendental functions: `log2`, `ln`, `exp2`, and `exp`.
- Activation functions: sigmoid and hyperbolic tangent.
- Trigonometric functions: sine and cosine.
- Supporting infrastructure: unpacking, constants, and AXI integration.

## Reusable Datapath

Higher-level functions reuse lower-level FPU operators instead of implementing an independent floating-point datapath for every function.

Examples:

```text
ln(x)      = log2(x) * ln(2)

exp(x)     = exp2(x * log2(e))

sigmoid(x) = 1 / (1 + exp(-x))

tanh(x)    = (exp(2x) - 1) / (exp(2x) + 1)
```

Polynomial-based functions use Horner evaluation to reduce the number of required multiplications and additions.

## Pipeline and Control

Several complex functions are implemented as finite-state machines that sequence reusable arithmetic units. The control logic asserts `valid_in` for a selected operation, waits for the corresponding `valid_out`, and advances to the next stage.

This approach favors resource reuse and a compact implementation over maximum parallel throughput.

## Current Scope

The current verification baseline focuses on functional simulation of the AXI-connected FP64 datapath. FPGA implementation and timing/resource characterization should be documented separately when those measurements are available.
