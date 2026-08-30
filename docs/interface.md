# FPU Interface

## AXI-Lite Control Interface

The FPU wrapper uses an AXI4-Lite control interface with a 32-bit data width.

The current verification environment programs the FPU operation and function selector through the following registers:

| Offset | Register | Description |
|---:|---|---|
| `0x08` | `reg_fpu_op` | Main FPU operation selector |
| `0x0C` | `reg_funct3` | Function/sub-operation selector |

The testbench writes these registers before sending operands through the AXI-Stream input.

## AXI-Stream Data Interface

The data path is 64 bits wide.

### Input

```text
s_axis_tdata   [63:0]
s_axis_tvalid
s_axis_tready
s_axis_tlast
```

For binary operations, the current testbench sends:

```text
beat 0: operand A, tlast = 0
beat 1: operand B, tlast = 1
```

For unary operations, the wrapper may use only the first operand according to its operation-specific implementation.

### Output

```text
m_axis_tdata   [63:0]
m_axis_tvalid
m_axis_tready
m_axis_tlast
```

The result is transferred when both `m_axis_tvalid` and `m_axis_tready` are asserted.

## Operation Selection

The current verification testbench uses the following main operation codes:

| `fpu_op` | Operation Group |
|---:|---|
| `0` | ADD |
| `1` | SUB |
| `2` | MUL |
| `3` | DIV |
| `4` | SQRT |
| `5` | Conversion: integer to FP64 |
| `6` | Conversion: FP64 to integer |
| `7` | Comparison/classification |
| `8` | Mathematical/transcendental functions |

For `fpu_op = 7`, `funct3` selects comparison/classification behavior.

For `fpu_op = 8`, `funct3` selects the mathematical function.

## Mathematical Function Codes

| `funct3` | Function |
|---:|---|
| `0` | `log2` |
| `1` | `ln` |
| `2` | `exp2` |
| `3` | `exp` |
| `4` | sigmoid |
| `5` | tanh |
| `6` | sin |
| `7` | cos |

## Reset

The design uses an active-low reset signal.

```text
rstn = 0  -> reset
rstn = 1  -> normal operation
```

The AXI wrapper uses `aresetn`, while individual FPU blocks use `rstn`.

## Handshake Convention

The internal FPU blocks use a simple valid pulse convention:

```text
valid_in  -> request accepted
valid_out -> result available
```

Complex functions sequence their internal operators using finite-state control and wait for the `valid_out` response of each dependent operation.
