# Display Sink Controller Micro-Architecture Specification

## 1. Overview & Architectural Boundaries

The `display-sink-rtl` subsystem is a production-grade, synthesizable SystemVerilog display processing and timing controller engine designed for modern flat-panel displays and SoC video pipelines. It provides real-time resolution adaptation, refresh rate frequency synthesis, broadcast color space correction, and physical glass timing strobe generation without external frame-buffer DRAM.

```
                                  +-------------------------------------------------------------+
                                  |                 display_sink_top                            |
                                  |                                                             |
+-------------------+             |  +---------------------+                                    |
| SoC APB Bus / CPU |============>|  |  display_sink_csr   | (0x00-0x14 APB Registers)          |
+-------------------+             |  +----------+----------+                                    |
                                  |             | (cfg_*)                                       |
+-------------------+             |  +----------v----------+     +---------------------------+  |
| AXI4-Stream Video |============>|  |    axis_video_rx    |     |  pattern_generator_live   |  |
+-------------------+             |  +----------+----------+     +-------------+-------------+  |
                                  |             | (ext_*)                      | (live_*)       |
                                  |             +--------------+---------------+                |
                                  |                            |                                |
                                  |                     [ Stream Mux ]                          |
                                  |                            |                                |
                                  |             +--------------v---------------+                |
                                  |             |          scaler_top          |                |
                                  |             |  - 4-Tap Catmull-Rom FIR (H) |                |
                                  |             |  - 3-Line Bilinear (V)       |                |
                                  |             +--------------+---------------+                |
                                  |                            |                                |
                                  |             +--------------v---------------+                |
                                  |             |          color_top           |                |
                                  |             |  - BT.709 YCbCr->RGB CSC     |                |
                                  |             |  - 256-Entry Gamma 2.2/sRGB  |                |
                                  |             |  - 2x2 Bayer Temporal Dither |                |
                                  |             +--------------+---------------+                |
                                  |                            |                                |
                                  |  +---------------------+   |                                |
                                  |  |   tcon_timing_fsm   |   |                                |
                                  |  +----------+----------+   |                                |
                                  |             |              |                                |
                                  |             | (strobes)    | (RGB)                          |
                                  +-------------|--------------|--------------------------------+
                                                |              |
                                                v              v
                                        [ Panel Strobes ]  [ Panel RGB ]
                                         STV CPV OE TP POL   R G B DE
```

---

## 2. Clock & Timing Synthesis Subsystem

### 2.1 Single-Clock Glitch-Free Rate Accumulator
To eliminate glitch-prone clock dividers and avoid crossing between asynchronous clock domains, the entire datapath operates on a unified system clock ($F_{\text{sys}} = 150.000\text{ MHz}$).
Pixel clock rates are generated using an exact 32-bit phase accumulator:
$$\text{acc}[31:0] \leftarrow \text{acc}[31:0] + \text{rate\_step}$$
$$\text{pixel\_en} = \text{carry\_out} = (\text{acc} + \text{rate\_step} \ge 2^{32})$$

$$\text{rate\_step} = \text{round}\left(\frac{F_{\text{pixel}}}{150.000\text{ MHz}} \times 2^{32}\right)$$

### 2.2 Exact 12-Mode CTA-861 / VESA Timing Matrix
All timing constants strictly obey CTA-861 and VESA DMT standards:

