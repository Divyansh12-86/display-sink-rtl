// =============================================================================
// File: tb_csr.sv
// Description: Comprehensive Self-Checking Testbench for SoC APB CSR Subsystem.
//              Verifies:
//                1. Power-on reset default values
//                2. Control register read/write integrity across all fields
//                3. Color pipeline configuration read/write
//                4. Status telemetry reflection (X/Y coordinates & frame counter)
//                5. Hardware VSync edge interrupt generation
//                6. Interrupt masking via IRQ_EN
//                7. Write-1-to-Clear (W1C) interrupt clearing
//                8. Out-of-bounds address decoding (0xDEADBEEF)
// =============================================================================

`timescale 1ns / 1ps

import display_pkg::*;

module tb_csr;

  // Clock & Reset
  logic        pclk;
  logic        presetn;

  // APB Bus
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  // Hardware Interface
  logic [11:0] stat_pixel_x;
  logic [11:0] stat_pixel_y;
  logic [31:0] stat_frame_count;
  logic        stat_vsync;

  // Pipeline Config Outputs
  logic          cfg_enable;
  res_mode_e     cfg_res_mode;
  res_mode_e     cfg_src_res_mode;
  rate_mode_e    cfg_rate_mode;
  pattern_mode_e cfg_pat_mode;
  logic          cfg_ext_video_sel;
  logic          cfg_fast_sim_en;
  logic          cfg_csc_enable;
  logic [1:0]    cfg_gamma_mode;
  logic          cfg_dither_enable;
  logic          irq;

  // Register Offsets
  localparam logic [11:0] ADDR_CTRL      = 12'h000;
  localparam logic [11:0] ADDR_COLOR     = 12'h004;
  localparam logic [11:0] ADDR_STATUS    = 12'h008;
  localparam logic [11:0] ADDR_FRAME_CNT = 12'h00C;
  localparam logic [11:0] ADDR_IRQ_EN    = 12'h010;
  localparam logic [11:0] ADDR_IRQ_STAT  = 12'h014;

  // DUT Instantiation
  display_sink_csr u_csr (
    .pclk              (pclk),
    .presetn           (presetn),
    .psel              (psel),
    .penable           (penable),
    .pwrite            (pwrite),
    .paddr             (paddr),
    .pwdata            (pwdata),
    .prdata            (prdata),
    .pready            (pready),
    .pslverr           (pslverr),
    .stat_pixel_x      (stat_pixel_x),
    .stat_pixel_y      (stat_pixel_y),
    .stat_frame_count  (stat_frame_count),
    .stat_vsync        (stat_vsync),
    .cfg_enable        (cfg_enable),
    .cfg_res_mode      (cfg_res_mode),
    .cfg_src_res_mode  (cfg_src_res_mode),
    .cfg_rate_mode     (cfg_rate_mode),
    .cfg_pat_mode      (cfg_pat_mode),
    .cfg_ext_video_sel (cfg_ext_video_sel),
    .cfg_fast_sim_en   (cfg_fast_sim_en),
    .cfg_csc_enable    (cfg_csc_enable),
    .cfg_gamma_mode    (cfg_gamma_mode),
    .cfg_dither_enable (cfg_dither_enable),
    .irq               (irq)
  );

  // Clock Generation: 100 MHz APB Bus
  initial pclk = 0;
  always #5 pclk = ~pclk;

  // APB Transaction Tasks
  task apb_write_reg(input logic [11:0] addr, input logic [31:0] data);
    @(posedge pclk);
    psel    <= 1'b1;
    penable <= 1'b0;
    pwrite  <= 1'b1;
    paddr   <= addr;
    pwdata  <= data;
    @(posedge pclk);
    penable <= 1'b1;
    @(posedge pclk);
    psel    <= 1'b0;
    penable <= 1'b0;
    pwrite  <= 1'b0;
  endtask

  task apb_read_reg(input logic [11:0] addr, output logic [31:0] data);
    @(posedge pclk);
    psel    <= 1'b1;
    penable <= 1'b0;
    pwrite  <= 1'b0;
    paddr   <= addr;
    @(posedge pclk);
    penable <= 1'b1;
    @(posedge pclk);
    data    = prdata;
    psel    <= 1'b0;
    penable <= 1'b0;
  endtask

  logic [31:0] read_val;

  initial begin
    $display("================================================================");
    $display("[TB_CSR] Starting SoC APB CSR Self-Checking Test Suite");
    $display("================================================================");

    // Initial bus state
    presetn          = 1'b0;
    psel             = 1'b0;
    penable          = 1'b0;
    pwrite           = 1'b0;
    paddr            = '0;
    pwdata           = '0;
    stat_pixel_x     = 12'd100;
    stat_pixel_y     = 12'd200;
    stat_frame_count = 32'd42;
    stat_vsync       = 1'b0;

    #20;
    presetn = 1'b1;
    #20;

    // -------------------------------------------------------------------------
    // Test 1: Reset Default Values
    // -------------------------------------------------------------------------
    $display("[TB_CSR] >> Test 1: Power-on Reset Defaults");
    apb_read_reg(ADDR_CTRL, read_val);
    // Expected: {src_res=10, fast_sim=0, ext_sel=0, pat=000, rate=11, res=10, enable=1} = 0x89D
    if (read_val[11:0] !== 12'b10_0_0_000_11_10_1) begin
      $fatal(1, "[TB_CSR] MISMATCH: ADDR_CTRL reset expected 12'b100000011101, got %b", read_val[11:0]);
    end
    assert(cfg_enable == 1'b1 && cfg_res_mode == RES_1080P && cfg_rate_mode == RATE_60HZ)
      else $fatal(1, "[TB_CSR] Pipeline outputs did not reflect reset defaults!");
    $display("[TB_CSR]    [PASS] ADDR_CTRL default verified (0x%03h)", read_val[11:0]);

    apb_read_reg(ADDR_COLOR, read_val);
    if (read_val !== 32'h0)
      $fatal(1, "[TB_CSR] MISMATCH: ADDR_COLOR reset expected 0, got 0x%08h", read_val);
    $display("[TB_CSR]    [PASS] ADDR_COLOR default verified (0x0)");

    // -------------------------------------------------------------------------
    // Test 2: Control Register RW Integrity
    // -------------------------------------------------------------------------
    $display("[TB_CSR] >> Test 2: Control Register R/W");
    // Write 720p output, 480p input, 30Hz, Pattern 2, ext_sel=1, fast_sim=1, enable=1
    // {src_res=00, fast_sim=1, ext_sel=1, pat=010, rate=01, res=01, enable=1}
    // bits: [11:10]=00, [9]=1, [8]=1, [7:5]=010, [4:3]=01, [2:1]=01, [0]=1
    // = 12'b00_1_1_010_01_01_1 = 12'b0011_0100_1011 = 0x34B
    apb_write_reg(ADDR_CTRL, 32'h0000_034B);
    apb_read_reg(ADDR_CTRL, read_val);
    if (read_val[11:0] !== 12'h34B)
      $fatal(1, "[TB_CSR] MISMATCH: ADDR_CTRL wrote 0x34B, read 0x%03h", read_val[11:0]);

    assert(cfg_enable == 1'b1 &&
           cfg_res_mode == RES_720P &&
           cfg_rate_mode == RATE_30HZ &&
           cfg_pat_mode == PAT_GEOMETRY &&
           cfg_ext_video_sel == 1'b1 &&
           cfg_fast_sim_en == 1'b1 &&
           cfg_src_res_mode == RES_480P)
      else $fatal(1, "[TB_CSR] Pipeline outputs failed to update from CSR!");
    $display("[TB_CSR]    [PASS] Full field write-read and hardware output drive verified!");

    // -------------------------------------------------------------------------
    // Test 3: Color Pipeline Config RW
    // -------------------------------------------------------------------------
    $display("[TB_CSR] >> Test 3: Color Pipeline Register R/W");
    // Enable CSC=1, Gamma=sRGB (2'b10), Dither=1 -> bits [3:0] = 4'b1101 = 0xD
    apb_write_reg(ADDR_COLOR, 32'h0000_000D);
    apb_read_reg(ADDR_COLOR, read_val);
    if (read_val[3:0] !== 4'hD)
      $fatal(1, "[TB_CSR] MISMATCH: ADDR_COLOR wrote 0xD, read 0x%01h", read_val[3:0]);

    assert(cfg_csc_enable == 1'b1 && cfg_gamma_mode == 2'b10 && cfg_dither_enable == 1'b1)
      else $fatal(1, "[TB_CSR] Color outputs failed to reflect CSR configuration!");
    $display("[TB_CSR]    [PASS] CSC, Gamma, and Dither register fields verified!");

    // -------------------------------------------------------------------------
    // Test 4: Live Telemetry Status Registers
    // -------------------------------------------------------------------------
    $display("[TB_CSR] >> Test 4: Hardware Telemetry Readback");
    stat_pixel_x     = 12'd1920;
    stat_pixel_y     = 12'd1080;
    stat_frame_count = 32'h0000_1234;
    #10;

    apb_read_reg(ADDR_STATUS, read_val);
    if (read_val !== {4'd0, 12'd1080, 4'd0, 12'd1920})
      $fatal(1, "[TB_CSR] MISMATCH: ADDR_STATUS expected X=1920, Y=1080, got 0x%08h", read_val);

    apb_read_reg(ADDR_FRAME_CNT, read_val);
    if (read_val !== 32'h0000_1234)
      $fatal(1, "[TB_CSR] MISMATCH: ADDR_FRAME_CNT expected 0x1234, got 0x%08h", read_val);
    $display("[TB_CSR]    [PASS] Live raster coordinates and 32-bit frame counter verified!");

    // -------------------------------------------------------------------------
    // Test 5: Interrupt Generation & W1C Handling
    // -------------------------------------------------------------------------
    $display("[TB_CSR] >> Test 5: VSync Interrupt Masking & W1C");
    // 1. Initial IRQ should be low
    assert(irq == 1'b0) else $fatal(1, "[TB_CSR] IRQ unexpectedly high at start!");

    // 2. Pulse VSync while IRQ_EN = 0
    @(posedge pclk);
    stat_vsync <= 1'b1;
    repeat (3) @(posedge pclk);
    stat_vsync <= 1'b0;
    @(posedge pclk);

    // Status bit should be set, but IRQ remains 0 because IRQ_EN is 0
    apb_read_reg(ADDR_IRQ_STAT, read_val);
    if (read_val[0] !== 1'b1)
      $fatal(1, "[TB_CSR] IRQ_STAT did not latch VSync edge!");
    assert(irq == 1'b0) else $fatal(1, "[TB_CSR] IRQ asserted while unmasked!");
    $display("[TB_CSR]    [PASS] VSync edge latched and properly masked by IRQ_EN!");

    // 3. Enable VSync IRQ
    apb_write_reg(ADDR_IRQ_EN, 32'h1);
    #5;
    assert(irq == 1'b1) else $fatal(1, "[TB_CSR] IRQ failed to assert after unmasking!");
    $display("[TB_CSR]    [PASS] IRQ line asserted when unmasked!");

    // 4. Clear VSync IRQ via Write-1-to-Clear (W1C)
    apb_write_reg(ADDR_IRQ_STAT, 32'h1);
    #5;
    assert(irq == 1'b0) else $fatal(1, "[TB_CSR] IRQ failed to deassert after W1C clear!");
    apb_read_reg(ADDR_IRQ_STAT, read_val);
    if (read_val[0] !== 1'b0)
      $fatal(1, "[TB_CSR] IRQ_STAT bit 0 failed to clear after W1C!");
    $display("[TB_CSR]    [PASS] W1C clear mechanism verified!");

    // -------------------------------------------------------------------------
    // Test 6: Unmapped Address Protection
    // -------------------------------------------------------------------------
    $display("[TB_CSR] >> Test 6: Unmapped Bus Address Decoding");
    apb_read_reg(12'hABC, read_val);
    if (read_val !== 32'hDEAD_BEEF)
      $fatal(1, "[TB_CSR] MISMATCH: Expected 0xDEADBEEF for unmapped address, got 0x%08h", read_val);
    $display("[TB_CSR]    [PASS] 0xDEADBEEF bus bus-fault response verified!");

    $display("================================================================");
    $display("[TB_CSR] ALL SoC CSR TESTS PASSED SUCCESSFULLY (0 errors)!");
    $display("================================================================");
    $finish;
  end

endmodule : tb_csr
