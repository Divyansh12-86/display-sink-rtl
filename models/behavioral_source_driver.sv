// =============================================================================
// File: behavioral_source_driver.sv
// Description: Behavioral Simulation Model of Column Source Drivers.
//              Models precision R-string DACs mounted on Chip-on-Film (COF).
//              Converts 8-bit digital color words to analog millivolt levels
//              (0V to 16V with ~62.5 mV step size) when tp_load strobes.
// =============================================================================

`timescale 1ns / 1ps

module behavioral_source_driver (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        tp_load,      // Line latch & DAC update strobe
  input  logic        pol,          // Polarity inversion signal
  input  logic [7:0]  pixel_r,
  input  logic [7:0]  pixel_g,
  input  logic [7:0]  pixel_b,

  // Simulated analog output voltages (in millivolts: 0 to 16000 mV)
  output real         v_col_r_mv,
  output real         v_col_g_mv,
  output real         v_col_b_mv
);

  localparam real V_AVDD_MV = 16000.0; // 16.0 V analog rail
  localparam real V_COM_MV  = 8000.0;  // 8.0 V common electrode reference

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      v_col_r_mv <= 0.0;
      v_col_g_mv <= 0.0;
      v_col_b_mv <= 0.0;
    end else if (tp_load) begin
      // Positive or negative drive relative to VCOM based on POL
      if (!pol) begin
        // Positive frame: VCOM to AVDD
        v_col_r_mv <= V_COM_MV + ((real'(pixel_r) / 255.0) * (V_AVDD_MV - V_COM_MV));
        v_col_g_mv <= V_COM_MV + ((real'(pixel_g) / 255.0) * (V_AVDD_MV - V_COM_MV));
        v_col_b_mv <= V_COM_MV + ((real'(pixel_b) / 255.0) * (V_AVDD_MV - V_COM_MV));
      end else begin
        // Negative frame: 0V to VCOM
        v_col_r_mv <= V_COM_MV - ((real'(pixel_r) / 255.0) * V_COM_MV);
        v_col_g_mv <= V_COM_MV - ((real'(pixel_g) / 255.0) * V_COM_MV);
        v_col_b_mv <= V_COM_MV - ((real'(pixel_b) / 255.0) * V_COM_MV);
      end
    end
  end

endmodule : behavioral_source_driver