| Resolution | Native Active | Total Blanked | Refresh | Pixel Clock ($F_{\text{pix}}$) | Exact `rate_step` (Hex) |
|---|---|---|---|---|---|
| **480p** (640x480) | 640 x 480 | 800 x 525 | 24 Hz | 10.080 MHz | `32'h1137_4BC6` |
| **480p** (640x480) | 640 x 480 | 800 x 525 | 30 Hz | 12.600 MHz | `32'h1585_1EB8` |
| **480p** (640x480) | 640 x 480 | 800 x 525 | 45 Hz | 18.900 MHz | `32'h2047_AE14` |
| **480p** (640x480) | 640 x 480 | 800 x 525 | 60 Hz | 25.175 MHz | `32'h2AF1_D97A` |
| **720p** (1280x720) | 1280 x 720 | 1650 x 750 | 24 Hz | 29.700 MHz | `32'h32AE_147A` |
| **720p** (1280x720) | 1280 x 720 | 1650 x 750 | 30 Hz | 37.125 MHz | `32'h3F59_9999` |
| **720p** (1280x720) | 1280 x 720 | 1650 x 750 | 45 Hz | 55.6875 MHz| `32'h5F06_6666` |
| **720p** (1280x720) | 1280 x 720 | 1650 x 750 | 60 Hz | 74.250 MHz | `32'h7EB8_51EB` |
| **1080p** (1920x1080) | 1920 x 1080 | 2200 x 1125 | 24 Hz | 59.400 MHz | `32'h655C_28F5` |
| **1080p** (1920x1080) | 1920 x 1080 | 2200 x 1125 | 30 Hz | 74.250 MHz | `32'h7EB8_51EB` |
| **1080p** (1920x1080) | 1920 x 1080 | 2200 x 1125 | 45 Hz | 111.375 MHz| `32'hBE14_7AE1` |
| **1080p** (1920x1080) | 1920 x 1080 | 2200 x 1125 | 60 Hz | 148.500 MHz| `32'hFD70_A3D7` |

---

## 3. T-CON Timing FSM & Panel Physical Strobes

The Timing Controller (`tcon_timing_fsm.sv`) generates the standard physical driving strobes required by TFT-LCD and AMOLED glass column/gate driver ICs:

1. **`STV` (Start Pulse Vertical):** Asserted for 1 horizontal line period at the beginning of the vertical active raster ($V_{\text{cnt}} = 0$) to load the shift registers of the gate/row driver ICs.
2. **`CPV` (Clock Pulse Vertical):** Row gate clock pulse pulsed once per horizontal scanline during horizontal blanking to step the gate driver to the next scanline.
3. **`OE` (Output Enable):** Gate output enable mask held active during line switching intervals to prevent gate line overlap and inter-row cross-conduction.
4. **`TP_LOAD` (Source Driver Line Latch):** High-speed strobe asserted at the conclusion of every horizontal active line to latch digital column DAC values into internal sample-and-hold buffers.
5. **`POL` (Liquid Crystal Polarity Inversion):** Alternates polarity every frame (or scanline) to prevent irreversible DC polarization damage to liquid crystal molecules.

```
       Line N Active Video                   H-Blanking             Line N+1 Active Video
DE     ---------------------------|____________________________|---------------------------
TP_LOAD                           _____
       __________________________|     |___________________________________________________
CPV                                          _____
       _____________________________________|     |________________________________________
OE     ___________________________             _________________
                                  |___________|                 |__________________________
```

---

## 4. 2D Spatial Scaling Engine (`scaler_top.sv`)

### 4.1 Architecture Overview
The scaler engine provides bidirectional spatial conversion (Upscaling: 480p->1080p, 720p->1080p; Downscaling: 1080p->720p, 1080p->480p) and zero-latency passthrough with zero external DRAM.

```
Input Video --> [ 4-Bank Interleaved Ping-Pong RAM ] --> [ 4-Tap Catmull-Rom FIR (H) ]
                        |
                        v
                [ Circular 3-Line Buffer Array ] --> [ Bilinear Interpolator (V) ] --> Scaled Video
```

### 4.2 Horizontal Scaler: 4-Tap Catmull-Rom FIR Filter
- **Coefficients:** 16-phase signed 10-bit Q8 Catmull-Rom filter weights ($C_0, C_1, C_2, C_3$) with negative side lobes for edge sharpening.
- **Normalized Sum:** $\sum_{i=0}^3 C_i = 256$ exactly across all 16 phases.
- **Memory Architecture:** Dual ping-pong line buffers partitioned into 4 interleaved memory banks ($A_0, A_1, A_2, A_3$) allowing single-cycle simultaneous access to 4 adjacent pixels without memory stalls.
- **Arithmetic Pipeline:**
  $$\text{acc} = C_0 \cdot P_0 + C_1 \cdot P_1 + C_2 \cdot P_2 + C_3 \cdot P_3$$
  $$\text{pixel}_{\text{out}} = \text{clamp}\left(\frac{\text{acc} + 128}{256}, 0, 255\right)$$
