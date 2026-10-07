// =============================================================================
// File: axis_video_rx.sv
// Description: AXI4-Stream Video Input Receiver Slave.
//              Converts standard AXI4-Stream video packets (tdata, tvalid,
//              tready, tuser [SOF], tlast [EOL]) into synchronized raster
//              pixels with de, hsync, and vsync flags.
// =============================================================================

`timescale 1ns / 1ps

module axis_video_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,

  // AXI4-Stream Video Slave Interface
  input  logic [23:0] s_axis_tdata,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tuser,   // Start of Frame (SOF)
  input  logic        s_axis_tlast,   // End of Line (EOL)

  // Decoded Raster Pixel Stream
  output logic [7:0]  pixel_r,
  output logic [7:0]  pixel_g,
  output logic [7:0]  pixel_b,
  output logic [11:0] pixel_x,
  output logic [11:0] pixel_y,
  output logic        de,
  output logic        hsync,
  output logic        vsync
);

  // AXI Stream handshake: ready when enabled
  assign s_axis_tready = enable;

  logic [11:0] x_cnt;
  logic [11:0] y_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_cnt   <= 12'd0;
      y_cnt   <= 12'd0;
      pixel_r <= 8'd0;
      pixel_g <= 8'd0;
      pixel_b <= 8'd0;
      pixel_x <= 12'd0;
      pixel_y <= 12'd0;
      de      <= 1'b0;
      hsync   <= 1'b0;
      vsync   <= 1'b0;
    end else if (enable) begin
      if (s_axis_tvalid && s_axis_tready) begin
        de      <= 1'b1;
        pixel_r <= s_axis_tdata[23:16];
        pixel_g <= s_axis_tdata[15:8];
        pixel_b <= s_axis_tdata[7:0];

        // Frame synchronization via tuser (SOF)
        if (s_axis_tuser) begin
          x_cnt   <= 12'd0;
          y_cnt   <= 12'd0;
          vsync   <= 1'b1;
          pixel_x <= 12'd0;
          pixel_y <= 12'd0;
        end else begin
          vsync   <= 1'b0;
          pixel_x <= x_cnt;
          pixel_y <= y_cnt;

          // Line increment on tlast (EOL)
          if (s_axis_tlast) begin
            x_cnt <= 12'd0;
            y_cnt <= y_cnt + 12'd1;
            hsync <= 1'b1;
          end else begin
            x_cnt <= x_cnt + 12'd1;
            hsync <= 1'b0;
          end
        end
      end else begin
        de    <= 1'b0;
        hsync <= 1'b0;
        vsync <= 1'b0;
      end
    end
  end

endmodule : axis_video_rx
