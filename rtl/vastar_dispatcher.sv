//============================================================================
//
//  Vastar dispatcher: ROM load map, shared CPU / sound chip / ROM / RAM pools, and the board
//  (rtl/boards/vastar/Vastar_CPU.sv, carrying the Zodiack CPU / audio logic and the Orca OVG-40c video board)
//  Copyright (C) 2026 Rodimus
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module vastar_dispatcher
(
	input                reset,
	input                clk_49m,

	input          [7:0] p1_controls,
	input          [7:0] p2_controls,
	input          [7:0] sys_controls,

	input         [15:0] dip_sw,

    input                rot_flip,
	input                ovg,
	input                zod,
	input          [7:0] zin0, zin1,
	input          [7:0] zin2,
	input                percuss,
	input                horz,
	input                crt_flip,

	output               video_hsync, video_vsync, video_csync,
	output               video_hblank, video_vblank,
	output               ce_pix,
	output         [4:0] video_r, video_g, video_b,

	output signed [15:0] sound,

	input          [3:0] h_center, v_center,

	input         [24:0] ioctl_addr,
	input          [7:0] ioctl_data,
	input                ioctl_wr,
	input          [7:0] ioctl_index,

	input                pause,

	input         [15:0] hs_address,
	input          [7:0] hs_data_in,
	output         [7:0] hs_data_out,
	input                hs_write
);

wire main_rom_cs_i, sub_rom_cs_i, fgtile_cs_i;
wire sprite0_cs_i, sprite1_cs_i;
wire bgtile0_cs_i, bgtile1_cs_i;
wire prom_r_cs_i, prom_g_cs_i, prom_b_cs_i, prom_unk_cs_i;
wire ovg_gfx_cs_i, ovg_prom_cs_i;

