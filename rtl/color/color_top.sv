// =============================================================================
// File: color_top.sv
// Description: Color & Image Processing Pipeline Top-Level Subsystem.
//              Cascades:
//                1. Color Space Conversion (YCbCr -> RGB or Passthrough)
//                2. 1D Gamma LUT (Gamma 2.2 / sRGB / Linear)
//                3. Spatial & Temporal Dithering (FRC)
// =============================================================================

`timescale 1ns / 1ps

module color_top (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,

  // Configuration Modes
  input  logic        csc_enable,    // 0=RGB, 1=YCbCr->RGB
  input  logic [1:0]  gamma_mode,    // 0=Bypass, 1=Gamma 2.2, 2=sRGB
  input  logic        dither_enable, // 0=Bypass, 1=Dither ON
  input  logic [31:0] frame_count,

  // Input Video Stream
  input  logic [7:0]  in_c0,         // Y  or R
  input  logic [7:0]  in_c1,         // Cb or G
  input  logic [7:0]  in_c2,         // Cr or B
  input  logic [11:0] pixel_x,
  input  logic [11:0] pixel_y,
  input  logic        in_de,
  input  logic        in_hsync,
  input  logic        in_vsync,

  // Output Video Stream (Fully Corrected RGB)
  output logic [7:0]  out_r,
  output logic [7:0]  out_g,
  output logic [7:0]  out_b,
  output logic        out_de,
  output logic        out_hsync,
  output logic        out_vsync
);

  // Stage 1 -> Stage 2 Wires
  logic [7:0] csc_r, csc_g, csc_b;
  logic       csc_de, csc_hsync, csc_vsync;

  csc_matrix u_csc (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (enable),
    .csc_enable (csc_enable),
    .in_c0      (in_c0),
    .in_c1      (in_c1),
    .in_c2      (in_c2),
    .in_de      (in_de),
    .in_hsync   (in_hsync),
    .in_vsync   (in_vsync),
    .out_r      (csc_r),
    .out_g      (csc_g),
    .out_b      (csc_b),
    .out_de     (csc_de),
    .out_hsync  (csc_hsync),
    .out_vsync  (csc_vsync)
  );

  // Stage 2 -> Stage 3 Wires
  logic [7:0] gamma_r, gamma_g, gamma_b;
  logic       gamma_de, gamma_hsync, gamma_vsync;

  gamma_lut u_gamma (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (enable),
    .gamma_mode (gamma_mode),
    .in_r       (csc_r),
    .in_g       (csc_g),
    .in_b       (csc_b),
    .in_de      (csc_de),
    .in_hsync   (csc_hsync),
    .in_vsync   (csc_vsync),
    .out_r      (gamma_r),
    .out_g      (gamma_g),
    .out_b      (gamma_b),
    .out_de     (gamma_de),
    .out_hsync  (gamma_hsync),
    .out_vsync  (gamma_vsync)
  );

  // Stage 3 -> Output Dithering
  dither_frc u_dither (
    .clk           (clk),
    .rst_n         (rst_n),
    .enable        (enable),
    .dither_enable (dither_enable),
    .frame_count   (frame_count),
    .in_r          (gamma_r),
    .in_g          (gamma_g),
    .in_b          (gamma_b),
    .pixel_x       (pixel_x),
    .pixel_y       (pixel_y),
    .in_de         (gamma_de),
    .in_hsync      (gamma_hsync),
    .in_vsync      (gamma_vsync),
    .out_r         (out_r),
    .out_g         (out_g),
    .out_b         (out_b),
    .out_de        (out_de),
    .out_hsync     (out_hsync),
    .out_vsync     (out_vsync)
  );

endmodule : color_top
