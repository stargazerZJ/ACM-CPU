`include "const_def.v"

module instruction_cache (
    input wire clk_in,
    input wire rst_in,

    // Interface with instruction fetcher
    input wire [31:0] req_pc,    // PC requested by fetcher
    output reg [31:0] inst_out,  // Instruction output
    output reg valid_out,        // Whether output is valid

    // Interface with memory controller
    input wire [7:0] mem_byte,   // Byte from memory
    input wire mem_valid,        // Whether memory data is valid
    output reg mem_en,           // Memory enable signal
    output reg [31:0] miss_addr  // Address to fetch on miss
);

    reg [7:0] cache_data [(`I_CACHE_SIZE * 2 + 2) - 1:0];
    reg [31:0] start_pos;
    reg [31:0] current_fill_pos;
    reg [`I_CACHE_SIZE_LOG+1:0] fill_index;
    reg cache_valid;
    reg last_load_success;
    wire[31:0] new_start_pos = {req_pc[31:`I_CACHE_SIZE_LOG+1], 1'b0, {`I_CACHE_SIZE_LOG{1'b0}}};
    wire [`I_CACHE_SIZE_LOG+1:0] cache_index = {1'b0, req_pc[`I_CACHE_SIZE_LOG:0]};

    always @(posedge clk_in) begin
        if (rst_in) begin
            start_pos <= 32'h0;
            current_fill_pos <= 32'h0;
            fill_index <= -1;
            cache_valid <= 1'b0;
            last_load_success <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            // Handle memory response
            if (!cache_valid) begin
                if (last_load_success) begin
                    cache_data[fill_index] <= mem_byte;
                end

                if (mem_valid) begin
                    last_load_success <= 1'b1;
                    if (fill_index == `I_CACHE_SIZE * 2 + 2) begin
                        cache_valid <= 1'b1;
                    end else begin
                        current_fill_pos <= current_fill_pos + 1;
                        fill_index <= fill_index + 1;
                    end
                end else begin
                    last_load_success <= 1'b0;
                end
            end

            // Handle instruction fetch request
            if (req_pc >= start_pos &&
                        req_pc < start_pos + `I_CACHE_SIZE * 2) begin
                valid_out <= (req_pc + 4 < current_fill_pos) ? 1'b1 : 1'b0;
                inst_out <= {
                    cache_data[cache_index + 3],
                    cache_data[cache_index + 2],
                    cache_data[cache_index + 1],
                    cache_data[cache_index]
                };
            end else begin
                // Cache miss - start new fill
                start_pos <= new_start_pos;
                current_fill_pos <= new_start_pos;
                fill_index <= -1;
                cache_valid <= 1'b0;
                valid_out <= 1'b0;
            end
        end
    end

    assign mem_en = !cache_valid;
    assign miss_addr = current_fill_pos;

    wire [31:0] debug = {
        cache_data[cache_index + 3],
        cache_data[cache_index + 2],
        cache_data[cache_index + 1],
        cache_data[cache_index]
    };

endmodule

module mem_controller (
    input wire clk_in,

    // Memory interface
    input wire [7:0] mem_din,
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
assign lsb_valid = lsb_en;

// ICache read data
assign icache_data = mem_din;

// ICache valid signal
assign icache_data_valid = icache_en && !lsb_en;

endmodule