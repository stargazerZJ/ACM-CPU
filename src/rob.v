`include "const_def.v"

module rob(
    input wire clk_in, // system clock signal
    input wire rst_in, // reset signal

    // Operation input
    input wire operation_enabled,
    input wire [1:0] operation_op,      // 00 for jalr, 01 for branch, 10 for others, 11 unused
    input wire operation_status,         // 1 for value acquired, 0 otherwise
    input wire [31:0] operation_value,   // for jalr, jump address; for branch/others, value to write to register
    input wire [31:0] operation_alt_value, // for jalr, pc+4; for branch, pc of branch; others, unused
    input wire [4:0] operation_dest,     // the register to store the value
    input wire operation_predicted_branch_taken,

    // CDB input (ALU)
    input wire [`ROB_RANGE] cdb_alu_rob_id,
    input wire [31:0] cdb_alu_value,

    // CDB input (MEM)
    input wire [`ROB_RANGE] cdb_mem_rob_id,
    input wire [31:0] cdb_mem_value,

    // Input from BCU
    input wire [`ROB_RANGE] bcu_rob_id, // 0 means invalid
    input wire bcu_taken,
    input wire [31:0] bcu_value,

    // Output to Register File
    output reg reg_file_enabled,
    output reg [4:0] reg_file_reg_id,
    output reg [31:0] reg_file_data,
    output reg [`ROB_RANGE] reg_file_rob_id,

    // Commit Output
    output reg [`ROB_RANGE] commit_rob_id, // to RS and Decoder, 0 if nothing is committed

    // Output to Fetcher
    output reg fetcher_pc_enabled,
    output reg [31:0] fetcher_pc,
    // Output to the branch predictor (inside Fetcher)
    output reg [31:0] fetcher_branch_pc,
    output reg fetcher_branch_taken,
    output reg fetcher_branch_record_enabled,

    // Output to Decoder
    output wire [31:0] decoder_value [`ROB_ARR],
    output wire decoder_ready [`ROB_ARR],

    // Status outputs
    output wire has_no_vacancy,    // whether the ROB is full
    output wire has_one_vacancy,   // whether the ROB has only one vacancy
    output wire [`ROB_RANGE] next_tail_output,
    output wire [`ROB_RANGE] next_next_tail_output,

    // To all modules
    output reg flush_outputs
);

// Internal registers for ROB entries
reg busy [`ROB_ARR];
reg [1:0] op [`ROB_ARR]; // 00 for jalr, 01 for branch, 10 for others, 11 for special halt instruction
reg value_ready [`ROB_ARR]; // 1 for value acquired, 0 otherwise
reg [31:0] value [`ROB_ARR]; // for jalr, the jump address; for branch and others, the value to write to the register
reg [31:0] alt_value [`ROB_ARR]; // for jalr, pc + 4; for branch, pc of the branch; for others, unused
reg [4:0] dest [`ROB_ARR]; // the register to store the value
reg branch_taken [`ROB_ARR];
reg pred_branch_taken [`ROB_ARR];

