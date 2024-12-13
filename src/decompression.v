
module decompression(
    input wire        clk_in,
    input [31:0]      inst_c,
    output reg [31:0] inst_out
);

    always @(posedge clk_in) begin
        case ({inst_c[15:13], inst_c[1:0]})
            // c.addi4spn
            5'b00000: inst_out <= {2'b00, inst_c[10:7], inst_c[12:11], inst_c[5], inst_c[6], 2'b00, 5'd2, 3'b000, 2'b01, inst_c[4:2], 7'b0010011};
            // c.lw
            5'b01000: inst_out <= {5'b00000, inst_c[5], inst_c[12:10], inst_c[6], 2'b00, 2'b01, inst_c[9:7], 3'b010, 2'b01, inst_c[4:2], 7'b0000011};
            // c.sw
            5'b11000: inst_out <= {5'b00000, inst_c[5], inst_c[12], 2'b01, inst_c[4:2], 2'b01, inst_c[9:7], 3'b010, inst_c[11:10], inst_c[6], 2'b00, 7'b0100011};
            5'b00001: begin
                // c.nop
                if (inst_c[12:2] == 11'b0)
                    inst_out <= {25'b0, 7'b0010011};
                // c.addi
                else inst_out <= {{7{inst_c[12]}}, inst_c[6:2], inst_c[11:7], 3'b000, inst_c[11:7], 7'b0010011};
            end
            // c.jal
            5'b00101: inst_out <= {inst_c[12], inst_c[8], inst_c[10:9], inst_c[6], inst_c[7], inst_c[2], inst_c[11], inst_c[5:3], inst_c[12], {8{inst_c[12]}}, 5'd1, 7'b1101111};
            // c.li
            5'b01001: inst_out <= {{7{inst_c[12]}}, inst_c[6:2], 5'd0, 3'b000, inst_c[11:7], 7'b0010011};
            5'b01101: begin
                // c.addi16sp
                if (inst_c[11:7] == 5'd2)
                    inst_out <= {{3{inst_c[12]}}, inst_c[4], inst_c[3], inst_c[5], inst_c[2], inst_c[6], 4'b0000, 5'd2, 3'b000, 5'd2, 7'b0010011};
                    // c.lui
                else inst_out <= {{15{inst_c[12]}}, inst_c[6:2], inst_c[11:7], 7'b0110111};
            end
            5'b10001: begin
                // c.sub
                if (inst_c[12:10] == 3'b011 && inst_c[6:5] == 2'b00)
                    inst_out <= {7'b0100000, 2'b01, inst_c[4:2], 2'b01, inst_c[9:7], 3'b000, 2'b01, inst_c[9:7], 7'b0110011};
                    // c.xor
                else if (inst_c[12:10] == 3'b011 && inst_c[6:5] == 2'b01)
                    inst_out <= {7'b0000000, 2'b01, inst_c[4:2], 2'b01, inst_c[9:7], 3'b100, 2'b01, inst_c[9:7], 7'b0110011};
                    // c.or
                else if (inst_c[12:10] == 3'b011 && inst_c[6:5] == 2'b10)
                    inst_out <= {7'b0000000, 2'b01, inst_c[4:2], 2'b01, inst_c[9:7], 3'b110, 2'b01, inst_c[9:7], 7'b0110011};
                    // c.and
                else if (inst_c[12:10] == 3'b011 && inst_c[6:5] == 2'b11)
                    inst_out <= {7'b0000000, 2'b01, inst_c[4:2], 2'b01, inst_c[9:7], 3'b111, 2'b01, inst_c[9:7], 7'b0110011};
                    // c.andi
                else if (inst_c[11:10] == 2'b10)
                    inst_out <= {{7{inst_c[12]}}, inst_c[6:2], 2'b01, inst_c[9:7], 3'b111, 2'b01, inst_c[9:7], 7'b0010011};
                    // Skip instruction
                else if (inst_c[12] == 1'b0 && inst_c[6:2] == 5'b0)
                    inst_out <= 32'b0;
                    // c.srli
                else if (inst_c[11:10] == 2'b00)
                    inst_out <= {7'b0000000, inst_c[6:2], 2'b01, inst_c[9:7], 3'b101, 2'b01, inst_c[9:7], 7'b0010011};
                    // c.srai
                else
                    inst_out <= {7'b0100000, inst_c[6:2], 2'b01, inst_c[9:7], 3'b101, 2'b01, inst_c[9:7], 7'b0010011};
            end
            // c.j
            5'b10101: inst_out <= {inst_c[12], inst_c[8], inst_c[10:9], inst_c[6], inst_c[7], inst_c[2], inst_c[11], inst_c[5:3], inst_c[12], {8{inst_c[12]}}, 5'd0, 7'b1101111};
            // c.beqz
            5'b11001: inst_out <= {{4{inst_c[12]}}, inst_c[6], inst_c[5], inst_c[2], 5'd0, 2'b01, inst_c[9:7], 3'b000, inst_c[11], inst_c[10], inst_c[4], inst_c[3], inst_c[12], 7'b1100011};
            // c.bnez
            5'b11101: inst_out <= {{4{inst_c[12]}}, inst_c[6], inst_c[5], inst_c[2], 5'd0, 2'b01, inst_c[9:7], 3'b001, inst_c[11], inst_c[10], inst_c[4], inst_c[3], inst_c[12], 7'b1100011};
            // c.slli
            5'b00010: inst_out <= {7'b0000000, inst_c[6:2], inst_c[11:7], 3'b001, inst_c[11:7], 7'b0010011};
            // c.lwsp
            5'b01010: inst_out <= {4'b0000, inst_c[3:2], inst_c[12], inst_c[6:4], 2'b0, 5'd2, 3'b010, inst_c[11:7], 7'b0000011};
            // c.swsp
            5'b11010: inst_out <= {4'b0000, inst_c[8:7], inst_c[12], inst_c[6:2], 5'd2, 3'b010, inst_c[11:9], 2'b00, 7'b0100011};
            5'b10010: begin
                if (inst_c[6:2] == 5'd0) begin
                    // c.jalr
                    if (inst_c[12] && inst_c[11:7] != 5'b0)
                        inst_out <= {12'b0, inst_c[11:7], 3'b000, 5'd1, 7'b1100111};
                        // c.jr
                    else inst_out <= {12'b0, inst_c[11:7], 3'b000, 5'd0, 7'b1100111};
                end
                else if (inst_c[11:7] != 5'b0) begin
                    // c.mv
                    if (inst_c[12] == 1'b0)
                        inst_out <= {7'b0000000, inst_c[6:2], 5'd0, 3'b000, inst_c[11:7], 7'b0110011};
                        // c.add
                    else inst_out <= {7'b0000000, inst_c[6:2], inst_c[11:7], 3'b000, inst_c[11:7], 7'b0110011};
                end
            end
            default : inst_out <= inst_c;
        endcase
    end

endmodule