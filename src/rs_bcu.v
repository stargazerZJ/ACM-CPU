`include "const_def.v"

module reservation_station_bcu(
    input wire clk_in, // system clock signal

    // Operation input
    input wire operation_enabled, // enabled signal for operation
    input wire [2:0] op, // operation code, func3
    input wire [31:0] Vj, // value of Vj
    input wire [31:0] Vk, // value of Vk
    input wire [`ROB_RANGE] Qj, // ROB index for Vj
    input wire [`ROB_RANGE] Qk, // ROB index for Vk
    input wire [`ROB_RANGE] dest, // destination ROB index
    input wire [31:0] pc_fallthrough, // pc fallthrough address
    input wire [31:0] pc_target, // pc target address

    // CDB input (ALU)
    input wire [`ROB_RANGE] cdb_alu_rob_id, // ROB id from ALU
    input wire [31:0] cdb_alu_value, // value from ALU

    // CDB input (MEM)
    input wire [`ROB_RANGE] cdb_mem_rob_id, // ROB id from MEM
    input wire [31:0] cdb_mem_value, // value from MEM

    input wire flush_input, // flush signal

    // Output to Decoder
    output wire has_no_vacancy, // whether the station is full at the end of the cycle
    output wire has_one_vacancy, // whether the station has only one vacancy at the end of the cycle

    // Output to BCU
    output reg [2:0] bcu_op, // operation code to BCU
    output reg [31:0] bcu_Vj, // Vj to BCU
    output reg [31:0] bcu_Vk, // Vk to BCU
    output reg [`ROB_RANGE] bcu_dest, // destination to BCU
    output reg [31:0] bcu_pc_fallthrough, // pc fallthrough to BCU
    output reg [31:0] bcu_pc_target // pc target to BCU
);

reg [`RS_ARR] busy;
reg [2:0] op_entries[`RS_ARR];
reg [31:0] Vj_entries[`RS_ARR];
reg [31:0] Vk_entries[`RS_ARR];
reg [`ROB_RANGE] Qj_entries[`RS_ARR];
reg [`ROB_RANGE] Qk_entries[`RS_ARR];
reg [`ROB_RANGE] dest_entries[`RS_ARR];
reg [31:0] pc_fallthrough_entries[`RS_ARR];
reg [31:0] pc_target_entries[`RS_ARR];

// Combinational logic for finding slots and counting vacancies
wire [3:0] vacant_index;
wire has_vacant;
wire [3:0] ready_index;
wire has_ready;

find_first_vacant vacant_finder(
    .busy(busy),
    .vacant_index(vacant_index),
    .has_vacant(has_vacant)
);

find_first_ready ready_finder(
    .busy(busy),
    .Qj_entries(Qj_entries),
    .Qk_entries(Qk_entries),
    .ready_index(ready_index),
    .has_ready(has_ready)
);

count_vacancies vacancy_counter(
    .busy(busy),
    .has_no_vacancy(has_no_vacancy),
    .has_one_vacancy(has_one_vacancy)
);

// Wire up the input values with CDB updates
wire [31:0] new_Vj = `GET_NEW_VAL(Vj, Qj, cdb_alu_rob_id, cdb_alu_value, cdb_mem_rob_id, cdb_mem_value);
wire [`ROB_RANGE] new_Qj = `GET_NEW_Q(Qj, cdb_alu_rob_id, cdb_mem_rob_id);
wire [31:0] new_Vk = `GET_NEW_VAL(Vk, Qk, cdb_alu_rob_id, cdb_alu_value, cdb_mem_rob_id, cdb_mem_value);
wire [`ROB_RANGE] new_Qk = `GET_NEW_Q(Qk, cdb_alu_rob_id, cdb_mem_rob_id);

integer i;

always @(posedge clk_in) begin
    if (flush_input) begin
        // Reset logic
        for (i = 0; i < `RS_SIZE; i = i + 1) begin
            busy[i] <= 0;
            op_entries[i] <= 0;
            Vj_entries[i] <= 0;
            Vk_entries[i] <= 0;
            Qj_entries[i] <= 0;
            Qk_entries[i] <= 0;
            dest_entries[i] <= 0;
            pc_fallthrough_entries[i] <= 0;
            pc_target_entries[i] <= 0;
        end
        bcu_op <= 0;
        bcu_Vj <= 0;
        bcu_Vk <= 0;
        bcu_dest <= 0;
        bcu_pc_fallthrough <= 0;
        bcu_pc_target <= 0;
    end else begin
        // Update existing entries with CDB data
        for (i = 0; i < `RS_SIZE; i = i + 1) begin
            if (busy[i]) begin
                `UPDATE_ENTRY_WITH_CDB(
                    Vj_entries[i], Qj_entries[i],
                    cdb_alu_rob_id, cdb_alu_value,
                    cdb_mem_rob_id, cdb_mem_value
                )
                `UPDATE_ENTRY_WITH_CDB(
                    Vk_entries[i], Qk_entries[i],
                    cdb_alu_rob_id, cdb_alu_value,
                    cdb_mem_rob_id, cdb_mem_value
                )
            end
        end

        // Add new operation if enabled
        if (operation_enabled && has_vacant) begin
            busy[vacant_index] <= 1;
            op_entries[vacant_index] <= op;
            Vj_entries[vacant_index] <= new_Vj;
            Vk_entries[vacant_index] <= new_Vk;
            Qj_entries[vacant_index] <= new_Qj;
            Qk_entries[vacant_index] <= new_Qk;
            dest_entries[vacant_index] <= dest;
            pc_fallthrough_entries[vacant_index] <= pc_fallthrough;
            pc_target_entries[vacant_index] <= pc_target;
        end

        // Issue operation to BCU if any is ready
        if (has_ready) begin
            bcu_op <= op_entries[ready_index];
            bcu_Vj <= Vj_entries[ready_index];
            bcu_Vk <= Vk_entries[ready_index];
            bcu_dest <= dest_entries[ready_index];
            bcu_pc_fallthrough <= pc_fallthrough_entries[ready_index];
            bcu_pc_target <= pc_target_entries[ready_index];
            busy[ready_index] <= 0;
        end else begin
            bcu_op <= 0;
            bcu_Vj <= 0;
            bcu_Vk <= 0;
            bcu_dest <= 0;
            bcu_pc_fallthrough <= 0;
            bcu_pc_target <= 0;
        end
    end
end

endmodule

module bcu(
    input wire clk_in, // system clock signal

    input wire [2:0] op, // operation code
    input wire [31:0] rs1,
    input wire [31:0] rs2,
    input wire [`ROB_RANGE] dest,
    input wire [31:0] pc_fallthrough,
    input wire [31:0] pc_target,

    // BCU output is not sent to CDB, but to ROB only.
    output reg [`ROB_RANGE] rob_id, // 0 means invalid
    output reg taken,               // branch taken flag (1 bit only)
    output reg [31:0] value         // next PC value (pc_target or pc_fallthrough)
);

wire take_branch;

// Combinational logic for branch evaluation
assign take_branch =
    (op == 3'b000) ? (rs1 == rs2) :              // BEQ
    (op == 3'b001) ? (rs1 != rs2) :              // BNE
    (op == 3'b100) ? ($signed(rs1) < $signed(rs2)) :   // BLT
    (op == 3'b101) ? ($signed(rs1) >= $signed(rs2)) :  // BGE
    (op == 3'b110) ? (rs1 < rs2) :               // BLTU
    (op == 3'b111) ? (rs1 >= rs2) :              // BGEU
    1'b0;  // Default case

always @(posedge clk_in) begin
    // if destination is 0, the output is invalid
    if (dest == 0) begin
        rob_id <= 0;
        taken  <= 0;
        value  <= 0;
    end else begin
        taken <= take_branch;
        value <= (take_branch ? pc_target : pc_fallthrough);

        // Set the rob_id to the 'dest' register
        rob_id <= dest;
    end
end

endmodule