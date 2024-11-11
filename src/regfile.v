`include "const_def.v"

module regfile(
    input wire clk_in, // system clock signal
    input wire rst_in, // reset signal

    // Input from ROB
    input wire from_rob_write_enabled,
    input wire [`ROB_RANGE] from_rob_reg_id,
    input wire [31:0] from_rob_data,
    input wire [`ROB_RANGE] from_rob_rob_id,

    // Input from Decoder
    input wire from_decoder_write_enabled,
    input wire [`ROB_RANGE] from_decoder_reg_id,
    input wire [`ROB_RANGE] from_decoder_rob_id,

    input wire flush_input,

    // Output to Decoder
    output wire [`ROB_RANGE] to_decoder_rob_id[31:0],
    output wire [31:0] to_decoder_data[31:0]
);

// Registers to store data and ROB IDs
reg [31:0] register_data[31:0];
reg [`ROB_RANGE] register_rob_id[31:0];

integer i;

always @(posedge clk_in) begin
    if (rst_in) begin
        // Reset all registers and ROB IDs to default values
        for (i = 0; i < 32; i = i + 1) begin
            register_data[i] <= 32'b0;
            register_rob_id[i] <= 0;
        end
    end else if (flush_input) begin
        for (i = 0; i < 32; i = i + 1) begin
            register_rob_id[i] <= 0;
        end
    end else begin
        // Handle Decoder updates
        if (from_decoder_write_enabled && from_decoder_reg_id != 0) begin
            register_rob_id[from_decoder_reg_id] <= from_decoder_rob_id;
        end

        // Handle ROB updates
        if (from_rob_write_enabled && from_rob_reg_id != 0) begin
            register_data[from_rob_reg_id] <= from_rob_data;
            // Only update if Decoder is not simultaneously writing to the same register
            if (!from_decoder_write_enabled || from_rob_reg_id != from_decoder_reg_id) begin
                if (from_rob_rob_id == from_rob_rob_id) begin
                    register_rob_id[from_rob_reg_id] <= 0;
                end
            end
        end
    end
end

always @(*) begin
    for (i = 1; i < 32; i = i + 1) begin
        to_decoder_data[i] = register_data[i];
        to_decoder_rob_id[i] = register_rob_id[i];
    end
    to_decoder_data[0] = 32'b0;
    to_decoder_rob_id[0] = 0;
end


endmodule