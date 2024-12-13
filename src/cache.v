`include "const_def.v"

module instruction_cache (
    input wire clk_in,
    input wire rst_in,

    // Interface with instruction fetcher
    input wire [31:0] req_pc,    // PC requested by fetcher
    output reg [31:0] inst_out,  // Instruction output
    output reg valid_out,        // Whether output is valid
    output reg compressed_out,   // Whether output is compressed

    // Interface with memory controller
    input wire [7:0] mem_byte,   // Byte from memory
    input wire mem_valid,        // Whether memory data is valid
    output reg mem_en,           // Memory enable signal
    output reg [31:0] miss_addr  // Address to fetch on miss
);

    // Cache organization constants
    localparam BLOCK_BITS = 4;    // 2^4 + 2 = 18 bytes per block
    localparam BLOCK_SIZE = 18;  // two extra bytes is because of unaligned 4 byte instruction in RV32IC.
    localparam WAY_COUNT = 2;    // 2-way associative
    localparam NUM_BLOCKS = 8;  // Total blocks: 2 * 32 = 64
    localparam INDEX_BITS = 3;   // log2(NUM_BLOCKS) = 5
    localparam TAG_BITS = 5;     // 14 - INDEX_BITS - log2(BLOCK_SIZE-2) = 8
    localparam TOTAL_BITS = TAG_BITS + INDEX_BITS + BLOCK_BITS;

    // Cache storage
    reg [7:0] data [WAY_COUNT-1:0][NUM_BLOCKS-1:0][BLOCK_SIZE-1:0];
    reg [TAG_BITS-1:0] tags [WAY_COUNT-1:0][NUM_BLOCKS-1:0];
    reg valid [WAY_COUNT-1:0][NUM_BLOCKS-1:0];
    reg lru [NUM_BLOCKS-1:0]; // LRU bits

    // Fill state
    reg [TOTAL_BITS - 1:0] current_fill_addr;
    reg [BLOCK_BITS:0] fill_index;
    reg filling;
    reg [INDEX_BITS-1:0] fill_block_idx;
    reg fill_way;
    wire next_fill_way = lru[req_index];
    reg last_load_success;

    // Address breakdown
    wire [TAG_BITS-1:0] req_tag = req_pc[TAG_BITS + INDEX_BITS + BLOCK_BITS - 1: INDEX_BITS + BLOCK_BITS ];
    wire [INDEX_BITS-1:0] req_index = req_pc[INDEX_BITS + BLOCK_BITS - 1:BLOCK_BITS];
    wire [BLOCK_BITS:0] req_offset = {1'b0, req_pc[BLOCK_BITS - 1:1], 1'b0}; // Block offset in bytes

    // Hit detection
    wire [WAY_COUNT-1:0] hit;
    assign hit[0] = valid[0][req_index] && (tags[0][req_index] == req_tag);
    assign hit[1] = valid[1][req_index] && (tags[1][req_index] == req_tag);
    wire cache_hit = |hit;

    wire way_sel = hit[1] ? 1 : 0;

    // Instruction assembly
    wire [31:0] instruction_raw = {
        data[way_sel][req_index][req_offset + 2'b11],
        data[way_sel][req_index][req_offset + 2'b10],
        data[way_sel][req_index][req_offset + 1'b1],
        data[way_sel][req_index][req_offset]
    };

    wire is_compressed = (instruction_raw[1:0] != 2'b11);

    decompression decompressor(
        .clk_in(clk_in),
        .inst_c(instruction_raw),
        .inst_out(inst_out)
    );
    // integer output_file;
    // initial begin
    //   output_file = $fopen("out.log", "w");
    // end

    always @(posedge clk_in) begin
        if (rst_in) begin
            filling <= 0;
            valid_out <= 0;
            last_load_success <= 0;
            // Reset valid bits
            for (integer j = 0; j < NUM_BLOCKS; j++) begin
                valid[0][j] <= 0;
                tags[0][j] <= 0;
                tags[1][j] <= 0;
                valid[1][j] <= 0;
                lru[j] <= 0;
            end
        end else begin
            if (filling) begin
                if (last_load_success) begin
                    data[fill_way][fill_block_idx][fill_index] <= mem_byte;
                end
                if (mem_valid) begin
                    last_load_success <= 1;
                    fill_index <= fill_index + 1;
                    current_fill_addr <= current_fill_addr + 1;

                    if (fill_index == BLOCK_SIZE) begin
                        filling <= 0;
                        valid[fill_way][fill_block_idx] <= 1;
                    end
                end else begin
                    last_load_success <= 0;
                end
            end

            valid_out <= cache_hit;
            if (cache_hit) begin
                compressed_out <= is_compressed;
                // Update LRU
                lru[req_index] <= ~way_sel;
                // $fwrite(output_file, "%h -> %h\n", req_pc, instruction_raw);
            end else if (!filling) begin
                // Handle miss
                filling <= 1;
                fill_index <= -1;
                fill_block_idx <= req_index;
                // Choose way based on LRU
                fill_way <= next_fill_way;
                current_fill_addr <= {req_tag, req_index, 4'b0};
                // Update tag
                tags[next_fill_way][req_index] <= req_tag;
                valid[next_fill_way][req_index] <= 0;
                last_load_success <= 0;
            end
        end
    end

    assign mem_en = filling;
    assign miss_addr = {18'b0, current_fill_addr};

    // wire [31:0] debug = {
    //     data[1'b1][req_index][req_offset + 2'b11],
    //     data[1'b1][req_index][req_offset + 2'b10],
    //     data[1'b1][req_index][req_offset + 1'b1],
    //     data[1'b1][req_index][req_offset]
    // };

endmodule

module mem_controller (
    input wire clk_in,

    // Memory interface
    input wire [7:0] mem_din,
    input wire mem_valid,
    output wire [7:0] mem_dout,
    output wire [31:0] mem_a,
    output wire mem_wr,

    // Load Store Buffer interface
    input wire [31:0] lsb_addr,
    input wire [7:0] lsb_data,
    input wire lsb_wr,
    input wire lsb_en,
    output wire [7:0] lsb_read_data,
    output wire lsb_valid,

    // ICache interface
    input wire [31:0] icache_addr,
    input wire icache_en,
    output wire icache_data_valid,
    output wire [7:0] icache_data
);

// Memory address mux
assign mem_a = lsb_en ? lsb_addr : icache_addr;

// Memory write control
assign mem_wr = lsb_en ? lsb_wr : 1'b0;

// Memory write data
assign mem_dout = lsb_data;

// Load Store Buffer read data
assign lsb_read_data = mem_din;

// LSB valid signal
assign lsb_valid = mem_valid && lsb_en;

// ICache read data
assign icache_data = mem_din;

// ICache valid signal
assign icache_data_valid = icache_en && !lsb_en && mem_valid;

endmodule