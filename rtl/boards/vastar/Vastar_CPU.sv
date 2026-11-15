// Based on MAME vastar.cpp, vastar_viddev.cpp, zodiack.cpp (Allard van der Bas, Zsolt Vasvari, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module Vastar_CPU
(
	input         reset,
	input         clk_49m,
	output  [4:0] red, green, blue,
	output        video_hsync, video_vsync, video_csync,
	output        video_hblank, video_vblank,
	output        ce_pix,
	input   [7:0] p1_controls,
	input   [7:0] p2_controls,
	input   [7:0] sys_controls,
	input  [15:0] dip_sw,
    input         rot_flip,
	input         ovg,
	input         zod,
	input   [7:0] zin0, zin1,
	input   [7:0] zin2,
	input         percuss,
	input         horz,
	input         crt_flip,
	output signed [15:0] sound,
	input   [3:0] h_center, v_center,
	input         pause,
	input  [15:0] hs_address,
	input   [7:0] hs_data_in,
	output  [7:0] hs_data_out,
	input         hs_write,

	output chip_pool_pkg::z80r_i_t [1:0] z80_i,
	input  chip_pool_pkg::z80r_o_t [1:0] z80_o,
	output chip_pool_pkg::ayr_i_t        ay_0_i,
	input  chip_pool_pkg::ayio_o_t       ay_0_o,

	output [14:0] main_rom_a,
	input   [7:0] main_rom_d,
	output [12:0] sub_rom_a,
	input   [7:0] sub_rom_d,
	output [12:0] fgtile_rom_a,
	input   [7:0] fgtile_rom_d,
	output [12:0] bgtile0_rom_a,
	input   [7:0] bgtile0_rom_d,
	output [12:0] bgtile1_rom_a,
	input   [7:0] bgtile1_rom_d,
	output [12:0] sprite_rom_a,
	input   [7:0] sprite0_rom_d,
	input   [7:0] sprite1_rom_d,
	output  [7:0] prom_a,
	input   [7:0] prom_r_d,
	input   [7:0] prom_g_d,
	input   [7:0] prom_b_d,
	output  [7:0] prom_unk_a,
	input   [7:0] prom_unk_d,
	output [13:0] ovg_gfx_a,
	input   [7:0] ovg_gfx_d,
	output  [5:0] ovg_prom_a,
	input   [7:0] ovg_prom_d,

	output ram_pool_pkg::pram_i_t [6:0] pr_i,
	input  ram_pool_pkg::pram_o_t [6:0] pr_o
);

// dot clock, htotal wrap, hsync window and page flip are coupled: change them together
wire [1:0] pix_cen_o;
jtframe_frac_cen #(2) pix_cen (.clk(clk_49m), .n(10'd4), .m(10'd32), .cen(pix_cen_o), .cenb());
wire cen_pix = pix_cen_o[0];
assign ce_pix = cen_pix;

