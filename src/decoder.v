`include "const_def.v"

module decoder(
    input wire clk_in,  // system clock signal

    // Input from Fetcher
    input wire instruction_valid,
    input wire [31:0] fetcher_instruction,
    input wire [31:0] fetcher_program_counter,
    input wire fetcher_predicted_branch_taken,

    // Input from RegFile
    input wire [`ROB_RANGE] regfile_rob_id [31:0],
    input wire [31:0] regfile_data [31:0],

    // Input from ROB
    input wire [31:0] rob_values [`ROB_ARR],
    input wire [`ROB_ARR] rob_ready,

    // CDB Input (ALU)
    input wire [`ROB_RANGE] cdb_alu_rob_id,
    input wire [31:0] cdb_alu_value,

    // CDB Input (MEM)
    input wire [`ROB_RANGE] cdb_mem_rob_id,
    input wire [31:0] cdb_mem_value,

    // Status inputs
    input wire rs_alu_full,
    input wire rs_bcu_full,
    input wire rs_mem_load_full,
    input wire rs_mem_store_full,
    input wire rob_full,
    input wire [`ROB_RANGE] rob_id,

    // Commit info input
    input wire [`ROB_RANGE] commit_rob_id,

    input wire flush_input,

    // Output to Fetcher
    output reg fetcher_enabled,
    output reg [31:0] fetcher_pc,

    // Output to ROB
    output reg rob_enabled,
    output reg [1:0] rob_op,          // 00 for jalr, 01 for branch, 10 for others, 11 unused
    output reg rob_value_ready,        // 1 for value acquired, 0 otherwise
    output reg [31:0] rob_value,       // for jalr, the jump address; for branch and others, the value to write to the register
    output reg [31:0] rob_alt_value,   // for jalr, pc + 4; for branch, pc of the branch; for others, unused
    output reg [4:0] rob_dest,         // the register to store the value
    output reg rob_predicted_branch_taken,

    // Output to RS ALU
    output reg rs_alu_enabled,
    output reg [3:0] rs_alu_op,       // func7 bit 5 and func3
    output reg [31:0] rs_alu_Vj,
    output reg [31:0] rs_alu_Vk,
    output reg [`ROB_RANGE] rs_alu_Qj,
    output reg [`ROB_RANGE] rs_alu_Qk,
    output reg [`ROB_RANGE] rs_alu_dest,

    // Output to RS BCU
    output reg rs_bcu_enabled,
    output reg [2:0] rs_bcu_op,       // func3
    output reg [31:0] rs_bcu_Vj,
    output reg [31:0] rs_bcu_Vk,
    output reg [`ROB_RANGE] rs_bcu_Qj,
    output reg [`ROB_RANGE] rs_bcu_Qk,
    output reg [`ROB_RANGE] rs_bcu_dest,
    output reg [31:0] rs_bcu_pc_fallthrough,
    output reg [31:0] rs_bcu_pc_target,

    // Output to RS Mem Load
    output reg rs_mem_load_enabled,
    output reg [2:0] rs_mem_load_op,  // func3
    output reg [31:0] rs_mem_load_Vj, // rs1, position
    output reg [`ROB_RANGE] rs_mem_load_Qj,
    output reg [`ROB_RANGE] rs_mem_load_dest,
    output reg [11:0] rs_mem_load_offset,

    // Output to RS Mem Store
    output reg rs_mem_store_enabled,
    output reg [2:0] rs_mem_store_op, // func3
    output reg [31:0] rs_mem_store_Vj, // rs1, position
    output reg [31:0] rs_mem_store_Vk, // rs2, value
    output reg [`ROB_RANGE] rs_mem_store_Qj,
    output reg [`ROB_RANGE] rs_mem_store_Qk,
    output reg [`ROB_RANGE] rs_mem_store_Qm, // last branch id
    output reg [`ROB_RANGE] rs_mem_store_dest,
    output reg [11:0] rs_mem_store_offset,

    // Output to RegFile
    output reg regfile_enabled,
    output reg [4:0] regfile_reg_id,
    output reg [`ROB_RANGE] regfile_rob_id_out
);

    // State encoding
    localparam STATE_SKIP_ONE_CYCLE = 2'd0;
    localparam STATE_TRY_TO_ISSUE = 2'd1;
    localparam STATE_ISSUE_PREVIOUS = 2'd2;
    localparam STATE_WAIT_FOR_JALR = 2'd3;

    // Internal state registers
    reg [1:0] state;
    reg [`ROB_RANGE] last_branch_id;
    reg [`ROB_RANGE] last_jalr_id;
    reg [31:0] last_instruction;
    reg [31:0] last_program_counter;
    reg last_predicted_branch_taken;

    // Main state machine
    always @(posedge clk_in) begin
        if (flush_input) begin
            state <= STATE_TRY_TO_ISSUE;
            last_branch_id <= 0;
            last_jalr_id <= 0;
            last_instruction <= 0;
            last_program_counter <= 0;
            last_predicted_branch_taken <= 0;
            disable_all_outputs();
        end
        else begin
            last_branch_id <= new_last_branch_id;
            case (state)
                STATE_SKIP_ONE_CYCLE: begin
                    state <= STATE_TRY_TO_ISSUE;
                    disable_all_outputs();
                end

                STATE_WAIT_FOR_JALR: begin
                    // Implementation of wait_for_jalr logic
                    if (cdb_alu_rob_id == last_jalr_id || cdb_mem_rob_id == last_jalr_id) begin
                        last_jalr_id <= 0;
                        fetcher_enabled <= 1;
                        fetcher_pc <= (cdb_alu_rob_id == last_jalr_id) ? cdb_alu_value : cdb_mem_value;
                        state <= STATE_SKIP_ONE_CYCLE;
                        disable_outputs_except(ENABLE_FETCH);
                    end else begin
                        disable_all_outputs();
                    end
                end

                STATE_ISSUE_PREVIOUS: begin
                    issue_instruction();
                end

                STATE_TRY_TO_ISSUE: begin
                    if (instruction_valid) begin
                        issue_instruction();
                    end
                    else begin
                        disable_all_outputs();
                    end
                end
            endcase

            // last_branch_id <= (opcode == 7'b1100011) ? rob_id : new_last_branch_id;
        end
    end

    // Issue logic for different instruction types

    // The instruction to issue
    wire [31:0] instruction = (state == STATE_ISSUE_PREVIOUS) ? last_instruction : fetcher_instruction;
    wire [31:0] program_counter = (state == STATE_ISSUE_PREVIOUS) ? last_program_counter : fetcher_program_counter;
    wire predicted_branch_taken = (state == STATE_ISSUE_PREVIOUS) ? last_predicted_branch_taken : fetcher_predicted_branch_taken;

    // Instruction decode wires
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] func3 = instruction[14:12];
    wire [6:0] func7 = instruction[31:25];
    wire [4:0] rs1 = instruction[19:15];
    wire [4:0] rs2 = instruction[24:20];
    wire [4:0] rd = instruction[11:7];

    // Immediate decode wires
    wire [11:0] imm_i = instruction[31:20];
    wire [11:0] imm_s = {instruction[31:25], instruction[11:7]};
    wire [12:0] imm_b = {instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
    wire [19:0] imm_u = instruction[31:12];
    wire [20:0] imm_j = {instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};

    // Common computed values
    wire [31:0] next_program_counter = program_counter + 32'd4;
    wire signed [31:0] imm_i_signed = {{20{imm_i[11]}}, imm_i};
    wire signed [31:0] imm_b_signed = {{19{imm_b[12]}}, imm_b};
    wire signed [31:0] imm_j_signed = {{11{imm_j[20]}}, imm_j};
    wire [31:0] imm_u_shifted = {imm_u, 12'b0};
    wire [31:0] branch_target_addr = program_counter + imm_b_signed;
    wire [31:0] branch_predicted_pc = predicted_branch_taken ? branch_target_addr : next_program_counter;

    // Register query results
    wire [31:0] rs1_value;
    wire [`ROB_RANGE] rs1_rob_id;
    wire [31:0] rs2_value;
    wire [`ROB_RANGE] rs2_rob_id;

    // Assign register query results
    wire [`ROB_RANGE] regfile_rob_id_rs1 = regfile_rob_id[rs1];
    assign {rs1_value, rs1_rob_id} =
        // Check last issued instruction first
        (rob_enabled && rob_dest == rs1 && rs1 != 3'b0) ? (
            rob_value_ready ? {rob_value, {`ROB_SIZE_LOG{1'b0}}} :
                            {32'b0, regfile_rob_id_out}
        ) : (
            // Regular register file lookup path
            (regfile_rob_id_rs1 == 0) ? {regfile_data[rs1], {`ROB_SIZE_LOG{1'b0}}} :
            (cdb_alu_rob_id == regfile_rob_id_rs1) ? {cdb_alu_value, {`ROB_SIZE_LOG{1'b0}}} :
            (cdb_mem_rob_id == regfile_rob_id_rs1) ? {cdb_mem_value, {`ROB_SIZE_LOG{1'b0}}} :
            (rob_ready[regfile_rob_id_rs1]) ? {rob_values[regfile_rob_id_rs1], {`ROB_SIZE_LOG{1'b0}}} :
                                            {32'b0, regfile_rob_id_rs1}
        );
    wire [`ROB_RANGE] regfile_rob_id_rs2 = regfile_rob_id[rs2];
    assign {rs2_value, rs2_rob_id} =
        (rob_enabled && rob_dest == rs2 && rs2 != 3'b0) ? (
            rob_value_ready ? {rob_value, {`ROB_SIZE_LOG{1'b0}}} :
                            {32'b0, regfile_rob_id_out}
        ) : (
            (regfile_rob_id_rs2 == 0) ? {regfile_data[rs2], {`ROB_SIZE_LOG{1'b0}}} :
            (cdb_alu_rob_id == regfile_rob_id_rs2) ? {cdb_alu_value, {`ROB_SIZE_LOG{1'b0}}} :
            (cdb_mem_rob_id == regfile_rob_id_rs2) ? {cdb_mem_value, {`ROB_SIZE_LOG{1'b0}}} :
            (rob_ready[regfile_rob_id_rs2]) ? {rob_values[regfile_rob_id_rs2], {`ROB_SIZE_LOG{1'b0}}} :
                                            {32'b0, regfile_rob_id_rs2}
        );

    // Branch dependency query results
    wire [`ROB_RANGE] new_last_branch_id;
    // Update last_branch_id on commit
    assign new_last_branch_id = (commit_rob_id == last_branch_id) ? 0 : last_branch_id;

    task issue_instruction;
    begin
        // Check ROB full condition first
        if (rob_full) begin
            issue_failure();
        end
        else begin
            case (opcode)
                7'b0110111: begin // LUI
                    write_rob(2'b10, 1'b1, imm_u_shifted, 32'b0, rd, 1'b0);
                    write_regfile(rd);
                    disable_outputs_except(ENABLE_ROB | ENABLE_REG);
                    state <= STATE_TRY_TO_ISSUE;
                end

                7'b0010111: begin // AUIPC
                    if (rs_alu_full) begin
                        issue_failure();
                    end else begin
                        write_rob(2'b10, 1'b0, 32'b0, 32'b0, rd, 1'b0);
                        write_regfile(rd);
                        write_rs_alu(4'b0000, program_counter, imm_u_shifted,
                                    {`ROB_SIZE_LOG{1'b0}}, {`ROB_SIZE_LOG{1'b0}});
                        disable_outputs_except(ENABLE_ROB | ENABLE_REG | ENABLE_ALU);
                        state <= STATE_TRY_TO_ISSUE;
                    end
                end

                7'b1101111: begin // JAL
                    write_rob(2'b10, 1'b1, next_program_counter, 32'b0, rd, 1'b0);
                    write_regfile(rd);
                    fetcher_enabled <= 1;
                    fetcher_pc <= program_counter + imm_j_signed;
                    state <= STATE_SKIP_ONE_CYCLE;
                    disable_outputs_except(ENABLE_ROB | ENABLE_REG | ENABLE_FETCH);
                end

                7'b1100111: begin // JALR
                    if (imm_i == 12'b0 && rd == 5'd0 && rs1_rob_id == 0) begin
                        // JR instruction with no dependencies
                        write_rob(2'b10, 1'b1, next_program_counter, 32'b0, 5'd0, 1'b0);
                        fetcher_enabled <= 1;
                        fetcher_pc <= rs1_value;
                        state <= STATE_SKIP_ONE_CYCLE;
                        disable_outputs_except(ENABLE_ROB | ENABLE_FETCH);
                    end else if (rs_alu_full) begin
                        issue_failure();
                    end else begin
                        write_rob(2'b00, 1'b0, 32'b0, next_program_counter, rd, 1'b0);
                        write_regfile(rd);
                        write_rs_alu(4'b0000, rs1_value, imm_i_signed, rs1_rob_id, {`ROB_SIZE_LOG{1'b0}});
                        state <= STATE_WAIT_FOR_JALR;
                        last_jalr_id <= rob_id;
                        disable_outputs_except(ENABLE_ROB | ENABLE_REG | ENABLE_ALU);
                    end
                end

                7'b1100011: begin // Branch instructions
                    if (rs_bcu_full) begin
                        issue_failure();
                    end else begin

                        write_rob(2'b01, 1'b0, 32'b0, program_counter, 5'd0, predicted_branch_taken);
                        write_rs_bcu(func3, rs1_value, rs2_value, rs1_rob_id, rs2_rob_id,
                                    next_program_counter, branch_target_addr);

                        fetcher_enabled <= 1;
                        fetcher_pc <= branch_predicted_pc;
                        state <= STATE_SKIP_ONE_CYCLE;
                        last_branch_id <= rob_id; // done in the main state machine

                        disable_outputs_except(ENABLE_ROB | ENABLE_BCU | ENABLE_FETCH);
                    end
                end

                7'b0000011: begin // Load Instructions
                    if (rs_mem_load_full) begin
                        issue_failure();
                    end else begin
                        write_rob(2'b10, 1'b0, 32'b0, 32'b0, rd, 1'b0);
                        write_regfile(rd);

                        // Write to RS Mem Load
                        rs_mem_load_enabled <= 1;
                        rs_mem_load_op <= func3;
                        rs_mem_load_Vj <= rs1_value;
                        rs_mem_load_Qj <= rs1_rob_id;
                        rs_mem_load_dest <= rob_id;
                        rs_mem_load_offset <= imm_i;

                        disable_outputs_except(ENABLE_ROB | ENABLE_REG | ENABLE_LOAD);
                        state <= STATE_TRY_TO_ISSUE;
                    end
                end

                7'b0100011: begin // Store Instructions
                    if (rs_mem_store_full) begin
                        issue_failure();
                    end else begin
                        write_rob(2'b10, 1'b0, 32'b0, 32'b0, 5'd0, 1'b0);

                        // Write to RS Mem Store
                        rs_mem_store_enabled <= 1;
                        rs_mem_store_op <= func3;
                        rs_mem_store_Vj <= rs1_value;
                        rs_mem_store_Vk <= rs2_value;
                        rs_mem_store_Qj <= rs1_rob_id;
                        rs_mem_store_Qk <= rs2_rob_id;
                        rs_mem_store_Qm <= new_last_branch_id;
                        rs_mem_store_dest <= rob_id;
                        rs_mem_store_offset <= imm_s;

                        disable_outputs_except(ENABLE_ROB | ENABLE_STORE);
                        state <= STATE_TRY_TO_ISSUE;
                    end
                end

                7'b0010011: begin // I-type ALU Instructions
                    if (rs_alu_full) begin
                        issue_failure();
                    end else begin

                        write_rob(2'b10, 1'b0, 32'b0, 32'b0, rd, 1'b0);
                        write_regfile(rd);

                        write_rs_alu(
                            (func3 == 3'b001 || func3 == 3'b101) ?
                              {instruction[30], func3} : {1'b0, func3},
                            rs1_value,
                            (func3 == 3'b001 || func3 == 3'b101) ?
                              {27'b0, instruction[24:20]} : imm_i_signed,
                            rs1_rob_id, {`ROB_SIZE_LOG{1'b0}});

                        disable_outputs_except(ENABLE_ROB | ENABLE_REG | ENABLE_ALU);
                        state <= STATE_TRY_TO_ISSUE;
                    end
                end

                7'b0110011: begin // R-type ALU Instructions
                    if (rs_alu_full) begin
                        issue_failure();
                    end else begin
                        write_rob(2'b10, 1'b0, 32'b0, 32'b0, rd, 1'b0);
                        write_regfile(rd);

                        // ALU operation is determined by func7[5] and func3
                        write_rs_alu({func7[5], func3}, rs1_value, rs2_value, rs1_rob_id, rs2_rob_id);

                        disable_outputs_except(ENABLE_ROB | ENABLE_REG | ENABLE_ALU);
                        state <= STATE_TRY_TO_ISSUE;
                    end
                end

                default: begin
                    // Handle invalid instruction
                    state <= STATE_TRY_TO_ISSUE;
                    disable_all_outputs();
                end
            endcase
        end

        // Store instruction info for potential retry
        last_instruction <= instruction;
        last_program_counter <= program_counter;
        last_predicted_branch_taken <= predicted_branch_taken;
    end
    endtask

    // Helper tasks
    task issue_failure;
    begin
        state <= STATE_ISSUE_PREVIOUS;
        fetcher_enabled <= 1;
        fetcher_pc <= next_program_counter;
        disable_outputs_except(2'b10);
    end
    endtask
    task write_rob;
        input [1:0] op;
        input value_ready;
        input [31:0] value;
        input [31:0] alt_value;
        input [4:0] dest;
        input predicted_taken;
    begin
        rob_enabled <= 1;
        rob_op <= op;
        rob_value_ready <= value_ready;
        rob_value <= value;
        rob_alt_value <= alt_value;
        rob_dest <= dest;
        rob_predicted_branch_taken <= predicted_taken;
    end
    endtask
    task write_regfile;
        input [4:0] reg_id;
    begin
        regfile_enabled <= 1;
        regfile_reg_id <= reg_id;
        regfile_rob_id_out <= rob_id;
    end
    endtask
    task write_rs_alu;
        input [3:0] op;
        input [31:0] Vj;
        input [31:0] Vk;
        input [`ROB_RANGE] Qj;
        input [`ROB_RANGE] Qk;
    begin
        rs_alu_enabled <= 1;
        rs_alu_op <= op;
        rs_alu_Vj <= Vj;
        rs_alu_Vk <= Vk;
        rs_alu_Qj <= Qj;
        rs_alu_Qk <= Qk;
        rs_alu_dest <= rob_id;
    end
    endtask
    task write_rs_bcu;
        input [2:0] op;
        input [31:0] Vj;
        input [31:0] Vk;
        input [`ROB_RANGE] Qj;
        input [`ROB_RANGE] Qk;
        input [31:0] pc_fallthrough;
        input [31:0] pc_target;
    begin
        rs_bcu_enabled <= 1;
        rs_bcu_op <= op;
        rs_bcu_Vj <= Vj;
        rs_bcu_Vk <= Vk;
        rs_bcu_Qj <= Qj;
        rs_bcu_Qk <= Qk;
        rs_bcu_dest <= rob_id;
        rs_bcu_pc_fallthrough <= pc_fallthrough;
        rs_bcu_pc_target <= pc_target;
    end
    endtask

    // Helper task to disable outputs
    localparam ENABLE_ROB = 7'b1000000;
    localparam ENABLE_ALU = 7'b0100000;
    localparam ENABLE_BCU = 7'b0010000;
    localparam ENABLE_LOAD = 7'b0001000;
    localparam ENABLE_STORE = 7'b0000100;
    localparam ENABLE_FETCH = 7'b0000010;
    localparam ENABLE_REG = 7'b0000001;
    task disable_outputs_except;
        input [6:0] enable_mask; // [rob,alu,bcu,mem_load,mem_store,fetcher,regfile]
        begin
            rob_enabled <= enable_mask[6];
            rs_alu_enabled <= enable_mask[5];
            rs_bcu_enabled <= enable_mask[4];
            rs_mem_load_enabled <= enable_mask[3];
            rs_mem_store_enabled <= enable_mask[2];
            fetcher_enabled <= enable_mask[1];
            regfile_enabled <= enable_mask[0];
        end
    endtask
    task disable_all_outputs;
        begin
            disable_outputs_except(7'b0);
        end
    endtask

endmodule