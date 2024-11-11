// Helper module to update from CDB
module update_from_CDB (
    input [31:0] current_V,
    input [`ROB_RANGE] current_Q,
    input [31:0] cdb_alu_value,
    input [`ROB_RANGE] cdb_alu_rob_id,
    input [31:0] cdb_mem_value,
    input [`ROB_RANGE] cdb_mem_rob_id,
    output [31:0] updated_V,
    output [`ROB_RANGE] updated_Q
);

    // Determine the new value based on CDB inputs
    assign updated_V = (current_Q == cdb_alu_rob_id) ? cdb_alu_value :
                       (current_Q == cdb_mem_rob_id) ? cdb_mem_value : current_V;

    // Update the tag if the data is already available
    assign updated_Q = (current_Q == cdb_alu_rob_id || current_Q == cdb_mem_rob_id) ? 0 : current_Q;

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

    // Generate ready signal for each entry
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : ready_gen
            assign ready[g] = busy[g] && (Qj_entries[g] == 0) && (Qk_entries[g] == 0);
        end
    endgenerate

    // Find first ready entry
    __find_first find_ready(
        .entries(ready),
        .index(ready_index),
        .has_entry(has_ready)
    );
endmodule


// Helper module to count vacancies
module count_vacancies(
    input wire [15:0] busy,
    output wire has_no_vacancy,
    output wire has_one_vacancy
);
    wire [4:0] count;
    integer i;

    assign count = $countones(~busy);

    assign has_no_vacancy = (count == 0);
    assign has_one_vacancy = (count == 1);
endmodule

// Helper module to find first ready load entry
module find_first_ready_load(
    input wire [`RS_ARR] busy,
    input wire [`ROB_RANGE] Qj_entries[`RS_ARR],
    input wire [`ROB_RANGE] Ql_entries[`RS_ARR],
    output wire [3:0] ready_index,
    output wire has_ready
);
    wire [15:0] ready;

    // Generate ready signal for each entry
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : ready_gen
            assign ready[g] = busy[g] && (Qj_entries[g] == 0) && (Ql_entries[g] == 0);
        end
    endgenerate

    // Find first ready entry
    __find_first find_ready(
        .entries(ready),
        .index(ready_index),
        .has_entry(has_ready)
    );
endmodule

// Helper module to find first ready store entry
module find_first_ready_store(
    input wire [`RS_ARR] busy,
    input wire [`ROB_RANGE] Qj_entries[`RS_ARR],
    input wire [`ROB_RANGE] Qk_entries[`RS_ARR],
    input wire [`ROB_RANGE] Ql_entries[`RS_ARR],
    input wire [`ROB_RANGE] Qm_entries[`RS_ARR],
    input wire [`RS_ARR] load_busy,
    input wire [`ROB_RANGE] load_Ql_entries[`RS_ARR],
    output wire [3:0] ready_index,
    output wire has_ready
);
    wire [15:0] ready;
    wire [15:0] load_ready;

    // Generate ready signal for each entry
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : ready_gen
            assign ready[g] = busy[g] && (Qj_entries[g] == 0) && (Qk_entries[g] == 0) && (Ql_entries[g] == 0) && (Qm_entries[g] == 0);
        end
    endgenerate

    wire store_has_ready;

    // Generate ready signal for load entries
    // If there is a load instruction whose store depenency has been resolved
    // this instruction must be issued before any store instruction
    generate
        for (g = 0; g < 16; g = g + 1) begin : load_ready_gen
            assign load_ready[g] = load_busy[g] && (load_Ql_entries[g] == 0);
        end
    endgenerate
    assign can_store = ~(|load_ready);

    // Find first ready entry
    __find_first find_ready(
        .entries(ready),
        .index(ready_index),
        .has_entry(store_has_ready)
    );

    assign has_ready = store_has_ready && can_store;

endmodule

// Generic module to find first index among 16 entries
module __find_first(
    input wire [15:0] entries,
    output wire [3:0] index,
    output wire has_entry
);
    wire [3:0] result;
    assign has_entry = |entries; // OR reduction - true if any entry is 1

    assign result[3] = ~(entries[15] | entries[14] | entries[13] | entries[12] | entries[11] | entries[10] | entries[9] | entries[8]);
    assign result[2] = ~(
        (result[3] ? entries[7] : entries[15]) |
        (result[3] ? entries[6] : entries[14]) |
        (result[3] ? entries[5] : entries[13]) |
        (result[3] ? entries[4] : entries[12])
    );
    assign result[1] = ~(
        (result[3:2] == 2'b10 ? entries[3] : (result[3:2] == 2'b11 ? entries[7] : entries[15])) |
        (result[3:2] == 2'b10 ? entries[2] : (result[3:2] == 2'b11 ? entries[6] : entries[14]))
    );
    assign result[0] = ~(
        (result[3:1] == 3'b100 ? entries[1] :
         result[3:1] == 3'b101 ? entries[3] :
         result[3:1] == 3'b110 ? entries[5] :
         result[3:1] == 3'b111 ? entries[7] : entries[15])
    );

    assign index = result;
endmodule

// Module to find first vacant slot for load reservation station
module find_first_vacant_load(
    input wire [15:0] busy,
    output wire [3:0] vacant_index,
    output wire has_vacant
);
    wire [15:0] vacant;
    assign vacant = ~busy; // Invert busy signals to get vacant slots

    __find_first find_vacant(
        .entries(vacant),
        .index(vacant_index),
        .has_entry(has_vacant)
    );
endmodule

// Module to find first vacant slot for store reservation station
module find_first_vacant_store(
    input wire [15:0] busy,
    output wire [3:0] vacant_index,
    output wire has_vacant
);
    wire [15:0] vacant;
    assign vacant = ~busy; // Invert busy signals to get vacant slots

    __find_first find_vacant(
        .entries(vacant),
        .index(vacant_index),
        .has_entry(has_vacant)
    );
endmodule

// Helper module to find first vacant slot
module find_first_vacant(
    input wire [15:0] busy,
    output wire [3:0] vacant_index,
    output wire has_vacant
);
    wire [15:0] vacant;
    assign vacant = ~busy;

    __find_first find_vacant(
        .entries(vacant),
        .index(vacant_index),
        .has_entry(has_vacant)
    );
endmodule