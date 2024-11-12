// const for RISC-V instructions

// RS-related
`define RS_SIZE       16
`define RS_RANGE      3:0
`define RS_ARR        15:0

// ROB-related
`define ROB_SIZE      32
`define ROB_RANGE     4:0
`define ROB_ARR       31:0
`define ROB_SIZE_LOG  5

// I-Cache-related
`define I_CACHE_SIZE_LOG  7
`define I_CACHE_SIZE      128 // 128 entries, 2 bytes per entry