// =============================================================================
// File: behavioral_pmic.sv
// Description: Behavioral Simulation Model of the Display PMIC.
//              Models power rail generation and validates proper sequencing:
//                VDD (3.3V) -> AVDD (15.0V) / VGL (-10.0V) -> VGH (+25.0V)
// =============================================================================

`timescale 1ns / 1ps

module behavioral_pmic (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        power_en,

  output real         v_core_v,     // Digital core logic: 1.2V
  output real         v_dd_v,       // I/O power: 3.3V
  output real         a_vdd_v,      // Column DAC rail: 15.0V
  output real         v_gh_v,       // Gate On rail: +25.0V
  output real         v_gl_v,       // Gate Off rail: -10.0V
  output real         v_com_v,      // Common backplane: +6.5V
  output logic        power_good
);

  int seq_stage;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seq_stage  <= 0;
      v_core_v   <= 0.0;
      v_dd_v     <= 0.0;
      a_vdd_v    <= 0.0;
      v_gh_v     <= 0.0;
      v_gl_v     <= 0.0;
      v_com_v    <= 0.0;
      power_good <= 1'b0;
    end else if (power_en) begin
      if (seq_stage < 50) begin
        seq_stage <= seq_stage + 1;
        // Stage 1: Logic rails
        v_core_v <= 1.2;
        v_dd_v   <= 3.3;
      end else if (seq_stage < 100) begin
        seq_stage <= seq_stage + 1;
        // Stage 2: Analog and negative gate rails
        a_vdd_v <= 15.0;
        v_gl_v  <= -10.0;
        v_com_v <= 6.5;
      end else if (seq_stage < 150) begin
        seq_stage <= seq_stage + 1;
        // Stage 3: High-voltage gate on rail
        v_gh_v <= 25.0;
      end else begin
        power_good <= 1'b1;
      end
    end else begin
      seq_stage  <= 0;
      v_core_v   <= 0.0;
      v_dd_v     <= 0.0;
      a_vdd_v    <= 0.0;
      v_gh_v     <= 0.0;
      v_gl_v     <= 0.0;
      v_com_v    <= 0.0;
      power_good <= 1'b0;
    end
  end

endmodule : behavioral_pmic
