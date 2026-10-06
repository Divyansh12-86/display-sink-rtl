// =============================================================================
// File: display_pkg.sv
// Description: Package defining display resolution modes, refresh rates,
//              timing parameters (CTA-861 / VESA DMT), and common structs.
// =============================================================================

`ifndef DISPLAY_PKG_SV
`define DISPLAY_PKG_SV

`timescale 1ns / 1ps

package display_pkg;

  // ---------------------------------------------------------------------------
  // Enumerations for Mode Selection
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    RES_480P  = 2'b00,  // 640  x 480
    RES_720P  = 2'b01,  // 1280 x 720
    RES_1080P = 2'b10   // 1920 x 1080
  } res_mode_e;

  typedef enum logic [1:0] {
    RATE_24HZ = 2'b00,
    RATE_30HZ = 2'b01,
    RATE_45HZ = 2'b10,
    RATE_60HZ = 2'b11
  } rate_mode_e;

  // ---------------------------------------------------------------------------
  // Timing Parameter Record Struct
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [11:0] h_active;
    logic [11:0] h_front;
    logic [11:0] h_sync;
    logic [11:0] h_back;
    logic [11:0] h_total;

    logic [11:0] v_active;
    logic [11:0] v_front;
    logic [11:0] v_sync;
    logic [11:0] v_back;
    logic [11:0] v_total;

    // Fractional clock enable rate step for Fsys = 150.000 MHz
    // Acc[31:0] += rate_step; pixel_en = carry_out
    // rate_step = round((F_pixel / 150_000_000) * 2^32)
    logic [31:0] rate_step;
  } timing_params_t;

  // ---------------------------------------------------------------------------
  // Standard Timing Look-Up Function
  // ---------------------------------------------------------------------------
  function automatic timing_params_t get_timing(input res_mode_e res, input rate_mode_e rate);
    timing_params_t p;
    case (res)
      RES_480P: begin
        p.h_active = 12'd640;
        p.h_front  = 12'd16;
        p.h_sync   = 12'd96;
        p.h_back   = 12'd48;
        p.h_total  = 12'd800;

        p.v_active = 12'd480;
        p.v_front  = 12'd10;
        p.v_sync   = 12'd2;
        p.v_back   = 12'd33;
        p.v_total  = 12'd525;

        // Fsys = 150 MHz
        case (rate)
          RATE_24HZ: p.rate_step = 32'd288597405;  // 10.080 MHz -> (10.08 / 150) * 2^32
          RATE_30HZ: p.rate_step = 32'd360746757;  // 12.600 MHz -> (12.60 / 150) * 2^32
          RATE_45HZ: p.rate_step = 32'd541120135;  // 18.900 MHz -> (18.90 / 150) * 2^32
          RATE_60HZ: p.rate_step = 32'd721493514;  // 25.200 MHz -> (25.20 / 150) * 2^32
          default:   p.rate_step = 32'd721493514;
        endcase
      end

      RES_720P: begin
        p.h_active = 12'd1280;
        p.h_front  = 12'd110;
        p.h_sync   = 12'd40;
        p.h_back   = 12'd220;
        p.h_total  = 12'd1650;

        p.v_active = 12'd720;
        p.v_front  = 12'd5;
        p.v_sync   = 12'd5;
        p.v_back   = 12'd20;
        p.v_total  = 12'd750;

        case (rate)
          RATE_24HZ: p.rate_step = 32'd850332354;   // 29.700 MHz
          RATE_30HZ: p.rate_step = 32'd1062915443;  // 37.125 MHz
          RATE_45HZ: p.rate_step = 32'd1594373164;  // 55.688 MHz
          RATE_60HZ: p.rate_step = 32'd2125830886;  // 74.250 MHz
          default:   p.rate_step = 32'd2125830886;
        endcase
      end

      RES_1080P: begin
        p.h_active = 12'd1920;
        p.h_front  = 12'd88;
        p.h_sync   = 12'd44;
        p.h_back   = 12'd148;
        p.h_total  = 12'd2200;

        p.v_active = 12'd1080;
        p.v_front  = 12'd4;
        p.v_sync   = 12'd5;
        p.v_back   = 12'd36;
        p.v_total  = 12'd1125;

        case (rate)
          RATE_24HZ: p.rate_step = 32'd1700664709;  // 59.400 MHz
          RATE_30HZ: p.rate_step = 32'd2125830886;  // 74.250 MHz
          RATE_45HZ: p.rate_step = 32'd3188746329;  // 111.375 MHz
          RATE_60HZ: p.rate_step = 32'd4251661772;  // 148.500 MHz
          default:   p.rate_step = 32'd4251661772;
        endcase
      end

      default: begin
        // Fallback to 1080p60
        p.h_active = 12'd1920;
        p.h_front  = 12'd88;
        p.h_sync   = 12'd44;
        p.h_back   = 12'd148;
        p.h_total  = 12'd2200;

        p.v_active = 12'd1080;
        p.v_front  = 12'd4;
        p.v_sync   = 12'd5;
        p.v_back   = 12'd36;
        p.v_total  = 12'd1125;
        p.rate_step = 32'd4251661772;
      end
    endcase
    return p;
  endfunction

endpackage : display_pkg

`endif // DISPLAY_PKG_SV
