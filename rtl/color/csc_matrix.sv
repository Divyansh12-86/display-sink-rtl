// =============================================================================
// File: csc_matrix.sv
// Description: Color Space Conversion (CSC) Matrix Multiplier.
//              Converts studio YCbCr (BT.709) into standard linear RGB:
//                R = 1.164 * (Y - 16) + 1.793 * (Cr - 128)
//                G = 1.164 * (Y - 16) - 0.534 * (Cr - 128) - 0.213 * (Cb - 128)
//                B = 1.164 * (Y - 16) + 2.115 * (Cb - 128)
//              Uses Q8.8 fixed-point arithmetic with overflow/underflow clamping.
//              Supports direct RGB passthrough when csc_enable is low.
// =============================================================================

`timescale 1ns / 1ps

module csc_matrix (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  input  logic        csc_enable,   // 0 = RGB Bypass, 1 = YCbCr -> RGB

  // Input Stream
  input  logic [7:0]  in_c0,        // Y  or R
  input  logic [7:0]  in_c1,        // Cb or G
  input  logic [7:0]  in_c2,        // Cr or B
  input  logic        in_de,
  input  logic        in_hsync,
  input  logic        in_vsync,

  // Output Stream
  output logic [7:0]  out_r,
  output logic [7:0]  out_g,
  output logic [7:0]  out_b,
  output logic        out_de,
  output logic        out_hsync,
  output logic        out_vsync
);

  // Q8.8 Fixed-point coefficients (Value * 256)
  // (255 / (235 - 16)) * 256 = (255 / 219) * 256 = 1.16438 * 256 = 299
  localparam signed [15:0] C_Y_COEFF  = 16'sd299;
  localparam signed [15:0] C_R_CR     = 16'sd459;
  localparam signed [15:0] C_G_CR     = 16'sd137;
  localparam signed [15:0] C_G_CB     = 16'sd55;
  localparam signed [15:0] C_B_CB     = 16'sd541;

  // Pipeline Stage 1: Offset subtraction
  logic signed [15:0] y_sub;
  logic signed [15:0] cb_sub;
  logic signed [15:0] cr_sub;

  logic        de_p1, hsync_p1, vsync_p1;
  logic        csc_en_p1;
  logic [7:0]  c0_p1, c1_p1, c2_p1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      y_sub     <= '0;
      cb_sub    <= '0;
      cr_sub    <= '0;
      de_p1     <= 1'b0;
      hsync_p1  <= 1'b0;
      vsync_p1  <= 1'b0;
      csc_en_p1 <= 1'b0;
      c0_p1     <= '0;
      c1_p1     <= '0;
      c2_p1     <= '0;
    end else if (enable) begin
      de_p1     <= in_de;
      hsync_p1  <= in_hsync;
      vsync_p1  <= in_vsync;
      csc_en_p1 <= csc_enable;
      c0_p1     <= in_c0;
      c1_p1     <= in_c1;
      c2_p1     <= in_c2;

      // Low-power operand isolation: gate inputs when csc_enable is inactive
      if (csc_enable) begin
        y_sub  <= $signed({8'd0, in_c0}) - 16'sd16;
        cb_sub <= $signed({8'd0, in_c1}) - 16'sd128;
        cr_sub <= $signed({8'd0, in_c2}) - 16'sd128;
      end else begin
        y_sub  <= '0;
        cb_sub <= '0;
        cr_sub <= '0;
      end
    end
  end

  // Pipeline Stage 2: Matrix Multiplications & Accumulations
  logic signed [31:0] r_mult, g_mult, b_mult;
  logic        de_p2, hsync_p2, vsync_p2;
  logic        csc_en_p2;
  logic [7:0]  c0_p2, c1_p2, c2_p2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_mult    <= '0;
      g_mult    <= '0;
      b_mult    <= '0;
      de_p2     <= 1'b0;
      hsync_p2  <= 1'b0;
      vsync_p2  <= 1'b0;
      csc_en_p2 <= 1'b0;
      c0_p2     <= '0;
      c1_p2     <= '0;
      c2_p2     <= '0;
    end else if (enable) begin
      de_p2     <= de_p1;
      hsync_p2  <= hsync_p1;
      vsync_p2  <= vsync_p1;
      csc_en_p2 <= csc_en_p1;
      c0_p2     <= c0_p1;
      c1_p2     <= c1_p1;
      c2_p2     <= c2_p1;

      // Low-power operand isolation: gate multipliers when csc is disabled
      if (csc_en_p1) begin
        r_mult <= (y_sub * C_Y_COEFF) + (cr_sub * C_R_CR);
        g_mult <= (y_sub * C_Y_COEFF) - (cr_sub * C_G_CR) - (cb_sub * C_G_CB);
        b_mult <= (y_sub * C_Y_COEFF) + (cb_sub * C_B_CB);
      end else begin
        r_mult <= '0;
        g_mult <= '0;
        b_mult <= '0;
      end
    end
  end

  // Pipeline Stage 3: Clamping & Output Assignment
  function automatic logic [7:0] clamp_q8(input signed [31:0] val);
    logic signed [15:0] shifted;
    begin
      shifted = val >>> 8; // Divide by 256
      if (shifted < 16'sd0)
        clamp_q8 = 8'h00;
      else if (shifted > 16'sd255)
        clamp_q8 = 8'hFF;
      else
        clamp_q8 = shifted[7:0];
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_r     <= 8'd0;
      out_g     <= 8'd0;
      out_b     <= 8'd0;
      out_de    <= 1'b0;
      out_hsync <= 1'b0;
      out_vsync <= 1'b0;
    end else if (enable) begin
      out_de    <= de_p2;
      out_hsync <= hsync_p2;
      out_vsync <= vsync_p2;

      if (!csc_en_p2) begin
        // RGB Passthrough mode
        out_r <= c0_p2;
        out_g <= c1_p2;
        out_b <= c2_p2;
      end else begin
        // Clamped converted RGB
        out_r <= clamp_q8(r_mult);
        out_g <= clamp_q8(g_mult);
        out_b <= clamp_q8(b_mult);
      end
    end
  end

endmodule : csc_matrix
