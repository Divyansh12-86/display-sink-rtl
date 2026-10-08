// =============================================================================
// File: pattern_generator_live.sv
// Description: Multi-pattern synthesizable video generator with zero RAM:
//              Supports 4 selectable default broadcast/display patterns:
//              1. PAT_COLORBARS : Standard 8-Bar SMPTE / EBU Color Bars
//                                 (White, Yellow, Cyan, Green, Magenta, Red, Blue, Black)
//              2. PAT_GRAYSCALE : 0-255 Horizontal Linear Luminance Ramp
//              3. PAT_GEOMETRY  : Calibration Grid & Sharp Corner/Center Reticles
//              4. PAT_MOTION    : High-Velocity Animated Target & Smooth Shifting Wave
// =============================================================================

`timescale 1ns / 1ps

module pattern_generator_live
  import display_pkg::*;
(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          pixel_en,
  input  logic [11:0]   pixel_x,
  input  logic [11:0]   pixel_y,
  input  logic          de,
  input  logic          vsync,
  input  logic [31:0]   frame_count,
  input  res_mode_e     res_mode,
  input  pattern_mode_e pat_mode,
  input  logic [23:0]   ext_video_rgb, // External frame pixel streaming input

  output logic [7:0]    pixel_r,
  output logic [7:0]    pixel_g,
  output logic [7:0]    pixel_b
);

  // ---------------------------------------------------------------------------
  // Active Screen Boundaries
  // ---------------------------------------------------------------------------
  logic [11:0] max_x;
  logic [11:0] max_y;

  always_comb begin
    case (res_mode)
      RES_480P:  begin max_x = 12'd640;  max_y = 12'd480;  end
      RES_720P:  begin max_x = 12'd1280; max_y = 12'd720;  end
      RES_1080P: begin max_x = 12'd1920; max_y = 12'd1080; end
      default:   begin max_x = 12'd1920; max_y = 12'd1080; end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Pattern 1: SMPTE 8-Bar Color Bars
  // Bar width = max_x / 8 (e.g. 80 for 480p, 160 for 720p, 240 for 1080p)
  // ---------------------------------------------------------------------------
  logic [2:0] bar_idx;
  logic [7:0] bar_r, bar_g, bar_b;

  always_comb begin
    case (res_mode)
      RES_480P:  bar_idx = pixel_x / 12'd80;
      RES_720P:  bar_idx = pixel_x / 12'd160;
      RES_1080P: bar_idx = pixel_x / 12'd240;
      default:   bar_idx = pixel_x / 12'd240;
    endcase

    case (bar_idx)
      3'd0: begin bar_r = 8'hEA; bar_g = 8'hEA; bar_b = 8'hEA; end // 75% White
      3'd1: begin bar_r = 8'hEA; bar_g = 8'hEA; bar_b = 8'h00; end // Yellow
      3'd2: begin bar_r = 8'h00; bar_g = 8'hEA; bar_b = 8'hEA; end // Cyan
      3'd3: begin bar_r = 8'h00; bar_g = 8'hEA; bar_b = 8'h00; end // Green
      3'd4: begin bar_r = 8'hEA; bar_g = 8'h00; bar_b = 8'hEA; end // Magenta
      3'd5: begin bar_r = 8'hEA; bar_g = 8'h00; bar_b = 8'h00; end // Red
      3'd6: begin bar_r = 8'h00; bar_g = 8'h00; bar_b = 8'hEA; end // Blue
      3'd7: begin bar_r = 8'h10; bar_g = 8'h10; bar_b = 8'h10; end // Black
    endcase
  end

  // ---------------------------------------------------------------------------
  // Pattern 2: Smooth 0-255 Horizontal Grayscale Ramp
  // ---------------------------------------------------------------------------
  logic [7:0] gray_level;
  always_comb begin
    case (res_mode)
      RES_480P:  gray_level = (pixel_x * 8'd255) / 12'd639;
      RES_720P:  gray_level = (pixel_x * 8'd255) / 12'd1279;
      RES_1080P: gray_level = (pixel_x * 8'd255) / 12'd1919;
      default:   gray_level = (pixel_x * 8'd255) / 12'd1919;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Pattern 3: Calibration Grid & Geometry Markers
  // ---------------------------------------------------------------------------
  logic grid_hit;
  logic corner_hit;
  always_comb begin
    // 32-pixel grid
    grid_hit = (pixel_x[4:0] == 5'd0) || (pixel_y[4:0] == 5'd0);
    // 16x16 corner calibration boxes
    corner_hit = ((pixel_x < 12'd16 || pixel_x >= max_x - 12'd16) &&
                  (pixel_y < 12'd16 || pixel_y >= max_y - 12'd16));
  end

  // ---------------------------------------------------------------------------
  // Pattern 4: High-Velocity Animated Target (Physics on Vsync)
  // ---------------------------------------------------------------------------
  localparam SPRITE_RADIUS = 12'd32;

  logic [11:0] ball_x;
  logic [11:0] ball_y;
  logic        ball_dx;
  logic        ball_dy;
  logic        vsync_d;
  wire         vsync_edge = vsync && !vsync_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ball_x   <= 12'd100;
      ball_y   <= 12'd100;
      ball_dx  <= 1'b0;
      ball_dy  <= 1'b0;
      vsync_d  <= 1'b0;
    end else begin
      vsync_d <= vsync;
      if (vsync_edge) begin
        if (!ball_dx) begin
          if (ball_x + SPRITE_RADIUS + 12'd6 >= max_x) ball_dx <= 1'b1;
          else ball_x <= ball_x + 12'd6;
        end else begin
          if (ball_x <= SPRITE_RADIUS + 12'd6) ball_dx <= 1'b0;
          else ball_x <= ball_x - 12'd6;
        end

        if (!ball_dy) begin
          if (ball_y + SPRITE_RADIUS + 12'd4 >= max_y) ball_dy <= 1'b1;
          else ball_y <= ball_y + 12'd4;
        end else begin
          if (ball_y <= SPRITE_RADIUS + 12'd4) ball_dy <= 1'b0;
          else ball_y <= ball_y - 12'd4;
        end
      end
    end
  end

  logic signed [12:0] diff_x, diff_y;
  logic [11:0] abs_x, abs_y;
  logic inside_ball;

  always_comb begin
    diff_x = $signed({1'b0, pixel_x}) - $signed({1'b0, ball_x});
    diff_y = $signed({1'b0, pixel_y}) - $signed({1'b0, ball_y});
    abs_x  = diff_x[12] ? 12'(-diff_x) : 12'(diff_x);
    abs_y  = diff_y[12] ? 12'(-diff_y) : 12'(diff_y);
    inside_ball = ((abs_x * abs_x) + (abs_y * abs_y)) <= (SPRITE_RADIUS * SPRITE_RADIUS);
  end

  // ---------------------------------------------------------------------------
  // Compositor & Pattern Selector
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pixel_r <= 8'd0;
      pixel_g <= 8'd0;
      pixel_b <= 8'd0;
    end else if (pixel_en) begin
      if (!de) begin
        pixel_r <= 8'd0;
        pixel_g <= 8'd0;
        pixel_b <= 8'd0;
      end else begin
        case (pat_mode)
          PAT_COLORBARS: begin
            pixel_r <= bar_r;
            pixel_g <= bar_g;
            pixel_b <= bar_b;
          end

          PAT_GRAYSCALE: begin
            pixel_r <= gray_level;
            pixel_g <= gray_level;
            pixel_b <= gray_level;
          end

          PAT_GEOMETRY: begin
            if (corner_hit) begin
              pixel_r <= 8'hFF; pixel_g <= 8'h00; pixel_b <= 8'h00; // Red corners
            end else if (grid_hit) begin
              pixel_r <= 8'hE0; pixel_g <= 8'hE0; pixel_b <= 8'hE0; // White grid
            end else begin
              pixel_r <= 8'h14; pixel_g <= 8'h14; pixel_b <= 8'h20; // Dark blueprint
            end
          end

          PAT_MOTION: begin
            if (inside_ball) begin
              pixel_r <= 8'hFF;
              pixel_g <= 8'hD7 + frame_count[4:0];
              pixel_b <= 8'h00;
            end else begin
              pixel_r <= pixel_x[7:0] + frame_count[7:0];
              pixel_g <= pixel_y[7:0] + (frame_count[7:0] << 1);
              pixel_b <= (pixel_x[7:0] ^ pixel_y[7:0]) + frame_count[7:0];
            end
          end

          PAT_VIDEO1, PAT_VIDEO2: begin
            pixel_r <= ext_video_rgb[23:16];
            pixel_g <= ext_video_rgb[15:8];
            pixel_b <= ext_video_rgb[7:0];
          end

          default: begin
            pixel_r <= bar_r;
            pixel_g <= bar_g;
            pixel_b <= bar_b;
          end
        endcase
      end
    end
  end

endmodule : pattern_generator_live
