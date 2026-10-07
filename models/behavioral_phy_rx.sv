// =============================================================================
// File: behavioral_phy_rx.sv
// Description: Behavioral Simulation Model of the Analog SerDes PHY Receiver.
//              Models clock/data recovery lock, link training status, and
//              parallel word alignment per §15 of the Reference Manual.
// =============================================================================

`timescale 1ns / 1ps

module behavioral_phy_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        link_active,  // Simulated cable connection

  output logic        phy_locked,   // CDR and PLL locked
  output logic        link_ready    // Link layer training complete
);

  int lock_counter;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lock_counter <= 0;
      phy_locked   <= 1'b0;
      link_ready   <= 1'b0;
    end else if (link_active) begin
      if (lock_counter < 100) begin
        lock_counter <= lock_counter + 1;
        phy_locked   <= 1'b0;
        link_ready   <= 1'b0;
      end else begin
        phy_locked <= 1'b1;
        link_ready <= 1'b1;
      end
    end else begin
      lock_counter <= 0;
      phy_locked   <= 1'b0;
      link_ready   <= 1'b0;
    end
  end

endmodule : behavioral_phy_rx
