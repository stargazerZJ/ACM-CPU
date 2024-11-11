`include "const_def.v"

module reservation_station_mem(
    input wire clk_in, // system clock signal

    // Load Operation input
    input wire load_enabled,
    input wire [2:0] load_op, // func3
    input wire [31:0] load_Vj,
    input wire [`ROB_RANGE] load_Qj,
    input wire [`ROB_RANGE] load_dest,
    input wire [11:0] load_offset,

    // Store Operation input
    input wire store_enabled,
    input wire [2:0] store_op, // func3
    input wire [31:0] store_Vj,
    input wire [31:0] store_Vk,
    input wire [`ROB_RANGE] store_Qj,
    input wire [`ROB_RANGE] store_Qk,
    input wire [`ROB_RANGE] store_Qm,
    input wire [`ROB_RANGE] store_dest,
    input wire [11:0] store_offset,

    // CDB input (ALU)
    input wire [`ROB_RANGE] cdb_alu_rob_id,
    input wire [31:0] cdb_alu_value,

    // CDB input (MEM)
    input wire [`ROB_RANGE] cdb_mem_rob_id,
    input wire [31:0] cdb_mem_value,

    // Commit Info from ROB
    input wire [`ROB_RANGE] rob_commit_id,

    // Control signals
    input wire recv, // From memory, whether the instruction is received. The RS keeps sending the same instruction until it is received
    input wire flush_input, // flush signal, serves as RST on the first cycle

    // Vacancy outputs
    output wire has_no_load_vacancy,
    output wire has_one_load_vacancy,
    output wire has_no_store_vacancy,
    output wire has_one_store_vacancy,

    // Output to MEM
    output reg mem_typ, // 0 for load, 1 for store
    output reg [2:0] mem_op,
    output reg [31:0] mem_Vj,
    output reg [31:0] mem_Vk,
    output reg [11:0] mem_offset,
    output reg [`ROB_RANGE] mem_dest // 0 means disabled
);

// Load RS entries
reg [`RS_ARR] load_busy;
reg [2:0] load_op_entries[`RS_ARR];
reg [31:0] load_Vj_entries[`RS_ARR];
reg [`ROB_RANGE] load_Qj_entries[`RS_ARR];
reg [`ROB_RANGE] load_Ql_entries[`RS_ARR]; // last store operation
reg [`ROB_RANGE] load_dest_entries[`RS_ARR];
reg [11:0] load_offset_entries[`RS_ARR];

// Store RS entries
reg [`RS_ARR] store_busy;
reg [2:0] store_op_entries[`RS_ARR];
reg [31:0] store_Vj_entries[`RS_ARR];
reg [31:0] store_Vk_entries[`RS_ARR];
reg [`ROB_RANGE] store_Qj_entries[`RS_ARR];
reg [`ROB_RANGE] store_Qk_entries[`RS_ARR];
reg [`ROB_RANGE] store_Ql_entries[`RS_ARR]; // last store operation
reg [`ROB_RANGE] store_Qm_entries[`RS_ARR]; // last branch operation
reg [`ROB_RANGE] store_dest_entries[`RS_ARR];
reg [11:0] store_offset_entries[`RS_ARR];

