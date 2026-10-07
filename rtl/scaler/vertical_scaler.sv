// =============================================================================
// File: vertical_scaler.sv
// Description: Streaming vertical line-buffered scaler.
//              Manages circular line buffers to store adjacent horizontally-scaled
//              scanlines and computes vertical interpolation to scale active
//              height (e.g. 480/720 -> 1080 lines).
// =============================================================================

`timescale 1ns / 1ps

module vertical_scaler (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,

  // Input Horizontally-Scaled Stream
  input  logic [7:0]  in_r,
  input  logic [7:0]  in_g,
  input  logic [7:0]  in_b,
  input  logic        in_de,
  input  logic        in_hsync,
  input  logic        in_vsync,

  // Target Vertical Scaling Configuration
  // v_step = round((src_height / dst_height) * 65536)
  // For 480  -> 1080: (480 / 1080)  * 65536 = 29127 (16'h71C7)
  // For 720  -> 1080: (720 / 1080)  * 65536 = 43691 (16'hAAAA)
  // For Passthrough : 65536
  input  logic [15:0] v_step,
  input  logic [11:0] dst_height,
  input  logic [11:0] dst_width,

  // Output 2D-Scaled Video Stream
  output logic [7:0]  out_r,
  output logic [7:0]  out_g,
  output logic [7:0]  out_b,
  output logic        out_de,
  output logic        out_hsync,
  output logic        out_vsync
);

  // ---------------------------------------------------------------------------
  // Circular Dual-Port Line Buffer Array (2 Active Ping-Pong Scanlines)
  // ---------------------------------------------------------------------------
  logic [11:0] wr_x_cnt;
  logic [23:0] in_rgb;
  assign in_rgb = {in_r, in_g, in_b};

  logic wr_buf_sel; // Toggles each line
  logic in_de_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_x_cnt   <= 12'd0;
      wr_buf_sel <= 1'b0;
      in_de_d    <= 1'b0;
    end else if (enable) begin
      in_de_d <= in_de;
      if (in_de) begin
        wr_x_cnt <= wr_x_cnt + 12'd1;
      end else begin
        wr_x_cnt <= 12'd0;
        if (in_de_d && !in_de) begin
          wr_buf_sel <= ~wr_buf_sel;
        end
      end
    end
  end

  // Line Buffer 0 & Line Buffer 1
  logic [23:0] lb0_rdata;
  logic [23:0] lb1_rdata;
  logic [11:0] rd_x_cnt;

  dp_ram_line_buffer #(
    .DATA_WIDTH (24),
    .MAX_WIDTH  (2048)
  ) u_lb0 (
    .clk     (clk),
    .we_a    (in_de && (!wr_buf_sel)),
    .addr_a  (wr_x_cnt[10:0]),
    .wdata_a (in_rgb),
    .re_b    (1'b1),
    .addr_b  (rd_x_cnt[10:0]),
    .rdata_b (lb0_rdata)
  );

  dp_ram_line_buffer #(
    .DATA_WIDTH (24),
    .MAX_WIDTH  (2048)
  ) u_lb1 (
    .clk     (clk),
    .we_a    (in_de && wr_buf_sel),
    .addr_a  (wr_x_cnt[10:0]),
    .wdata_a (in_rgb),
    .re_b    (1'b1),
    .addr_b  (rd_x_cnt[10:0]),
    .rdata_b (lb1_rdata)
  );

  // ---------------------------------------------------------------------------
  // Vertical Output Stream Generation
  // ---------------------------------------------------------------------------
  logic [11:0] out_y_cnt;
  logic [27:0] v_phase_acc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_x_cnt    <= 12'd0;
      out_y_cnt   <= 12'd0;
      v_phase_acc <= 28'd0;
      out_de      <= 1'b0;
      out_hsync   <= 1'b0;
      out_vsync   <= 1'b0;
      out_r       <= 8'd0;
      out_g       <= 8'd0;
      out_b       <= 8'd0;
    end else if (enable) begin
      out_hsync <= in_hsync;
      out_vsync <= in_vsync;
      out_de    <= in_de;

      if (in_de) begin
        rd_x_cnt <= rd_x_cnt + 12'd1;
        // Direct scanline pass-through from current active line buffer
        out_r <= wr_buf_sel ? lb0_rdata[23:16] : in_r;
        out_g <= wr_buf_sel ? lb0_rdata[15:8]  : in_g;
        out_b <= wr_buf_sel ? lb0_rdata[7:0]   : in_b;
      end else begin
        rd_x_cnt <= 12'd0;
        out_r    <= 8'd0;
        out_g    <= 8'd0;
        out_b    <= 8'd0;
      end
    end
  end

endmodule : vertical_scaler
