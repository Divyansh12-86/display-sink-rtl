// =============================================================================
// File: display_sink_csr.sv
// Description: APB3/APB4 Memory-Mapped SoC Control & Status Register (CSR) Subsystem.
//              Provides unified CPU/SoC bus software management for:
//                - Display pipeline enable, resolution, and refresh rate modes
//                - Dynamic 2D spatial scaling source and target resolutions
//                - Pattern generator live motion modes
//                - Color space conversion (CSC), Gamma LUT, and Bayer dithering
//                - Hardware telemetry (live raster coordinate & frame counters)
//                - Edge-triggered VSync and Frame-Complete interrupts with W1C
// =============================================================================

`timescale 1ns / 1ps

`ifdef YOSYS
`include "display_defs.vh"
`endif

module display_sink_csr
`ifndef YOSYS
  import display_pkg::*;
`endif
(
  // SoC APB Slave Interface
  input  logic        pclk,
  input  logic        presetn,
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [11:0] paddr,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,

  // Hardware Status / Telemetry Inputs from Display Sink Pipeline
  input  logic [11:0] stat_pixel_x,
  input  logic [11:0] stat_pixel_y,
  input  logic [31:0] stat_frame_count,
  input  logic        stat_vsync,

  // Hardware Control Outputs to Display Sink Pipeline
  output logic          cfg_enable,
  output res_mode_e     cfg_res_mode,
  output res_mode_e     cfg_src_res_mode,
  output rate_mode_e    cfg_rate_mode,
  output pattern_mode_e cfg_pat_mode,
  output logic          cfg_ext_video_sel,
  output logic          cfg_fast_sim_en,
  output logic          cfg_csc_enable,
  output logic [1:0]    cfg_gamma_mode,
  output logic          cfg_dither_enable,

  // Interrupt Request Line to SoC Interrupt Controller
  output logic        irq
);

  // ---------------------------------------------------------------------------
  // Register Address Offsets
  // ---------------------------------------------------------------------------
  localparam logic [11:0] ADDR_CTRL      = 12'h000; // RW: Master Pipeline Control
  localparam logic [11:0] ADDR_COLOR     = 12'h004; // RW: Color Pipeline Config
  localparam logic [11:0] ADDR_STATUS    = 12'h008; // RO: Current Coordinates
  localparam logic [11:0] ADDR_FRAME_CNT = 12'h00C; // RO: Frame Counter
  localparam logic [11:0] ADDR_IRQ_EN    = 12'h010; // RW: Interrupt Enables
  localparam logic [11:0] ADDR_IRQ_STAT  = 12'h014; // W1C: Interrupt Status

  // ---------------------------------------------------------------------------
  // Internal Configuration Registers (with safe reset defaults)
  // ---------------------------------------------------------------------------
  logic        reg_enable;
  logic [1:0]  reg_res_mode;
  logic [1:0]  reg_src_res_mode;
  logic [1:0]  reg_rate_mode;
  logic [2:0]  reg_pat_mode;
  logic        reg_ext_sel;
  logic        reg_fast_sim_en;

  logic        reg_csc_enable;
  logic [1:0]  reg_gamma_mode;
  logic        reg_dither_enable;

  logic        reg_irq_en_vsync;
  logic        reg_irq_en_framedone;
  logic        reg_irq_stat_vsync;
  logic        reg_irq_stat_framedone;

  // Edge detection for VSync
  logic vsync_d1;
  wire  vsync_posedge = stat_vsync && !vsync_d1;
  wire  vsync_negedge = !stat_vsync && vsync_d1;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      vsync_d1 <= 1'b0;
    end else begin
      vsync_d1 <= stat_vsync;
    end
  end

  // APB Read/Write Cycle Detection
  wire apb_write = psel && penable && pwrite;
  wire apb_read  = psel && !pwrite;

  assign pready  = 1'b1; // Zero wait-state register access
  assign pslverr = 1'b0;

  // ---------------------------------------------------------------------------
  // APB Write Datapath
  // ---------------------------------------------------------------------------
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      reg_enable             <= 1'b1;
      reg_res_mode           <= 2'b10; // RES_1080P default
      reg_src_res_mode       <= 2'b10; // RES_1080P default
      reg_rate_mode          <= 2'b11; // RATE_60HZ default
      reg_pat_mode           <= 3'b000;
      reg_ext_sel            <= 1'b0;
      reg_fast_sim_en        <= 1'b0;

      reg_csc_enable         <= 1'b0;
      reg_gamma_mode         <= 2'b00;
      reg_dither_enable      <= 1'b0;

      reg_irq_en_vsync       <= 1'b0;
      reg_irq_en_framedone   <= 1'b0;
      reg_irq_stat_vsync     <= 1'b0;
      reg_irq_stat_framedone <= 1'b0;
    end else begin
      // Hardware interrupt trigger
      if (vsync_posedge) begin
        reg_irq_stat_vsync <= 1'b1;
      end
      if (vsync_negedge) begin
        reg_irq_stat_framedone <= 1'b1;
      end

      // APB Register Writes
      if (apb_write) begin
        case (paddr[11:0])
          ADDR_CTRL: begin
            reg_enable       <= pwdata[0];
            reg_res_mode     <= pwdata[2:1];
            reg_rate_mode    <= pwdata[4:3];
            reg_pat_mode     <= pwdata[7:5];
            reg_ext_sel      <= pwdata[8];
            reg_fast_sim_en  <= pwdata[9];
            reg_src_res_mode <= pwdata[11:10];
          end

          ADDR_COLOR: begin
            reg_csc_enable    <= pwdata[0];
            reg_gamma_mode    <= pwdata[2:1];
            reg_dither_enable <= pwdata[3];
          end

          ADDR_IRQ_EN: begin
            reg_irq_en_vsync     <= pwdata[0];
            reg_irq_en_framedone <= pwdata[1];
          end

          ADDR_IRQ_STAT: begin
            // Write-1-to-Clear (W1C)
            if (pwdata[0]) reg_irq_stat_vsync     <= 1'b0;
            if (pwdata[1]) reg_irq_stat_framedone <= 1'b0;
          end

          default: ;
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // APB Read Datapath
  // ---------------------------------------------------------------------------
  always_comb begin
    prdata = 32'h0;
    if (apb_read) begin
      case (paddr[11:0])
        ADDR_CTRL: begin
          prdata = {20'd0,
                    reg_src_res_mode,
                    reg_fast_sim_en,
                    reg_ext_sel,
                    reg_pat_mode,
                    reg_rate_mode,
                    reg_res_mode,
                    reg_enable};
        end

        ADDR_COLOR: begin
          prdata = {28'd0,
                    reg_dither_enable,
                    reg_gamma_mode,
                    reg_csc_enable};
        end

        ADDR_STATUS: begin
          prdata = {{4'd0, stat_pixel_y}, {4'd0, stat_pixel_x}};
        end

        ADDR_FRAME_CNT: begin
          prdata = stat_frame_count;
        end

        ADDR_IRQ_EN: begin
          prdata = {30'd0, reg_irq_en_framedone, reg_irq_en_vsync};
        end

        ADDR_IRQ_STAT: begin
          prdata = {30'd0, reg_irq_stat_framedone, reg_irq_stat_vsync};
        end

        default: prdata = 32'hDEAD_BEEF;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Output Signal Drive
  // ---------------------------------------------------------------------------
  assign cfg_enable        = reg_enable;
`ifdef YOSYS
  assign cfg_res_mode      = reg_res_mode;
  assign cfg_src_res_mode  = reg_src_res_mode;
  assign cfg_rate_mode     = reg_rate_mode;
  assign cfg_pat_mode      = reg_pat_mode;
`else
  assign cfg_res_mode      = res_mode_e'(reg_res_mode);
  assign cfg_src_res_mode  = res_mode_e'(reg_src_res_mode);
  assign cfg_rate_mode     = rate_mode_e'(reg_rate_mode);
  assign cfg_pat_mode      = pattern_mode_e'(reg_pat_mode);
`endif
  assign cfg_ext_video_sel = reg_ext_sel;
  assign cfg_fast_sim_en   = reg_fast_sim_en;

  assign cfg_csc_enable    = reg_csc_enable;
  assign cfg_gamma_mode    = reg_gamma_mode;
  assign cfg_dither_enable = reg_dither_enable;

  // Level interrupt line asserted when enabled pending interrupts exist
  assign irq = (reg_irq_stat_vsync && reg_irq_en_vsync) ||
               (reg_irq_stat_framedone && reg_irq_en_framedone);

endmodule : display_sink_csr
