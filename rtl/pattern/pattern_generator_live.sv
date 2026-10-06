// =============================================================================
// File: pattern_generator_live.sv
// Description: Multi-frame synthesizable algorithmic video motion generator.
//              Generates dynamic animated video in real time with ZERO external RAM:
//              1. Bouncing color sprite / raster ball with velocity physics.
//              2. Dynamic smooth RGB gradient sweep shifting across time.
//              3. High-frequency pixel grid / zone boundary markers.
// =============================================================================

`timescale 1ns / 1ps

module pattern_generator_live
  import display_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        pixel_en,
  input  logic [11:0] pixel_x,
  input  logic [11:0] pixel_y,
  input  logic        de,
  input  logic        vsync,
  input  logic [31:0] frame_count,
  input  res_mode_e   res_mode,

  output logic [7:0]  pixel_r,
  output logic [7:0]  pixel_g,
  output logic [7:0]  pixel_b
);

  // ---------------------------------------------------------------------------
  // Screen Boundary Limits based on Resolution
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
  // Sprite Animation Physics (Evaluated once per frame at Vsync rising edge)
  // ---------------------------------------------------------------------------
  localparam SPRITE_RADIUS = 12'd32;

  logic [11:0] ball_x;
  logic [11:0] ball_y;
  logic        ball_dx; // 0 = right (+), 1 = left (-)
  logic        ball_dy; // 0 = down  (+), 1 = up   (-)

  logic vsync_d;
  wire  vsync_edge = vsync && !vsync_d;

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
        // Horizontal trajectory update (speed: 4 pixels per frame)
        if (!ball_dx) begin
          if (ball_x + SPRITE_RADIUS + 12'd4 >= max_x)
            ball_dx <= 1'b1;
          else
            ball_x  <= ball_x + 12'd4;
        end else begin
          if (ball_x <= SPRITE_RADIUS + 12'd4)
            ball_dx <= 1'b0;
          else
            ball_x  <= ball_x - 12'd4;
        end

        // Vertical trajectory update (speed: 3 pixels per frame)
        if (!ball_dy) begin
          if (ball_y + SPRITE_RADIUS + 12'd3 >= max_y)
            ball_dy <= 1'b1;
          else
            ball_y  <= ball_y + 12'd3;
        end else begin
          if (ball_y <= SPRITE_RADIUS + 12'd3)
            ball_dy <= 1'b0;
          else
            ball_y  <= ball_y - 12'd3;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Bounding Box & Manhattan Distance for Bouncing Sprite
  // ---------------------------------------------------------------------------
  logic signed [12:0] diff_x;
  logic signed [12:0] diff_y;
  logic [11:0] abs_x;
  logic [11:0] abs_y;
  logic        inside_ball;

  always_comb begin
    diff_x = $signed({1'b0, pixel_x}) - $signed({1'b0, ball_x});
    diff_y = $signed({1'b0, pixel_y}) - $signed({1'b0, ball_y});
    abs_x  = diff_x[12] ? 12'(-diff_x) : 12'(diff_x);
    abs_y  = diff_y[12] ? 12'(-diff_y) : 12'(diff_y);
    inside_ball = ((abs_x * abs_x) + (abs_y * abs_y)) <= (SPRITE_RADIUS * SPRITE_RADIUS);
  end

  // ---------------------------------------------------------------------------
  // Dynamic Background: Moving Color Wave & Grid Patterns
  // ---------------------------------------------------------------------------
  logic [7:0] time_offset;
  assign time_offset = frame_count[7:0];

  logic [7:0] bg_r;
  logic [7:0] bg_g;
  logic [7:0] bg_b;
  logic       grid_line;

  always_comb begin
    // Moving diagonal wave
    bg_r = pixel_x[7:0] + time_offset;
    bg_g = pixel_y[7:0] + (time_offset << 1);
    bg_b = (pixel_x[7:0] ^ pixel_y[7:0]) + time_offset;

    // 64x64 pixel alignment grid
    grid_line = (pixel_x[5:0] == 6'd0) || (pixel_y[5:0] == 6'd0);
  end

  // ---------------------------------------------------------------------------
  // Pixel Compositor
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pixel_r <= 8'd0;
      pixel_g <= 8'd0;
      pixel_b <= 8'd0;
    end else if (pixel_en) begin
      if (!de) begin
        // Blanking intervals must be pure black
        pixel_r <= 8'd0;
        pixel_g <= 8'd0;
        pixel_b <= 8'd0;
      end else if (inside_ball) begin
        // Animated sprite: bright yellow/amber with pulsating core
        pixel_r <= 8'hFF;
        pixel_g <= 8'hD7 + frame_count[4:0];
        pixel_b <= 8'h00;
      end else if (grid_line) begin
        // Clean white grid overlay
        pixel_r <= 8'hE0;
        pixel_g <= 8'hE0;
        pixel_b <= 8'hE0;
      end else begin
        // Moving background gradients
        pixel_r <= bg_r;
        pixel_g <= bg_g;
        pixel_b <= bg_b;
      end
    end
  end

endmodule : pattern_generator_live
