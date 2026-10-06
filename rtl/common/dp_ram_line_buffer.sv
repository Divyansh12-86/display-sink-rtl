// =============================================================================
// File: dp_ram_line_buffer.sv
// Description: Synthesizable Dual-Port RAM Line Buffer.
//              Allows simultaneous write of incoming scanline pixels while
//              reading horizontally/vertically aligned pixels for scaling.
// =============================================================================

`timescale 1ns / 1ps

module dp_ram_line_buffer #(
  parameter int DATA_WIDTH = 24,    // RGB888
  parameter int MAX_WIDTH  = 2048   // Supports up to 1080p (1920 active)
)(
  input  logic                            clk,
  // Port A: Write Interface
  input  logic                            we_a,
  input  logic [$clog2(MAX_WIDTH)-1:0]    addr_a,
  input  logic [DATA_WIDTH-1:0]           wdata_a,

  // Port B: Read Interface
  input  logic                            re_b,
  input  logic [$clog2(MAX_WIDTH)-1:0]    addr_b,
  output logic [DATA_WIDTH-1:0]           rdata_b
);

  // Inferred dual-port block RAM
  (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:MAX_WIDTH-1];

  // Port A - Synchronous Write
  always_ff @(posedge clk) begin
    if (we_a) begin
      mem[addr_a] <= wdata_a;
    end
  end

  // Port B - Synchronous Read
  always_ff @(posedge clk) begin
    if (re_b) begin
      rdata_b <= mem[addr_b];
    end
  end

endmodule : dp_ram_line_buffer
