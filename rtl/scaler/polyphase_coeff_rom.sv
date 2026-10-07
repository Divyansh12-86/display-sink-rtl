// =============================================================================
// File: polyphase_coeff_rom.sv
// Description: Polyphase FIR filter coefficient ROM for 2D spatial scaling.
//              Provides 16 sub-pixel phases with 4-tap Catmull-Rom spline
//              weights. Coefficients sum to 256 (Q8 fixed-point unity gain).
// =============================================================================

`timescale 1ns / 1ps

module polyphase_coeff_rom (
  input  logic [3:0] phase,     // Sub-pixel fractional phase (0 to 15)
  output logic [8:0] coeff_0,   // Signed/unsigned Q8 weight for tap 0 (x-1)
  output logic [8:0] coeff_1,   // Weight for tap 1 (x0)
  output logic [8:0] coeff_2,   // Weight for tap 2 (x1)
  output logic [8:0] coeff_3    // Weight for tap 3 (x2)
);

  // Normalized Catmull-Rom cubic spline weights scaled by 256
  always_comb begin
    case (phase)
      4'd0:  begin coeff_0 = 9'd0;   coeff_1 = 9'd256; coeff_2 = 9'd0;   coeff_3 = 9'd0;   end
      4'd1:  begin coeff_0 = 9'd0;   coeff_1 = 9'd240; coeff_2 = 9'd16;  coeff_3 = 9'd0;   end
      4'd2:  begin coeff_0 = 9'd0;   coeff_1 = 9'd224; coeff_2 = 9'd32;  coeff_3 = 9'd0;   end
      4'd3:  begin coeff_0 = 9'd1;   coeff_1 = 9'd207; coeff_2 = 9'd48;  coeff_3 = 9'd0;   end
      4'd4:  begin coeff_0 = 9'd2;   coeff_1 = 9'd190; coeff_2 = 9'd64;  coeff_3 = 9'd0;   end
      4'd5:  begin coeff_0 = 9'd3;   coeff_1 = 9'd173; coeff_2 = 9'd80;  coeff_3 = 9'd0;   end
      4'd6:  begin coeff_0 = 9'd4;   coeff_1 = 9'd156; coeff_2 = 9'd96;  coeff_3 = 9'd0;   end
      4'd7:  begin coeff_0 = 9'd5;   coeff_1 = 9'd139; coeff_2 = 9'd112; coeff_3 = 9'd0;   end
      4'd8:  begin coeff_0 = 9'd6;   coeff_1 = 9'd122; coeff_2 = 9'd122; coeff_3 = 9'd6;   end
      4'd9:  begin coeff_0 = 9'd0;   coeff_1 = 9'd112; coeff_2 = 9'd139; coeff_3 = 9'd5;   end
      4'd10: begin coeff_0 = 9'd0;   coeff_1 = 9'd96;  coeff_2 = 9'd156; coeff_3 = 9'd4;   end
      4'd11: begin coeff_0 = 9'd0;   coeff_1 = 9'd80;  coeff_2 = 9'd173; coeff_3 = 9'd3;   end
      4'd12: begin coeff_0 = 9'd0;   coeff_1 = 9'd64;  coeff_2 = 9'd190; coeff_3 = 9'd2;   end
      4'd13: begin coeff_0 = 9'd0;   coeff_1 = 9'd48;  coeff_2 = 9'd207; coeff_3 = 9'd1;   end
      4'd14: begin coeff_0 = 9'd0;   coeff_1 = 9'd32;  coeff_2 = 9'd224; coeff_3 = 9'd0;   end
      4'd15: begin coeff_0 = 9'd0;   coeff_1 = 9'd16;  coeff_2 = 9'd240; coeff_3 = 9'd0;   end
      default: begin coeff_0 = 9'd0; coeff_1 = 9'd256; coeff_2 = 9'd0;   coeff_3 = 9'd0;   end
    endcase
  end

endmodule : polyphase_coeff_rom