- **Latency:** Fixed 4 clock cycles between horizontal phase generation and output validation.

### 4.3 Vertical Scaler: Circular 3-Line Bilinear Interpolator
- **Memory Architecture:** Circular array of 3 dual-port block line buffers storing Lines $K-1$, $K$, and $K+1$.
- **Line State Machine:** Reads adjacent scanlines $Y_0$ and $Y_1$ based on the vertical fractional phase accumulator:
  $$\text{acc}_V = (256 - v_{\text{frac}}) \cdot \text{line}_0 + v_{\text{frac}} \cdot \text{line}_1 + 128$$
  $$\text{line}_{\text{out}} = \text{clamp}\left(\frac{\text{acc}_V}{256}, 0, 255\right)$$

---

## 5. Color & Image Processing Pipeline (`color_top.sv`)

### 5.1 Color Space Conversion (CSC) Matrix
Converts Studio BT.709 YCbCr into standard linear RGB:
$$R = 1.164 \times (Y - 16) + 1.793 \times (Cr - 128)$$
$$G = 1.164 \times (Y - 16) - 0.534 \times (Cr - 128) - 0.213 \times (Cb - 128)$$
$$B = 1.164 \times (Y - 16) + 2.115 \times (Cb - 128)$$
- **Arithmetic:** Q8.8 signed fixed-point multipliers.
- **Low-Power Operand Isolation:** When `csc_enable == 0`, multiplier inputs and offset terms are gated to zero, eliminating dynamic switching power in arithmetic DSP blocks.

### 5.2 256-Entry Exact Gamma 2.2 & sRGB ROMs
- Synthesized combinatorial case functions mapping each 8-bit input to its exact non-linear optical power curve.
- **Gamma 2.2 Curve:** $y = \text{round}\left(255 \times (x/255)^{2.2}\right)$
- **sRGB Curve:** Linear transfer for $x \le 0.04045$, exponent $2.4$ with $0.055$ offset above.

### 5.3 Spatial 2x2 Bayer Matrix & Temporal FRC Dithering
Simulates 10-bit color depth on 8-bit digital panels using spatial-temporal dispersion:
- Spatial 2x2 Bayer threshold matrix:
  $$M = \begin{bmatrix} 0 & 2 \\ 3 & 1 \end{bmatrix}$$
- Temporal modulation: Frame toggle alternates threshold phase each scan frame ($F_{\text{toggle}} = \text{frame\_count}[0]$), eliminating visual stationary pattern artifacts.

---

## 6. SoC APB Memory-Mapped CSR Subsystem (`display_sink_csr.sv`)

### 6.1 APB3/APB4 Bus Protocol
- Standard 32-bit synchronous APB interface (`pclk`, `presetn`, `psel`, `penable`, `pwrite`, `paddr[11:0]`, `pwdata[31:0]`, `prdata[31:0]`, `pready`, `pslverr`).
- Zero wait-state responsive transfers (`pready = 1'b1`, `pslverr = 1'b0`).
- Out-of-bounds address protection returning `32'hDEAD_BEEF`.

### 6.2 Register Map

