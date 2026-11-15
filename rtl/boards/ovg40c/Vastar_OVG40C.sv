// Based on MAME orca40c.cpp, zodiack.cpp, vastar.cpp (Zsolt Vasvari, Allard van der Bas, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module Vastar_OVG40C
(
	input         clk_49m,
	input         reset,

	input  [15:0] cpu_A,
	input   [7:0] cpu_Dout,
	input         cpu_mem_valid,
	input         cpu_wr,
	output        cs,
	output  [7:0] cpu_Din,

	input         render_start,
	input   [7:0] rline,
	input         lb_page,
	input   [7:0] disp_x,
	input         blank,
	input         flip,
	input         percuss,

	output [13:0] gfx_rom_a,
	input   [7:0] gfx_rom_d,
	output  [5:0] prom_a,
	input   [7:0] prom_d,

	output ram_pool_pkg::pram_i_t obj_i, fg_i, bg_i, lb_i,
	input  ram_pool_pkg::pram_o_t obj_o, fg_o, bg_o, lb_o,

	output  [4:0] red, green, blue
);

wire cs_obj = cpu_mem_valid & (cpu_A[15:10] == 6'b100100);
wire cs_fg  = cpu_mem_valid & (cpu_A[15:10] == 6'b101000);
wire cs_bg  = cpu_mem_valid & (cpu_A[15:10] == 6'b101100);
assign cs = cs_obj | cs_fg | cs_bg;

reg  [9:0] obj_raddr, fg_raddr, bg_raddr;
wire [7:0] obj_q, fg_q, bg_q, obj_cq, fg_cq, bg_cq;

assign obj_i.a_addr = {6'd0, cpu_A[9:0]}; assign obj_i.a_d = cpu_Dout; assign obj_i.a_we = cs_obj & cpu_wr;
assign obj_i.b_addr = {6'd0, obj_raddr}; assign obj_i.b_d = 8'd0; assign obj_i.b_we = 1'b0;
assign obj_cq = obj_o.a_q;
assign obj_q = obj_o.b_q;

assign fg_i.a_addr = {6'd0, cpu_A[9:0]}; assign fg_i.a_d = cpu_Dout; assign fg_i.a_we = cs_fg & cpu_wr;
assign fg_i.b_addr = {6'd0, fg_raddr}; assign fg_i.b_d = 8'd0; assign fg_i.b_we = 1'b0;
assign fg_cq = fg_o.a_q;
assign fg_q = fg_o.b_q;

assign bg_i.a_addr = {6'd0, cpu_A[9:0]}; assign bg_i.a_d = cpu_Dout; assign bg_i.a_we = cs_bg & cpu_wr;
assign bg_i.b_addr = {6'd0, bg_raddr}; assign bg_i.b_d = 8'd0; assign bg_i.b_we = 1'b0;
assign bg_cq = bg_o.a_q;
assign bg_q = bg_o.b_q;

assign cpu_Din = cs_obj ? obj_cq : cs_fg ? fg_cq : bg_cq;

reg  [13:0] gfx_addr;
wire  [7:0] gfx_q;
assign gfx_rom_a = gfx_addr;
assign gfx_q = gfx_rom_d;

reg  [7:0] lb_waddr;
reg  [7:0] lb_wdata;
reg        lb_we = 1'b0;
wire [7:0] lb_q;
assign lb_i.a_addr = {7'd0, {lb_page, lb_waddr}}; assign lb_i.a_d = lb_wdata; assign lb_i.a_we = lb_we;
assign lb_i.b_addr = {7'd0, {~lb_page, disp_x}}; assign lb_i.b_d = 8'd0; assign lb_i.b_we = 1'b0;
assign lb_q = lb_o.b_q;

wire [7:0] tline = flip ? 8'd255 - rline : rline;
function [7:0] tx(input [7:0] x);
	tx = flip ? 8'd255 - x : x;
endfunction

localparam S_IDLE = 4'd0, S_BG = 4'd1, S_FG = 4'd2, S_BUL = 4'd3, S_SPR = 4'd4;
reg  [3:0] state = S_IDLE;
reg  [4:0] step;
reg  [4:0] col;
reg  [3:0] px;
reg  [7:0] code, attr, scroll, p0, p1, b51;
reg  [7:0] sy, sx;
reg  [8:0] bx;
reg  [3:0] srow;
reg        sfx, sfy;
reg  [2:0] scol;
wire [7:0] fy  = tline + scroll;
wire [7:0] sdy = rline - sy;

always @(posedge clk_49m) begin
	lb_we <= 1'b0;
	if (!reset) state <= S_IDLE;
	else case (state)
	S_IDLE: if (render_start) begin state <= S_BG; col <= 5'd0; step <= 5'd0; end

	S_BG: begin
		step <= step + 5'd1;
		case (step)
		5'd0: begin bg_raddr <= {tline[7:3], col}; obj_raddr <= {4'd0, col, 1'b1}; end
		5'd2: begin code <= bg_q; attr <= obj_q; end
		5'd3: gfx_addr <= {3'b000, code, tline[2:0]};
		5'd5: begin p0 <= gfx_q; px <= 4'd0; end
		5'd6: begin
			lb_waddr <= tx({col, px[2:0]});
			lb_wdata <= {2'b00, 2'b10, p0[3'd7 - px[2:0]], attr[6:4]};
			lb_we    <= 1'b1;
			px       <= px + 4'd1;
			if (px[2:0] == 3'd7) begin
				step <= 5'd0;
				col  <= col + 5'd1;
				if (col == 5'd31) state <= S_FG;
			end else step <= 5'd6;
		end
		default: ;
		endcase
	end

	S_FG: begin
		step <= step + 5'd1;
		case (step)
		5'd0: obj_raddr <= {4'd0, col, 1'b0};
		5'd1: obj_raddr <= {4'd0, col, 1'b1};
		5'd2: scroll <= obj_q;
		5'd3: begin attr <= obj_q; fg_raddr <= {fy[7:3], col}; end
		5'd5: code <= fg_q;
		5'd6: gfx_addr <= {3'b010, code, fy[2:0]};
		5'd7: gfx_addr <= {3'b100, code, fy[2:0]};
		5'd8: p0 <= gfx_q;
		5'd9: begin p1 <= gfx_q; px <= 4'd0; end
		5'd10: begin
			if (p0[3'd7 - px[2:0]] | p1[3'd7 - px[2:0]]) begin
				lb_waddr <= tx({col, px[2:0]});
				lb_wdata <= {2'b00, 1'b0, attr[2:0], p0[3'd7 - px[2:0]], p1[3'd7 - px[2:0]]};
				lb_we    <= 1'b1;
			end
			px <= px + 4'd1;
			if (px[2:0] == 3'd7) begin
				step <= 5'd0;
				col  <= col + 5'd1;
				if (col == 5'd31) begin state <= S_BUL; col <= 5'd0; end
			end else step <= 5'd10;
		end
		default: ;
		endcase
	end

	S_BUL: begin
		step <= step + 5'd1;
		case (step)
		5'd0: begin gfx_addr <= 14'h0051; obj_raddr <= {5'b00011, col[2:0], 2'd1}; end
		5'd1: obj_raddr <= {5'b00011, col[2:0], 2'd3};
		5'd2: begin b51 <= gfx_q; sy <= (flip & percuss) ? obj_q : 8'd255 - obj_q; end
		5'd3: begin bx <= {1'b0, obj_q} + 9'd7; px <= 4'd0; end
		5'd4: begin
			if (sy == rline && (px == 4'd0 ? b51[4] : b51[0]) && bx + {6'd0, px[2:0]} < 9'd256) begin
				lb_waddr <= bx[7:0] + {5'd0, px[2:0]};
				lb_wdata <= 8'h80;
				lb_we    <= 1'b1;
			end
			px <= px + 4'd1;
			if (px == 4'd6) begin
				step <= 5'd0;
				col  <= col + 5'd1;
				if (col[2:0] == 3'd7) begin state <= S_SPR; col <= 5'd7; end
			end else step <= 5'd4;
		end
		default: ;
		endcase
	end

	S_SPR: begin
		step <= step + 5'd1;
		case (step)
		5'd0: obj_raddr <= {5'b00010, col[2:0], 2'd0};
		5'd1: obj_raddr <= {5'b00010, col[2:0], 2'd1};
		5'd2: begin obj_raddr <= {5'b00010, col[2:0], 2'd2}; sy <= 8'd240 - obj_q; end
		5'd3: begin obj_raddr <= {5'b00010, col[2:0], 2'd3}; code <= obj_q; end
		5'd4: begin
			scol <= obj_q[2:0];
			if (flip & percuss) sy <= 8'd240 - sy;
			sfx <= ~code[6];
			sfy <= code[7] ^ (flip & percuss);
		end
		5'd5: begin
			sx <= 8'd240 - obj_q;
			srow <= sdy[3:0];
			if (sdy >= 8'd16) step <= 5'd15;
		end
		5'd6: begin
			gfx_addr <= {3'b001, code[5:0], (srow ^ {4{sfy}}) >= 4'd8, 1'b0, (srow[2:0] ^ {3{sfy}})};
		end
		5'd7: gfx_addr <= {3'b001, code[5:0], (srow ^ {4{sfy}}) >= 4'd8, 1'b1, (srow[2:0] ^ {3{sfy}})};
		5'd8: begin p0 <= gfx_q; gfx_addr <= {3'b011, code[5:0], (srow ^ {4{sfy}}) >= 4'd8, 1'b0, (srow[2:0] ^ {3{sfy}})}; end
		5'd9: begin b51 <= gfx_q; gfx_addr <= {3'b011, code[5:0], (srow ^ {4{sfy}}) >= 4'd8, 1'b1, (srow[2:0] ^ {3{sfy}})}; end
		5'd10: p1 <= gfx_q;
		5'd11: begin attr <= gfx_q; px <= 4'd0; end
		5'd12: begin
			begin
				reg [3:0] c;
				reg       b0, b1;
				reg [8:0] x;
				c  = px ^ {4{sfx}};
				b0 = c[3] ? b51[3'd7 - c[2:0]] : p0[3'd7 - c[2:0]];
				b1 = c[3] ? attr[3'd7 - c[2:0]] : p1[3'd7 - c[2:0]];
				x  = {1'b0, sx} + {5'd0, px};
				if ((b0 | b1) && (sx < 8'd241 ? x < 9'd256 : x >= 9'd256)) begin
					lb_waddr <= x[7:0];
					lb_wdata <= {2'b00, 1'b0, scol, b0, b1};
					lb_we    <= 1'b1;
				end
			end
			px <= px + 4'd1;
			if (px == 4'd15) step <= 5'd15;
			else step <= 5'd12;
		end
		5'd15: begin
			step <= 5'd0;
			col  <= col - 5'd1;
			if (col[2:0] == 3'd0) state <= S_IDLE;
		end
		default: ;
		endcase
	end

	default: state <= S_IDLE;
	endcase
end

assign prom_a = lb_q[5:0];
wire [7:0] pv = prom_d;
wire [7:0] r8 = (pv[0] ? 8'h21 : 8'h00) + (pv[1] ? 8'h47 : 8'h00) + (pv[2] ? 8'h97 : 8'h00);
wire [7:0] g8 = (pv[3] ? 8'h21 : 8'h00) + (pv[4] ? 8'h47 : 8'h00) + (pv[5] ? 8'h97 : 8'h00);
wire [7:0] b8 = (pv[6] ? 8'h47 : 8'h00) + (pv[7] ? 8'h97 : 8'h00);

assign red   = blank ? 5'd0 : lb_q[7] ? 5'h1F : r8[7:3];
assign green = blank ? 5'd0 : lb_q[7] ? 5'h1F : g8[7:3];
assign blue  = blank ? 5'd0 : lb_q[7] ? 5'h1F : b8[7:3];

endmodule