reg [3:0] cpu_div = 4'd0;
always_ff @(posedge clk_49m) cpu_div <= cpu_div + 4'd1;
wire cen_cpu = (cpu_div == 4'd0);

reg ay_toggle = 1'b0;
always_ff @(posedge clk_49m) if (cen_cpu) ay_toggle <= ~ay_toggle;
wire cen_ay = cen_cpu & ~ay_toggle & ~pause;

reg [8:0] base_h_cnt = 9'd0;
reg [8:0] v_cnt      = 9'd0;

wire [8:0] h_cnt_rot;
wire [8:0] v_cnt_rot;

assign h_cnt_rot = { base_h_cnt[8], base_h_cnt[7:0] ^ {8{flip_screen}} };
assign v_cnt_rot = { v_cnt[8],      v_cnt[7:0]      ^ {8{flip_screen}} };

always_ff @(posedge clk_49m) begin
	if (cen_pix) begin
		if (base_h_cnt == 9'd383) begin
			base_h_cnt <= 9'd0;
			v_cnt <= (v_cnt == 9'd263) ? 9'd0 : v_cnt + 9'd1;
		end else begin
			base_h_cnt <= base_h_cnt + 9'd1;
		end
	end
end

wire hblk = (base_h_cnt >= 9'd256);
wire vblk = (v_cnt < 9'd17) | (v_cnt >= 9'd241);
assign video_hblank = hblk;
assign video_vblank = vblk;

wire [8:0] hs_start = 9'd280 + {{5{h_center[3]}}, h_center};
wire [8:0] hs_end   = hs_start + 9'd16;
wire [8:0] vs_start = 9'd249 + {{5{v_center[3]}}, v_center};
wire [8:0] vs_end   = vs_start + 9'd4;
// syncs from the unflipped counters: the flipped count never reaches the hsync window
assign video_hsync = (base_h_cnt >= hs_start && base_h_cnt < hs_end);
assign video_vsync = (v_cnt >= vs_start && v_cnt < vs_end);
assign video_csync = ~(video_hsync ^ video_vsync);

wire [15:0] cpu1_A;
reg         z_irq = 1'b0, z_nmi_en = 1'b0;
wire [7:0]  cpu1_Dout;
wire        cpu1_WR_n, cpu1_RD_n, cpu1_MREQ_n, cpu1_IORQ_n, cpu1_M1_n, cpu1_RFSH_n;

assign cpu1_M1_n = z80_o[0].m1_n; assign cpu1_MREQ_n = z80_o[0].mreq_n; assign cpu1_IORQ_n = z80_o[0].iorq_n;
assign cpu1_RD_n = z80_o[0].rd_n; assign cpu1_WR_n = z80_o[0].wr_n; assign cpu1_RFSH_n = z80_o[0].rfsh_n;
assign cpu1_A = z80_o[0].a; assign cpu1_Dout = z80_o[0].dout;

reg cpu1_nmi = 1'b0;
reg vblk_prev = 1'b0;
always_ff @(posedge clk_49m) begin
	if (!reset) begin cpu1_nmi <= 0; vblk_prev <= 0; end
	else begin vblk_prev <= vblk; cpu1_nmi <= (vblk && !vblk_prev && (zod ? z_nmi_en : nmi_mask)); end
end

wire cpu1_mem_valid = ~cpu1_MREQ_n & cpu1_RFSH_n;
wire cs_rom      = cpu1_mem_valid & ~zod & ~cpu1_A[15];
wire cs_bg1      = cpu1_mem_valid & ~ovg & ((cpu1_A[15:12] == 4'h8) | (cpu1_A[15:12] == 4'hA));
wire cs_bg0      = cpu1_mem_valid & ~ovg & ((cpu1_A[15:12] == 4'h9) | (cpu1_A[15:12] == 4'hB));
wire cs_priority = cpu1_mem_valid & ~ovg & (cpu1_A[15:0] == 16'hC000);
wire cs_fgvram   = cpu1_mem_valid & ~ovg & (cpu1_A[15:12] == 4'hC) & (cpu1_A[11:10] != 2'b00);
wire cs_watchdog = cpu1_mem_valid & (cpu1_A[15:12] == 4'hE);
wire cs_shared   = cpu1_mem_valid & ~zod & (cpu1_A[15:11] == 5'b11110);
wire cs_zrom     = cpu1_mem_valid & zod & (cpu1_A < 16'h5000 || cpu1_A[15:12] == 4'hC);
wire cs_zram     = cpu1_mem_valid & zod & (cpu1_A[15:11] == 5'b01011);
wire cs_zio      = cpu1_mem_valid & zod & (cpu1_A[15:8] == 8'h60);
wire cs_mainlatch = ~cpu1_IORQ_n & ~cpu1_WR_n & (cpu1_A[3:0] <= 4'h7);

reg [7:0] mainlatch = 8'd0;
always_ff @(posedge clk_49m) begin
	if (!reset) mainlatch <= 8'd0;
	else if (cen_cpu && cs_mainlatch) mainlatch[cpu1_A[2:0]] <= cpu1_Dout[0];
end
wire nmi_mask    = mainlatch[0];
wire game_flip   = rot_flip ^ (mainlatch[1] & ~ovg);
wire flip_screen = game_flip ^ crt_flip;
wire cpu2_rst    = ~mainlatch[2] & ~zod;

wire [15:0] cpu2_A;
reg         z_pend = 1'b0, z_snmi = 1'b0;
wire [7:0]  cpu2_Dout;
wire        cpu2_WR_n, cpu2_RD_n, cpu2_MREQ_n, cpu2_IORQ_n, cpu2_M1_n, cpu2_RFSH_n;

assign cpu2_M1_n = z80_o[1].m1_n; assign cpu2_MREQ_n = z80_o[1].mreq_n; assign cpu2_IORQ_n = z80_o[1].iorq_n;
assign cpu2_RD_n = z80_o[1].rd_n; assign cpu2_WR_n = z80_o[1].wr_n; assign cpu2_RFSH_n = z80_o[1].rfsh_n;
assign cpu2_A = z80_o[1].a; assign cpu2_Dout = z80_o[1].dout;

reg [17:0] cpu2_irq_cnt = 18'd0;
reg        cpu2_irq = 1'b0;
always_ff @(posedge clk_49m) begin
	if (!reset || cpu2_rst) begin cpu2_irq_cnt <= 0; cpu2_irq <= 0; end
	else begin
		if (cpu2_irq_cnt == 18'd203107) begin cpu2_irq_cnt <= 0; cpu2_irq <= 1; end
		else cpu2_irq_cnt <= cpu2_irq_cnt + 1;
		if (~cpu2_IORQ_n & ~cpu2_M1_n) cpu2_irq <= 0;
	end
end

wire cpu2_mem_valid = ~cpu2_MREQ_n & cpu2_RFSH_n;
wire cs2_rom    = cpu2_mem_valid & ~cpu2_A[15] & ~cpu2_A[14] & ~cpu2_A[13];
wire cs2_shared = cpu2_mem_valid & ~zod & (cpu2_A[15:11] == 5'b01000);
wire cs2_p2     = cpu2_mem_valid & ~zod & (cpu2_A[15:0] == 16'h8000);
wire cs2_p1     = cpu2_mem_valid & ~zod & (cpu2_A[15:0] == 16'h8040);
wire cs2_system = cpu2_mem_valid & ~zod & (cpu2_A[15:0] == 16'h8080);
wire cs2_zram   = cpu2_mem_valid & zod & (cpu2_A[15:10] == 6'b001000);
wire cs2_zlat   = cpu2_mem_valid & zod & (cpu2_A[15:0] == 16'h6000);
wire cs2_znmi   = cpu2_mem_valid & zod & (cpu2_A[15:0] == 16'h4000);
wire cs2_ay_addr = ~cpu2_IORQ_n & ~cpu2_WR_n & (cpu2_A[3:0] == 4'h0);
wire cs2_ay_wr   = ~cpu2_IORQ_n & ~cpu2_WR_n & (cpu2_A[3:0] == 4'h1);
wire cs2_ay_rd   = ~cpu2_IORQ_n & ~cpu2_RD_n & (cpu2_A[3:0] == 4'h2);

wire [7:0] main_rom_D;
assign main_rom_a = zod && cpu1_A[15] ? {3'b101, cpu1_A[11:0]} : cpu1_A[14:0];
assign main_rom_D = main_rom_d;

wire [7:0] sub_rom_D;
assign sub_rom_a = cpu2_A[12:0];
assign sub_rom_D = sub_rom_d;

ram_pool_pkg::pram_i_t [3:0] vs_pr_i;
ram_pool_pkg::pram_i_t [2:0] ovg_pr_i;
ram_pool_pkg::pram_i_t       z_pr_i;
assign pr_i[0] = ovg ? ovg_pr_i[0] : vs_pr_i[0];
assign pr_i[1] = ovg ? ovg_pr_i[1] : vs_pr_i[1];
assign pr_i[2] = ovg ? ovg_pr_i[2] : vs_pr_i[2];
assign pr_i[3] = zod ? z_pr_i : vs_pr_i[3];

wire [10:0] shared_addr_a = pause ? hs_address[10:0] : cpu1_A[10:0];
wire shared_wr_a = pause ? hs_write : (cs_shared & ~cpu1_WR_n);
wire [7:0] shared_din_a = pause ? hs_data_in : cpu1_Dout;
wire [2:0] hs_bank = rot_flip ? 3'b011 : 3'b001;

wire [7:0] bg1_vram_D, bg1_vram_rD;
reg [11:0] bg1_raddr;
assign vs_pr_i[0].a_addr = {4'd0, cpu1_A[11:0]}; assign vs_pr_i[0].a_d = cpu1_Dout; assign vs_pr_i[0].a_we = cs_bg1 & ~cpu1_WR_n;
assign vs_pr_i[0].b_addr = {4'd0, bg1_raddr}; assign vs_pr_i[0].b_d = 8'd0; assign vs_pr_i[0].b_we = 1'b0;
assign bg1_vram_D = pr_o[0].a_q;
assign bg1_vram_rD = pr_o[0].b_q;

wire [7:0] bg0_vram_D, bg0_vram_rD;
reg [11:0] bg0_raddr;
assign vs_pr_i[1].a_addr = {4'd0, cpu1_A[11:0]}; assign vs_pr_i[1].a_d = cpu1_Dout; assign vs_pr_i[1].a_we = cs_bg0 & ~cpu1_WR_n;
assign vs_pr_i[1].b_addr = {4'd0, bg0_raddr}; assign vs_pr_i[1].b_d = 8'd0; assign vs_pr_i[1].b_we = 1'b0;
assign bg0_vram_D = pr_o[1].a_q;
assign bg0_vram_rD = pr_o[1].b_q;

wire [7:0] fg_vram_D, fg_vram_rD;
reg [11:0] fg_raddr;
assign vs_pr_i[2].a_addr = {4'd0, cpu1_A[11:0]}; assign vs_pr_i[2].a_d = cpu1_Dout; assign vs_pr_i[2].a_we = cs_fgvram & ~cpu1_WR_n;
assign vs_pr_i[2].b_addr = {4'd0, fg_raddr}; assign vs_pr_i[2].b_d = 8'd0; assign vs_pr_i[2].b_we = 1'b0;
assign fg_vram_D = pr_o[2].a_q;
assign fg_vram_rD = pr_o[2].b_q;

wire [7:0] shared_ram_D_cpu1, shared_ram_D_cpu2;
assign vs_pr_i[3].a_addr = {5'd0, hs_write ? {hs_bank, hs_address[7:0]} : cpu1_A[10:0]}; assign vs_pr_i[3].a_d = hs_write ? hs_data_in : cpu1_Dout; assign vs_pr_i[3].a_we = (cs_shared & ~cpu1_WR_n) | hs_write;
assign vs_pr_i[3].b_addr = {5'd0, cpu2_A[10:0]}; assign vs_pr_i[3].b_d = cpu2_Dout; assign vs_pr_i[3].b_we = cs2_shared & ~cpu2_WR_n;
assign shared_ram_D_cpu1 = pr_o[3].a_q;
assign shared_ram_D_cpu2 = pr_o[3].b_q;

wire [7:0] hs_ram_q;
assign pr_i[4].a_addr = {8'd0, cpu1_A[7:0]}; assign pr_i[4].a_d = cpu1_Dout; assign pr_i[4].a_we = cs_shared & ~cpu1_WR_n & (cpu1_A[10:8] == hs_bank);
assign pr_i[4].b_addr = {8'd0, hs_address[7:0]}; assign pr_i[4].b_d = hs_data_in; assign pr_i[4].b_we = hs_write;
assign hs_ram_q = pr_o[4].b_q;

wire       ovg_cs;
wire [7:0] ovg_D;
wire [4:0] ovg_r, ovg_g, ovg_b;

wire [7:0] cpu1_Din = cs_rom ? main_rom_D : cs_bg1 ? bg1_vram_D : cs_bg0 ? bg0_vram_D :
                      cs_fgvram ? fg_vram_D : cs_shared ? shared_ram_D_cpu1 : ovg_cs ? ovg_D :
                      cs_zrom ? main_rom_D : cs_zram ? zram_D : cs_zio ? zio_D : 8'hFF;

wire [7:0] p1_inputs     = p1_controls;
wire [7:0] p2_inputs     = p2_controls;
wire [7:0] system_inputs = sys_controls;

assign hs_data_out = hs_ram_q;

wire [7:0] ay_ioa;
wire [7:0] zram_D;
assign z_pr_i.a_addr = {5'd0, cpu1_A[10:0]}; assign z_pr_i.a_d = cpu1_Dout; assign z_pr_i.a_we = cs_zram & ~cpu1_WR_n;
assign z_pr_i.b_addr = {5'd0, 11'd0}; assign z_pr_i.b_d = 8'd0; assign z_pr_i.b_we = 1'b0;
assign zram_D = pr_o[3].a_q;

reg  [7:0] z_lat0 = 8'd0, z_lat1 = 8'd0;
reg        z_irq_en = 1'b0, z_flip_d = 1'b1, z_snmi_en = 1'b0;
wire [7:0] zio_D = cpu1_A[7:0] == 8'h81 ? dip_sw[7:0] | zin2 : cpu1_A[7:0] == 8'h82 ? dip_sw[15:8] :
                   cpu1_A[7:0] == 8'h83 ? zin0 : cpu1_A[7:0] == 8'h84 ? zin1 : cpu1_A[7:0] == 8'h90 ? z_lat1 : 8'hFF;
wire       z_wr1 = cen_cpu & zod & cpu1_mem_valid & ~cpu1_WR_n;
wire       z_wr2 = cen_cpu & zod & cpu2_mem_valid & ~cpu2_WR_n;

always_ff @(posedge clk_49m) begin
	if (!reset) begin
		z_nmi_en <= 0; z_irq_en <= 0; z_irq <= 0; z_pend <= 0; z_snmi_en <= 0; z_flip_d <= 1'b1;
	end else begin
		if (z_wr1) case (cpu1_A)
			16'h6090: begin z_lat0 <= cpu1_Dout; z_pend <= 1'b1; end
			16'h7100: z_nmi_en <= ~cpu1_Dout[0];
			16'h7200: z_flip_d <= cpu1_Dout[0];
			16'h8000: z_irq_en <= cpu1_Dout[0];
			default: ;
		endcase
		if (zod && vblk && !vblk_prev && z_irq_en) z_irq <= 1'b1;
		else if (~cpu1_IORQ_n & ~cpu1_M1_n) z_irq <= 1'b0;
		if (z_wr2 && cs2_zlat) z_lat1 <= cpu2_Dout;
		if (z_wr2 && cs2_znmi) z_snmi_en <= cpu2_Dout[0];
		if (cs2_zlat && ~cpu2_RD_n) z_pend <= 1'b0;
	end
end

wire [7:0] zram2_D;
assign pr_i[5].a_addr = {6'd0, cpu2_A[9:0]}; assign pr_i[5].a_d = cpu2_Dout; assign pr_i[5].a_we = cs2_zram & ~cpu2_WR_n;
assign pr_i[5].b_addr = {6'd0, 10'd0}; assign pr_i[5].b_d = 8'd0; assign pr_i[5].b_we = 1'b0;
assign zram2_D = pr_o[5].a_q;

reg [7:0] z_sfreq = 8'd0;
reg [6:0] z_slines = 7'd0;
always_ff @(posedge clk_49m) begin
	z_snmi <= 1'b0;
	if (ay_ioa == 8'h00 || ay_ioa == 8'hC0 || ay_ioa == 8'hE0) z_sfreq <= ay_ioa;
	if (cen_pix && base_h_cnt == 9'd0) begin
		if (z_slines >= (z_sfreq == 8'hC0 ? 7'd65 : 7'd32)) begin
			z_slines <= 7'd0;
			z_snmi   <= zod & z_snmi_en & (z_sfreq != 8'h00);
		end else z_slines <= z_slines + 7'd1;
	end
end

wire [7:0] ay_dout;
wire [9:0] ay_sound;
assign ay_0_i.rst_n = reset; assign ay_0_i.ce = cen_ay; assign ay_0_i.bdir = cs2_ay_addr | cs2_ay_wr; assign ay_0_i.bc1 = cs2_ay_addr | cs2_ay_rd;
assign ay_0_i.din = cpu2_Dout; assign ay_0_i.ioa_in = dip_sw[7:0]; assign ay_0_i.iob_in = dip_sw[15:8];
assign ay_dout = ay_0_o.dout; assign ay_sound = ay_0_o.sound; assign ay_ioa = ay_0_o.ioa_out;
assign sound = {1'b0, ay_sound, 5'd0};

wire [7:0] cpu2_Din = (~cpu2_IORQ_n) ? (cs2_ay_rd ? ay_dout : 8'hFF) :
                      cs2_rom ? sub_rom_D : cs2_shared ? shared_ram_D_cpu2 : cs2_zram ? zram2_D : cs2_zlat ? z_lat0 :
                      cs2_p2 ? p2_inputs : cs2_p1 ? p1_inputs :
                      cs2_system ? system_inputs : 8'hFF;

reg [2:0] priority_mode = 3'd0;
always_ff @(posedge clk_49m) begin
	if (!reset) priority_mode <= 0;
	else if (cs_priority & ~cpu1_WR_n) priority_mode <= cpu1_Dout[2:0];
end

reg [12:0] fgtile_addr;
wire [7:0] fgtile_D;
assign fgtile_rom_a = fgtile_addr;
assign fgtile_D = fgtile_rom_d;

reg [12:0] bgtile0_addr;
wire [7:0] bgtile0_D;
assign bgtile0_rom_a = bgtile0_addr;
assign bgtile0_D = bgtile0_rom_d;

reg [12:0] bgtile1_addr;
wire [7:0] bgtile1_D;
assign bgtile1_rom_a = bgtile1_addr;
assign bgtile1_D = bgtile1_rom_d;

reg [12:0] sprite_addr;
wire [7:0] sprite0_D, sprite1_D;
assign sprite_rom_a = sprite_addr;
assign sprite0_D = sprite0_rom_d;
assign sprite1_D = sprite1_rom_d;

wire [7:0] prom_r_D, prom_g_D, prom_b_D, prom_unk_D;
assign prom_r_D = prom_r_d;
assign prom_g_D = prom_g_d;
assign prom_b_D = prom_b_d;
assign prom_unk_a = 8'd0;
assign prom_unk_D = prom_unk_d;

reg [7:0] fg_lb_0  [0:255];
reg [7:0] fg_lb_1  [0:255];
reg [7:0] bg0_lb_0 [0:255];
reg [7:0] bg0_lb_1 [0:255];
reg [7:0] bg1_lb_0 [0:255];
reg [7:0] bg1_lb_1 [0:255];
reg [7:0] spr_lb_0 [0:255];
reg [7:0] spr_lb_1 [0:255];

reg lb_page;

reg [4:0] rstate;
reg [8:0] rx;
reg [9:0] r_tile_num;
reg [5:0] r_color;
reg       r_flipx, r_flipy;
reg [7:0] r_byte_a, r_byte_b;
reg [7:0] r_scroll;
reg [2:0] r_layer;

// tear fix: rnext = v_cnt_rot (no +1), page flip at end of hblank; change all three together
wire [8:0] rnext     = v_cnt_rot;
wire [7:0] rline     = (8'd255 - rnext[7:0]);

function [1:0] pix2bpp;
    input [7:0] byt;
    input [1:0] x;
    begin
        pix2bpp = {byt[x+4], byt[x]};
    end
endfunction

localparam S_IDLE     = 5'd0;
localparam S_FG_CODE  = 5'd1,  S_FG_ATTR  = 5'd2,  S_FG_COL  = 5'd3;
localparam S_FG_ROMA  = 5'd4,  S_FG_ROMB  = 5'd5,  S_FG_DRAW = 5'd6;
localparam S_BG0_SCR  = 5'd7,  S_BG0_CODE = 5'd8,  S_BG0_ATTR = 5'd9,  S_BG0_COL = 5'd10;
localparam S_BG0_ROMA = 5'd11, S_BG0_ROMB = 5'd12, S_BG0_DRAW = 5'd13;
localparam S_BG1_SCR  = 5'd14, S_BG1_CODE = 5'd15, S_BG1_ATTR = 5'd16, S_BG1_COL = 5'd17;
localparam S_BG1_ROMA = 5'd18, S_BG1_ROMB = 5'd19, S_BG1_DRAW = 5'd20;
localparam S_SPR_INIT = 5'd21, S_SPR_RUN  = 5'd22;
localparam S_DONE     = 5'd23;

reg [4:0] spr_state;
reg [3:0] spr_idx;
reg [7:0] spr_y, spr_x, spr_code_raw, spr_attr_raw, spr_color_raw;
reg [7:0] spr_code;
reg [5:0] spr_color;
reg       spr_flipx, spr_flipy, spr_dbl;
reg [4:0] spr_next_state;
reg [4:0] spr_row;
reg [3:0] spr_col;
reg [7:0] spr_byte_a, spr_byte_b;
reg       spr_rom_half;
reg       spr_reading_b;

wire [4:0] rx_col = rx[7:3];
wire [2:0] rx_fine = rx[2:0];
reg wait_cycle;

always_ff @(posedge clk_49m) begin
	if (!reset) begin
		rstate <= S_IDLE;
		rx <= 0;
		wait_cycle <= 0;
	end else if (rstate == S_IDLE) begin
		wait_cycle <= 0;
		if (cen_pix && base_h_cnt == 9'd0 && v_cnt_rot >= 9'd15 && v_cnt_rot < 9'd241) begin
			rx <= 0;
			rstate <= S_FG_CODE;
		end
	end else if (wait_cycle) begin
		wait_cycle <= 0;
	end else begin
		if (rstate != S_FG_DRAW && rstate != S_BG0_DRAW && rstate != S_BG1_DRAW
		    && rstate != S_SPR_INIT && rstate != S_DONE && rstate != S_SPR_RUN)
			wait_cycle <= 1;
		case (rstate)

		S_FG_CODE: begin
			fg_raddr <= 12'hC00 + {2'b00, rline[7:3], rx_col};
			rstate <= S_FG_ATTR;
		end
		S_FG_ATTR: begin
			r_tile_num[7:0] <= fg_vram_rD;
			fg_raddr <= 12'h800 + {2'b00, rline[7:3], rx_col};
			rstate <= S_FG_COL;
		end
		S_FG_COL: begin
			r_tile_num[9:8] <= fg_vram_rD[1:0];
			r_flipy <= fg_vram_rD[2];
			r_flipx <= fg_vram_rD[3];
			fg_raddr <= 12'h400 + {2'b00, rline[7:3], rx_col};
			rstate <= S_FG_ROMA;
		end
		S_FG_ROMA: begin
			r_color <= fg_vram_rD[5:0];
			begin
				reg [2:0] fy;
				fy = r_flipy ? (3'd7 - rline[2:0]) : rline[2:0];
				fgtile_addr <= {r_tile_num[8:0], 1'b0, fy};
			end
			rstate <= S_FG_ROMB;
		end
		S_FG_ROMB: begin
			r_byte_a <= fgtile_D;
			begin
				reg [2:0] fy;
				fy = r_flipy ? (3'd7 - rline[2:0]) : rline[2:0];
				fgtile_addr <= {r_tile_num[8:0], 1'b1, fy};
			end
			rstate <= S_FG_DRAW;
		end
		S_FG_DRAW: begin
			begin
				reg [7:0] ba, bb;
				reg [1:0] pval;
				ba = r_byte_a;
				bb = fgtile_D;
				if (r_flipx) begin
					if (lb_page) begin
						fg_lb_1[rx+7] <= {r_color, ba[7], ba[3]};
						fg_lb_1[rx+6] <= {r_color, ba[6], ba[2]};
						fg_lb_1[rx+5] <= {r_color, ba[5], ba[1]};
						fg_lb_1[rx+4] <= {r_color, ba[4], ba[0]};
						fg_lb_1[rx+3] <= {r_color, bb[7], bb[3]};
						fg_lb_1[rx+2] <= {r_color, bb[6], bb[2]};
						fg_lb_1[rx+1] <= {r_color, bb[5], bb[1]};
						fg_lb_1[rx+0] <= {r_color, bb[4], bb[0]};
					end else begin
						fg_lb_0[rx+7] <= {r_color, ba[7], ba[3]};
						fg_lb_0[rx+6] <= {r_color, ba[6], ba[2]};
						fg_lb_0[rx+5] <= {r_color, ba[5], ba[1]};
						fg_lb_0[rx+4] <= {r_color, ba[4], ba[0]};
						fg_lb_0[rx+3] <= {r_color, bb[7], bb[3]};
						fg_lb_0[rx+2] <= {r_color, bb[6], bb[2]};
						fg_lb_0[rx+1] <= {r_color, bb[5], bb[1]};
						fg_lb_0[rx+0] <= {r_color, bb[4], bb[0]};
					end
				end else begin
					if (lb_page) begin
						fg_lb_1[rx+7] <= {r_color, bb[4], bb[0]};
						fg_lb_1[rx+6] <= {r_color, bb[5], bb[1]};
						fg_lb_1[rx+5] <= {r_color, bb[6], bb[2]};
						fg_lb_1[rx+4] <= {r_color, bb[7], bb[3]};
						fg_lb_1[rx+3] <= {r_color, ba[4], ba[0]};
						fg_lb_1[rx+2] <= {r_color, ba[5], ba[1]};
						fg_lb_1[rx+1] <= {r_color, ba[6], ba[2]};
						fg_lb_1[rx+0] <= {r_color, ba[7], ba[3]};
					end else begin
						fg_lb_0[rx+7] <= {r_color, bb[4], bb[0]};
						fg_lb_0[rx+6] <= {r_color, bb[5], bb[1]};
						fg_lb_0[rx+5] <= {r_color, bb[6], bb[2]};
						fg_lb_0[rx+4] <= {r_color, bb[7], bb[3]};
						fg_lb_0[rx+3] <= {r_color, ba[4], ba[0]};
						fg_lb_0[rx+2] <= {r_color, ba[5], ba[1]};
						fg_lb_0[rx+1] <= {r_color, ba[6], ba[2]};
						fg_lb_0[rx+0] <= {r_color, ba[7], ba[3]};
					end
				end
			end
			rx <= rx + 9'd8;
			if (rx == 9'd248) begin
				rx <= 0;
				rstate <= S_BG0_SCR;
			end else
				rstate <= S_FG_CODE;
		end

		S_BG0_SCR: begin
			fg_raddr <= 12'h7C0 + {7'd0, rx_col};
			rstate <= S_BG0_CODE;
		end
		S_BG0_CODE: begin
			r_scroll <= fg_vram_rD;
			begin
				reg [7:0] sy;
				sy = rline + fg_vram_rD;
				bg0_raddr <= {2'b10, sy[7:3], rx_col};
			end
			rstate <= S_BG0_ATTR;
		end
		S_BG0_ATTR: begin
			r_tile_num[7:0] <= bg0_vram_rD;
			begin
				reg [7:0] sy;
				sy = rline + r_scroll;
				bg0_raddr <= {2'b00, sy[7:3], rx_col};
			end
			rstate <= S_BG0_COL;
		end
		S_BG0_COL: begin
			r_tile_num[9:8] <= bg0_vram_rD[1:0];
			r_flipy <= bg0_vram_rD[2];
			r_flipx <= bg0_vram_rD[3];
			begin
				reg [7:0] sy;
				sy = rline + r_scroll;
				bg0_raddr <= {2'b11, sy[7:3], rx_col};
			end
			rstate <= S_BG0_ROMA;
		end
		S_BG0_ROMA: begin
			r_color <= bg0_vram_rD[5:0];
			begin
				reg [7:0] sy;
				reg [2:0] fy;
				sy = rline + r_scroll;
				fy = r_flipy ? (3'd7 - sy[2:0]) : sy[2:0];
				bgtile0_addr <= {r_tile_num[8:0], 1'b0, fy};
			end
			rstate <= S_BG0_ROMB;
		end
		S_BG0_ROMB: begin
			r_byte_a <= bgtile0_D;
			begin
				reg [7:0] sy;
				reg [2:0] fy;
				sy = rline + r_scroll;
				fy = r_flipy ? (3'd7 - sy[2:0]) : sy[2:0];
				bgtile0_addr <= {r_tile_num[8:0], 1'b1, fy};
			end
			rstate <= S_BG0_DRAW;
		end
		S_BG0_DRAW: begin
			begin
				reg [7:0] ba, bb;
				ba = r_byte_a;
				bb = bgtile0_D;
				if (r_flipx) begin
					if (lb_page) begin
						bg0_lb_1[rx+7] <= {r_color, ba[7], ba[3]};
						bg0_lb_1[rx+6] <= {r_color, ba[6], ba[2]};
						bg0_lb_1[rx+5] <= {r_color, ba[5], ba[1]};
						bg0_lb_1[rx+4] <= {r_color, ba[4], ba[0]};
						bg0_lb_1[rx+3] <= {r_color, bb[7], bb[3]};
						bg0_lb_1[rx+2] <= {r_color, bb[6], bb[2]};
						bg0_lb_1[rx+1] <= {r_color, bb[5], bb[1]};
						bg0_lb_1[rx+0] <= {r_color, bb[4], bb[0]};
					end else begin
						bg0_lb_0[rx+7] <= {r_color, ba[7], ba[3]};
						bg0_lb_0[rx+6] <= {r_color, ba[6], ba[2]};
						bg0_lb_0[rx+5] <= {r_color, ba[5], ba[1]};
						bg0_lb_0[rx+4] <= {r_color, ba[4], ba[0]};
						bg0_lb_0[rx+3] <= {r_color, bb[7], bb[3]};
						bg0_lb_0[rx+2] <= {r_color, bb[6], bb[2]};
						bg0_lb_0[rx+1] <= {r_color, bb[5], bb[1]};
						bg0_lb_0[rx+0] <= {r_color, bb[4], bb[0]};
					end
				end else begin
					if (lb_page) begin
						bg0_lb_1[rx+7] <= {r_color, bb[4], bb[0]};
						bg0_lb_1[rx+6] <= {r_color, bb[5], bb[1]};
						bg0_lb_1[rx+5] <= {r_color, bb[6], bb[2]};
						bg0_lb_1[rx+4] <= {r_color, bb[7], bb[3]};
						bg0_lb_1[rx+3] <= {r_color, ba[4], ba[0]};
						bg0_lb_1[rx+2] <= {r_color, ba[5], ba[1]};
						bg0_lb_1[rx+1] <= {r_color, ba[6], ba[2]};
						bg0_lb_1[rx+0] <= {r_color, ba[7], ba[3]};
					end else begin
						bg0_lb_0[rx+7] <= {r_color, bb[4], bb[0]};
						bg0_lb_0[rx+6] <= {r_color, bb[5], bb[1]};
						bg0_lb_0[rx+5] <= {r_color, bb[6], bb[2]};
						bg0_lb_0[rx+4] <= {r_color, bb[7], bb[3]};
						bg0_lb_0[rx+3] <= {r_color, ba[4], ba[0]};
						bg0_lb_0[rx+2] <= {r_color, ba[5], ba[1]};
						bg0_lb_0[rx+1] <= {r_color, ba[6], ba[2]};
						bg0_lb_0[rx+0] <= {r_color, ba[7], ba[3]};
					end
				end
			end
			rx <= rx + 9'd8;
			if (rx == 9'd248) begin
				rx <= 0;
				rstate <= S_BG1_SCR;
			end else
				rstate <= S_BG0_SCR;
		end

		S_BG1_SCR: begin
			fg_raddr <= 12'h7E0 + {7'd0, rx_col};
			rstate <= S_BG1_CODE;
		end
		S_BG1_CODE: begin
			r_scroll <= fg_vram_rD;
			begin
				reg [7:0] sy;
				sy = rline + fg_vram_rD;
				bg1_raddr <= {2'b10, sy[7:3], rx_col};
			end
			rstate <= S_BG1_ATTR;
		end
		S_BG1_ATTR: begin
			r_tile_num[7:0] <= bg1_vram_rD;
			begin
				reg [7:0] sy;
				sy = rline + r_scroll;
				bg1_raddr <= {2'b00, sy[7:3], rx_col};
			end
			rstate <= S_BG1_COL;
		end
		S_BG1_COL: begin
			r_tile_num[9:8] <= bg1_vram_rD[1:0];
			r_flipy <= bg1_vram_rD[2];
			r_flipx <= bg1_vram_rD[3];
			begin
				reg [7:0] sy;
				sy = rline + r_scroll;
				bg1_raddr <= {2'b11, sy[7:3], rx_col};
			end
			rstate <= S_BG1_ROMA;
		end
		S_BG1_ROMA: begin
			r_color <= bg1_vram_rD[5:0];
			begin
				reg [7:0] sy;
				reg [2:0] fy;
				sy = rline + r_scroll;
				fy = r_flipy ? (3'd7 - sy[2:0]) : sy[2:0];
				bgtile1_addr <= {r_tile_num[8:0], 1'b0, fy};
			end
			rstate <= S_BG1_ROMB;
		end
		S_BG1_ROMB: begin
			r_byte_a <= bgtile1_D;
			begin
				reg [7:0] sy;
				reg [2:0] fy;
				sy = rline + r_scroll;
				fy = r_flipy ? (3'd7 - sy[2:0]) : sy[2:0];
				bgtile1_addr <= {r_tile_num[8:0], 1'b1, fy};
			end
			rstate <= S_BG1_DRAW;
		end
		S_BG1_DRAW: begin
			begin
				reg [7:0] ba, bb;
				ba = r_byte_a;
				bb = bgtile1_D;
				if (r_flipx) begin
					if (lb_page) begin
						bg1_lb_1[rx+7] <= {r_color, ba[7], ba[3]};
						bg1_lb_1[rx+6] <= {r_color, ba[6], ba[2]};
						bg1_lb_1[rx+5] <= {r_color, ba[5], ba[1]};
						bg1_lb_1[rx+4] <= {r_color, ba[4], ba[0]};
						bg1_lb_1[rx+3] <= {r_color, bb[7], bb[3]};
						bg1_lb_1[rx+2] <= {r_color, bb[6], bb[2]};
						bg1_lb_1[rx+1] <= {r_color, bb[5], bb[1]};
						bg1_lb_1[rx+0] <= {r_color, bb[4], bb[0]};
					end else begin
						bg1_lb_0[rx+7] <= {r_color, ba[7], ba[3]};
						bg1_lb_0[rx+6] <= {r_color, ba[6], ba[2]};
						bg1_lb_0[rx+5] <= {r_color, ba[5], ba[1]};
						bg1_lb_0[rx+4] <= {r_color, ba[4], ba[0]};
						bg1_lb_0[rx+3] <= {r_color, bb[7], bb[3]};
						bg1_lb_0[rx+2] <= {r_color, bb[6], bb[2]};
						bg1_lb_0[rx+1] <= {r_color, bb[5], bb[1]};
						bg1_lb_0[rx+0] <= {r_color, bb[4], bb[0]};
					end
				end else begin
					if (lb_page) begin
						bg1_lb_1[rx+7] <= {r_color, bb[4], bb[0]};
						bg1_lb_1[rx+6] <= {r_color, bb[5], bb[1]};
						bg1_lb_1[rx+5] <= {r_color, bb[6], bb[2]};
						bg1_lb_1[rx+4] <= {r_color, bb[7], bb[3]};
						bg1_lb_1[rx+3] <= {r_color, ba[4], ba[0]};
						bg1_lb_1[rx+2] <= {r_color, ba[5], ba[1]};
						bg1_lb_1[rx+1] <= {r_color, ba[6], ba[2]};
						bg1_lb_1[rx+0] <= {r_color, ba[7], ba[3]};
					end else begin
						bg1_lb_0[rx+7] <= {r_color, bb[4], bb[0]};
						bg1_lb_0[rx+6] <= {r_color, bb[5], bb[1]};
						bg1_lb_0[rx+5] <= {r_color, bb[6], bb[2]};
						bg1_lb_0[rx+4] <= {r_color, bb[7], bb[3]};
						bg1_lb_0[rx+3] <= {r_color, ba[4], ba[0]};
						bg1_lb_0[rx+2] <= {r_color, ba[5], ba[1]};
						bg1_lb_0[rx+1] <= {r_color, ba[6], ba[2]};
						bg1_lb_0[rx+0] <= {r_color, ba[7], ba[3]};
					end
				end
			end
			rx <= rx + 9'd8;
			if (rx == 9'd248) begin
				rx <= 0;
				rstate <= S_SPR_INIT;
			end else
				rstate <= S_BG1_SCR;
		end

		S_SPR_INIT: begin
			if (lb_page) begin
				for (integer i = 0; i < 256; i = i + 1) spr_lb_1[i] <= 8'd0;
			end else begin
				for (integer i = 0; i < 256; i = i + 1) spr_lb_0[i] <= 8'd0;
			end
			spr_idx <= 0;
			spr_state <= 0;
			rstate <= S_SPR_RUN;
		end

		S_SPR_RUN: begin
			case (spr_state)
			5'd0: begin
				begin
					reg [11:0] rambase;
					rambase = (spr_idx < 8) ? 12'h430 : 12'h410;
					fg_raddr <= rambase + {8'd0, spr_idx[2:0], 1'b0};
				end
			    spr_next_state <= 1;
			    spr_state <= 11;
			end
			5'd1: begin
				spr_y <= fg_vram_rD;
				begin
					reg [11:0] rambase;
					rambase = (spr_idx < 8) ? 12'h430 : 12'h410;
					fg_raddr <= rambase + {8'd0, spr_idx[2:0], 1'b1};
				end
				spr_next_state <= 2;
				spr_state <= 11;
			end
			5'd2: begin
				spr_color <= fg_vram_rD[5:0];
				begin
					reg [11:0] rambase;
					rambase = (spr_idx < 8) ? 12'h430 : 12'h410;
					fg_raddr <= rambase + 12'h400 + {8'd0, spr_idx[2:0], 1'b0};
				end
				spr_next_state <= 3;
				spr_state <= 11;
			end
			5'd3: begin
				spr_attr_raw <= fg_vram_rD;
				begin
					reg [11:0] rambase;
					rambase = (spr_idx < 8) ? 12'h430 : 12'h410;
					fg_raddr <= rambase + 12'h800 + {8'd0, spr_idx[2:0], 1'b0};
				end
				spr_next_state <= 4;
				spr_state <= 11;
			end
			5'd4: begin
				spr_code_raw <= fg_vram_rD;
				begin
					reg [11:0] rambase;
					rambase = (spr_idx < 8) ? 12'h430 : 12'h410;
					fg_raddr <= rambase + 12'h800 + {8'd0, spr_idx[2:0], 1'b1};
				end
				spr_next_state <= 5;
				spr_state <= 11;
			end
			5'd5: begin
				spr_x <= fg_vram_rD;
				begin
					reg [7:0] code;
					reg [7:0] tilebase;
					tilebase = (spr_idx < 8) ? 8'd128 : 8'd0;
					code = {spr_attr_raw[0], spr_code_raw[7:2]} + tilebase;
					spr_code <= code;
					spr_flipy <= spr_code_raw[0] ^ game_flip;
					spr_flipx <= spr_code_raw[1] ^ game_flip;
					spr_dbl <= spr_attr_raw[3];
				end
				spr_state <= 6;
			end
			5'd6: begin
				begin
					reg [7:0] sy, sprite_height;
					reg [8:0] local_y;
					sy = game_flip ? spr_y : (spr_dbl ? (8'd224 - spr_y) : (8'd240 - spr_y));
					sprite_height = spr_dbl ? 8'd32 : 8'd16;
					local_y = {1'b0, rline} - {1'b0, sy};
					if (local_y[8:0] < {1'b0, sprite_height}) begin
						spr_row <= local_y[4:0];
						spr_col <= 0;
						spr_reading_b <= 0;
						spr_state <= 7;
					end else begin
						if (spr_idx == 4'd15) rstate <= S_DONE;
						else begin spr_idx <= spr_idx + 1; spr_state <= 0; end
					end
				end
			end
			5'd7: begin
				begin
					reg [13:0] base;
					reg [4:0] erow;
					reg [3:0] quarter;
					erow = spr_flipy ? ((spr_dbl ? 5'd31 : 5'd15) - spr_row) : spr_row;
					if (spr_dbl)
						base = {spr_code[7:1], 7'd0};
					else
						base = {spr_code, 6'd0};
					quarter = spr_flipx ? (2'd3 - spr_col[3:2]) : spr_col[3:2];
					begin
						reg [6:0] row_base;
						reg [13:0] full_addr;
						if (spr_dbl) begin
							row_base = {erow[4:3], 2'b00, erow[2:0]};
						end else begin
							row_base = erow[3] ? (7'd32 + {4'd0, erow[2:0]}) : {4'd0, erow[2:0]};
						end
						full_addr = base + {7'd0, row_base} + {10'd0, quarter, 3'b000};
						sprite_addr <= full_addr[12:0];
						spr_rom_half <= full_addr[13];
					end
				end
				spr_state <= 10;
			end
			5'd8: begin
				spr_byte_a <= spr_rom_half ? sprite1_D : sprite0_D;
				spr_state <= 9;
			end
			5'd9: begin
				begin
					reg [1:0] pval;
					reg [2:0] bx;
					reg [7:0] xpos;
					bx = spr_flipx ? spr_col[1:0] : (3'd3 - spr_col[1:0]);
					pval = {spr_byte_a[bx + 4], spr_byte_a[bx]};
					xpos = rot_flip ? ((8'd240 - spr_x) + {4'd0, spr_col}) : (spr_x + {4'd0, spr_col});
					if (lb_page) begin
						if (pval != 2'd0 && spr_lb_1[xpos] == 8'd0)
							spr_lb_1[xpos] <= {spr_color, pval};
					end else begin
						if (pval != 2'd0 && spr_lb_0[xpos] == 8'd0)
							spr_lb_0[xpos] <= {spr_color, pval};
					end
				end
				if (spr_col == 4'd15) begin
					if (spr_idx == 4'd15) rstate <= S_DONE;
					else begin spr_idx <= spr_idx + 1; spr_state <= 0; end
				end else begin
					spr_col <= spr_col + 1;
					if (spr_col[1:0] == 2'd3) spr_state <= 7;
				end
			end
			5'd10: begin
				spr_state <= 8;
			end
			5'd11: begin
				spr_state <= spr_next_state;
			end
			default: spr_state <= 0;
			endcase
		end

		S_DONE: begin
			rstate <= S_IDLE;
		end

		default: rstate <= S_IDLE;
		endcase
	end
end

// part of the tear-fix triple (rnext / rline): do not change alone
always_ff @(posedge clk_49m) begin
	if (!reset) begin
		lb_page <= 1'b0;
	end else if (cen_pix && base_h_cnt == 9'd383 && v_cnt_rot >= 9'd15 && v_cnt_rot < 9'd241) begin
		lb_page <= ~lb_page;
	end
end

wire [7:0] disp_x = 8'd255 - h_cnt_rot[7:0];
wire [7:0] fg_pix  = lb_page ? fg_lb_0[disp_x]  : fg_lb_1[disp_x];
wire [7:0] bg0_pix = lb_page ? bg0_lb_0[disp_x] : bg0_lb_1[disp_x];
wire [7:0] bg1_pix = lb_page ? bg1_lb_0[disp_x] : bg1_lb_1[disp_x];
wire [7:0] spr_pix = lb_page ? spr_lb_0[disp_x] : spr_lb_1[disp_x];

wire fg_opaque  = (fg_pix[1:0]  != 2'd0);
wire bg0_opaque = (bg0_pix[1:0] != 2'd0);
wire bg1_opaque = (bg1_pix[1:0] != 2'd0);
wire spr_opaque = (spr_pix[1:0] != 2'd0);

reg [7:0] final_pixel;
always_comb begin
	case (priority_mode)
	3'd0: begin
		if (fg_opaque)       final_pixel = fg_pix;
		else if (bg1_opaque) final_pixel = bg1_pix;
		else if (spr_opaque) final_pixel = spr_pix;
		else                 final_pixel = bg0_pix;
	end
	3'd1: begin
		if (fg_opaque)       final_pixel = fg_pix;
		else if (spr_opaque) final_pixel = spr_pix;
		else if (bg1_opaque) final_pixel = bg1_pix;
		else                 final_pixel = bg0_pix;
	end
	3'd2: begin
		if (fg_opaque)       final_pixel = fg_pix;
		else if (bg1_opaque) final_pixel = bg1_pix;
		else if (bg0_opaque) final_pixel = bg0_pix;
		else if (spr_opaque) final_pixel = spr_pix;
		else                 final_pixel = bg0_pix;
	end
	3'd3: begin
		if (spr_opaque)      final_pixel = spr_pix;
		else if (fg_opaque)  final_pixel = fg_pix;
		else if (bg1_opaque) final_pixel = bg1_pix;
		else                 final_pixel = bg0_pix;
	end
	3'd4: begin
		if (bg1_opaque)      final_pixel = bg1_pix;
		else if (bg0_opaque) final_pixel = bg0_pix;
		else if (spr_opaque) final_pixel = spr_pix;
		else                 final_pixel = fg_pix;
	end
	default: final_pixel = bg0_pix;
	endcase
end

wire [7:0] prom_addr = (hblk | vblk) ? 8'd0 : final_pixel;

assign red   = ovg ? ovg_r : {prom_r_D[3:0], prom_r_D[3]};
assign green = ovg ? ovg_g : {prom_g_D[3:0], prom_g_D[3]};
assign blue  = ovg ? ovg_b : {prom_b_D[3:0], prom_b_D[3]};

Vastar_OVG40C ovg_pcb
(
	.clk_49m(clk_49m),
	.reset(reset),
	.cpu_A(cpu1_A),
	.cpu_Dout(cpu1_Dout),
	.cpu_mem_valid(cpu1_mem_valid & ovg),
	.cpu_wr(~cpu1_WR_n),
	.cs(ovg_cs),
	.cpu_Din(ovg_D),
	.render_start(ovg && cen_pix && base_h_cnt == 9'd0 && v_cnt_rot >= 9'd15 && v_cnt_rot < 9'd241),
	.rline(horz ? 8'd255 - v_cnt_rot[7:0] : v_cnt_rot[7:0]),
	.lb_page(lb_page),
	.disp_x(horz ? 8'd255 - h_cnt_rot[7:0] : h_cnt_rot[7:0]),
	.blank(hblk | vblk),
	.flip(zod ? ~z_flip_d : ~mainlatch[1]),
	.percuss(~zod | percuss),
	.red(ovg_r),
	.green(ovg_g),
	.blue(ovg_b),
	.gfx_rom_a(ovg_gfx_a), .gfx_rom_d(ovg_gfx_d), .prom_a(ovg_prom_a), .prom_d(ovg_prom_d),
	.obj_i(ovg_pr_i[0]), .fg_i(ovg_pr_i[1]), .bg_i(ovg_pr_i[2]), .lb_i(pr_i[6]),
	.obj_o(pr_o[0]), .fg_o(pr_o[1]), .bg_o(pr_o[2]), .lb_o(pr_o[6])
);

assign prom_a = prom_addr;
assign z80_i[0].reset_n = reset; assign z80_i[0].ce = cen_cpu & ~pause; assign z80_i[0].int_n = ~z_irq; assign z80_i[0].nmi_n = ~cpu1_nmi;
assign z80_i[0].di = cpu1_Din;
assign z80_i[1].reset_n = reset & ~cpu2_rst; assign z80_i[1].ce = cen_cpu & ~pause; assign z80_i[1].int_n = ~(zod ? z_pend : cpu2_irq); assign z80_i[1].nmi_n = ~z_snmi;
assign z80_i[1].di = cpu2_Din;

endmodule
