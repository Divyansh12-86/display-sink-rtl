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

`ifdef YOSYS
`include "display_defs.vh"
`endif

module display_sink_top
`ifndef YOSYS
  import display_pkg::*;
`endif
(
  input  logic        clk,          // System clock: 150 MHz
  input  logic        rst_n,        // Active-low reset
  input  logic        enable,       // Global raster enable

  // Mode & Configuration Controls
  input  res_mode_e     res_mode,     // Target Display Panel Resolution (480p, 720p, 1080p)
  input  res_mode_e     src_res_mode, // Video Source Native Resolution (480p, 720p, 1080p)
  input  rate_mode_e    rate_mode,    // 24Hz, 30Hz, 45Hz, 60Hz
  input  pattern_mode_e pat_mode,     // 0..3: Built-in Patterns, 4: Video1, 5: Video2
  input  logic [23:0]   ext_video_rgb,// External frame pixel data for Video1/Video2
  input  logic          ext_video_sel,// 0 = Internal Pattern/Video, 1 = External AXI-Stream
  input  logic          fast_sim_en,  // 1 = High-speed real-time simulation (1 cycle per pixel)
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
  output logic        pol,          // Liquid Crystal Polarity Inversion Clock

  // Optional SoC APB Slave Interface (Zero wait-state)
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [11:0] paddr,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,
  output logic        irq
);

  // ---------------------------------------------------------------------------
  // 0. Asynchronous Reset Synchronizer (2-Stage Metastability Hardening)
  // ---------------------------------------------------------------------------
  logic rst_sync_meta_n;
  logic sync_rst_n;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_sync_meta_n <= 1'b0;
      sync_rst_n      <= 1'b0;
    end else begin
      rst_sync_meta_n <= 1'b1;
      sync_rst_n      <= rst_sync_meta_n;
    end
  end

  // ---------------------------------------------------------------------------
  // Timing Status Wires (shared with CSR telemetry)
  // ---------------------------------------------------------------------------
  logic        pixel_en;
  logic [11:0] pixel_x;
  logic [11:0] pixel_y;
  logic        tcon_de;
  logic        tcon_hsync;
  logic        tcon_vsync;
  logic [31:0] frame_count;

  // ---------------------------------------------------------------------------
  // 1. SoC Memory-Mapped APB CSR Subsystem
  // ---------------------------------------------------------------------------
  logic          csr_enable;
  res_mode_e     csr_res_mode;
  res_mode_e     csr_src_res_mode;
  rate_mode_e    csr_rate_mode;
  pattern_mode_e csr_pat_mode;
  logic          csr_ext_video_sel;
  logic          csr_fast_sim_en;
  logic          csr_csc_enable;
  logic [1:0]    csr_gamma_mode;
  logic          csr_dither_enable;

  display_sink_csr u_csr (
    .pclk              (clk),
    .presetn           (sync_rst_n),
    .psel              (psel),
    .penable           (penable),
    .pwrite            (pwrite),
    .paddr             (paddr),
    .pwdata            (pwdata),
    .prdata            (prdata),
    .pready            (pready),
    .pslverr           (pslverr),
    .stat_pixel_x      (pixel_x),
    .stat_pixel_y      (pixel_y),
    .stat_frame_count  (frame_count),
    .stat_vsync        (tcon_vsync),
    .cfg_enable        (csr_enable),
    .cfg_res_mode      (csr_res_mode),
    .cfg_src_res_mode  (csr_src_res_mode),
    .cfg_rate_mode     (csr_rate_mode),
    .cfg_pat_mode      (csr_pat_mode),
    .cfg_ext_video_sel (csr_ext_video_sel),
    .cfg_fast_sim_en   (csr_fast_sim_en),
    .cfg_csc_enable    (csr_csc_enable),
    .cfg_gamma_mode    (csr_gamma_mode),
    .cfg_dither_enable (csr_dither_enable),
    .irq               (irq)
  );

  // Switch to software CSR control if any APB write transaction has occurred
  logic apb_written;
  always_ff @(posedge clk or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      apb_written <= 1'b0;
    end else if (psel && penable && pwrite) begin
      apb_written <= 1'b1;
    end
  end

  wire                eff_enable        = apb_written ? csr_enable        : enable;
  wire res_mode_e     eff_res_mode      = apb_written ? csr_res_mode      : res_mode;
  wire res_mode_e     eff_src_res       = apb_written ? csr_src_res_mode  : src_res_mode;
  wire rate_mode_e    eff_rate_mode     = apb_written ? csr_rate_mode     : rate_mode;
  wire pattern_mode_e eff_pat_mode      = apb_written ? csr_pat_mode      : pat_mode;
  wire                eff_ext_video_sel = apb_written ? csr_ext_video_sel : ext_video_sel;
  wire                eff_fast_sim_en   = apb_written ? csr_fast_sim_en   : fast_sim_en;
  wire                eff_csc_enable    = apb_written ? csr_csc_enable    : csc_enable;
  wire [1:0]          eff_gamma_mode    = apb_written ? csr_gamma_mode    : gamma_mode;
  wire                eff_dither_enable = apb_written ? csr_dither_enable : dither_enable;

  // ---------------------------------------------------------------------------
  // 2. T-CON Timing Generator (Coordinates, Clock Enable, Strobes)
  // ---------------------------------------------------------------------------
  tcon_timing_fsm u_tcon_fsm (
    .clk         (clk),
    .rst_n       (sync_rst_n),
    .res_mode    (eff_res_mode),
    .rate_mode   (eff_rate_mode),
    .enable      (eff_enable),
    .fast_sim_en (eff_fast_sim_en),
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
    .rst_n         (sync_rst_n),
    .pixel_en      (pixel_en),
    .pixel_x       (pixel_x),
    .pixel_y       (pixel_y),
    .de            (tcon_de),
    .vsync         (tcon_vsync),
    .frame_count   (frame_count),
    .res_mode      (eff_res_mode),
    .pat_mode      (eff_pat_mode),
    .ext_video_rgb (ext_video_rgb),
    .pixel_r       (live_r),
    .pixel_g       (live_g),
    .pixel_b       (live_b)
  );

  // ---------------------------------------------------------------------------
  // 4. External AXI4-Stream Video Receiver
  // ---------------------------------------------------------------------------
  logic [7:0]  ext_r, ext_g, ext_b;
  logic [11:0] ext_x, ext_y;
  logic        ext_de, ext_hsync, ext_vsync;

  axis_video_rx u_axis_rx (
    .clk           (clk),
    .rst_n         (sync_rst_n),
    .enable        (eff_enable),
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
  // 5. Video Source Multiplexer
  // ---------------------------------------------------------------------------
  logic [7:0] mux_r, mux_g, mux_b;
  logic [11:0] mux_x, mux_y;
  logic        mux_de, mux_hsync, mux_vsync;

  always_comb begin
    if (!eff_ext_video_sel) begin
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
  // 6. 2D Spatial Scaling Engine
  // ---------------------------------------------------------------------------
  logic [7:0] scale_r, scale_g, scale_b;
  logic       scale_de, scale_hsync, scale_vsync;

  wire res_mode_e active_src_res = eff_ext_video_sel ? eff_src_res : eff_res_mode;

  scaler_top u_scaler (
    .clk       (clk),
    .rst_n     (sync_rst_n),
    .enable    (eff_enable),
    .src_res   (active_src_res),
    .dst_res   (eff_res_mode), // Scaled to current active panel target resolution
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
  // 7. Color, Gamma & Dithering Processing Pipeline
  // ---------------------------------------------------------------------------
  color_top u_color_pipe (
    .clk           (clk),
    .rst_n         (sync_rst_n),
    .enable        (eff_enable),
    .csc_enable    (eff_csc_enable),
    .gamma_mode    (eff_gamma_mode),
    .dither_enable (eff_dither_enable),
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
