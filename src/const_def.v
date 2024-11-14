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

// CDB-related
// Macro for checking if CDB value should be used
`define IS_VALID_CDB_UPDATE(Q, CDB_ROB_ID) ((Q) == (CDB_ROB_ID) && (CDB_ROB_ID) != 3'b0)

// Macro for getting new value based on CDB updates
`define GET_NEW_VAL(V, Q, CDB_ALU_ROB_ID, CDB_ALU_VAL, CDB_MEM_ROB_ID, CDB_MEM_VAL) \
    (`IS_VALID_CDB_UPDATE(Q, CDB_ALU_ROB_ID) ? CDB_ALU_VAL : \
     `IS_VALID_CDB_UPDATE(Q, CDB_MEM_ROB_ID) ? CDB_MEM_VAL : V)

// Macro for getting new Q value based on CDB updates
`define GET_NEW_Q(Q, CDB_ALU_ROB_ID, CDB_MEM_ROB_ID) \
    (`IS_VALID_CDB_UPDATE(Q, CDB_ALU_ROB_ID) || `IS_VALID_CDB_UPDATE(Q, CDB_MEM_ROB_ID) ? 3'b0 : Q)

// Macro for sequential CDB update block
`define UPDATE_ENTRY_WITH_CDB(V, Q, CDB_ALU_ROB_ID, CDB_ALU_VAL, CDB_MEM_ROB_ID, CDB_MEM_VAL) \
    if (`IS_VALID_CDB_UPDATE(Q, CDB_ALU_ROB_ID)) begin \
        V <= CDB_ALU_VAL; \
        Q <= 3'b0; \
    end else if (`IS_VALID_CDB_UPDATE(Q, CDB_MEM_ROB_ID)) begin \
        V <= CDB_MEM_VAL; \
        Q <= 3'b0; \
    end