| Offset | Register Name | Access | Reset Default | Bitfield Description |
|---|---|---|---|---|
| `0x000` | `CR_CTRL` | R/W | `32'h0000_081D` | **[0]**: `enable` (Global pipeline raster enable)<br>**[2:1]**: `res_mode` (Target display: 00=480p, 01=720p, 10=1080p)<br>**[4:3]**: `rate_mode` (Refresh: 00=24Hz, 01=30Hz, 10=45Hz, 11=60Hz)<br>**[7:5]**: `pat_mode` (Pattern: 0..3 built-in, 4=Video1, 5=Video2)<br>**[8]**: `ext_video_sel` (0=Internal, 1=AXI-Stream)<br>**[9]**: `fast_sim_en` (1=1 cycle/pixel fast mode)<br>**[11:10]**: `src_res_mode` (Video native source resolution) |
| `0x004` | `CR_COLOR` | R/W | `32'h0000_0000` | **[0]**: `csc_enable` (0=RGB bypass, 1=BT.709 YCbCr->RGB)<br>**[2:1]**: `gamma_mode` (0=Bypass, 1=Gamma 2.2, 2=sRGB)<br>**[3]**: `dither_enable` (0=Bypass, 1=Bayer+FRC ON) |
| `0x008` | `SR_STATUS` | RO | `32'h0000_0000` | **[11:0]**: `cur_pixel_x` (Current active scanline X coordinate)<br>**[27:16]**: `cur_pixel_y` (Current active scanline Y coordinate) |
| `0x00C` | `SR_FRAME_CNT`| RO | `32'h0000_0000` | **[31:0]**: `frame_count` (Monotonic 32-bit frame counter) |
| `0x010` | `REG_IRQ_EN` | R/W | `32'h0000_0000` | **[0]**: `irq_en_vsync` (Interrupt enable on VSync edge)<br>**[1]**: `irq_en_framedone` (Interrupt enable on frame completion) |
| `0x014` | `REG_IRQ_STAT` | W1C | `32'h0000_0000` | **[0]**: `irq_stat_vsync` (Write 1 to clear)<br>**[1]**: `irq_stat_framedone` (Write 1 to clear) |

---

## 7. Verification Architecture & Coverage Matrix

### 7.1 Regression Suite Summary
All 7 testbenches run deterministically via `make -C sim regress`:

| Testbench | Description | Verification Checks | Status |
|---|---|---|---|
| `tb_pattern.sv` | Pattern Generator Monotonicity & Geometric Coordinates | Grayscale ramp linearity, Color bar ordering, Motion ball kinematics | **PASS** |
| `tb_tcon.sv` | Full Frame Timing Counter & Physical Strobe FSM | 12-mode active/blank pixel totals, STV blanking, CPV/TP_LOAD exclusivity | **PASS** |
| `tb_scaler.sv` | 2D Spatial Scaler Golden Verification | Passthrough bit-exactness, 480p->1080p, 720p->1080p, 1080p->720p, 1080p->480p | **PASS** |
| `tb_color.sv` | BT.709 CSC, Gamma 2.2 / sRGB ROMs, Bayer Dither | Standard white/black, ROM exact values, Spatial/temporal toggle | **PASS** |
| `tb_csr.sv` | SoC Memory-Mapped APB CSR Subsystem | Reset values, RW integrity, Status telemetry, VSync IRQ, W1C clear | **PASS** |
| `tb_top.sv` | Master Top-Level Display Sink Pipeline | Analog power rails, PHY link lock, AXI4-Stream ingestion, Source driver DAC | **PASS** |
| `tb_crv_top.sv` | Constrained-Random Verification & SVA Assertions | 50 random iterations + sweep across 29 bins (100% coverage), 0 SVA violations | **PASS** |

### 7.2 SystemVerilog Assertions (`display_sva.sv`)
- `p_reset_quiescence`: Asserts all outputs remain low during reset.
- `p_axis_data_stable`: Enforces standard AXI-Stream protocol stability during stalls (`s_axis_tvalid && !s_axis_tready`).
- `p_de_no_xz`: Prevents unknown logic states (`'X` or `'Z`) on active video data.
- `p_stv_only_in_vblank`: Enforces physical glass rule that `STV` gate frame start strobe occurs exclusively during vertical blanking.
- `p_cpv_tpload_exclusive`: Ensures row clock `CPV` and column latch `TP_LOAD` never assert simultaneously.
- `p_active_line_width`: Dynamically verifies that active scanline pixel count exactly equals standard CTA-861 line width (with 4-line transition masking during resolution switches).

---

## 8. Synthesis & PPA Characterization

Synthesized using Yosys Open-Source Synthesis Suite (`synth.ys`, `synth_yosys.tcl`):
- **Target Top:** `display_sink_top`
- **Latch Verification:** 0 latches inferred (`check -assert` passed).
- **Multi-Driven Nets:** 0 multi-driven nets.
- **Clock Domain:** Unified synchronous 150 MHz domain with 2-stage metastability reset synchronizer.
- **Power Optimization:** Mult-operand isolation implemented on CSC inputs and accumulator paths.
