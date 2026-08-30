# RTL

This directory contains the RTL sources used by the VRM FPU.

## FIFO Dependency

The FIFO functionality required by the VRM FPU is provided by the reusable **`vrm_fifo`** module maintained in the separate **VRM21-RTL-Utilities** repository.

The module is intentionally not duplicated in this repository to keep the FIFO implementation centralized and reusable across the VRM21 RTL ecosystem.

### `vrm_fifo`

Source:

[VRM21-RTL-Utilities/rtl/vrm_fifo.v](https://github.com/VRM21-Studios/VRM21-RTL-Utilities/blob/main/rtl/vrm_fifo.v?utm_source=chatgpt.com)

Repository:

[VRM21-RTL-Utilities](https://github.com/VRM21-Studios/VRM21-RTL-Utilities?utm_source=chatgpt.com)

The module provides an AXI4-Stream FIFO interface and can be reused by other VRM21 hardware components requiring buffered streaming data.

## Repository Organization

The RTL sources specific to the VRM FPU are maintained in this directory, while common reusable infrastructure is maintained separately under **VRM21-RTL-Utilities**.

This separation avoids unnecessary source duplication and allows shared RTL components to be maintained independently.
