`include "const_def.v"

// Helper module to find first vacant slot
module find_first_vacant(
    input wire [15:0] busy,
    output wire [3:0] vacant_index,
    output wire has_vacant
);
    wire [3:0] result;
    assign has_vacant = ~(&busy); // NOT of AND reduction - true if any slot is vacant

    // Priority encoder to find first zero (vacant slot)
    assign result[3] = ~(busy[15] | busy[14] | busy[13] | busy[12] | busy[11] | busy[10] | busy[9] | busy[8]);
    assign result[2] = ~(
        (result[3] ? busy[7] : busy[15]) |
        (result[3] ? busy[6] : busy[14]) |
        (result[3] ? busy[5] : busy[13]) |
        (result[3] ? busy[4] : busy[12])
    );
    assign result[1] = ~(
        (result[3:2] == 2'b10 ? busy[3] : (result[3:2] == 2'b11 ? busy[7] : busy[15])) |
        (result[3:2] == 2'b10 ? busy[2] : (result[3:2] == 2'b11 ? busy[6] : busy[14]))
    );
    assign result[0] = ~(
        (result[3:1] == 3'b100 ? busy[1] :
         result[3:1] == 3'b101 ? busy[3] :
         result[3:1] == 3'b110 ? busy[5] :
         result[3:1] == 3'b111 ? busy[7] : busy[15])
    );

    assign vacant_index = result;
endmodule

// Helper module to find first ready-to-issue entry
module find_first_ready(
    input wire [15:0] busy,
    input wire [`ROB_RANGE] Qj_entries [15:0],
    input wire [`ROB_RANGE] Qk_entries [15:0],
    output wire [3:0] ready_index,
    output wire has_ready
);
    wire [15:0] ready;
    integer i;

    // Generate ready signal for each entry
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : ready_gen
            assign ready[g] = busy[g] && (Qj_entries[g] == 0) && (Qk_entries[g] == 0);
        end
    endgenerate

    // Priority encoder for ready entries
    wire [3:0] result;
    assign has_ready = |ready; // OR reduction - true if any entry is ready

    assign result[3] = ~(ready[15] | ready[14] | ready[13] | ready[12] | ready[11] | ready[10] | ready[9] | ready[8]);
    assign result[2] = ~(
        (result[3] ? ready[7] : ready[15]) |
        (result[3] ? ready[6] : ready[14]) |
        (result[3] ? ready[5] : ready[13]) |
        (result[3] ? ready[4] : ready[12])
    );
    assign result[1] = ~(
        (result[3:2] == 2'b10 ? ready[3] : (result[3:2] == 2'b11 ? ready[7] : ready[15])) |
        (result[3:2] == 2'b10 ? ready[2] : (result[3:2] == 2'b11 ? ready[6] : ready[14]))
    );
    assign result[0] = ~(
        (result[3:1] == 3'b100 ? ready[1] :
         result[3:1] == 3'b101 ? ready[3] :
         result[3:1] == 3'b110 ? ready[5] :
         result[3:1] == 3'b111 ? ready[7] : ready[15])
    );

    assign ready_index = result;
endmodule

// Helper module to count vacancies
module count_vacancies(
    input wire [15:0] busy,
    output wire has_no_vacancy,
    output wire has_one_vacancy
);
    wire [4:0] count;
    integer i;

    // Count zeros in busy array using reduction
    assign count = ~busy[0] + ~busy[1] + ~busy[2] + ~busy[3] +
                  ~busy[4] + ~busy[5] + ~busy[6] + ~busy[7] +
                  ~busy[8] + ~busy[9] + ~busy[10] + ~busy[11] +
                  ~busy[12] + ~busy[13] + ~busy[14] + ~busy[15];

    assign has_no_vacancy = (count == 0);
    assign has_one_vacancy = (count == 1);
endmodule

module reservation_station_alu(
    input wire clk_in,
    input wire operation_enabled,
    input wire [3:0] op,
    input wire [31:0] Vj,
    input wire [31:0] Vk,
    input wire [`ROB_RANGE] Qj,
    input wire [`ROB_RANGE] Qk,
    input wire [`ROB_RANGE] dest,
    input wire [`ROB_RANGE] cdb_alu_rob_id,
    input wire [31:0] cdb_alu_value,
    input wire [`ROB_RANGE] cdb_mem_rob_id,
    input wire [31:0] cdb_mem_value,
    input wire flush_input,
    output reg has_no_vacancy,
    output reg has_one_vacancy,
    output reg [3:0] alu_op,
    output reg [31:0] alu_Vj,
    output reg [31:0] alu_Vk,
    output reg [`ROB_RANGE] alu_dest
);

localparam RS_SIZE = 16;

reg [RS_SIZE-1:0] busy;
reg [3:0] op_entries[RS_SIZE-1:0];
reg [31:0] Vj_entries[RS_SIZE-1:0];
reg [31:0] Vk_entries[RS_SIZE-1:0];
reg [`ROB_RANGE] Qj_entries[RS_SIZE-1:0];
reg [`ROB_RANGE] Qk_entries[RS_SIZE-1:0];
reg [`ROB_RANGE] dest_entries[RS_SIZE-1:0];

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
        for (i = 0; i < RS_SIZE; i = i + 1) begin
            busy[i] <= 0;
            op_entries[i] <= 0;
            Vj_entries[i] <= 0;
            Vk_entries[i] <= 0;
            Qj_entries[i] <= 0;
            Qk_entries[i] <= 0;
            dest_entries[i] <= 0;
        end
        alu_op <= 0;
        alu_Vj <= 0;
        alu_Vk <= 0;
        alu_dest <= 0;
    end else begin
        // Update existing entries with CDB data
        for (i = 0; i < RS_SIZE; i = i + 1) begin
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
        end

        // Issue operation to ALU if any is ready
        if (has_ready) begin
            alu_op <= op_entries[ready_index];
            alu_Vj <= Vj_entries[ready_index];
            alu_Vk <= Vk_entries[ready_index];
            alu_dest <= dest_entries[ready_index];
            busy[ready_index] <= 0;
        end else begin
            alu_op <= 0;
            alu_Vj <= 0;
            alu_Vk <= 0;
            alu_dest <= 0;
        end

        // Update vacancy flags
        has_no_vacancy <= comb_has_no_vacancy;
        has_one_vacancy <= comb_has_one_vacancy;
    end
