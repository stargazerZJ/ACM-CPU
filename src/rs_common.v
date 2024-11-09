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

    assign count = $countones(~busy);

    assign has_no_vacancy = (count == 0);
    assign has_one_vacancy = (count == 1);
endmodule