// Last issue state
reg last_issue_status; // 0 for not issued, 1 for issued
reg last_issue_typ; // 0 for load, 1 for store
reg [`ROB_RANGE] last_store_id; // the ROB id of the latest store instruction, used to update Ql

// Combinational logic for finding slots and counting vacancies
wire [3:0] load_vacant_index;
wire load_has_vacant;
wire [3:0] store_vacant_index;
wire store_has_vacant;

wire [3:0] load_ready_index;
wire has_load_ready;
wire [3:0] store_ready_index;
wire has_store_ready;

// Instantiate helper modules for finding vacant and ready entries
find_first_vacant_load load_vacant_finder(
    .busy(load_busy),
    .vacant_index(load_vacant_index),
    .has_vacant(load_has_vacant)
);

find_first_vacant_store store_vacant_finder(
    .busy(store_busy),
    .vacant_index(store_vacant_index),
    .has_vacant(store_has_vacant)
);

find_first_ready_load load_ready_finder(
    .busy(load_busy),
    .Qj_entries(load_Qj_entries),
    .Ql_entries(load_Ql_entries),
    .ready_index(load_ready_index),
    .has_ready(has_load_ready)
);

find_first_ready_store store_ready_finder(
    .busy(store_busy),
    .Qj_entries(store_Qj_entries),
    .Qk_entries(store_Qk_entries),
    .Ql_entries(store_Ql_entries),
    .Qm_entries(store_Qm_entries),
    .load_busy(load_busy),
    .load_Ql_entries(load_Ql_entries),
    .ready_index(store_ready_index),
    .has_ready(has_store_ready)
);

count_load_vacancies load_vacancy_counter(
    .busy(load_busy),
    .has_no_vacancy(has_no_load_vacancy),
    .has_one_vacancy(has_one_load_vacancy)
);

count_store_vacancies store_vacancy_counter(
    .busy(store_busy),
    .has_no_vacancy(has_no_store_vacancy),
    .has_one_vacancy(has_one_store_vacancy)
);

// Helper wires for CDB updates
wire [31:0] load_new_Vj = (load_Qj == cdb_alu_rob_id) ? cdb_alu_value :
                          (load_Qj == cdb_mem_rob_id) ? cdb_mem_value : load_Vj;
wire [`ROB_RANGE] load_new_Qj = (load_Qj == cdb_alu_rob_id || load_Qj == cdb_mem_rob_id) ? 0 : load_Qj;

// For store operation inputs
wire [31:0] store_new_Vj = (store_Qj == cdb_alu_rob_id) ? cdb_alu_value :
                           (store_Qj == cdb_mem_rob_id) ? cdb_mem_value : store_Vj;
wire [31:0] store_new_Vk = (store_Qk == cdb_alu_rob_id) ? cdb_alu_value :
                           (store_Qk == cdb_mem_rob_id) ? cdb_mem_value : store_Vk;

wire [`ROB_RANGE] store_new_Qj = (store_Qj == cdb_alu_rob_id || store_Qj == cdb_mem_rob_id) ? 0 : store_Qj;
wire [`ROB_RANGE] store_new_Qk = (store_Qk == cdb_alu_rob_id || store_Qk == cdb_mem_rob_id) ? 0 : store_Qk;

wire [`ROB_RANGE] new_Ql = (recv && last_issue_status && last_issue_typ && last_store_id == mem_dest) ? 0 : last_store_id;
wire [`ROB_RANGE] store_new_Qm = (store_Qm == rob_commit_id) ? 0 : store_Qm;

