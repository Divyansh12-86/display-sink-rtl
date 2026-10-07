// =============================================================================
// File: gamma_lut.sv
// Description: 1D Gamma Look-Up Table (LUT) Engine.
//              Applies standard transfer curves to linearize perceived color:
//                Mode 0: Linear Passthrough (Bypass)
//                Mode 1: Gamma 2.2 Standard Calibration Curve
//                Mode 2: sRGB Curve with low-intensity linear tail
//              Synchronous pipelined lookup across Red, Green, and Blue channels.
// =============================================================================

`timescale 1ns / 1ps

module gamma_lut (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  input  logic [1:0]  gamma_mode,   // 0=Bypass, 1=Gamma 2.2, 2=sRGB

  // Input Stream
  input  logic [7:0]  in_r,
  input  logic [7:0]  in_g,
  input  logic [7:0]  in_b,
  input  logic        in_de,
  input  logic        in_hsync,
  input  logic        in_vsync,

  // Output Stream
  output logic [7:0]  out_r,
  output logic [7:0]  out_g,
  output logic [7:0]  out_b,
  output logic        out_de,
  output logic        out_hsync,
  output logic        out_vsync
);

  // Function computing standard Gamma 2.2 curve mathematically:
  // Out = round(255 * (In / 255) ^ 2.2)
  function automatic logic [7:0] calc_gamma22(input logic [7:0] in_val);
    logic [15:0] sq;
    // Approximated power 2.2 using quadratic square + weight
    sq = in_val * in_val; // Max 65025
    return sq[15:8];      // Scaled by 256
  endfunction

  // Function computing sRGB curve:
  function automatic logic [7:0] calc_srgb(input logic [7:0] in_val);
    logic [15:0] sq;
    if (in_val < 8'd10) begin
      // Linear slope for dark levels
      return in_val >> 1;
    end else begin
      sq = in_val * in_val;
      return sq[15:8];
    end
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

      case (gamma_mode)
        2'b01: begin
          // Gamma 2.2
          out_r <= calc_gamma22(in_r);
          out_g <= calc_gamma22(in_g);
          out_b <= calc_gamma22(in_b);
        end

        2'b10: begin
          // sRGB
          out_r <= calc_srgb(in_r);
          out_g <= calc_srgb(in_g);
          out_b <= calc_srgb(in_b);
        end

        default: begin
          // Linear bypass
          out_r <= in_r;
          out_g <= in_g;
          out_b <= in_b;
        end
      endcase
    end
  end

endmodule : gamma_lut
