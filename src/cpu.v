// RISCV32 CPU top module
// port modification allowed for debugging purposes

`include "const_def.v"

module cpu (
  input  wire                 clk_in,			// system clock signal
  input  wire                 rst_in,			// reset signal
  input  wire					        rdy_in,			// ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,		// data input bus
  output wire [ 7:0]          mem_dout,		// data output bus
  output wire [31:0]          mem_a,			// address bus (only 17:0 is used)
  output wire                 mem_wr,			// write/read signal (1 for write)

  input  wire                 io_buffer_full, // 1 if uart buffer is full

  output wire [31:0]			dbgreg_dout		// cpu register output (debugging demo)
);

// Specifications:
// - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)

    // Internal wires for CDB (Common Data Bus)
    wire [`ROB_RANGE] cdb_alu_rob_id;
    wire [31:0] cdb_alu_value;
    wire [`ROB_RANGE] cdb_mem_rob_id;
    wire [31:0] cdb_mem_value;

    // Wires between Memory Controller and Load/Store Unit
    wire [31:0] lsb_addr;
    wire [7:0] lsb_data;
    wire lsb_wr;
    wire lsb_en;
    wire [7:0] lsb_read_data;
    wire lsb_valid;

    // Wires between Memory Controller and IFU
    wire [31:0] icache_addr;
    wire icache_en;
    wire icache_data_valid;
    wire [7:0] icache_data;

    // Memory Controller
    mem_controller mem_ctrl(
        .clk_in(clk_in),
        .mem_din(mem_din),
        .mem_valid(~io_buffer_full),
        .mem_dout(mem_dout),
        .mem_a(mem_a),
        .mem_wr(mem_wr),
        .lsb_addr(lsb_addr),
        .lsb_data(lsb_data),
        .lsb_wr(lsb_wr),
        .lsb_en(lsb_en),
        .lsb_read_data(lsb_read_data),
        .lsb_valid(lsb_valid),
        .icache_addr(icache_addr),
        .icache_en(icache_en),
        .icache_data_valid(icache_data_valid),
        .icache_data(icache_data)
    );

    // Wires for IFU
    wire [31:0] inst_out;
    wire [31:0] program_counter;
    wire ifu_valid_out;
    wire pred_branch_taken;
    wire [31:0] rob_pc;
    wire rob_pc_valid;
    wire [31:0] decoder_pc;
    wire decoder_pc_valid;
    wire [31:0] branch_pc;
    wire branch_taken;
    wire branch_record_valid;

    // Instruction Fetch Unit
    instruction_fetch_unit ifu(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .pc_from_rob(rob_pc),
        .valid_from_rob(rob_pc_valid),
        .pc_from_decoder(decoder_pc),
        .valid_from_decoder(decoder_pc_valid),
        .pc_of_branch(branch_pc),
        .branch_taken(branch_taken),
        .branch_record_valid(branch_record_valid),
        .mem_byte(icache_data),
        .mem_valid(icache_data_valid),
        .mem_en(icache_en),
        .miss_addr(icache_addr),
        .inst_out(inst_out),
        .program_counter(program_counter),
        .valid_out(ifu_valid_out),
        .pred_branch_taken(pred_branch_taken)
    );

    // Wires for RegFile
    wire [`ROB_RANGE] regfile_rob_id [31:0];
    wire [31:0] regfile_data [31:0];
    wire regfile_write_enabled;
    wire [`ROB_RANGE] regfile_write_reg_id;
    wire [31:0] regfile_write_data;
    wire [`ROB_RANGE] regfile_write_rob_id;
    wire decoder_regfile_enabled;
    wire [`ROB_RANGE] decoder_regfile_reg_id;
    wire [`ROB_RANGE] decoder_regfile_rob_id_out;

    // Register File
    regfile rf(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .from_rob_write_enabled(regfile_write_enabled),
        .from_rob_reg_id(regfile_write_reg_id),
        .from_rob_data(regfile_write_data),
        .from_rob_rob_id(regfile_write_rob_id),
        .from_decoder_write_enabled(decoder_regfile_enabled),
        .from_decoder_reg_id(decoder_regfile_reg_id),
        .from_decoder_rob_id(decoder_regfile_rob_id_out),
        .flush_input(rob_flush),
        .to_decoder_rob_id(regfile_rob_id),
        .to_decoder_data(regfile_data)
    );

    // Wires for Reservation Stations
    wire rs_alu_has_no_vacancy, rs_alu_has_one_vacancy;
    wire rs_bcu_has_no_vacancy, rs_bcu_has_one_vacancy;
    wire rs_mem_has_no_load_vacancy, rs_mem_has_one_load_vacancy;
    wire rs_mem_has_no_store_vacancy, rs_mem_has_one_store_vacancy;

    // Compute full signals for decoder
    wire rs_alu_full = rs_alu_has_no_vacancy || (rs_alu_has_one_vacancy && decoder_rs_alu_enabled);
    wire rs_bcu_full = rs_bcu_has_no_vacancy || (rs_bcu_has_one_vacancy && decoder_rs_bcu_enabled);
    wire rs_mem_load_full = rs_mem_has_no_load_vacancy || (rs_mem_has_one_load_vacancy && decoder_rs_mem_load_enabled);
    wire rs_mem_store_full = rs_mem_has_no_store_vacancy || (rs_mem_has_one_store_vacancy && decoder_rs_mem_store_enabled);

    // Wires for ALU Reservation Station and ALU
    wire decoder_rs_alu_enabled;
    wire [3:0] decoder_rs_alu_op;
    wire [31:0] decoder_rs_alu_Vj, decoder_rs_alu_Vk;
    wire [`ROB_RANGE] decoder_rs_alu_Qj, decoder_rs_alu_Qk, decoder_rs_alu_dest;
    wire [3:0] alu_op;
    wire [31:0] alu_Vj, alu_Vk;
    wire [`ROB_RANGE] alu_dest;

    // ALU Reservation Station
    reservation_station_alu rs_alu(
        .clk_in(clk_in),
        .operation_enabled(decoder_rs_alu_enabled),
        .op(decoder_rs_alu_op),
        .Vj(decoder_rs_alu_Vj),
        .Vk(decoder_rs_alu_Vk),
        .Qj(decoder_rs_alu_Qj),
        .Qk(decoder_rs_alu_Qk),
        .dest(decoder_rs_alu_dest),
        .cdb_alu_rob_id(cdb_alu_rob_id),
        .cdb_alu_value(cdb_alu_value),
        .cdb_mem_rob_id(cdb_mem_rob_id),
        .cdb_mem_value(cdb_mem_value),
        .flush_input(rob_flush),
        .has_no_vacancy(rs_alu_has_no_vacancy),
        .has_one_vacancy(rs_alu_has_one_vacancy),
        .alu_op(alu_op),
        .alu_Vj(alu_Vj),
        .alu_Vk(alu_Vk),
        .alu_dest(alu_dest)
    );

    // ALU
    alu alu_unit(
        .clk_in(clk_in),
        .op(alu_op),
        .rs1(alu_Vj),
        .rs2(alu_Vk),
        .dest(alu_dest),
        .rob_id(cdb_alu_rob_id),
        .value(cdb_alu_value)
    );

    // Wires for BCU Reservation Station and BCU
    wire decoder_rs_bcu_enabled;
    wire [2:0] decoder_rs_bcu_op;
    wire [31:0] decoder_rs_bcu_Vj, decoder_rs_bcu_Vk;
    wire [`ROB_RANGE] decoder_rs_bcu_Qj, decoder_rs_bcu_Qk, decoder_rs_bcu_dest;
    wire [31:0] decoder_rs_bcu_pc_fallthrough, decoder_rs_bcu_pc_target;
    wire [2:0] bcu_op;
    wire [31:0] bcu_Vj, bcu_Vk;
    wire [`ROB_RANGE] bcu_dest;
    wire [31:0] bcu_pc_fallthrough, bcu_pc_target;
    wire [`ROB_RANGE] bcu_rob_id;
    wire bcu_taken;
    wire [31:0] bcu_value;

    // BCU Reservation Station
    reservation_station_bcu rs_bcu(
        .clk_in(clk_in),
        .operation_enabled(decoder_rs_bcu_enabled),
        .op(decoder_rs_bcu_op),
        .Vj(decoder_rs_bcu_Vj),
        .Vk(decoder_rs_bcu_Vk),
        .Qj(decoder_rs_bcu_Qj),
        .Qk(decoder_rs_bcu_Qk),
        .dest(decoder_rs_bcu_dest),
        .pc_fallthrough(decoder_rs_bcu_pc_fallthrough),
        .pc_target(decoder_rs_bcu_pc_target),
        .cdb_alu_rob_id(cdb_alu_rob_id),
        .cdb_alu_value(cdb_alu_value),
        .cdb_mem_rob_id(cdb_mem_rob_id),
        .cdb_mem_value(cdb_mem_value),
        .flush_input(rob_flush),
        .has_no_vacancy(rs_bcu_has_no_vacancy),
        .has_one_vacancy(rs_bcu_has_one_vacancy),
        .bcu_op(bcu_op),
        .bcu_Vj(bcu_Vj),
        .bcu_Vk(bcu_Vk),
        .bcu_dest(bcu_dest),
        .bcu_pc_fallthrough(bcu_pc_fallthrough),
        .bcu_pc_target(bcu_pc_target)
    );

    // BCU
    bcu bcu_unit(
        .clk_in(clk_in),
        .op(bcu_op),
        .rs1(bcu_Vj),
        .rs2(bcu_Vk),
        .dest(bcu_dest),
        .pc_fallthrough(bcu_pc_fallthrough),
        .pc_target(bcu_pc_target),
        .rob_id(bcu_rob_id),
        .taken(bcu_taken),
        .value(bcu_value)
    );

    // Wires for Memory Reservation Station and Load/Store Unit
    wire decoder_rs_mem_load_enabled;
    wire [2:0] decoder_rs_mem_load_op;
    wire [31:0] decoder_rs_mem_load_Vj;
    wire [11:0] decoder_rs_mem_load_offset;
    wire [`ROB_RANGE] decoder_rs_mem_load_Qj, decoder_rs_mem_load_dest;
    wire decoder_rs_mem_store_enabled;
    wire [2:0] decoder_rs_mem_store_op;
    wire [31:0] decoder_rs_mem_store_Vj, decoder_rs_mem_store_Vk;
    wire [11:0] decoder_rs_mem_store_offset;
    wire [`ROB_RANGE] decoder_rs_mem_store_Qj, decoder_rs_mem_store_Qk, decoder_rs_mem_store_Qm, decoder_rs_mem_store_dest;
    wire mem_typ;
    wire [2:0] mem_op;
    wire [31:0] mem_Vj, mem_Vk;
    wire [11:0] mem_offset;
    wire [`ROB_RANGE] mem_dest;
    wire mem_recv;

    // Memory Reservation Station
    reservation_station_mem rs_mem(
        .clk_in(clk_in),
        .load_enabled(decoder_rs_mem_load_enabled),
        .load_op(decoder_rs_mem_load_op),
        .load_Vj(decoder_rs_mem_load_Vj),
        .load_Qj(decoder_rs_mem_load_Qj),
        .load_dest(decoder_rs_mem_load_dest),
        .load_offset(decoder_rs_mem_load_offset),
        .store_enabled(decoder_rs_mem_store_enabled),
        .store_op(decoder_rs_mem_store_op),
        .store_Vj(decoder_rs_mem_store_Vj),
        .store_Vk(decoder_rs_mem_store_Vk),
        .store_Qj(decoder_rs_mem_store_Qj),
        .store_Qk(decoder_rs_mem_store_Qk),
        .store_Qm(decoder_rs_mem_store_Qm),
        .store_dest(decoder_rs_mem_store_dest),
        .store_offset(decoder_rs_mem_store_offset),
        .cdb_alu_rob_id(cdb_alu_rob_id),
        .cdb_alu_value(cdb_alu_value),
        .cdb_mem_rob_id(cdb_mem_rob_id),
        .cdb_mem_value(cdb_mem_value),
        .rob_commit_id(rob_commit_id),
        .recv(mem_recv),
        .flush_input(rob_flush),
        .has_no_load_vacancy(rs_mem_has_no_load_vacancy),
        .has_one_load_vacancy(rs_mem_has_one_load_vacancy),
        .has_no_store_vacancy(rs_mem_has_no_store_vacancy),
        .has_one_store_vacancy(rs_mem_has_one_store_vacancy),
        .mem_typ(mem_typ),
        .mem_op(mem_op),
        .mem_Vj(mem_Vj),
        .mem_Vk(mem_Vk),
        .mem_offset(mem_offset),
        .mem_dest(mem_dest)
    );

    // Load/Store Unit
    load_store_unit lsu(
        .clk_in(clk_in),
        .typ(mem_typ),
        .op(mem_op),
        .rs1(mem_Vj),
        .rs2(mem_Vk),
        .offset(mem_offset),
        .dest(mem_dest),
        .flush_input(rob_flush),
        .mem_din(lsb_read_data),
        .mem_success(lsb_valid),
        .mem_addr(lsb_addr),
        .mem_dout(lsb_data),
        .mem_wr(lsb_wr),
        .mem_en(lsb_en),
        .rob_id(cdb_mem_rob_id),
        .value(cdb_mem_value),
        .recv(mem_recv)
    );
    // Wires for ROB
    wire decoder_rob_enabled;
    wire [1:0] decoder_rob_op;
    wire decoder_rob_value_ready;
    wire [31:0] decoder_rob_value, decoder_rob_alt_value;
    wire [`ROB_RANGE] decoder_rob_dest;
    wire decoder_rob_predicted_branch_taken;
    wire rob_has_no_vacancy, rob_has_one_vacancy;
    wire [`ROB_RANGE] rob_next_tail, rob_next_next_tail;
    wire rob_flush;
    wire [`ROB_RANGE] rob_commit_id;
    wire [31:0] rob_decoder_value [`ROB_ARR];
    wire [`ROB_ARR] rob_decoder_ready;

    // ROB
    rob reorder_buffer(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .operation_enabled(decoder_rob_enabled),
        .operation_op(decoder_rob_op),
        .operation_status(decoder_rob_value_ready),
        .operation_value(decoder_rob_value),
        .operation_alt_value(decoder_rob_alt_value),
        .operation_dest(decoder_rob_dest),
        .operation_predicted_branch_taken(decoder_rob_predicted_branch_taken),
        .cdb_alu_rob_id(cdb_alu_rob_id),
        .cdb_alu_value(cdb_alu_value),
        .cdb_mem_rob_id(cdb_mem_rob_id),
        .cdb_mem_value(cdb_mem_value),
        .bcu_rob_id(bcu_rob_id),
        .bcu_taken(bcu_taken),
        .bcu_value(bcu_value),
        .reg_file_enabled(regfile_write_enabled),
        .reg_file_reg_id(regfile_write_reg_id),
        .reg_file_data(regfile_write_data),
        .reg_file_rob_id(regfile_write_rob_id),
        .commit_rob_id(rob_commit_id),
        .fetcher_pc_enabled(rob_pc_valid),
        .fetcher_pc(rob_pc),
        .fetcher_branch_pc(branch_pc),
        .fetcher_branch_taken(branch_taken),
        .fetcher_branch_record_enabled(branch_record_valid),
        .decoder_value(rob_decoder_value),
        .decoder_ready(rob_decoder_ready),
        .has_no_vacancy(rob_has_no_vacancy),
        .has_one_vacancy(rob_has_one_vacancy),
        .next_tail_output(rob_next_tail),
        .next_next_tail_output(rob_next_next_tail),
        .flush_outputs(rob_flush)
    );

    // Compute ROB full and tail signal for decoder
    wire rob_full = rob_has_no_vacancy || (rob_has_one_vacancy && decoder_rob_enabled);
    wire [`ROB_RANGE] rob_tail = decoder_rob_enabled ? rob_next_next_tail : rob_next_tail;

    // Decoder
    decoder decoder_unit(
        .clk_in(clk_in),
        .instruction_valid(ifu_valid_out),
        .fetcher_instruction(inst_out),
        .fetcher_program_counter(program_counter),
        .fetcher_predicted_branch_taken(pred_branch_taken),
        .regfile_rob_id(regfile_rob_id),
        .regfile_data(regfile_data),
        .rob_values(rob_decoder_value),
        .rob_ready(rob_decoder_ready),
        .cdb_alu_rob_id(cdb_alu_rob_id),
        .cdb_alu_value(cdb_alu_value),
        .cdb_mem_rob_id(cdb_mem_rob_id),
        .cdb_mem_value(cdb_mem_value),
        .rs_alu_full(rs_alu_full),
        .rs_bcu_full(rs_bcu_full),
        .rs_mem_load_full(rs_mem_load_full),
        .rs_mem_store_full(rs_mem_store_full),
        .rob_full(rob_full),
        .rob_id(rob_tail),
        .commit_rob_id(rob_commit_id),
        .flush_input(rob_flush),

        // Outputs to Fetcher
        .fetcher_enabled(decoder_pc_valid),
        .fetcher_pc(decoder_pc),

        // Outputs to ROB
        .rob_enabled(decoder_rob_enabled),
        .rob_op(decoder_rob_op),
        .rob_value_ready(decoder_rob_value_ready),
        .rob_value(decoder_rob_value),
        .rob_alt_value(decoder_rob_alt_value),
        .rob_dest(decoder_rob_dest),
        .rob_predicted_branch_taken(decoder_rob_predicted_branch_taken),

        // Outputs to RS ALU
        .rs_alu_enabled(decoder_rs_alu_enabled),
        .rs_alu_op(decoder_rs_alu_op),
        .rs_alu_Vj(decoder_rs_alu_Vj),
        .rs_alu_Vk(decoder_rs_alu_Vk),
        .rs_alu_Qj(decoder_rs_alu_Qj),
        .rs_alu_Qk(decoder_rs_alu_Qk),
        .rs_alu_dest(decoder_rs_alu_dest),

        // Outputs to RS BCU
        .rs_bcu_enabled(decoder_rs_bcu_enabled),
        .rs_bcu_op(decoder_rs_bcu_op),
        .rs_bcu_Vj(decoder_rs_bcu_Vj),
        .rs_bcu_Vk(decoder_rs_bcu_Vk),
        .rs_bcu_Qj(decoder_rs_bcu_Qj),
        .rs_bcu_Qk(decoder_rs_bcu_Qk),
        .rs_bcu_dest(decoder_rs_bcu_dest),
        .rs_bcu_pc_fallthrough(decoder_rs_bcu_pc_fallthrough),
        .rs_bcu_pc_target(decoder_rs_bcu_pc_target),

        // Outputs to RS Mem Load
        .rs_mem_load_enabled(decoder_rs_mem_load_enabled),
        .rs_mem_load_op(decoder_rs_mem_load_op),
        .rs_mem_load_Vj(decoder_rs_mem_load_Vj),
        .rs_mem_load_Qj(decoder_rs_mem_load_Qj),
        .rs_mem_load_dest(decoder_rs_mem_load_dest),
        .rs_mem_load_offset(decoder_rs_mem_load_offset),

        // Outputs to RS Mem Store
        .rs_mem_store_enabled(decoder_rs_mem_store_enabled),
        .rs_mem_store_op(decoder_rs_mem_store_op),
        .rs_mem_store_Vj(decoder_rs_mem_store_Vj),
        .rs_mem_store_Vk(decoder_rs_mem_store_Vk),
        .rs_mem_store_Qj(decoder_rs_mem_store_Qj),
        .rs_mem_store_Qk(decoder_rs_mem_store_Qk),
        .rs_mem_store_Qm(decoder_rs_mem_store_Qm),
        .rs_mem_store_dest(decoder_rs_mem_store_dest),
        .rs_mem_store_offset(decoder_rs_mem_store_offset),

        // Outputs to RegFile
        .regfile_enabled(decoder_regfile_enabled),
        .regfile_reg_id(decoder_regfile_reg_id),
        .regfile_rob_id_out(decoder_regfile_rob_id_out)
    );

endmodule