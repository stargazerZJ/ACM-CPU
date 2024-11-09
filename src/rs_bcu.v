`include "const_def.v"

module reservation_station(
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
    output reg has_no_vacancy, // whether the station is full at the end of the cycle
    output reg has_one_vacancy, // whether the station has only one vacancy at the end of the cycle

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
wire comb_has_no_vacancy;
wire comb_has_one_vacancy;

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
    .has_no_vacancy(comb_has_no_vacancy),
    .has_one_vacancy(comb_has_one_vacancy)
);

// Wire up the input values with CDB updates
wire [31:0] new_Vj = (Qj == cdb_alu_rob_id) ? cdb_alu_value :
                     (Qj == cdb_mem_rob_id) ? cdb_mem_value : Vj;
wire [`ROB_RANGE] new_Qj = (Qj == cdb_alu_rob_id || Qj == cdb_mem_rob_id) ? 0 : Qj;

wire [31:0] new_Vk = (Qk == cdb_alu_rob_id) ? cdb_alu_value :
                     (Qk == cdb_mem_rob_id) ? cdb_mem_value : Vk;
wire [`ROB_RANGE] new_Qk = (Qk == cdb_alu_rob_id || Qk == cdb_mem_rob_id) ? 0 : Qk;

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
                if (Qj_entries[i] == cdb_alu_rob_id) begin
                    Vj_entries[i] <= cdb_alu_value;
                    Qj_entries[i] <= 0;
                end
                if (Qj_entries[i] == cdb_mem_rob_id) begin
                    Vj_entries[i] <= cdb_mem_value;
                    Qj_entries[i] <= 0;
                end
                if (Qk_entries[i] == cdb_alu_rob_id) begin
                    Vk_entries[i] <= cdb_alu_value;
                    Qk_entries[i] <= 0;
                end
                if (Qk_entries[i] == cdb_mem_rob_id) begin
                    Vk_entries[i] <= cdb_mem_value;
                    Qk_entries[i] <= 0;
                end
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

    // Update vacancy flags
    has_no_vacancy <= comb_has_no_vacancy;
    has_one_vacancy <= comb_has_one_vacancy;
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

always @(posedge clk_in) begin
    // if destination is 0, the output is invalid
    if (dest == 0) begin
        rob_id <= 0;
        taken  <= 0;
        value  <= 0;
    end else begin
        // Temporary variable to hold branch decision
        reg take_branch;

        // Check the opcode to determine the type of branch
        case (op)
            3'b000: // BEQ: Branch if Equal
                take_branch = (rs1 == rs2);
            3'b001: // BNE: Branch if Not Equal
                take_branch = (rs1 != rs2);
            3'b100: // BLT: Branch if Less Than (signed)
                take_branch = ($signed(rs1) < $signed(rs2));
            3'b101: // BGE: Branch if Greater Equal (signed)
                take_branch = ($signed(rs1) >= $signed(rs2));
            3'b110: // BLTU: Branch if Less Than (unsigned)
                take_branch = (rs1 < rs2);
            3'b111: // BGEU: Branch if Greater Equal (unsigned)
                take_branch = (rs1 >= rs2);
            default:
                $fatal("Invalid branch operation: %b", op);
        endcase

        // Update `taken` and `value` based on the branch decision
        taken <= take_branch;
        value <= (take_branch ? pc_target : pc_fallthrough);

        // Set the rob_id to the 'dest' register
        rob_id <= dest;
    end
end

endmodule