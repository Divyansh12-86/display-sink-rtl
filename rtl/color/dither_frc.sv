// =============================================================================
// File: dither_frc.sv
// Description: Spatial and Temporal Dithering / Frame Rate Control (FRC).
//              Applies a 2x2 Bayer spatial matrix combined with frame temporal
//              phase flipping to suppress quantization color banding:
//                Bayer Matrix = [ 0  2 ]
//                               [ 3  1 ]
// =============================================================================

`timescale 1ns / 1ps

module dither_frc (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  input  logic        dither_enable, // 0 = Bypass, 1 = Enable Dithering
  input  logic [31:0] frame_count,

  // Stream Input
  input  logic [7:0]  in_r,
  input  logic [7:0]  in_g,
  input  logic [7:0]  in_b,
  input  logic [11:0] pixel_x,
  input  logic [11:0] pixel_y,
  input  logic        in_de,
  input  logic        in_hsync,
  input  logic        in_vsync,

  // Stream Output
  output logic [7:0]  out_r,
  output logic [7:0]  out_g,
  output logic [7:0]  out_b,
  output logic        out_de,
  output logic        out_hsync,
  output logic        out_vsync
);

  // 2x2 Spatial Bayer Matrix threshold [0..3]
  logic [1:0] bayer_val;
  always_comb begin
    case ({pixel_y[0], pixel_x[0]})
      2'b00: bayer_val = 2'd0;
      2'b01: bayer_val = 2'd2;
      2'b10: bayer_val = 2'd3;
      2'b11: bayer_val = 2'd1;
    endcase
  end

  // Temporal offset toggling phase every frame
  wire [1:0] dither_thresh = bayer_val ^ {2{frame_count[0]}};

  // Helper function to dither channel
  function automatic logic [7:0] apply_dither(input logic [7:0] val, input logic [1:0] th);
    if (val == 8'hFF)
      return 8'hFF;
    else if (val[1:0] > th)
      return val + 8'd1;
    else
      return val;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_r     <= 8'd0;
      out_g     <= 8'd0;
      out_b     <= 8'd0;
      out_de    <= 1'b0;
      out_hsync <= 1'b0;
      out_vsync <= 1'b0;
    end else if (enable) begin
      out_de    <= in_de;
      out_hsync <= in_hsync;
      out_vsync <= in_vsync;

      if (!dither_enable) begin
        out_r <= in_r;
        out_g <= in_g;
        out_b <= in_b;
      end else begin
        out_r <= apply_dither(in_r, dither_thresh);
        out_g <= apply_dither(in_g, dither_thresh);
        out_b <= apply_dither(in_b, dither_thresh);
      end
    end
  end

endmodule : dither_frc
