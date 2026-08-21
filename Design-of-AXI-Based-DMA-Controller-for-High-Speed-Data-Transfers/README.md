# AXI-Based DMA Controller for High-Speed Data Transfers

## Overview

This project implements an **AXI4-based Direct Memory Access (DMA) Controller** in **SystemVerilog**. The controller enables high-speed data transfer between source and destination memory without continuous CPU intervention. It supports multiple DMA channels, burst-based AXI transactions, and interrupt generation upon transfer completion.

## Features

- AXI4 Master Interface
- Multi-channel DMA architecture
- Burst-based data transfers
- Round-robin channel scheduling
- Interrupt generation after transfer completion
- Modular RTL design
- Simple SystemVerilog testbench for functional verification

## Project Structure

```
.
├── rtl/    # RTL source files
└── tb/     # Testbench files
```

## Design Highlights

- Multi-channel DMA Controller
- Independent Read and Write Engines
- Per-channel Data Buffers
- Round-Robin Arbitration
- AXI Burst Transfers
- Interrupt Handling

## Verification

The design is verified using a lightweight SystemVerilog testbench. Functional simulations validate:

- Basic data transfer
- Multi-channel operation
- Interrupt generation
- Burst transactions

## Tools Used

- SystemVerilog
- QuestaSim

## Future Improvements

- Channel priority scheduling
- Performance optimization
- Additional functional coverage
- UVM-based verification environment

## Authors

DVLSI Batch04

Soumya Karukula- soumyakarukula06@gmail.com
Shhadaja Chaudhari- shhadaja963@gmail.com
Thallapalli Nikitha- thallapallinikitha@gmail.com
Swati Kotrange- swatikatrange07@gmail.com