end

endmodule

module alu(
    input wire clk_in, // system clock signal

    input wire [3:0] op, // operation code, the bit 30 of func7, and func3
    input wire [31:0] rs1,
    input wire [31:0] rs2,
    input wire [`ROB_RANGE] dest,

    output reg [`ROB_RANGE] rob_id, // 0 means invalid
    output reg [31:0] value
);

always @(posedge clk_in) begin
    if (dest == 0) begin
        rob_id <= 0;
        value <= 0;
    end else begin
        case (op)
            4'b0000: // ADD, ADDI, auipc, jalr
                value <= rs1 + rs2;
            4'b1000: // SUB
                value <= rs1 - rs2;
            4'b0001: // SLL, SLLI
                value <= rs1 << (rs2[4:0]); // only consider lower 5 bits for shift
            4'b0010: // SLT, SLTI
                value <= ($signed(rs1) < $signed(rs2)) ? 1 : 0;
            4'b0011: // SLTU, SLTIU
                value <= (rs1 < rs2) ? 1 : 0;
            4'b0100: // XOR, XORI
                value <= rs1 ^ rs2;
            4'b0101: // SRL, SRLI
                value <= rs1 >> rs2[4:0]; // logical shift
            4'b1101: // SRA, SRAI
                value <= $signed(rs1) >>> rs2[4:0]; // arithmetic shift
            4'b0110: // OR, ORI
                value <= rs1 | rs2;
            4'b0111: // AND, ANDI
                value <= rs1 & rs2;
            default: // handle unexpected opcodes
                $fatal("Unreachable code reached: unsupported operation.");
        endcase
        rob_id <= dest;
    end
end

endmodule