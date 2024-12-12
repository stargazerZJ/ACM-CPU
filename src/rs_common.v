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

// Generic module to find first 1 among 16 entries
module __find_first(
    input wire [15:0] entries,
    output wire [3:0] index,
    output wire has_entry
);
    // OR reduction - true if any entry is 1
    assign has_entry = |entries;

    // Break down the logic bit by bit
    // result[3] is 1 if first '1' is in upper 8 bits
    // result[2] is 1 if first '1' is in upper half of the relevant 8 bits
    // result[1] is 1 if first '1' is in upper half of the relevant 4 bits
    // result[0] is 1 if first '1' is in upper half of the relevant 2 bits

    wire [3:0] result;

    // Most significant bit (bit 3)
    // '1' if first occurrence is in upper 8 bits [15:8]
    assign result[3] = ~|entries[7:0] & |entries[15:8];

    // Bit 2
    // Check upper/lower 4 bits in the relevant 8-bit section
    wire [7:0] relevant_byte = result[3] ? entries[15:8] : entries[7:0];
    assign result[2] = ~|relevant_byte[3:0] & |relevant_byte[7:4];

    // Bit 1
    // Check upper/lower 2 bits in the relevant 4-bit section
    wire [3:0] relevant_nibble = result[2] ?
                                (result[3] ? entries[15:12] : entries[7:4]) :
                                (result[3] ? entries[11:8]  : entries[3:0]);
    assign result[1] = ~|relevant_nibble[1:0] & |relevant_nibble[3:2];

    // Least significant bit (bit 0)
    // Check upper/lower bit in the relevant 2-bit section
    wire [1:0] relevant_bits = result[1] ?
                              (result[2] ?
                               (result[3] ? entries[15:14] : entries[7:6]) :
                               (result[3] ? entries[11:10] : entries[3:2])) :
                              (result[2] ?
                               (result[3] ? entries[13:12] : entries[5:4]) :
                               (result[3] ? entries[9:8]   : entries[1:0]));
    assign result[0] = ~relevant_bits[0] & relevant_bits[1];

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