reg [`ROB_RANGE] head, tail;

wire operation_value_ready = operation_status ||
                           (operation_dest == cdb_alu_rob_id) ||
                           (operation_dest == cdb_mem_rob_id) ||
                           (operation_dest == bcu_rob_id);

wire [31:0] new_operation_value =
    (operation_dest == cdb_alu_rob_id) ? cdb_alu_value :
    (operation_dest == cdb_mem_rob_id) ? cdb_mem_value :
    (operation_dest == bcu_rob_id) ? bcu_value :
    operation_value;

// Helper function to calculate next tail position
function [`ROB_RANGE] next_tail;
    input [`ROB_RANGE] current_tail;
    begin
        next_tail = (current_tail == 31) ? 1 : current_tail + 1;
    end
endfunction

// Output assignments
assign next_tail_output = next_tail(tail);
assign next_next_tail_output = next_tail(next_tail(tail));
assign has_no_vacancy = (next_tail_output == head) && busy[head];
assign has_one_vacancy = (next_next_tail_output == head);

// Connect decoder outputs
genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : decoder_connections
        assign decoder_value[i] = value[i];
        assign decoder_ready[i] = value_ready[i];
    end
endgenerate

// Main logic
always @(posedge clk_in) begin
    if (rst_in) begin
        // Reset logic
        head <= 1;
        tail <= 0;
        flush_outputs <= 1; // Reset other modules
        // Reset all ROB entries
        for (integer j = 0; j < 32; j = j + 1) begin
            busy[j] <= 0;
            op[j] <= 0;
            value_ready[j] <= 0;
            value[j] <= 0;
            alt_value[j] <= 0;
            dest[j] <= 0;
            branch_taken[j] <= 0;
            pred_branch_taken[j] <= 0;
        end
        // Reset program counter to 0x0000
        fetcher_pc_enabled <= 1;
        fetcher_pc <= 0;
    end else begin
        // Handle new operation input
        if (operation_enabled && !flush_outputs) begin
            busy[next_tail_output] <= 1;
            op[next_tail_output] <= operation_op;
            value_ready[next_tail_output] <= operation_value_ready;
            value[next_tail_output] <= new_operation_value;
            alt_value[next_tail_output] <= operation_alt_value;
            dest[next_tail_output] <= operation_dest;
            branch_taken[next_tail_output] <= 0;
            pred_branch_taken[next_tail_output] <= operation_predicted_branch_taken;
            tail <= next_tail_output;
        end

        // Handle CDB updates (ALU)
        if (cdb_alu_rob_id != 0) begin
            if (busy[cdb_alu_rob_id] && !value_ready[cdb_alu_rob_id]) begin
                value[cdb_alu_rob_id] <= cdb_alu_value;
                value_ready[cdb_alu_rob_id] <= 1;
            end
        end

        // Handle CDB updates (MEM)
        if (cdb_mem_rob_id != 0) begin
            if (busy[cdb_mem_rob_id] && !value_ready[cdb_mem_rob_id]) begin
                value[cdb_mem_rob_id] <= cdb_mem_value;
                value_ready[cdb_mem_rob_id] <= 1;
            end
        end

        // Handle BCU updates
        if (bcu_rob_id != 0) begin
            if (busy[bcu_rob_id] && !value_ready[bcu_rob_id] && op[bcu_rob_id] == 2'b01) begin
                value[bcu_rob_id] <= bcu_value;
                value_ready[bcu_rob_id] <= 1;
                branch_taken[bcu_rob_id] <= bcu_taken;
            end
        end

        // Commit logic
        if (busy[head] && value_ready[head]) begin
            case (op[head])
                2'b00: begin // JALR
                    reg_file_enabled <= 1;
                    reg_file_reg_id <= dest[head];
                    reg_file_data <= alt_value[head];
                    reg_file_rob_id <= head;
                    fetcher_pc_enabled <= 0;
                    commit_rob_id <= head;
                    flush_outputs <= 0;
                    busy[head] <= 0;
                    head <= next_tail(head);
                end

                2'b01: begin // Branch
                    if (branch_taken[head] != pred_branch_taken[head]) begin
                        // Mispredict - flush
                        flush_outputs <= 1;
                        fetcher_pc_enabled <= 1;
                        fetcher_pc <= value[head];
                        fetcher_branch_pc <= alt_value[head];
                        fetcher_branch_taken <= branch_taken[head];
                        fetcher_branch_record_enabled <= 1;
                        // Reset ROB state
                        head <= 1;
                        tail <= 0;
                        for (integer k = 0; k < 32; k = k + 1) begin
                            busy[k] <= 0;
                        end
                    end else begin
                        // Correct prediction
                        fetcher_pc_enabled <= 0;
                        fetcher_branch_pc <= value[head];
                        fetcher_branch_taken <= branch_taken[head];
                        fetcher_branch_record_enabled <= 1;
                        commit_rob_id <= head;
                        reg_file_enabled <= 0;
                        flush_outputs <= 0;
                        busy[head] <= 0;
                        head <= next_tail(head);
                    end
                end

                2'b10: begin // Other operations
                    reg_file_enabled <= 1;
                    reg_file_reg_id <= dest[head];
                    reg_file_data <= value[head];
                    reg_file_rob_id <= head;
                    commit_rob_id <= head;
                    fetcher_pc_enabled <= 0;
                    flush_outputs <= 0;
                    busy[head] <= 0;
                    head <= next_tail(head);
                end
            endcase
        end else begin
            // No commit
            reg_file_enabled <= 0;
            commit_rob_id <= 0;
            fetcher_pc_enabled <= 0;
            fetcher_branch_record_enabled <= 0;
            flush_outputs <= 0;
        end
    end
end

// Debugging
wire head_busy = busy[head];
wire [1:0] head_op = op[head];
wire head_value_ready = value_ready[head];
wire [31:0] head_value = value[head];
wire [31:0] head_alt_value = alt_value[head];
wire [4:0] head_dest = dest[head];
wire head_branch_taken = branch_taken[head];
wire head_pred_branch_taken = pred_branch_taken[head];

endmodule