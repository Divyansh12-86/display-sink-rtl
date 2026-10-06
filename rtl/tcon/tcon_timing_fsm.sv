// =============================================================================
// File: tcon_timing_fsm.sv
// Description: Multi-resolution, multi-refresh rate T-CON glass timing generator.
//              Generates Row Gate strobes (STV, CPV, OE), Column Source latch (TP/LOAD),
//              and Liquid Crystal Polarity Inversion (POL).
// =============================================================================

`timescale 1ns / 1ps

module tcon_timing_fsm
  import display_pkg::*;
(
  input  logic        clk,          // System Clock (e.g. 150 MHz)
  input  logic        rst_n,        // Active-low asynchronous reset
  input  res_mode_e   res_mode,     // 480p, 720p, 1080p
  input  rate_mode_e  rate_mode,    // 24Hz, 30Hz, 45Hz, 60Hz
  input  logic        enable,       // Global raster enable

  // Pixel Enable & Coordinate Outputs
  output logic        pixel_en,     // Single-cycle fractional clock enable
  output logic [11:0] pixel_x,      // Active horizontal coordinate [0 .. h_active-1]
  output logic [11:0] pixel_y,      // Active vertical coordinate [0 .. v_active-1]
  output logic        de,           // Data Enable (high strictly during active raster)
  output logic        hsync,        // Horizontal sync
  output logic        vsync,        // Vertical sync
  output logic [31:0] frame_count,  // Monotonically increasing frame index

  // Panel Glass Physical Control Strobes (§7.1 of Reference Manual)
  output logic        stv,          // Start Pulse Vertical (Frame start marker to Gate Driver)
  output logic        cpv,          // Clock Pulse Vertical (Row advance clock to Gate Driver)
  output logic        oe,           // Output Enable / Gate Mask (Active during row switching)
  output logic        tp_load,      // Source Driver Line-Latch & DAC Update Strobe
  output logic        pol           // Liquid Crystal Polarity Inversion Clock
);

  // ---------------------------------------------------------------------------
  // Dynamic Timing Parameters
  // ---------------------------------------------------------------------------
  timing_params_t params;
  assign params = get_timing(res_mode, rate_mode);

  // ---------------------------------------------------------------------------
  // Fractional Pixel Rate Accumulator (Fsys = 150.0 MHz)
  // Acc[32] overflow produces a precise single-cycle pixel_en strobe.
  // ---------------------------------------------------------------------------
  logic [32:0] rate_acc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rate_acc <= 33'd0;
      pixel_en <= 1'b0;
    end else if (enable) begin
      rate_acc <= {1'b0, rate_acc[31:0]} + {1'b0, params.rate_step};
      pixel_en <= rate_acc[32];
    end else begin
      rate_acc <= 33'd0;
      pixel_en <= 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Raster Coordinates and Counters
  // ---------------------------------------------------------------------------
  logic [11:0] h_cnt;
  logic [11:0] v_cnt;

  // Boundary comparison signals
  logic h_line_end;
  assign h_line_end = (h_cnt == (params.h_total - 12'd1));

  logic v_frame_end;
  assign v_frame_end = (v_cnt == (params.v_total - 12'd1));

  // Horizontal and Vertical Raster Scan Counter
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      h_cnt       <= 12'd0;
      v_cnt       <= 12'd0;
      frame_count <= 32'd0;
    end else if (enable && pixel_en) begin
      if (h_line_end) begin
        h_cnt <= 12'd0;
        if (v_frame_end) begin
          v_cnt       <= 12'd0;
          frame_count <= frame_count + 32'd1;
        end else begin
          v_cnt <= v_cnt + 12'd1;
        end
      end else begin
        h_cnt <= h_cnt + 12'd1;
      end
    end
  end

  // Active Coordinates & Data Enable
  always_comb begin
    de      = (h_cnt < params.h_active) && (v_cnt < params.v_active);
    pixel_x = de ? h_cnt : 12'd0;
    pixel_y = de ? v_cnt : 12'd0;
  end

  // Standard Hsync / Vsync (Active High convention)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hsync <= 1'b0;
      vsync <= 1'b0;
    end else if (enable && pixel_en) begin
      hsync <= (h_cnt >= (params.h_active + params.h_front)) &&
               (h_cnt <  (params.h_active + params.h_front + params.h_sync));

      vsync <= (v_cnt >= (params.v_active + params.v_front)) &&
               (v_cnt <  (params.v_active + params.v_front + params.v_sync));
    end
  end

  // ---------------------------------------------------------------------------
  // T-CON Glass Physical Control Strobes (§7.1 of Architecture Spec)
  // ---------------------------------------------------------------------------

  // STV: Start Pulse Vertical.
  // Fired during vertical front-porch / start of frame to load '1' into Gate shift register.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stv <= 1'b0;
    end else if (enable && pixel_en) begin
      // Pulse high on the first line of the vertical sync period
      stv <= (v_cnt == (params.v_active + params.v_front)) && (h_cnt < 12'd64);
    end
  end

  // CPV: Clock Pulse Vertical (Row advance clock).
  // Strobe once per horizontal line interval during horizontal blanking.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cpv <= 1'b0;
    end else if (enable && pixel_en) begin
      // Pulse high during middle of horizontal front porch
      cpv <= (h_cnt >= (params.h_active + 12'd4)) &&
             (h_cnt <  (params.h_active + 12'd20));
    end
  end

  // OE: Output Enable / Gate Mask.
  // Must be high (masking gate outputs) during row switching to prevent vertical overlap.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      oe <= 1'b1;
    end else if (enable && pixel_en) begin
      // Mask active row gates during horizontal blanking transitions
      oe <= (h_cnt >= params.h_active) || (v_cnt >= params.v_active);
    end
  end

  // TP_LOAD: Source Driver Line-Latch & DAC Strobe.
  // Fires when a complete row of column data has been shifted into the Source Driver latches.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tp_load <= 1'b0;
    end else if (enable && pixel_en) begin
      // Strobe at the onset of horizontal blanking
      tp_load <= (h_cnt == params.h_active);
    end
  end

  // POL: Liquid Crystal Polarity Inversion Clock.
  // Inverts polarity every horizontal line (Line Inversion) and flips base phase every frame
  // to ensure exactly ZERO net DC voltage across liquid crystal molecules.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pol <= 1'b0;
    end else if (enable && pixel_en) begin
      // Line Inversion with frame phase alternation
      pol <= v_cnt[0] ^ frame_count[0];
    end
  end

endmodule : tcon_timing_fsm