integer i;
always @(posedge clk_in) begin
    if (flush_input) begin
        // Reset all state
        for (i = 0; i < `RS_SIZE; i = i + 1) begin
            load_busy[i] <= 0;
            store_busy[i] <= 0;
        end
        last_store_id <= 0;
        last_issue_status <= 0;
        last_issue_typ <= 0;
        mem_typ <= 0;
        mem_op <= 0;
        mem_Vj <= 0;
        mem_Vk <= 0;
        mem_offset <= 0;
        mem_dest <= 0;
    end else begin
        // Handle recv signal
        if (recv && last_issue_status) begin
            if (last_issue_typ) begin // store
                // Update Ql for all entries
                for (i = 0; i < `RS_SIZE; i = i + 1) begin
                    if (load_Ql_entries[i] == mem_dest) begin
                        load_Ql_entries[i] <= 0;
                    end
                    if (store_Ql_entries[i] == mem_dest) begin
                        store_Ql_entries[i] <= 0;
                    end
                end
            end
            last_issue_status <= 0;
        end

        // Add new operations
        if (load_enabled && load_has_vacant) begin
            load_busy[load_vacant_index] <= 1;
            load_op_entries[load_vacant_index] <= load_op;
            load_Vj_entries[load_vacant_index] <= load_new_Vj;
            load_Qj_entries[load_vacant_index] <= load_new_Qj;
            load_Ql_entries[load_vacant_index] <= new_Ql;
            load_dest_entries[load_vacant_index] <= load_dest;
            load_offset_entries[load_vacant_index] <= load_offset;
        end else if (store_enabled && store_has_vacant) begin
            store_busy[store_vacant_index] <= 1;
            store_op_entries[store_vacant_index] <= store_op;
            store_Vj_entries[store_vacant_index] <= store_new_Vj;
            store_Vk_entries[store_vacant_index] <= store_new_Vk;
            store_Qj_entries[store_vacant_index] <= store_new_Qj;
            store_Qk_entries[store_vacant_index] <= store_new_Qk;
            store_Ql_entries[store_vacant_index] <= new_Ql;
            store_Qm_entries[store_vacant_index] <= store_new_Qm;
            store_dest_entries[store_vacant_index] <= store_dest;
            store_offset_entries[store_vacant_index] <= store_offset;
        end

        // Update last store id
        last_store_id <= (store_enabled) ? store_dest : new_Ql;

        // Update from CDB
        for (i = 0; i < `RS_SIZE; i = i + 1) begin
            // Update load entries
            if (load_busy[i]) begin
                if (load_Qj_entries[i] == cdb_alu_rob_id) begin
                    load_Vj_entries[i] <= cdb_alu_value;
                    load_Qj_entries[i] <= 0;
                end
                if (load_Qj_entries[i] == cdb_mem_rob_id) begin
                    load_Vj_entries[i] <= cdb_mem_value;
                    load_Qj_entries[i] <= 0;
                end
            end
            // Update store entries
            if (store_busy[i]) begin
                if (store_Qj_entries[i] == cdb_alu_rob_id) begin
                    store_Vj_entries[i] <= cdb_alu_value;
                    store_Qj_entries[i] <= 0;
                end
                if (store_Qk_entries[i] == cdb_alu_rob_id) begin
                    store_Vk_entries[i] <= cdb_alu_value;
                    store_Qk_entries[i] <= 0;
                end
                if (store_Qj_entries[i] == cdb_mem_rob_id) begin
                    store_Vj_entries[i] <= cdb_mem_value;
                    store_Qj_entries[i] <= 0;
                end
                if (store_Qk_entries[i] == cdb_mem_rob_id) begin
                    store_Vk_entries[i] <= cdb_mem_value;
                    store_Qk_entries[i] <= 0;
                end
            end
        end

        // Update branch dependency
        if (rob_commit_id != 0) begin
            for (i = 0; i < `RS_SIZE; i = i + 1) begin
                if (store_busy[i] && store_Qm_entries[i] == rob_commit_id) begin
                    store_Qm_entries[i] <= 0;
                end
            end
        end

        // Issue operation
        if (last_issue_status && !recv) begin
            // Resend last operation
        end else begin
            // Try to issue new operation
            if (has_load_ready) begin
                // Issue load
                mem_typ <= 0;
                mem_op <= load_op_entries[load_ready_index];
                mem_Vj <= load_Vj_entries[load_ready_index];
                mem_Vk <= 0;
                mem_offset <= load_offset_entries[load_ready_index];
                mem_dest <= load_dest_entries[load_ready_index];
                last_issue_status <= 1;
                last_issue_typ <= 0;
                load_busy[load_ready_index] <= 0;
            end else if (has_store_ready) begin
                // Issue store
                mem_typ <= 1;
                mem_op <= store_op_entries[store_ready_index];
                mem_Vj <= store_Vj_entries[store_ready_index];
                mem_Vk <= store_Vk_entries[store_ready_index];
                mem_offset <= store_offset_entries[store_ready_index];
                mem_dest <= store_dest_entries[store_ready_index];
                last_issue_status <= 1;
                last_issue_typ <= 1;
                store_busy[store_ready_index] <= 0;
            end else begin
                // No operation to issue
                mem_typ <= 0;
                mem_op <= 0;
                mem_Vj <= 0;
                mem_Vk <= 0;
                mem_offset <= 0;
                mem_dest <= 0;
                last_issue_status <= 0;
            end
        end
    end
end
endmodule

module memory_unit(
    input wire clk_in, // system clock signal

    // Memory Operation Input
    input wire typ, // 0 for load, 1 for store
    input wire [2:0] op,
    input wire [31:0] rs1,
    input wire [31:0] rs2, // 0 for load instruction
    input wire [11:0] offset,
    input wire [`ROB_RANGE] dest,

    input wire flush_input, // flush signal. a flush signal is received on the first cycle, serving as RST

    // Input and Output from memory
    // TODO: add memory input and output

    // CDB Output
    output reg [`ROB_RANGE] rob_id, // ROB ID in the CDB output
    output reg [31:0] value, // value in the CDB output
    output reg recv // whether the instruction is received. The RS keeps sending the same instruction until it is received
);
// ......
endmodule