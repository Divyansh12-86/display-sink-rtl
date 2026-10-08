// =============================================================================
// File: display_sink_top.sv
// Description: Master Integrated Display Sink Controller Top-Level.
//              Integrates:
//                1. Input Stream Mux (Internal Algorithmic Motion vs External AXI4-Stream)
//                2. 2D Spatial Scaling Engine (scaler_top.sv)
//                3. Color & Gamma Processing Pipeline (color_top.sv)
//                4. Panel Timing Controller & Glass Strobe Generator (tcon_timing_fsm.sv)
// =============================================================================

`timescale 1ns / 1ps

module display_sink_top
  import display_pkg::*;
(
  input  logic        clk,          // System clock: 150 MHz
  input  logic        rst_n,        // Active-low reset
  input  logic        enable,       // Global raster enable

  // Mode & Configuration Controls
  input  res_mode_e     res_mode,     // 480p, 720p, 1080p
  input  rate_mode_e    rate_mode,    // 24Hz, 30Hz, 45Hz, 60Hz
  input  pattern_mode_e pat_mode,     // 0..3: Built-in Patterns, 4: Video1, 5: Video2
  input  logic [23:0]   ext_video_rgb,// External frame pixel data for Video1/Video2
  input  logic          ext_video_sel,// 0 = Internal Pattern/Video, 1 = External AXI-Stream
  input  logic          csc_enable,   // 0 = RGB Bypass, 1 = YCbCr -> RGB
  input  logic [1:0]    gamma_mode,   // 0 = Bypass, 1 = Gamma 2.2, 2 = sRGB
  input  logic          dither_enable,// 0 = Bypass, 1 = Dither ON

  // External AXI4-Stream Video In
  input  logic [23:0] s_axis_tdata,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tuser,
  input  logic        s_axis_tlast,

  // Digital Panel Video Out
  output logic [7:0]  panel_r,
  output logic [7:0]  panel_g,
  output logic [7:0]  panel_b,
  output logic        panel_de,
  output logic        panel_hsync,
  output logic        panel_vsync,

  // Current Raster Coordinates (Direct access for emulator / OSD)
  output logic [11:0] cur_pixel_x,
  output logic [11:0] cur_pixel_y,
  output logic        cur_pixel_en,

  // Panel Physical Control Strobes
  output logic        stv,          // Start Pulse Vertical (Frame start)
  output logic        cpv,          // Clock Pulse Vertical (Row clock)
  output logic        oe,           // Output Enable (Gate mask)
  output logic        tp_load,      // Source Driver Line-Latch Strobe
  output logic        pol           // Liquid Crystal Polarity Inversion Clock
);

  // ---------------------------------------------------------------------------
  // 1. T-CON Timing Generator (Coordinates, Clock Enable, Strobes)
  // ---------------------------------------------------------------------------
  logic        pixel_en;
  logic [11:0] pixel_x;
  logic [11:0] pixel_y;
  logic        tcon_de;
  logic        tcon_hsync;
  logic        tcon_vsync;
  logic [31:0] frame_count;

  tcon_timing_fsm u_tcon_fsm (
    .clk         (clk),
    .rst_n       (rst_n),
    .res_mode    (res_mode),
    .rate_mode   (rate_mode),
    .enable      (enable),
    .pixel_en    (pixel_en),
    .pixel_x     (pixel_x),
    .pixel_y     (pixel_y),
    .de          (tcon_de),
    .hsync       (tcon_hsync),
    .vsync       (tcon_vsync),
    .frame_count (frame_count),
    .stv         (stv),
    .cpv         (cpv),
    .oe          (oe),
    .tp_load     (tp_load),
    .pol         (pol)
  );

  // ---------------------------------------------------------------------------
  // 2. Internal Live Motion Algorithmic Engine
  // ---------------------------------------------------------------------------
  logic [7:0] live_r, live_g, live_b;

  assign cur_pixel_x  = pixel_x;
  assign cur_pixel_y  = pixel_y;
  assign cur_pixel_en = pixel_en;

  pattern_generator_live u_pattern_live (
    .clk           (clk),
    .rst_n         (rst_n),
    .pixel_en      (pixel_en),
    .pixel_x       (pixel_x),
    .pixel_y       (pixel_y),
    .de            (tcon_de),
    .vsync         (tcon_vsync),
    .frame_count   (frame_count),
    .res_mode      (res_mode),
    .pat_mode      (pat_mode),
    .ext_video_rgb (ext_video_rgb),
    .pixel_r       (live_r),
    .pixel_g       (live_g),
    .pixel_b       (live_b)
  );

  // ---------------------------------------------------------------------------
  // 3. External AXI4-Stream Video Receiver
  // ---------------------------------------------------------------------------
  logic [7:0]  ext_r, ext_g, ext_b;
  logic [11:0] ext_x, ext_y;
  logic        ext_de, ext_hsync, ext_vsync;

  axis_video_rx u_axis_rx (
    .clk           (clk),
    .rst_n         (rst_n),
    .enable        (enable),
    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),
    .s_axis_tuser  (s_axis_tuser),
    .s_axis_tlast  (s_axis_tlast),
    .pixel_r       (ext_r),
    .pixel_g       (ext_g),
    .pixel_b       (ext_b),
    .pixel_x       (ext_x),
    .pixel_y       (ext_y),
    .de            (ext_de),
    .hsync         (ext_hsync),
    .vsync         (ext_vsync)
  );

  // ---------------------------------------------------------------------------
  // 4. Video Source Multiplexer
  // ---------------------------------------------------------------------------
  logic [7:0] mux_r, mux_g, mux_b;
  logic [11:0] mux_x, mux_y;
  logic        mux_de, mux_hsync, mux_vsync;

  always_comb begin
    if (!ext_video_sel) begin
      mux_r     = live_r;
      mux_g     = live_g;
      mux_b     = live_b;
      mux_x     = pixel_x;
      mux_y     = pixel_y;
      mux_de    = tcon_de;
      mux_hsync = tcon_hsync;
      mux_vsync = tcon_vsync;
    end else begin
      mux_r     = ext_r;
      mux_g     = ext_g;
      mux_b     = ext_b;
      mux_x     = ext_x;
      mux_y     = ext_y;
      mux_de    = ext_de;
      mux_hsync = ext_hsync;
      mux_vsync = ext_vsync;
    end
  end

  // ---------------------------------------------------------------------------
  // 5. 2D Spatial Scaling Engine
  // ---------------------------------------------------------------------------
  logic [7:0] scale_r, scale_g, scale_b;
  logic       scale_de, scale_hsync, scale_vsync;

  scaler_top u_scaler (
    .clk       (clk),
    .rst_n     (rst_n),
    .enable    (enable),
    .src_res   (res_mode),
    .dst_res   (RES_1080P), // Output scaled to native 1080p
    .in_r      (mux_r),
    .in_g      (mux_g),
    .in_b      (mux_b),
    .in_de     (mux_de),
    .in_hsync  (mux_hsync),
    .in_vsync  (mux_vsync),
    .out_r     (scale_r),
    .out_g     (scale_g),
    .out_b     (scale_b),
    .out_de    (scale_de),
    .out_hsync (scale_hsync),
    .out_vsync (scale_vsync)
  );

  // ---------------------------------------------------------------------------
  // 6. Color, Gamma & Dithering Processing Pipeline
  // ---------------------------------------------------------------------------
  color_top u_color_pipe (
    .clk           (clk),
    .rst_n         (rst_n),
    .enable        (enable),
    .csc_enable    (csc_enable),
    .gamma_mode    (gamma_mode),
    .dither_enable (dither_enable),
    .frame_count   (frame_count),
    .in_c0         (scale_r),
    .in_c1         (scale_g),
    .in_c2         (scale_b),
    .pixel_x       (mux_x),
    .pixel_y       (mux_y),
    .in_de         (scale_de),
    .in_hsync      (scale_hsync),
    .in_vsync      (scale_vsync),
    .out_r         (panel_r),
    .out_g         (panel_g),
    .out_b         (panel_b),
    .out_de        (panel_de),
    .out_hsync     (panel_hsync),
    .out_vsync     (panel_vsync)
  );

endmodule : display_sink_top
