// =============================================================================
// File: tcon_top.sv
// Description: T-CON Top-Level Subsystem.
//              Combines Timing FSM, live motion pattern generator, and
//              panel driver output interfaces.
// =============================================================================

`timescale 1ns / 1ps

module tcon_top
  import display_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,
  input  res_mode_e     res_mode,
  input  rate_mode_e    rate_mode,
  input  pattern_mode_e pat_mode,
  input  logic [23:0]   ext_video_rgb,
  input  logic          enable,

  // Stream status
  output logic        pixel_en,
  output logic [11:0] pixel_x,
  output logic [11:0] pixel_y,
  output logic        de,
  output logic        hsync,
  output logic        vsync,
  output logic [31:0] frame_count,

  // Live Motion Color Output (24-bit RGB)
  output logic [7:0]  rgb_r,
  output logic [7:0]  rgb_g,
  output logic [7:0]  rgb_b,

  // Glass Control Physical Strobes
  output logic        stv,
  output logic        cpv,
  output logic        oe,
  output logic        tp_load,
  output logic        pol
);

  // Internal wires
  logic [11:0] cur_x;
  logic [11:0] cur_y;
  logic        cur_de;
  logic        cur_vsync;
  logic        cur_hsync;
  logic        cur_en;
  logic [31:0] cur_frame;

  assign pixel_x     = cur_x;
  assign pixel_y     = cur_y;
  assign de          = cur_de;
  assign hsync       = cur_hsync;
  assign vsync       = cur_vsync;
  assign pixel_en    = cur_en;
  assign frame_count = cur_frame;

  // ---------------------------------------------------------------------------
  // Instantiate T-CON Glass Timing FSM
  // ---------------------------------------------------------------------------
  tcon_timing_fsm u_timing_fsm (
    .clk         (clk),
    .rst_n       (rst_n),
    .res_mode    (res_mode),
    .rate_mode   (rate_mode),
    .enable      (enable),
    .pixel_en    (cur_en),
    .pixel_x     (cur_x),
    .pixel_y     (cur_y),
    .de          (cur_de),
    .hsync       (cur_hsync),
    .vsync       (cur_vsync),
    .frame_count (cur_frame),
    .stv         (stv),
    .cpv         (cpv),
    .oe          (oe),
    .tp_load     (tp_load),
    .pol         (pol)
  );

  // ---------------------------------------------------------------------------
  // Instantiate Live Motion Pattern Generator
  // ---------------------------------------------------------------------------
  pattern_generator_live u_pattern_gen (
    .clk         (clk),
    .rst_n       (rst_n),
    .pixel_en    (cur_en),
    .pixel_x     (cur_x),
    .pixel_y     (cur_y),
    .de          (cur_de),
    .vsync       (cur_vsync),
    .frame_count (cur_frame),
    .res_mode      (res_mode),
    .pat_mode      (pat_mode),
    .ext_video_rgb (ext_video_rgb),
    .pixel_r       (rgb_r),
    .pixel_g       (rgb_g),
    .pixel_b       (rgb_b)
  );

endmodule : tcon_top