wire ioctl_wr_cpu = ioctl_wr && (ioctl_index == 8'd0);

selector DLSEL
(
	.ioctl_addr(ioctl_addr),
	.main_rom_cs(main_rom_cs_i),
	.sub_rom_cs(sub_rom_cs_i),
	.fgtile_cs(fgtile_cs_i),
	.sprite0_cs(sprite0_cs_i),
	.sprite1_cs(sprite1_cs_i),
	.bgtile0_cs(bgtile0_cs_i),
	.bgtile1_cs(bgtile1_cs_i),
	.prom_r_cs(prom_r_cs_i),
	.prom_g_cs(prom_g_cs_i),
	.prom_b_cs(prom_b_cs_i),
	.prom_unk_cs(prom_unk_cs_i),
	.ovg_gfx_cs(ovg_gfx_cs_i),
	.ovg_prom_cs(ovg_prom_cs_i)
);

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// z80_0: main CPU (Vastar CPU board, Zodiack CPU board); z80_1: sub CPU (Vastar) / audio CPU (Zodiack). Both must stay
chip_pool_pkg::z80r_i_t [1:0] z80_i;
chip_pool_pkg::z80r_o_t [1:0] z80_o;

wire [15:0] z80_0_a, z80_1_a;
wire  [7:0] z80_0_do, z80_1_do;
wire        z80_0_m1_n, z80_0_mreq_n, z80_0_iorq_n, z80_0_rd_n, z80_0_wr_n, z80_0_rfsh_n;
wire        z80_1_m1_n, z80_1_mreq_n, z80_1_iorq_n, z80_1_rd_n, z80_1_wr_n, z80_1_rfsh_n;

t80sv_T80s z80_0
(
	.RESET_n(z80_i[0].reset_n), .CLK(clk_49m), .CEN(z80_i[0].ce), .WAIT_n(1'b1), .BUSRQ_n(1'b1), .OUT0(1'b0),
	.INT_n(z80_i[0].int_n), .NMI_n(z80_i[0].nmi_n),
	.M1_n(z80_0_m1_n), .MREQ_n(z80_0_mreq_n), .IORQ_n(z80_0_iorq_n),
	.RD_n(z80_0_rd_n), .WR_n(z80_0_wr_n), .RFSH_n(z80_0_rfsh_n),
	.A(z80_0_a), .DI(z80_i[0].di), .DO(z80_0_do)
);
assign z80_o[0].a = z80_0_a;         assign z80_o[0].dout = z80_0_do;
assign z80_o[0].m1_n = z80_0_m1_n;   assign z80_o[0].mreq_n = z80_0_mreq_n; assign z80_o[0].iorq_n = z80_0_iorq_n;
assign z80_o[0].rd_n = z80_0_rd_n;   assign z80_o[0].wr_n = z80_0_wr_n;     assign z80_o[0].rfsh_n = z80_0_rfsh_n;

t80sv_T80s z80_1
(
	.RESET_n(z80_i[1].reset_n), .CLK(clk_49m), .CEN(z80_i[1].ce), .WAIT_n(1'b1), .BUSRQ_n(1'b1), .OUT0(1'b0),
	.INT_n(z80_i[1].int_n), .NMI_n(z80_i[1].nmi_n),
	.M1_n(z80_1_m1_n), .MREQ_n(z80_1_mreq_n), .IORQ_n(z80_1_iorq_n),
	.RD_n(z80_1_rd_n), .WR_n(z80_1_wr_n), .RFSH_n(z80_1_rfsh_n),
	.A(z80_1_a), .DI(z80_i[1].di), .DO(z80_1_do)
);
assign z80_o[1].a = z80_1_a;         assign z80_o[1].dout = z80_1_do;
assign z80_o[1].m1_n = z80_1_m1_n;   assign z80_o[1].mreq_n = z80_1_mreq_n; assign z80_o[1].iorq_n = z80_1_iorq_n;
assign z80_o[1].rd_n = z80_1_rd_n;   assign z80_o[1].wr_n = z80_1_wr_n;     assign z80_o[1].rfsh_n = z80_1_rfsh_n;

chip_pool_pkg::ayr_i_t  ay_0_i;
chip_pool_pkg::ayio_o_t ay_0_o;

jt49_bus ay_0
(
	.rst_n(ay_0_i.rst_n), .clk(clk_49m), .clk_en(ay_0_i.ce), .bdir(ay_0_i.bdir), .bc1(ay_0_i.bc1),
	.din(ay_0_i.din), .dout(ay_0_o.dout), .sel(1'b1),
	.sound(ay_0_o.sound), .sample(), .A(ay_0_o.a), .B(ay_0_o.b), .C(ay_0_o.c),
	.IOA_in(ay_0_i.ioa_in), .IOB_in(ay_0_i.iob_in), .IOA_out(ay_0_o.ioa_out), .IOB_out(ay_0_o.iob_out)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire [14:0] main_rom_a;
wire [12:0] sub_rom_a, fgtile_rom_a, bgtile0_rom_a, bgtile1_rom_a, sprite_rom_a;
wire  [7:0] prom_a, prom_unk_a;
wire [13:0] ovg_gfx_a;
wire  [5:0] ovg_prom_a;
wire  [7:0] main_rom_d, sub_rom_d, fgtile_rom_d, bgtile0_rom_d, bgtile1_rom_d, sprite0_rom_d, sprite1_rom_d;
wire  [7:0] prom_r_d, prom_g_d, prom_b_d, prom_unk_d, ovg_gfx_d, ovg_prom_d;

eprom_32k main_rom (.CLK(clk_49m), .ADDR(main_rom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(main_rom_d));
eprom_8k sub_rom (.CLK(clk_49m), .ADDR(sub_rom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(sub_rom_cs_i), .WR(ioctl_wr_cpu), .DATA(sub_rom_d));
eprom_8k fgtile_rom (.CLK(clk_49m), .ADDR(fgtile_rom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(fgtile_cs_i), .WR(ioctl_wr_cpu), .DATA(fgtile_rom_d));
eprom_8k bgtile_rom0 (.CLK(clk_49m), .ADDR(bgtile0_rom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(bgtile1_cs_i), .WR(ioctl_wr_cpu), .DATA(bgtile0_rom_d));
eprom_8k bgtile_rom1 (.CLK(clk_49m), .ADDR(bgtile1_rom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(bgtile0_cs_i), .WR(ioctl_wr_cpu), .DATA(bgtile1_rom_d));
eprom_8k sprite_rom0 (.CLK(clk_49m), .ADDR(sprite_rom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(sprite0_cs_i), .WR(ioctl_wr_cpu), .DATA(sprite0_rom_d));
eprom_8k sprite_rom1 (.CLK(clk_49m), .ADDR(sprite_rom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(sprite1_cs_i), .WR(ioctl_wr_cpu), .DATA(sprite1_rom_d));
eprom_256b prom_r_rom (.CLK(clk_49m), .ADDR(prom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_r_cs_i), .WR(ioctl_wr_cpu), .DATA(prom_r_d));
eprom_256b prom_g_rom (.CLK(clk_49m), .ADDR(prom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_g_cs_i), .WR(ioctl_wr_cpu), .DATA(prom_g_d));
eprom_256b prom_b_rom (.CLK(clk_49m), .ADDR(prom_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_b_cs_i), .WR(ioctl_wr_cpu), .DATA(prom_b_d));
eprom_256b prom_unk_rom (.CLK(clk_49m), .ADDR(prom_unk_a), .CLK_DL(clk_49m),
	.ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(prom_unk_cs_i), .WR(ioctl_wr_cpu), .DATA(prom_unk_d));

dpram_dc #(.widthad_a(14)) ovg_gfx_rom (
	.clock_a(clk_49m), .address_a(ioctl_addr[13:0] - 14'h0400), .data_a(ioctl_data), .wren_a(ioctl_wr_cpu & ovg_gfx_cs_i),
	.clock_b(clk_49m), .address_b(ovg_gfx_a), .q_b(ovg_gfx_d));

reg [7:0] ovg_prom[64];
always @(posedge clk_49m) if (ioctl_wr_cpu & ovg_prom_cs_i) ovg_prom[ioctl_addr[5:0]] <= ioctl_data;
assign ovg_prom_d = ovg_prom[ovg_prom_a];

/////////////////////////////  Board RAM pool  /////////////////////////////
//   pr 0  4K   Vastar bg1 video RAM 8000 / A000          | OVG-40c obj RAM 9000 (1K)
//   pr 1  4K   Vastar bg0 video RAM 9000 / B000          | OVG-40c fg RAM A000 (1K)
//   pr 2  4K   Vastar fg video RAM C400-CFFF             | OVG-40c bg RAM B000 (1K)
//   pr 3  2K   CPU-shared RAM F000 / 4000 (+ hiscore)    | Zodiack main RAM 5800
//   pr 4  256  hiscore copy of the score bank
//   pr 5  1K   Zodiack audio RAM 2000
//   pr 6  512  OVG-40c line buffer (two pages)
ram_pool_pkg::pram_i_t [6:0] pr_i;
ram_pool_pkg::pram_o_t [6:0] pr_o;

dpram_dc #(.widthad_a(12)) pr_0 (
	.clock_a(clk_49m), .address_a(pr_i[0].a_addr[11:0]), .data_a(pr_i[0].a_d), .wren_a(pr_i[0].a_we), .q_a(pr_o[0].a_q),
	.clock_b(clk_49m), .address_b(pr_i[0].b_addr[11:0]), .data_b(pr_i[0].b_d), .wren_b(pr_i[0].b_we), .q_b(pr_o[0].b_q));
dpram_dc #(.widthad_a(12)) pr_1 (
	.clock_a(clk_49m), .address_a(pr_i[1].a_addr[11:0]), .data_a(pr_i[1].a_d), .wren_a(pr_i[1].a_we), .q_a(pr_o[1].a_q),
	.clock_b(clk_49m), .address_b(pr_i[1].b_addr[11:0]), .data_b(pr_i[1].b_d), .wren_b(pr_i[1].b_we), .q_b(pr_o[1].b_q));
dpram_dc #(.widthad_a(12)) pr_2 (
	.clock_a(clk_49m), .address_a(pr_i[2].a_addr[11:0]), .data_a(pr_i[2].a_d), .wren_a(pr_i[2].a_we), .q_a(pr_o[2].a_q),
	.clock_b(clk_49m), .address_b(pr_i[2].b_addr[11:0]), .data_b(pr_i[2].b_d), .wren_b(pr_i[2].b_we), .q_b(pr_o[2].b_q));
dpram_dc #(.widthad_a(11)) pr_3 (
	.clock_a(clk_49m), .address_a(pr_i[3].a_addr[10:0]), .data_a(pr_i[3].a_d), .wren_a(pr_i[3].a_we), .q_a(pr_o[3].a_q),
	.clock_b(clk_49m), .address_b(pr_i[3].b_addr[10:0]), .data_b(pr_i[3].b_d), .wren_b(pr_i[3].b_we), .q_b(pr_o[3].b_q));
dpram_dc #(.widthad_a(8)) pr_4 (
	.clock_a(clk_49m), .address_a(pr_i[4].a_addr[7:0]), .data_a(pr_i[4].a_d), .wren_a(pr_i[4].a_we), .q_a(pr_o[4].a_q),
	.clock_b(clk_49m), .address_b(pr_i[4].b_addr[7:0]), .data_b(pr_i[4].b_d), .wren_b(pr_i[4].b_we), .q_b(pr_o[4].b_q));
dpram_dc #(.widthad_a(10)) pr_5 (
	.clock_a(clk_49m), .address_a(pr_i[5].a_addr[9:0]), .data_a(pr_i[5].a_d), .wren_a(pr_i[5].a_we), .q_a(pr_o[5].a_q),
	.clock_b(clk_49m), .address_b(pr_i[5].b_addr[9:0]), .data_b(pr_i[5].b_d), .wren_b(pr_i[5].b_we), .q_b(pr_o[5].b_q));
dpram_dc #(.widthad_a(9)) pr_6 (
	.clock_a(clk_49m), .address_a(pr_i[6].a_addr[8:0]), .data_a(pr_i[6].a_d), .wren_a(pr_i[6].a_we), .q_a(pr_o[6].a_q),
	.clock_b(clk_49m), .address_b(pr_i[6].b_addr[8:0]), .data_b(pr_i[6].b_d), .wren_b(pr_i[6].b_we), .q_b(pr_o[6].b_q));

/////////////////////////////  Board  /////////////////////////////

Vastar_CPU main_pcb
(
	.reset(reset),
	.clk_49m(clk_49m),

	.red(video_r),
	.green(video_g),
	.blue(video_b),
	.video_hsync(video_hsync),
	.video_vsync(video_vsync),
	.video_csync(video_csync),
	.video_hblank(video_hblank),
	.video_vblank(video_vblank),
	.ce_pix(ce_pix),

	.p1_controls(p1_controls),
	.p2_controls(p2_controls),
	.sys_controls(sys_controls),

	.dip_sw(dip_sw),

    .rot_flip(rot_flip),
	.ovg(ovg),
	.zod(zod),
	.zin0(zin0),
	.zin1(zin1),
	.zin2(zin2),
	.percuss(percuss),
	.horz(horz),
	.crt_flip(crt_flip),

	.sound(sound),

	.h_center(h_center),
	.v_center(v_center),

	.pause(pause),

	.hs_address(hs_address),
	.hs_data_out(hs_data_out),
	.hs_data_in(hs_data_in),
	.hs_write(hs_write),

	.z80_i(z80_i), .z80_o(z80_o), .ay_0_i(ay_0_i), .ay_0_o(ay_0_o),
	.main_rom_a(main_rom_a), .main_rom_d(main_rom_d), .sub_rom_a(sub_rom_a), .sub_rom_d(sub_rom_d),
	.fgtile_rom_a(fgtile_rom_a), .fgtile_rom_d(fgtile_rom_d), .bgtile0_rom_a(bgtile0_rom_a), .bgtile0_rom_d(bgtile0_rom_d),
	.bgtile1_rom_a(bgtile1_rom_a), .bgtile1_rom_d(bgtile1_rom_d), .sprite_rom_a(sprite_rom_a),
	.sprite0_rom_d(sprite0_rom_d), .sprite1_rom_d(sprite1_rom_d), .prom_a(prom_a), .prom_r_d(prom_r_d),
	.prom_g_d(prom_g_d), .prom_b_d(prom_b_d), .prom_unk_a(prom_unk_a), .prom_unk_d(prom_unk_d), .ovg_gfx_a(ovg_gfx_a), .ovg_gfx_d(ovg_gfx_d),
	.ovg_prom_a(ovg_prom_a), .ovg_prom_d(ovg_prom_d),
	.pr_i(pr_i), .pr_o(pr_o)
);

endmodule
