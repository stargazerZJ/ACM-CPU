module icache #(
    parameter I_CACHE_SIZE_LOG = 7
)(
    input wire clk_in,
    input wire rst_in,

    // Interface with instruction fetcher
    input wire [31:0] req_pc,    // PC requested by fetcher
    output reg [31:0] inst_out,  // Instruction output
    output reg valid_out,        // Whether output is valid

    // Interface with memory controller
    input wire [7:0] mem_byte,   // Byte from memory
    input wire mem_valid,        // Whether memory data is valid
    output reg [31:0] miss_addr  // Address to fetch on miss
);

    localparam I_CACHE_SIZE = 1 << I_CACHE_SIZE_LOG;

    reg [7:0] cache_data [(I_CACHE_SIZE * 2 + 2) - 1:0];
    reg [31:0] start_pos;
    reg [31:0] current_fill_pos;
    reg is_filling;
    reg cache_valid;
    wire[31:0] new_start_pos = {req_pc[31:I_CACHE_SIZE_LOG], I_CACHE_SIZE_LOG{1'b0}};
    wire [I_CACHE_SIZE_LOG:0] cache_index = {1'b0, req_pc[I_CACHE_SIZE_LOG-1:0]};

    always @(posedge clk_in) begin
        if (rst_in) begin
            start_pos <= 32'h0;
            current_fill_pos <= 32'h0;
            is_filling <= 1'b1;
            cache_valid <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            // Handle memory response
            if (mem_valid && is_filling) begin
                cache_data[current_fill_pos - start_pos] <= mem_byte;

                if (current_fill_pos - start_pos == I_CACHE_SIZE * 2 + 1) begin
                    is_filling <= 1'b0;
                    cache_valid <= 1'b1;
                end else begin
                    current_fill_pos <= current_fill_pos + 1;
                end
            end

            // Handle instruction fetch request
            if (req_pc >= start_pos &&
                req_pc + 3 < current_fill_pos) begin
                // Cache hit
                valid_out <= 1'b1;
                inst_out <= {
                    cache_data[cache_index + 3],
                    cache_data[cache_index + 2],
                    cache_data[cache_index + 1],
                    cache_data[cache_index]
                };
            end else if (req_pc[31:16] == 16'h0) begin
                // Cache miss - start new fill
                start_pos <= new_start_pos;
                current_fill_pos <= new_start_pos;
                is_filling <= 1'b1;
                cache_valid <= 1'b0;
                valid_out <= 1'b0;
                miss_addr <= req_pc;
            end
        end
    end
endmodule

module mem_controller (
    // Memory interface
    input wire [7:0] mem_din,
    wire [7:0] mem_dout,
    wire [31:0] mem_a,
    wire mem_wr,

    // Load Store Buffer interface
    input wire [31:0] lsb_addr,
    input wire [7:0] lsb_data,
    input wire lsb_wr,
    input wire lsb_valid,
    wire [7:0] lsb_read_data,
    wire lsb_done,

    // ICache interface
    input wire [31:0] icache_addr,
    input wire icache_busy,
    wire icache_data_valid,
    wire [7:0] icache_data
);

// Memory address mux
assign mem_a = lsb_valid ? lsb_addr : icache_addr;

// Memory write control
assign mem_wr = lsb_valid ? lsb_wr : 1'b0;

// Memory write data
assign mem_dout = lsb_data;

// Load Store Buffer read data
assign lsb_read_data = mem_din;

// Load Store Buffer done signal
assign lsb_done = lsb_valid;

// ICache interface signals
assign icache_data = mem_din;
assign icache_data_valid = icache_busy && !lsb_valid;

endmodule