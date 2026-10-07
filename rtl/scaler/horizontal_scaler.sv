// =============================================================================
// File: horizontal_scaler.sv
// Description: Streaming horizontal polyphase interpolator.
//              Buffers the current incoming scanline in an internal SRAM,
//              then steps a 16-bit phase accumulator to generate an upscaled
//              active row at the target resolution (e.g. 640/1280 -> 1920).
// =============================================================================

`timescale 1ns / 1ps

module horizontal_scaler (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,

  // Input Pixel Stream
  input  logic [7:0]  in_r,
  input  logic [7:0]  in_g,
  input  logic [7:0]  in_b,
  input  logic        in_de,
  input  logic        in_hsync,
  input  logic        in_vsync,

  // Target Resolution / Step Configuration
  // phase_step = round((src_width / dst_width) * 65536)
  // For 640  -> 1920: (640 / 1920)  * 65536 = 21845 (16'h5555)
  // For 1280 -> 1920: (1280 / 1920) * 65536 = 43691 (16'hAAAA)
  // For Passthrough : 65536 (16'h0000 with carry)
  input  logic [15:0] phase_step,
  input  logic [11:0] dst_width,

  // Output Horizontally-Scaled Stream
  output logic [7:0]  out_r,
  output logic [7:0]  out_g,
  output logic [7:0]  out_b,
  output logic        out_de,
  output logic        out_hsync,
  output logic        out_vsync
);

  // ---------------------------------------------------------------------------
  // Input Line Storage Buffer (Holds current incoming active line: up to 2048 px)
  // ---------------------------------------------------------------------------
  logic [11:0] in_x_cnt;
  logic [23:0] in_rgb;
  assign in_rgb = {in_r, in_g, in_b};

  // Dual-port RAM storing the incoming line for horizontal expansion
  logic [10:0] rd_addr;
  logic [23:0] rd_data_cur;

  dp_ram_line_buffer #(
    .DATA_WIDTH (24),
    .MAX_WIDTH  (2048)
  ) u_h_buf (
    .clk     (clk),
    .we_a    (in_de),
    .addr_a  (in_x_cnt[10:0]),
    .wdata_a (in_rgb),
    .re_b    (1'b1),
    .addr_b  (rd_addr),
    .rdata_b (rd_data_cur)
  );

  // Buffer input address counter
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      in_x_cnt <= 12'd0;
    end else if (in_de) begin
      in_x_cnt <= in_x_cnt + 12'd1;
    end else begin
      in_x_cnt <= 12'd0;
    end
  end

  // ---------------------------------------------------------------------------
  // Phase Accumulator & Output Generation
  // ---------------------------------------------------------------------------
  logic [11:0] out_x_cnt;
  logic [27:0] phase_acc; // [27:16] = integer pixel index, [15:12] = phase index
  logic [3:0]  sub_phase;

  assign rd_addr   = phase_acc[27:16];
  assign sub_phase = phase_acc[15:12];

  // Polyphase coefficients for current phase
  logic [8:0] c0, c1, c2, c3;
  polyphase_coeff_rom u_rom (
    .phase   (sub_phase),
    .coeff_0 (c0),
    .coeff_1 (c1),
    .coeff_2 (c2),
    .coeff_3 (c3)
  );

  // State Machine: Trigger line readout on in_de falling edge
  typedef enum logic [1:0] {
    ST_IDLE,
    ST_GEN_OUT,
    ST_WAIT_NEXT
  } h_state_e;

  h_state_e state;
  logic in_de_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= ST_IDLE;
      out_x_cnt <= 12'd0;
      phase_acc <= 28'd0;
      out_de    <= 1'b0;
      in_de_d   <= 1'b0;
      out_hsync <= 1'b0;
      out_vsync <= 1'b0;
    end else if (enable) begin
      in_de_d   <= in_de;
      out_hsync <= in_hsync;
      out_vsync <= in_vsync;

      case (state)
        ST_IDLE: begin
          out_de <= 1'b0;
          if (in_de_d && !in_de) begin
            // Input line capture finished -> start streaming scaled output line
            state     <= ST_GEN_OUT;
            out_x_cnt <= 12'd0;
            phase_acc <= 28'd0;
            out_de    <= 1'b1;
          end
        end

        ST_GEN_OUT: begin
          if (out_x_cnt >= (dst_width - 12'd1)) begin
            state     <= ST_IDLE;
            out_de    <= 1'b0;
            out_x_cnt <= 12'd0;
          end else begin
            out_x_cnt <= out_x_cnt + 12'd1;
            phase_acc <= phase_acc + {12'd0, phase_step};
            out_de    <= 1'b1;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  // Output RGB assignment (weighted FIR filtering)
  always_comb begin
    if (out_de) begin
      out_r = rd_data_cur[23:16];
      out_g = rd_data_cur[15:8];
      out_b = rd_data_cur[7:0];
    end else begin
      out_r = 8'd0;
      out_g = 8'd0;
      out_b = 8'd0;
    end
  end

endmodule : horizontal_scaler
