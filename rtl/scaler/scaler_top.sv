// =============================================================================
// File: scaler_top.sv
// Description: Scaler Top-Level Subsystem.
//              Combines Horizontal Polyphase Scaler and Vertical Line Buffer
//              Interpolator with runtime dynamic resolution mode controls.
// =============================================================================

`timescale 1ns / 1ps

module scaler_top
  import display_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,

  // Mode Selection
  input  res_mode_e   src_res,      // Input stream resolution (480p, 720p, 1080p)
  input  res_mode_e   dst_res,      // Target display resolution (typically 1080p)

  // Input Video Stream
  input  logic [7:0]  in_r,
  input  logic [7:0]  in_g,
  input  logic [7:0]  in_b,
  input  logic        in_de,
  input  logic        in_hsync,
  input  logic        in_vsync,

  // Scaled Output Video Stream
  output logic [7:0]  out_r,
  output logic [7:0]  out_g,
  output logic [7:0]  out_b,
  output logic        out_de,
  output logic        out_hsync,
  output logic        out_vsync
);

  // ---------------------------------------------------------------------------
  // Scaling Step & Dimension Parameters
  // ---------------------------------------------------------------------------
  logic [15:0] h_step;
  logic [15:0] v_step;
  logic [11:0] target_w;
  logic [11:0] target_h;

  always_comb begin
    case (dst_res)
      RES_1080P: begin
        target_w = 12'd1920;
        target_h = 12'd1080;
        case (src_res)
          RES_480P: begin
            h_step = 16'd21845; // (640 / 1920) * 65536
            v_step = 16'd29127; // (480 / 1080) * 65536
          end
          RES_720P: begin
            h_step = 16'd43691; // (1280 / 1920) * 65536
            v_step = 16'd43691; // (720 / 1080) * 65536
          end
          default: begin
            h_step = 16'd65535; // 1:1 Passthrough
            v_step = 16'd65535;
          end
        endcase
      end

      default: begin
        target_w = 12'd1920;
        target_h = 12'd1080;
        h_step   = 16'd65535;
        v_step   = 16'd65535;
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Horizontal Scaler Stage
  // ---------------------------------------------------------------------------
  logic [7:0] h_r, h_g, h_b;
  logic       h_de, h_hsync, h_vsync;

  horizontal_scaler u_h_scale (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (enable),
    .in_r       (in_r),
    .in_g       (in_g),
    .in_b       (in_b),
    .in_de      (in_de),
    .in_hsync   (in_hsync),
    .in_vsync   (in_vsync),
    .phase_step (h_step),
    .dst_width  (target_w),
    .out_r      (h_r),
    .out_g      (h_g),
    .out_b      (h_b),
    .out_de     (h_de),
    .out_hsync  (h_hsync),
    .out_vsync  (h_vsync)
  );

  // ---------------------------------------------------------------------------
  // Vertical Scaler Stage
  // ---------------------------------------------------------------------------
  vertical_scaler u_v_scale (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (enable),
    .in_r       (h_r),
    .in_g       (h_g),
    .in_b       (h_b),
    .in_de      (h_de),
    .in_hsync   (h_hsync),
    .in_vsync   (h_vsync),
    .v_step     (v_step),
    .dst_height (target_h),
    .dst_width  (target_w),
    .out_r      (out_r),
    .out_g      (out_g),
    .out_b      (out_b),
    .out_de     (out_de),
    .out_hsync  (out_hsync),
    .out_vsync  (out_vsync)
  );

endmodule : scaler_top
