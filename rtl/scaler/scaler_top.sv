// =============================================================================
// File: scaler_top.sv
// Description: Multi-Resolution 2D Spatial Scaling Engine.
//              Supports bidirectional scaling (Upscaling & Downscaling) between
//              any pair of CTA-861 / VESA resolutions: 480p, 720p, and 1080p.
//              Provides zero-latency passthrough when src_res == dst_res.
// =============================================================================

`timescale 1ns / 1ps

module scaler_top
  import display_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,

  // Mode Selection
  input  res_mode_e   src_res,      // Input stream native resolution (480p, 720p, 1080p)
  input  res_mode_e   dst_res,      // Target display panel resolution (480p, 720p, 1080p)

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
  // 1. Target Dimensions & Scaling Step Configuration Matrix
  //    step = round((src_dim / dst_dim) * 65536)
  // ---------------------------------------------------------------------------
  logic [19:0] h_step;
  logic [19:0] v_step;
  logic [11:0] target_w;
  logic [11:0] target_h;

  wire is_passthrough = (src_res == dst_res);

  always_comb begin
    case (dst_res)
      RES_480P: begin
        target_w = 12'd640;
        target_h = 12'd480;
        case (src_res)
          RES_480P: begin
            h_step = 20'd65536; // 1:1 Passthrough
            v_step = 20'd65536;
          end
          RES_720P: begin
            h_step = 20'd131072; // (1280 / 640) * 65536 = 2.0x downscale
            v_step = 20'd98304;  // (720 / 480) * 65536 = 1.5x downscale
          end
          RES_1080P: begin
            h_step = 20'd196608; // (1920 / 640) * 65536 = 3.0x downscale
            v_step = 20'd147456; // (1080 / 480) * 65536 = 2.25x downscale
          end
          default: begin
            h_step = 20'd65536;
            v_step = 20'd65536;
          end
        endcase
      end

      RES_720P: begin
        target_w = 12'd1280;
        target_h = 12'd720;
        case (src_res)
          RES_480P: begin
            h_step = 20'd32768; // (640 / 1280) * 65536 = 0.5x upscale
            v_step = 20'd43691; // (480 / 720) * 65536 = 0.667x upscale
          end
          RES_720P: begin
            h_step = 20'd65536; // 1:1 Passthrough
            v_step = 20'd65536;
          end
          RES_1080P: begin
            h_step = 20'd98304; // (1920 / 1280) * 65536 = 1.5x downscale
            v_step = 20'd98304; // (1080 / 720) * 65536 = 1.5x downscale
          end
          default: begin
            h_step = 20'd65536;
            v_step = 20'd65536;
          end
        endcase
      end

      RES_1080P: begin
        target_w = 12'd1920;
        target_h = 12'd1080;
        case (src_res)
          RES_480P: begin
            h_step = 20'd21845; // (640 / 1920) * 65536 = 0.333x upscale
            v_step = 20'd29127; // (480 / 1080) * 65536 = 0.444x upscale
          end
          RES_720P: begin
            h_step = 20'd43691; // (1280 / 1920) * 65536 = 0.667x upscale
            v_step = 20'd43691; // (720 / 1080) * 65536 = 0.667x upscale
          end
          RES_1080P: begin
            h_step = 20'd65536; // 1:1 Passthrough
            v_step = 20'd65536;
          end
          default: begin
            h_step = 20'd65536;
            v_step = 20'd65536;
          end
        endcase
      end

      default: begin
        target_w = 12'd1920;
        target_h = 12'd1080;
        h_step   = 20'd65536;
        v_step   = 20'd65536;
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // 2. Horizontal Polyphase Scaler Stage
  // ---------------------------------------------------------------------------
  logic [7:0] h_r, h_g, h_b;
  logic       h_de, h_hsync, h_vsync;

  horizontal_scaler u_h_scale (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (enable && !is_passthrough),
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
  // 3. Vertical Line-Buffer Scaler Stage
  // ---------------------------------------------------------------------------
  logic [7:0] v_r, v_g, v_b;
  logic       v_de, v_hsync, v_vsync;

  vertical_scaler u_v_scale (
    .clk        (clk),
    .rst_n      (rst_n),
    .enable     (enable && !is_passthrough),
    .in_r       (h_r),
    .in_g       (h_g),
    .in_b       (h_b),
    .in_de      (h_de),
    .in_hsync   (h_hsync),
    .in_vsync   (h_vsync),
    .v_step     (v_step),
    .dst_height (target_h),
    .dst_width  (target_w),
    .out_r      (v_r),
    .out_g      (v_g),
    .out_b      (v_b),
    .out_de     (v_de),
    .out_hsync  (v_hsync),
    .out_vsync  (v_vsync)
  );

  // ---------------------------------------------------------------------------
  // 4. Output MUX: Pure 1:1 Passthrough vs 2D Scaled Stream
  // ---------------------------------------------------------------------------
  always_comb begin
    if (is_passthrough) begin
      out_r     = in_r;
      out_g     = in_g;
      out_b     = in_b;
      out_de    = in_de;
      out_hsync = in_hsync;
      out_vsync = in_vsync;
    end else begin
      out_r     = v_r;
      out_g     = v_g;
      out_b     = v_b;
      out_de    = v_de;
      out_hsync = v_hsync;
      out_vsync = v_vsync;
    end
  end

endmodule : scaler_top
