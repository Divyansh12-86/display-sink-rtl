// =============================================================================
// File: display_defs.vh
// Description: Synthesizable definitions, enumerations, and structs for
//              display-sink-rtl. Fully compatible with all synthesis tools
//              including Yosys, Quartus, Vivado, and QuestaSim.
// =============================================================================

`ifndef DISPLAY_DEFS_VH
`define DISPLAY_DEFS_VH

// -----------------------------------------------------------------------------
// Enumerations for Display Mode Selection
// -----------------------------------------------------------------------------
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

typedef enum logic [2:0] {
  PAT_COLORBARS = 3'b000, // Standard SMPTE / EBU Multi-Color Bars
  PAT_GRAYSCALE = 3'b001, // Dynamic 0-255 Horizontal Luminance Ramp
  PAT_GEOMETRY  = 3'b010, // Alignment Grid & Corner Calibration Markers
  PAT_MOTION    = 3'b011, // High-Velocity Animated Target & Smooth Waves
  PAT_VIDEO1    = 3'b100, // Custom External User Video 1 (from media/video1/)
  PAT_VIDEO2    = 3'b101  // Custom External User Video 2 (from media/video2/)
} pattern_mode_e;

// -----------------------------------------------------------------------------
// Timing Parameter Record Struct
// -----------------------------------------------------------------------------
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

`endif // DISPLAY_DEFS_VH
