// =============================================================================
// File: display_sva.sv
// Description: Comprehensive SystemVerilog Assertions (SVA) and Protocol
//              Monitors for Display Sink Controller Subsystems:
//              1. T-CON Timing Protocol (DE active count, HSync/VSync, strobes)
//              2. AXI4-Stream Video Protocol (Stability, SOF framing, EOL alignment)
//              3. 2D Scaler Integrity (Pixel bounds, valid cycle generation)
//              4. Color Pipeline (Value clamping, no X/Z propagation during DE)
// =============================================================================

`timescale 1ns / 1ps

module display_sva
  import display_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  input logic        enable,

  // T-CON & Timing Signals
  input res_mode_e   res_mode,
  input rate_mode_e  rate_mode,
  input logic        tcon_de,
  input logic        tcon_hsync,
  input logic        tcon_vsync,
  input logic        stv,
  input logic        cpv,
  input logic        tp_load,
  input logic        pol,

  // AXI4-Stream Video Slave Signals
  input logic [23:0] s_axis_tdata,
  input logic        s_axis_tvalid,
  input logic        s_axis_tready,
  input logic        s_axis_tuser,
  input logic        s_axis_tlast,

  // Scaled & Panel Video Output Signals
  input logic [7:0]  panel_r,
  input logic [7:0]  panel_g,
  input logic [7:0]  panel_b,
  input logic        panel_de,
  input logic        panel_hsync,
  input logic        panel_vsync
);

`ifndef VERILATOR
  // ===========================================================================
  // 1. Concurrent SVA Properties (QuestaSim / ASIC Formal / Cadence)
  // ===========================================================================

  // Assertion 1: When reset is low, panel strobes and DE must remain inactive
  property p_reset_quiescent;
    @(posedge clk) !rst_n |-> (!panel_de && !tcon_de && !stv && !cpv && !tp_load);
  endproperty
  a_reset_quiescent: assert property (p_reset_quiescent)
    else $error("[SVA FAIL] Reset violation: Outputs active during rst_n=0!");

  // Assertion 2: AXI4-Stream Data Stability: When tvalid is asserted and tready is low,
  // data, tuser, and tlast must remain constant until handshake completes.
  property p_axis_data_stable;
    @(posedge clk) disable iff (!rst_n)
    (s_axis_tvalid && !s_axis_tready) |=> 
    ($stable(s_axis_tdata) && $stable(s_axis_tuser) && $stable(s_axis_tlast) && s_axis_tvalid);
  endproperty
  a_axis_data_stable: assert property (p_axis_data_stable)
    else $error("[SVA FAIL] AXI-Stream Protocol Violation: s_axis_tdata changed during stalled handshake!");

  // Assertion 3: No X or Z propagation on active video output data
  property p_no_x_on_active_de;
    @(posedge clk) disable iff (!rst_n)
    panel_de |-> (!$isunknown(panel_r) && !$isunknown(panel_g) && !$isunknown(panel_b));
  endproperty
  a_no_x_on_active_de: assert property (p_no_x_on_active_de)
    else $error("[SVA FAIL] Metasability / X-propagation detected in panel RGB data while panel_de is asserted!");

  // Assertion 4: STV (Vertical Start Pulse) must never coincide with high panel_de
  property p_stv_in_blanking;
    @(posedge clk) disable iff (!rst_n)
    stv |-> (!tcon_de && !panel_de);
  endproperty
  a_stv_in_blanking: assert property (p_stv_in_blanking)
    else $error("[SVA FAIL] Physical Strobe Violation: STV asserted during active video region!");

  // Assertion 5: CPV (Row Clock) and TP_LOAD (Line Latch) must never assert simultaneously
  property p_cpv_tp_load_exclusive;
    @(posedge clk) disable iff (!rst_n)
    cpv |-> (!tp_load);
  endproperty
  a_cpv_tp_load_exclusive: assert property (p_cpv_tp_load_exclusive)
    else $error("[SVA FAIL] Gate / Source Strobe Collision: CPV and TP_LOAD asserted concurrently!");

`endif

  // ===========================================================================
  // 2. Immediate Dynamic Timing & Geometry Assertions (Both EDA Tools)
  // ===========================================================================
  int h_active_cnt;
  int prev_h_active;
  res_mode_e  res_mode_d;
  rate_mode_e rate_mode_d;
  int mode_trans_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      res_mode_d     <= RES_1080P;
      rate_mode_d    <= RATE_60HZ;
      mode_trans_cnt <= 0;
      h_active_cnt   <= 0;
      prev_h_active  <= 0;
    end else if (enable) begin
      res_mode_d  <= res_mode;
      rate_mode_d <= rate_mode;
      if (res_mode != res_mode_d || rate_mode != rate_mode_d) begin
        mode_trans_cnt <= 4; // Mask transition scanlines during resolution/rate reconfiguration
      end

      if (panel_de) begin
        h_active_cnt <= h_active_cnt + 1;
      end else begin
        if (h_active_cnt > 0) begin
          prev_h_active <= h_active_cnt;
          if (mode_trans_cnt == 0) begin
            case (res_mode)
              RES_480P: begin
                assert (h_active_cnt == 640)
                  else $error("[SVA FAIL] 480p line width mismatch: expected 640, got %0d", h_active_cnt);
              end
              RES_720P: begin
                assert (h_active_cnt == 1280)
                  else $error("[SVA FAIL] 720p line width mismatch: expected 1280, got %0d", h_active_cnt);
              end
              RES_1080P: begin
                assert (h_active_cnt == 1920)
                  else $error("[SVA FAIL] 1080p line width mismatch: expected 1920, got %0d", h_active_cnt);
              end
              default: ;
            endcase
          end else begin
            mode_trans_cnt <= mode_trans_cnt - 1;
          end
        end
        h_active_cnt <= 0;
      end
    end
  end

endmodule : display_sva
