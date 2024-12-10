
module instruction_fetch_unit (
    input wire clk_in,
    input wire rst_in,

    input wire [31:0] pc_from_rob,  // Program counter from ROB
    input wire valid_from_rob,

    input wire [31:0] pc_from_decoder,  // Program counter from Decoder
    input wire valid_from_decoder,

    input wire [31:0] pc_of_branch,  // Program counter of branch instruction
    input wire branch_taken,
    input wire branch_record_valid,

    // Interface with memory controller
    input wire [7:0] mem_byte,   // Byte from memory
    input wire mem_valid,        // Whether memory data is valid
    output reg mem_en,           // Memory enable signal
    output wire [31:0] miss_addr,  // Address to fetch on miss

    output wire [31:0] inst_out,  // Instruction output
    output reg [31:0] program_counter,  // Program counter output
    output wire valid_out,        // Whether output is valid
    output reg compressed_out,   // Whether output is compressed
    output reg pred_branch_taken // Whether branch is predicted taken
);

wire [31:0] pc;

assign pc = valid_from_rob ? pc_from_rob :
            valid_from_decoder ? pc_from_decoder :
            !valid_out ? program_counter :
            compressed_out ? program_counter + 2 : program_counter + 4;

instruction_cache icache(
    .clk_in(clk_in),
    .rst_in(rst_in),
    .req_pc(pc),
    .inst_out(inst_out),
    .valid_out(valid_out),
    .compressed_out(compressed_out),
    .mem_byte(mem_byte),
    .mem_valid(mem_valid),
    .mem_en(mem_en),
    .miss_addr(miss_addr)
);

always @(posedge clk_in) begin
    pred_branch_taken <= pc[2]; // The branch predictor is not implemented yet
    program_counter <= pc;
    // rst_in is not used in this module because rob will reset the pc
end


endmodule