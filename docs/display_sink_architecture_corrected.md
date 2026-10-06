# Display Sink Architecture: Everything After the HDMI / DisplayPort Cable
*Corrected and extended reference covering the complete sink-side hardware of a monitor, laptop panel and smartphone display*

---

## 0. Scope, Terminology, Conventions

**"Display controller" is used in four different senses in industry.** Keep them apart:

| Term | Meaning | In scope here? |
| :--- | :--- | :--- |
| GPU display engine | Scan-out, planes, encoders on the *source* side | No (source side) |
| Scaler / video processor | The monitor's main controller SoC | Yes |
| T-CON | Panel timing controller | Yes |
| DDIC | Single-chip display driver IC (phones, small panels) | Yes |

This document treats the **entire sink side** as the "display controller system": everything from the connector pins to the photons.

**Tags used throughout**
- **[LCD]** applies to liquid-crystal panels only (incl. Mini-LED backlit LCD)
- **[OLED]** applies to emissive panels only
- **[Both]** applies to either
- **[Mon]** desktop monitor, **[Lap]** laptop eDP, **[Ph]** smartphone

**Honesty note.** Many details (which chip hosts overdrive, where the PMIC lives, number of rails, interface names) differ by vendor and panel generation. Where that happens the text says "typically" or "vendor-dependent". Numbers are representative, not universal.

---

## 1. System Topology

### 1.1 Subsystem partition

| ID | Subsystem | Contains |
| :--- | :--- | :--- |
| **A** | Connector side & control plane | Connectors, ESD, AC-coupling, HPD, DDC/EDID, AUX, CEC, USB-C/PD |
| **B** | Receiver PHY & link layer | Equalizers, CDR, SerDes, decoders, descrambler, FEC, HDCP, DSC, packet/audio demux |
| **C** | Video processor & host | Scaler SoC, frame DRAM, MCU/OSD, firmware flash |
| **D** | Internal video link | LVDS / V-by-One / eDP between mainboard and panel |
| **E** | Panel drive electronics | T-CON, level shifters, gamma buffer, VCOM, source drivers, gate drivers / GIP |
| **F** | Panel glass | TFT array + LC cell, or OLED pixel circuits |
| **G** | Light generation | LCD backlight, LED drivers, local-dimming (absent in OLED) |
| **H** | Power | AC-DC, DC-DC, panel PMIC |
| **I** | Peripherals | Audio path, USB hub/KVM, sensors |

### 1.2 Block diagram (LCD monitor)

```
 GPU ══ HDMI / DP / USB-C cable ══╗
                                  ║
┌─────────────────────────────────╨──────────────────────────────────────────────────────┐
│ MAINBOARD                                                                              │
│ [A] Connector, ESD, AC caps, +5V/DP_PWR, HPD, DDC/AUX, EDID EEPROM, CEC, USB-C PD      │
│         │ main link (3-4 diff pairs)           │ control (I2C / AUX / HPD)             │
│         ▼                                      ▼                                       │
│ [B] Rx PHY: CTLE/DFE → CDR/PLL → SIPO ─► link layer (align, deskew, descramble,        │
│     decode, FEC) ─► HDCP ─► DSC decode ─► packet demux (infoframes, audio)             │
│         │ pixel bus (1/2/4 px per clock) + timing          │ audio                     │
│         ▼                                                  ▼                           │
│ [C] SCALER / VIDEO PROCESSOR ◄──► [DRAM]            [Audio codec → amp → speakers]     │
│     • color, scaling, OD, dither, VRR, HDR           [I2S / S/PDIF]                    │
│     • local-dimming analysis      ◄──► [MCU + OSD + SPI flash]                         │
│         │                │                                                             │
│         │                └──► zone data ──────────► [G] LED driver(s) ──► LED strings  │
│         ▼                                                                              │
│ [D] LVDS / V-by-One HS / eDP transmitter                                               │
└─────────┼──────────────────────────────────────────────────────────────────────────────┘
          │ FFC / ribbon
          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ [E] T-CON BOARD / PANEL CONTROL BOARD                                                  │
│     T-CON ASIC (+ optional DRAM, flash/EEPROM for LUTs, demura, gamma, VCOM)           │
│       │ timing: STV/CPV/OE (or GIP clocks) │ data: mini-LVDS / EPI / etc. + TP, POL    │
│     [Level shifter] [PMIC: VDD, AVDD, VGH, VGL, VCOM] [Gamma buffer]                   │
└───────┼───────────────────────────────────────────┼────────────────────────────────────┘
        ▼                                           ▼
  Gate drivers (COF or GIP)                  Source drivers (COF / COG)
        └──────────────────┬────────────────────────┘
                           ▼
              [F] PANEL GLASS: TFT array + LC cell + color filter + polarizers
                           ▲
              [G] BACKLIGHT UNIT: LEDs + light guide / diffusers (+ zones)

 [H] AC-DC supply (adapter or internal) ──► 12 V / 5 V / 24 V rails to all boards
```

### 1.3 Block inventory

| # | Block | Typical location | Technology | Domain |
| :--- | :--- | :--- | :--- | :--- |
| A1 | Connectors, ESD, filters | Mainboard edge | Passive / TVS | Analog |
| A2 | EDID EEPROM, DDC/AUX/HPD logic | Mainboard | Serial memory + I/O | Mixed |
| A3 | USB-C PD controller, mux, hub | Mainboard | Mixed-signal | Mixed |
| B1 | Rx PHY (EQ, CDR, PLL, SIPO) | Scaler die or separate Rx IC | Analog hard macro | Analog |
| B2 | Link layer, HDCP, DSC, packet demux | Scaler die | Digital RTL | Digital |
| C1 | Scaler / video processor | Mainboard | Digital SoC | Digital |
| C2 | Frame DRAM | Mainboard (or T-CON side) | DDR3/DDR4/LPDDR | Memory |
| C3 | MCU, OSD, SPI flash | Inside scaler + flash chip | CPU + NOR | Digital |
| C4 | Audio codec, amplifier | Mainboard | Mixed-signal | Analog |
| D1 | LVDS / V-by-One / eDP Tx and Rx | Scaler out / T-CON in | SerDes | Mixed |
| E1 | T-CON | Control board (often panel-vendor supplied) | Digital + PLL/SerDes | Mixed |
| E2 | Level shifter, gamma buffer, VCOM driver | PMIC or discrete | HV analog | Analog |
| E3 | Source drivers | COF/COG on glass edge | HV mixed-signal | Mixed |
| E4 | Gate drivers or GIP | COF, or fabricated in glass | HV / TFT logic | Analog |
| F1 | TFT array, LC, color filter, polarizers | Glass | Display process | Physical |
| G1 | LED driver, local-dimming zone drivers | Power/backlight board | Power analog | Analog |
| G2 | LED strings, light guide, optical films | Panel module | Optical | Physical |
| H1 | AC-DC, DC-DC | Power board | Power | Analog |

---

## 2. Subsystem A: Connector Side & Control Plane

Video is only half the interface. A cable also carries a **bidirectional control plane** without which the GPU will not even send a picture.

### 2.1 Physical protection and coupling
- **ESD protection**: low-capacitance TVS diode arrays (a fraction of a pF per line) on every high-speed pair, since connectors are hot-plugged and touched.
- **Common-mode filtering and layout matching**: pair-length matching, controlled 100 Ω differential impedance, via/stub minimization.
- **DisplayPort main-link lanes are AC-coupled** (series capacitors); **HDMI TMDS is DC-coupled current-mode signaling**, terminated at the sink to a 3.3 V rail through 50 Ω per leg.
- **Source-supplied power**: HDMI provides +5 V (small current) and DP provides DP_PWR (3.3 V) on the connector. Sinks and cables use these to let the source read EDID even when the monitor's main supply is off. Back-power and over-voltage protection are required on these pins.

### 2.2 Hot-plug, EDID, DDC
- **HPD (Hot Plug Detect)**: sink pulls the line high to say "I'm here". On DP, short HPD pulses (IRQ_HPD) are used as an interrupt channel to tell the source "read my status".
- **DDC (I²C over two wires, HDMI)** and **I²C-over-AUX (DP)** carry:
  - **EDID** (typically at I²C address 0x50): 128-byte base block (supported modes, native timing, physical size, colorimetry) plus extensions.
  - **CTA-861 extension**: HDMI vendor blocks, HDR static metadata block, supported colorimetry, audio capabilities, VRR range, etc.
  - **DisplayID 2.x**: newer extensible format for high-refresh, tiled and VRR descriptors.
  - **E-DDC segment pointer** (0x30) to reach EDID blocks beyond the first 256 bytes.
- EDID lives in a small I²C EEPROM, or is **emulated by the scaler** from flash (common when several ports must report consistent data).
- **DDC/CI** (VESA MCCS over I²C, address 0x37): lets the OS change brightness, input source, color preset by talking to the scaler's MCU.

### 2.3 HDMI-specific control lines
- **SCDC** (Status and Control Data Channel, over DDC at 0x54): scrambling enable, TMDS clock ratio, **FRL link training** and status (HDMI 2.1), FEC/lock flags.
- **CEC**: single-wire bus for remote-control and device commands.
- **ARC / eARC**: return audio path from the sink to an AV receiver (eARC uses the HEC differential pair, supports high-bitrate immersive audio).

### 2.4 DisplayPort-specific control
- **AUX channel**: AC-coupled, differential, half-duplex, Manchester-coded at roughly 1 Mbit/s. It carries:
  - **DPCD** register reads/writes (capabilities: max link rate, lane count, DSC support, FEC, Adaptive-Sync, PSR, etc.)
  - **Link training** handshakes (see §3.4)
  - **I²C-over-AUX** for EDID
  - Sideband messaging for **MST** (multi-stream transport: daisy-chaining and hubs)
- **Adaptive-Sync** capability is advertised in DPCD/EDID; it is the DP transport of VRR.

### 2.5 USB-C / Thunderbolt monitors
Modern monitors often take video over USB-C:
- **CC lines + USB-PD controller** negotiate role, voltage/current (the monitor can charge a laptop, 15-100 W typical) and **DP Alt Mode** entry.
- A **mux / redriver / retimer** reallocates the four high-speed lanes: all four to DisplayPort, or two to DisplayPort and two to USB 3.x.
- A **USB hub controller** (and often Ethernet/KVM) shares the same cable.
- **USB4 / Thunderbolt**: DisplayPort is *tunneled*; a router/DP-adapter chip reconstructs an ordinary DP stream for the scaler.

---
## 3. Subsystem B: Receiver PHY and Link Layer

### 3.1 Standards at a glance

| Standard | Per-lane raw rate | Lanes | Coding | Aggregate raw | Payload after coding |
| :--- | :--- | :--- | :--- | :--- | :--- |
| HDMI 1.4 TMDS | up to 3.4 Gbps | 3 data + clock | TMDS 8-to-10 | 10.2 Gbps | ~8.2 Gbps |
| HDMI 2.0 TMDS | up to 6 Gbps | 3 data + clock | TMDS 8-to-10 | 18 Gbps | ~14.4 Gbps |
| HDMI 2.1 FRL | 3 / 6 / 8 / 10 / 12 Gbps | 3 or 4 (clock lane becomes lane 4) | 16b/18b + Reed-Solomon FEC | 48 Gbps max | ~42.7 Gbps |
| DP 1.4 | 1.62 / 2.7 / 5.4 / **8.1** Gbps (RBR/HBR/HBR2/HBR3) | 1, 2 or 4 | 8b/10b | 32.4 Gbps (HBR3 x4) | 25.92 Gbps |
| DP 2.1 | **10 / 13.5 / 20** Gbps (UHBR10/13.5/20) | 1, 2 or 4 | 128b/132b + Reed-Solomon FEC | 80 Gbps (UHBR20 x4) | ~77.4 Gbps |

Important distinctions:
- **TMDS carries an explicit pixel clock**. **DP and HDMI FRL do not**: the clock is embedded in the data and the pixel clock must be *regenerated* at the sink (see §3.6).
- Bit rate is not frequency. A 12 Gbps NRZ lane has a Nyquist frequency of ~6 GHz; a 20 Gbps UHBR lane ~10 GHz. Channel loss is evaluated at Nyquist.

### 3.2 Analog front end

1. **Termination and input buffer**: matched 100 Ω differential (DP, FRL) or 50 Ω single-ended-to-rail (TMDS).
2. **CTLE (continuous-time linear equalizer)**: analog high-frequency boost that offsets cable and PCB skin-effect/dielectric loss, re-opening the eye.
3. **DFE (decision-feedback equalizer)**: subtracts post-cursor ISI using previously decided bits through feedback taps. Needed at the high rates (HBR3, FRL, UHBR); at low rates a CTLE alone is usually enough.
4. **CDR + PLL**: a bang-bang (Alexander) or Hogge phase detector with a VCO/loop filter recovers sampling phase and frequency from data transitions; the PLL provides a low-jitter multi-GHz sampling clock. For TMDS the forwarded clock channel assists lock.
5. **Deserializer (SIPO)**: shifts bits into 10-, 20- or 40-bit parallel words at a divided clock for the digital core.
6. **Equalizer adaptation**: LMS-style or training-driven adjustment of CTLE gain and DFE tap weights (see link training below).

### 3.3 Link layer (digital)

In order, per lane unless stated:

1. **Word/symbol alignment** (comma/control-symbol detection or block-header alignment).
2. **Lane deskew** across 2 or 4 lanes: lanes arrive with different delays; elastic buffers re-align them.
3. **Descrambler** (LFSR-based). DP and HDMI 2.0+ scramble data to flatten the spectrum and reduce EMI.
4. **Line decoder**:
   - TMDS: 10-bit symbols back to 8-bit pixels (undo XOR/XNOR transition minimization and DC-balance inversion). Control periods and data-island TERC4 symbols are separate codes.
   - 8b/10b (DP 1.x): decode with running-disparity check.
   - 128b/132b (DP 2.1) and 16b/18b (HDMI FRL): block decoders locking onto the block header.
5. **FEC decoder**: Reed-Solomon FEC (mandatory in HDMI FRL and DP 128b/132b; used on DP 1.4 links when DSC is enabled).
6. **Stream reconstruction**: separate the video stream, **secondary data packets** (infoframes, audio) and, on DP, MST virtual channels.

### 3.4 Link training

The sink cannot adapt blindly: the source and sink negotiate a link both can sustain.

**DisplayPort (8b/10b)**
1. Source reads DPCD for max rate and lane count.
2. **Clock-recovery phase**: source sends a simple pattern (TPS1); the CDR must lock. The sink reports per-lane lock in DPCD; the source adjusts **voltage swing** and **pre-emphasis** on request.
3. **Channel-equalization phase**: richer patterns (TPS2/3/4) let the sink adapt its equalizer and verify symbol lock, alignment and inter-lane deskew.
4. On failure the source falls back to lower rate or fewer lanes. Link re-training can occur at any time (cable disturbed, power state change).
5. DP 2.1 128b/132b uses a different procedure with transmitter FFE presets instead of swing/pre-emphasis.

**HDMI 2.1 FRL**: the sink drives training through **SCDC** registers, requesting FRL rate and lane count and TX FFE levels; the source sends training patterns; the sink reports lock/error flags. TMDS (HDMI ≤2.0) has no training: the receiver just locks to the forwarded clock.

### 3.5 Content protection, compression, packets

- **HDCP**
  - **HDCP 1.x**: proprietary stream cipher with 56-bit keys and a device-key set stored in OTP/secure memory. It is **not AES**.
  - **HDCP 2.x**: RSA-based authentication and key exchange, SHA-256 HMAC checks, **AES-128 (CTR)** for content encryption. Locality check enforces a round-trip time bound.
  - Implemented as a hardwired cipher block in the receive path *before* the scaler, with zero added frame delay; the keys live in secure OTP/NVM.
- **DSC (VESA Display Stream Compression)**:
  - Slice-based, line-oriented, visually lossless codec (typical ratios up to ~3:1; selectable bits per pixel).
  - Used when the uncompressed pixel stream exceeds link payload (see worked example §13). Latency is on the order of a few lines, not frames.
  - A decoder core sits behind HDCP in the Rx or scaler and outputs uncompressed RGB / YCbCr 4:4:4/4:2:2.
- **Packets and metadata** (HDMI data islands / DP SDPs):
  - **InfoFrames**: AVI (format, colorimetry, range), Audio, SPD, Vendor-Specific, **DRM** (HDR10 static metadata).
  - **Dynamic HDR** metadata via vendor/extended packets (e.g. HDR10+ or Dolby Vision signaling).
  - **VRR / ALLM / QMS** signaling flags in HDMI; **Adaptive-Sync** flags in DP.
  - **Audio sample packets** plus **ACR** (N/CTS clock regeneration) on HDMI.
  - On DP SST, **MSA** (Main Stream Attributes) / VB-ID carry video timing and format info.

### 3.6 Reconstructing video timing

- Because DP and FRL carry **no pixel clock**, the sink rebuilds it with a **stream-clock-recovery PLL** using ratio information transmitted in the stream (M/N values on DP).
- The sink regenerates **DE (data enable), Hsync, Vsync** from the stream framing and timing attributes.
- Pixel data is released in parallel form, typically **2 or 4 pixels per clock** to keep clock rates manageable. Illustration: 4K144 with reduced blanking has ~1.25 Gpixel/s, which at 4 px/clk is a ~313 MHz pixel-domain clock.

**Outputs of subsystem B**
- Pixel bus: RGB 4:4:4 or YCbCr 4:4:4 / 4:2:2 / 4:2:0, 6-16 bit per component
- DE, Hsync, Vsync (or equivalent sideband timing)
- Recovered pixel clock
- Audio stream (I²S / S/PDIF) and parsed infoframe/metadata registers

---
## 4. Subsystem C: Video Processor ("Scaler SoC"), Memory, Host

### 4.1 Role
The scaler is the monitor's system SoC: it hosts (or sits next to) the link receiver, runs the image pipeline, supervises everything through an embedded MCU, and emits a panel-format video stream. Some designs split it into a separate Rx IC and a processor; some fold the T-CON into it (common in low-cost and laptop designs).

### 4.2 Pixel pipeline (typical order; vendor-dependent)

1. **Input mux and format normalization**: select among HDMI/DP/USB-C inputs; handle PIP/PBP sources.
2. **Chroma upsampling** (4:2:0 / 4:2:2 to 4:4:4) and **range conversion** (limited 16-235 to full 0-255 as signaled by the AVI InfoFrame).
3. **Color space conversion**: YCbCr to RGB by a 3x3 matrix plus offsets:

   $$\begin{bmatrix} R \\ G \\ B \end{bmatrix} = \begin{bmatrix} C_{11} & C_{12} & C_{13} \\ C_{21} & C_{22} & C_{23} \\ C_{31} & C_{32} & C_{33} \end{bmatrix} \begin{bmatrix} Y \\ Cb \\ Cr \end{bmatrix} + \begin{bmatrix} D_1 \\ D_2 \\ D_3 \end{bmatrix}$$

   (coefficients depend on BT.601 / BT.709 / BT.2020 and range).
4. **De-interlacing and noise reduction** (mainly TV-class scalers; PC monitors rarely need them). De-interlacing is *temporal / motion-adaptive*, which is why it needs field/frame memory.
5. **Spatial scaling**:
   - Line buffers: dual-port SRAM holding N adjacent lines; a vertical filter with N taps needs about N-1 buffered lines.
   - **Bilinear** (2x2 window):

     $$P(x,y) = (1-\alpha)(1-\beta)P_{0,0} + \alpha(1-\beta)P_{1,0} + (1-\alpha)\beta P_{0,1} + \alpha\beta P_{1,1}$$

   - **Polyphase FIR / bicubic-class** scaling: separable horizontal and vertical filters with typically 4-8 taps and 16-64 phases; coefficient sets selectable for sharpness vs ringing.
6. **Picture controls**: brightness, contrast, hue/saturation, 6-axis color, sharpness, black stabilizer, gaming overlays (crosshair, FPS counter, timer).
7. **Color management**:
   - **1D LUTs**: per-channel gamma / EOTF shaping (sRGB, 2.2, 2.4, PQ, HLG).
   - **3D LUT**: grid of 17^3 or 33^3 nodes with **tetrahedral interpolation** to map input colors into the panel's native gamut (sRGB, DCI-P3, Adobe RGB emulation, factory calibration).
8. **HDR handling**: parse DRM/dynamic metadata, apply tone mapping when content peak exceeds panel capability, drive backlight zones accordingly.
9. **Local-dimming analysis** (Mini-LED / FALD LCD): analyze the frame (max/average per zone), compute per-zone LED levels with spatial smoothing and temporal filtering, then compute **pixel compensation** so the LCD data compensates for the known backlight light distribution. Zone levels go to the LED driver(s) (§10.3).
10. **Overdrive / response-time compensation (OD)** (see §4.3).
11. **Dithering**: spatial/temporal dithering (often called **FRC** in the panel context) to render 10-bit (or higher) pipeline values on an 8-bit or 6-bit+FRC panel interface by alternating adjacent levels across frames/pixels.
12. **VRR engine** (see §4.4).
13. **OSD blend**: menu overlay merged by alpha-blending a bitmap/palette layer onto the video.
14. **Output formatter**: pack to LVDS / V-by-One HS / eDP (or mini-LVDS directly if T-CON is integrated).

### 4.3 Overdrive (response-time compensation)

**Problem.** Liquid-crystal molecules take several ms to rotate after the applied voltage changes. A pixel stepping from level A to level B reaches B after more than a frame interval for some transitions, causing trailing/smear.

**Principle.** For one frame, drive the pixel with a voltage *beyond* the target so the field overcomes viscosity faster, then settle on the target in the next frame.

**Implementation.**
- The previous frame $N-1$ is kept in memory (full precision, or **compressed/sub-sampled** to save bandwidth).
- As frame $N$ streams in, each pixel pair is looked up:

  $$\text{Driven}(x,y) = \text{LUT}\big[\,P_N(x,y),\; P_{N-1}(x,y)\,\big]$$

  The LUT is usually a **coarse grid** (e.g., 9x9 or 17x17 nodes) with interpolation between nodes, calibrated per panel batch, sometimes with temperature compensation. Falling transitions get an *undershoot* drive for the same reason.
- Example (illustrative): a 20% to 70% grey transition may be driven at ~95% for one frame.
- **Latency.** Because the output is computed from the *streaming* current frame and the *stored* previous frame, OD does not by itself add a frame of delay. Frame-rate conversion and temporal noise reduction do.
- **Where it lives is vendor-dependent.** Gaming monitors often do OD in the scaler; many panels, and most TVs, do it in the **panel T-CON** with its own DRAM. Overshoot mis-tuning appears as "inverse ghosting".

### 4.4 Variable refresh rate (VRR) / Adaptive-Sync

- Mechanism: the scan-out of a new frame begins when the GPU sends it; the interval between frames is stretched by extending **vertical blanking (front porch)** while the panel holds the last frame.
- **Constraints**: panel has a minimum and maximum refresh (LC cell voltage decays and brightness drifts if frames come too slowly), so the scaler implements **low-framerate compensation (LFC)** by repeating frames when the source drops below the range.
- **Side effects the hardware must manage**: brightness/flicker variation vs frame time (notably VA and OLED), overdrive tuning across a refresh *range* rather than at one rate, and a T-CON that tolerates variable frame periods.
- Transport: DP Adaptive-Sync, HDMI 2.1 VRR (and vendor schemes layered on them).

### 4.5 Embedded MCU, OSD, firmware

- **MCU**: 8051, ARM Cortex-M/R, or RISC-V class core inside the scaler.
- Responsibilities: button/joystick scan, OSD menu logic, **DDC/CI**, EDID selection, input auto-detect and power sequencing, USB-C/PD policy (sometimes a separate PD MCU), firmware update (USB or DDC), thermal and backlight control.
- **SPI NOR flash** stores: firmware, OSD fonts/bitmaps, EDID images, **OD/gamma/3D-LUT/uniformity tables**, factory calibration. Small **I²C EEPROMs** may hold EDID and panel parameters.
- **Clocking**: a crystal (e.g., 24-27 MHz class) feeds PLLs for the pixel, memory and serializer domains.

### 4.6 Audio path (carried by the same cable)
- Audio is extracted from HDMI audio sample packets (ACR-reconstructed clock) or DP SDPs.
- Passed over **I²S** (or S/PDIF) to a **codec/DAC**, then a **class-D amplifier** to speakers, and a headphone output. Optional **eARC** return path.
- Compressed formats (e.g., Dolby/DTS) are passed through to an AV receiver rather than decoded in most monitors.

### 4.7 Sensors and misc.
Ambient light sensor, proximity/presence sensor, temperature sensors on backlight and panel, tilt/pivot sensors, USB downstream hub, KVM switching.

---

## 5. Frame Memory Subsystem

### 5.1 Hardware
DDR3 / DDR4 / LPDDR, from tens of MB up to hundreds of MB, adjacent to the scaler (or a separate one next to the T-CON). Some SoCs integrate memory or use only on-chip SRAM, so **low-end monitors may have no external DRAM at all** and no full-frame OD.

### 5.2 Size and bandwidth (checked)

One uncompressed 4K 10-bit RGB frame:

$$3840 \times 2160 \times 30\ \text{bit} = 248.8\ \text{Mbit} \approx 31.1\ \text{MB}$$

Active-pixel data rate at 144 Hz:

$$3840 \times 2160 \times 30 \times 144 \approx 35.8\ \text{Gbit/s}$$

For overdrive with a stored previous frame you write one stream and read one stream, roughly **35.8 Gbit/s each way** (~72 Gbit/s combined) *before* DRAM efficiency losses and any compression. This is why OD frame stores are commonly compressed.

### 5.3 Uses
1. **Overdrive reference** (previous frame).
2. **Frame-rate conversion** and frame synchronization, mainly when the panel's scan rate is decoupled from the input rate (TV-class). Typical PC monitors with VRR *off* simply run the panel at the input refresh rate.
3. **Temporal noise reduction / motion-adaptive de-interlacing**.
4. **Local-dimming latency alignment** (frame delay while zones are computed).
5. **PIP/PBP** buffering and scaler line-to-frame rate decoupling.

### 5.4 What the memory does *not* do
It does not let a monitor keep scanning if the link drops. A traditional monitor in video mode shows "No Signal" when the stream stops. Autonomous self-refresh from a *panel-side* remote frame buffer is a different mechanism (eDP **PSR / PSR2**, DP 2.1 **Panel Replay**), covered in §11.

---

## 6. Subsystem D: Internal Video Link (Scaler to T-CON)

| Interface | Notes |
| :--- | :--- |
| **LVDS** | Parallel-to-serial 7:1 per pair; single-link carries one pixel/clock (e.g., 4 data pairs + clock for 24-bit), dual-link two pixels/clock. Legacy to ~FHD/QHD class. |
| **V-by-One HS** | Point-to-point, embedded clock, ~3.75-4 Gbps per lane depending on spec revision; lock-detect (LOCKN) and hot-plug (HTPDN) handshake lines. Dominant in TVs and 4K monitors. |
| **eDP** | Embedded DisplayPort: rates up to HBR3 (8.1 Gbps/lane), 1/2/4 lanes, AUX channel, **PSR/PSR2**, Adaptive-Sync, backlight control over AUX/DPCD. Standard in laptops. |
| **MIPI DSI** | Phones and small panels (see §11). |

If the T-CON is integrated in the scaler, this link vanishes and mini-LVDS-class signals go straight to the source drivers.

---
## 7. Subsystem E: Panel Drive Electronics

### 7.1 T-CON (timing controller) [LCD, and the timing role in OLED]

**Definition.** A mixed-signal ASIC (digital logic plus PLLs and high-speed SerDes I/O, so *not* "purely digital") that converts a standard raster stream into the panel-specific timing and data formats the glass drivers need. On many panels the T-CON is chosen and supplied by the **panel maker**, not the monitor maker.

```
                    ┌──────────────────────────────────────────────────────┐
                    │                      T-CON                           │
 From scaler        │ ┌─────────────┐   ┌────────────────┐                 │  Gate-side control
 (LVDS / V-by-One / │ │ Rx + PLL    │──►│ Timing gen FSM │─────────────────┼─► STV, CPV, OE
  eDP) ═══════════► │ │ + FIFO      │   └────────────────┘                 │   (or GIP clocks)
                    │ └──────┬──────┘                                      │
                    │        ▼                                             │  Source-side control
                    │ ┌─────────────┐   ┌────────────────┐                 │  TP/LOAD, POL, SOE
                    │ │ Panel image │──►│ Reorder, scram-│─────────────────┼─► + data: mini-LVDS /
                    │ │ proc (OD,   │   │ ble, serialize │                 │   point-to-point
                    │ │ demura, DGC,│   └────────────────┘                 │
                    │ │ dither)     │◄──► [DRAM] [flash / EEPROM]          │
                    │ └─────────────┘     ◄──► I²C to PMIC / gamma / VCOM  │
                    └──────────────────────────────────────────────────────┘
```

**Functions**
1. **Receive and unpack** the internal link; clock-domain crossing into the panel timing domain.
2. **Gate timing generation**
   - Classic gate-IC panels: `STV` (frame start pulse, loads a `1` into the gate shift register), `CPV` (row clock, advances the active row), `OE` (output enable/mask: forces outputs low in the dead time between rows to avoid overlap and vertical crosstalk).
   - **GIP / GOA panels** (gate driver fabricated in the glass): the T-CON provides a **multi-phase clock set** and start pulses instead; the shift-register logic is made of TFTs in the border.
3. **Source-side control**
   - **TP / LOAD / STB** latch-and-output strobe: tells source drivers when a full line has been loaded and its analog outputs should update.
   - **POL**: polarity-inversion control (see §8.4).
   - **Charge-share / output-enable** control to save power.
4. **Data formatting**: reorder pixels across the multiple source-driver chips, apply bit-mapping, optional **data scrambling**, and serialize.
5. **Panel-side image processing** (panel and generation dependent): overdrive with its own DRAM, **demura** (mura-compensation coefficients from flash correct luminance non-uniformity), **digital gamma / DGC**, dithering/FRC down to the driver bit depth, **sub-pixel rendering**, and sometimes **local dimming** hand-off.
6. **Calibration and configuration**: read panel tables from EEPROM/flash; program **VCOM** and **gamma reference** levels in the PMIC/gamma IC over I²C.
7. **VRR tolerance**: accommodate variable frame periods by extending blanking and keeping gate/source timing legal.

**Source-driver data buses (T-CON to column ICs)**
- **mini-LVDS / RSDS / PPDS**: reduced-swing (~200 mV class) differential, multi-drop or per-driver pairs with a forwarded clock; legacy to mainstream FHD.
- **Embedded-clock point-to-point** (names vary by vendor, e.g., **EPI, USI-T, CEDS**): one pair per driver IC, clock embedded, lower EMI and wire count; used on high-resolution/high-refresh panels.

### 7.2 Gate drivers (rows)

- **Function**: sequentially select one row at a time by applying $V_{GH}$ to its gate line (turning every TFT in that row on) while all other rows sit at $V_{GL}$ (TFTs off, preserving stored charge).
- **Forms**
  - **Gate IC on COF** at the panel's side edge(s): bidirectional shift register + HV level shifters + push-pull outputs.
  - **GIP / GOA (Gate-in-Panel)**: the shift register is built from TFTs (a-Si, IGZO or LTPS) in the glass border; saves ICs and cost; the dominant approach in most current mass-market panels.
- **Row time budget (4K, 144 Hz)**: with ~2,222 total lines (reduced blanking), line time $\approx 1/(144 \times 2222) \approx 3.1\ \mu s$. At 60 Hz it's about 7.4 µs. The pixel must be charged through the TFT within a *fraction* of this window.
- **Signal-integrity issues**: RC delay down the long gate line; far-end gate pulse rounding; **gate-pulse shaping / modulation** (e.g., controlled falling-edge slew) is used to limit feedthrough error (see $\Delta V_p$ in §8.3).
- **Architecture tricks (vendor-dependent)**: *dual-gate / half-source-driver* panels double the number of gate lines and halve the number of data lines to cut source-driver count and cost, at the price of shorter row time.

### 7.3 Source drivers (columns)

- **Form factor**: long narrow ICs on **COF** ribbons (or **COG**) along the top/bottom glass edge; each IC drives a slice of columns (e.g., 480-960 outputs). A 4K RGB panel has $3840 \times 3 = 11{,}520$ data lines, shared across many ICs (**each IC buffers only its own slice**).
- **Per-channel signal path**
  1. **Shift register / input latch**: accepts its slice of data from the T-CON bus.
  2. **Line (hold) latch**: holds the complete row slice until `TP/LOAD` fires.
  3. **Level shifter**: logic-level (1.8-3.3 V class) to the driver's high-voltage domain.
  4. **DAC**: resistor-string ($R$-string) selecting among interpolated reference voltages. The ICs are fed **gamma reference taps** (typically on the order of ten to a few tens of voltage points, supplied by a **gamma buffer**) and the R-string interpolates between them to produce 256 (8-bit) to 1024 (10-bit) levels. **Positive and negative DAC sets** (relative to VCOM) are used so each output can swing to either polarity.
  5. **Polarity mux + output buffer**: rail-to-rail op-amp (class-AB) drives the data line; a **charge-sharing switch** can short outputs together during blanking to recycle charge and cut power.
- **Voltage step size**: tens of millivolts, not microvolts. Example: 10-bit across ~16 V is ~15 mV per step.
- **Supply domains**: logic $V_{DD}$ (1.8-3.3 V), analog $A_{VDD}$ (typ. ~8-18 V for LCD), ground.
- **Data lines are metal** (Mo / Al / Cu stacks), not ITO. ITO is used for the transparent *electrodes* (pixel and common).
- **Power**: scales with $C \cdot V^2 \cdot f$ of the data lines. Column inversion minimizes toggling; dot inversion toggles most.

---

## 8. Subsystem F: Panel Glass

### 8.1 TFT-LCD structure (cross-section, bottom to top)
```
 Backlight unit (G)
 ───────────────────────────────  rear polarizer
 TFT substrate (glass):
     gate lines (rows)   data lines (columns)   TFT + storage cap per sub-pixel
     pixel electrode (ITO)       [IPS/FFS: common electrode also on this substrate]
 ───────────────────────────────  liquid-crystal layer (sealed, few µm)
 Color-filter substrate (glass):
     R/G/B color filters, black matrix   [TN/VA: common electrode (VCOM) here]
 ───────────────────────────────  front polarizer (crossed)
```

- **Sub-pixel**: one TFT switch (gate to row, source to column, drain to pixel electrode), a **storage capacitor $C_{st}$** and the LC capacitance $C_{lc}$.
- **LC modes**: TN, **IPS/FFS** (in-plane field, wide viewing angles), **VA** (high contrast). Normally-black or normally-white behavior depends on the mode and polarizer orientation.
- **TFT technology** sets drive capability: **a-Si** (mobility ~0.5-1 cm²/Vs, cheap, limits refresh/size), **IGZO/oxide** (~10 cm²/Vs, low leakage, high refresh and VRR friendly), **LTPS** (~50-100+ cm²/Vs, small high-PPI panels, phone LCD/OLED).

### 8.2 How a pixel is written
1. The gate driver raises one row to $V_{GH}$; all TFTs in that row conduct.
2. Source drivers put the target analog voltages on all columns; each pixel capacitor charges toward its data voltage during the row time.
3. The row returns to $V_{GL}$; TFTs turn off; the pixel holds its charge ($C_{st}$ prevents decay) until the next frame refreshes it.
4. Optical output depends on the RMS field across the LC, i.e., on $|V_{pixel} - V_{COM}|$.

### 8.3 Non-idealities the electronics must compensate
- **Gate-to-pixel feedthrough (kickback)**: when the gate falls, the parasitic capacitance $C_{gd}$ couples a step into the pixel:

  $$\Delta V_p \approx \Delta V_{gate}\cdot\frac{C_{gd}}{C_{lc}+C_{st}+C_{gd}}$$

  This offsets the pixel voltage; **VCOM is tuned** to center the positive and negative frames around it.
- **Flicker**: if VCOM is mis-set, positive and negative frames have different luminance and the eye sees flicker at half the frame rate. Factory VCOM calibration (stored in EEPROM, programmed into the VCOM driver) removes it.
- **RC delay and sheet resistance** on gate/data lines cause position-dependent charging error.
- **Leakage and hold decay**: more critical at low refresh (VRR low end).

### 8.4 Polarity inversion (POL) [LCD only]
- LC is damaged by sustained DC (ion migration, image sticking), so the field polarity relative to VCOM is alternated every frame.
- Spatial patterns reduce visible flicker and crosstalk: **frame, row (line), column, dot, 2-dot** inversion. Column inversion is the lowest power; dot inversion has the best flicker behaviour but the highest power.
- Because luminance depends on $|V_{pixel}-V_{COM}|$ (not the sign), the eye sees steady brightness; the long-term net DC across the LC cancels to zero **only if VCOM is set correctly**.
- Control: T-CON sends `POL` to the source drivers, which select the positive- or negative-DAC outputs.

### 8.5 Module assembly
Open cell (glass + COFs + polarizers) plus: source-side and gate-side COF/FPC, **T-CON/control PCB** (sometimes "C-board" / "S-board" naming), backlight unit, bezel/frame. Some modules are "open cell" sold without backlight so the monitor maker adds its own.

---
## 9. Subsystem H: Power

### 9.1 Power tree

```
 Mains (100-240 V AC)
    │
 [AC-DC: EMI filter → rectifier → PFC (larger units) → isolated flyback/LLC]   (internal board or external adapter)
    │  12 V (typ.) / 19-24 V / USB-PD rail
    ├──► mainboard DC-DC: 5 V, 3.3 V, 1.8 V, 1.2 V / 1.1 V core, DRAM rail (1.2-1.5 V), audio amp rail
    ├──► panel PMIC / T-CON board: VDD, AVDD, VGH, VGL, VCOM, gamma references
    └──► backlight boost / LED driver: strings of tens to 100+ V, high current
```

- Large displays and USB-C monitors with laptop charging (up to 100 W class) have significant additional PD power capacity.
- **Protection**: input surge, OCP, OVP, thermal shutdown, short-circuit and brown-out handling on each rail.

### 9.2 Panel rails [LCD]

| Rail | Typical range | Generated by | Purpose |
| :--- | :--- | :--- | :--- |
| $V_{DD}$ / $V_{CORE}$ | 1.0-3.3 V | Buck regulators | T-CON logic and I/O |
| $A_{VDD}$ | ~8-18 V | Boost converter | Source-driver analog supply (DAC ladder, output buffers) |
| $V_{GH}$ | ~+20 to +35 V | Charge pump / boost | TFT "on" level on selected row |
| $V_{GL}$ | ~-5 to -12 V | Inverting charge pump | TFT "off" level, blocks leakage |
| $V_{COM}$ | panel-specific, a few volts (roughly in the 3-8 V range on many panels) | Programmable op-amp driver | Common-electrode potential, calibrated per panel; noise-sensitive |
| Gamma references | tens of taps between ~0 V and $A_{VDD}$ | Gamma buffer / PMIC | Reference voltages interpolated by source-driver DACs |

Additional items:
- **Level shifter** (often inside the PMIC): converts T-CON gate-control logic to the $V_{GH}$/$V_{GL}$ swing.
- **Power sequencing**: logic first, then analog, then gate rails ($V_{DD}$ → $A_{VDD}$/$V_{GL}$ → $V_{GH}$), with a reverse and *discharge* sequence at power-off (e.g., turning all gates on briefly) so stored charge clears and no residual image or stress remains.
- **Programmable gamma/VCOM**: values written by the T-CON/MCU over I²C from stored calibration.

---

## 10. Subsystem G: Light Generation (LCD) and Emission (OLED)

### 10.1 Why it matters
An LCD modulates light; it does not make it. Backlight subsystems dominate **power consumption, HDR capability, contrast, motion clarity, thickness and cost**.

### 10.2 Backlight unit architectures

| Type | Description | Characteristics |
| :--- | :--- | :--- |
| **Edge-lit** | LED bars on one or more edges + light-guide plate | Thin, cheap, limited local dimming |
| **Direct-lit** | LED array directly behind diffuser | Better uniformity, can support zones |
| **FALD** | Full-array local dimming, tens to hundreds of zones | Improved contrast, visible blooming |
| **Mini-LED** | Thousands of small LEDs, hundreds to thousands of zones (often with quantum-dot or phosphor films) | High peak brightness, strong HDR, thicker |

Optical stack: reflector, light-guide or LED array, diffuser, quantum-dot or phosphor color-conversion film, prism/brightness-enhancement films, reflective polarizer.

### 10.3 Electronics

- **LED driver**: boost converter creating a string voltage (white LEDs are ~3 V each; strings of ~10-30 LEDs give tens of volts and up) plus **constant-current sinks**, one per string or zone.
- **Dimming**
  - **PWM dimming**: chopping at typically hundreds of Hz to tens of kHz; low frequencies cause visible/PWM flicker, high frequencies ease it.
  - **DC (analog) dimming**: lower current; avoids flicker but shifts LED color/efficiency.
  - **Hybrid** schemes: DC at high brightness, PWM at low.
- **Local-dimming zone drivers**: multi-channel LED driver ICs (tens of channels each, many per unit) receiving per-zone levels from the scaler/local-dimming processor through a serial interface (SPI-like or vendor-specific).
- **Motion-clarity strobing / backlight scanning (BFI)**: pulses or scans the backlight in sync with panel refresh to shorten the persistence of vision blur, at the cost of brightness and sometimes flicker.
- **Calibration**: per-LED or per-zone uniformity and color tables in flash; thermal and optical sensors for feedback.
- **Brightness control**: OSD/MCU sets duty or current; HDR mode requests peak current boosts for limited areas/time.

### 10.4 OLED: emission replaces backlight [OLED]
No backlight unit. Light generation moves *into the pixel* (see §12).

---
## 11. Smartphone and Laptop Architectures

### 11.1 Smartphone: DDIC + MIPI DSI [Ph]

```
 Application SoC ── MIPI DSI (1-4 D-PHY lanes, or C-PHY trios) ──► DDIC (on glass / plastic / film)
                                                                     │  D-PHY/C-PHY Rx + DCS command decoder
 Power IC (separate, AMOLED) ── ELVDD / ELVSS / etc. ──────────────►│  GRAM (frame memory, if command mode)
                                                                     │  Timing generation, gamma / DAC
 Touch controller (separate, or TDDI-integrated) ───────────────────│  Brightness (DBV), compensation
                                                                     ▼
                                    Panel: gate / scan + emission (EM) drivers (GIP) + pixel array
```

- **Packaging**: **COG** (chip on glass), **COF** (chip on film) or **COP** (chip on plastic, for foldable/borderless AMOLED).
- **Interface**: **MIPI DSI** over **D-PHY** (clock lane + 1-4 data lanes) or **C-PHY** (3-wire, 3-level symbols, more bits per symbol). Lane signaling has two modes:
  - **HS (high-speed)**: low-swing differential, ~200 mV nominal.
  - **LP (low-power)**: **~1.2 V single-ended CMOS** levels used for escape/command and idle states.
- **DSC** is commonly used on DSI for high-resolution/high-refresh panels.
- **Modes**
  - **Video mode**: host streams pixels continuously, like a monitor.
  - **Command mode with GRAM**: the DDIC holds a full frame and refreshes the panel autonomously; the host sends **DCS commands** and partial updates only when content changes. A **TE (tearing-effect)** signal from the DDIC tells the host when it is safe to write. Example frame: $1080 \times 2400 \times 24\ \text{bit} \approx 62.2\ \text{Mbit} \approx 7.8\ \text{MB}$.
  - Not every phone panel/DDIC has full GRAM; some operate effectively in video mode.
- **LTPO** panels (LTPS plus oxide TFTs) allow variable refresh from ~1 Hz to 120 Hz and support always-on display at very low power.
- **Power**: LCD phone DDICs often integrate charge pumps; **AMOLED power rails typically come from a separate PMIC** and the DDIC receives them. The **gate/scan and emission drivers are usually GIP** on the panel, controlled by timing signals from the DDIC.
- **TDDI** (touch and display driver integration) merges touch sensing into the display IC on some LCD phones.

### 11.2 Laptop: eDP panel [Lap]
- Scaler/GPU outputs eDP directly; the panel contains a **T-CON** (or a combined T-CON + source-driver "TED" chip) with an eDP Rx.
- **Panel Self-Refresh (PSR / PSR2, "Panel Replay" in newer DP)**: the T-CON has a **remote frame buffer**. When the screen is static, the GPU/link goes idle and the panel keeps refreshing from its own memory; PSR2 supports selective-region updates. Classic desktop monitors in video mode have no such self-refresh capability.
- **Backlight** control by PWM pin or over **eDP AUX/DPCD**; adaptive refresh (VRR) for battery life.

### 11.3 Comparison

| Aspect | Desktop monitor [Mon] | Laptop eDP [Lap] | Smartphone [Ph] |
| :--- | :--- | :--- | :--- |
| Input | HDMI / DP / USB-C | eDP | MIPI DSI (D-PHY / C-PHY) |
| Controller | Scaler SoC + separate T-CON | GPU/SoC + panel T-CON (+PSR memory) | Single DDIC |
| Frame memory | DRAM next to scaler (OD, FRC, etc.); no self-refresh on link loss | Panel-side buffer for PSR | GRAM in DDIC (command mode) |
| Gate drive | COF or GIP | GIP common | GIP |
| Power | AC-DC + PMIC + backlight driver | Battery rail + PMIC | Battery + separate display PMIC (OLED) |
| Light | LCD backlight (often) or OLED | LCD backlight or OLED | OLED (most) or LCD backlight |
| Idle behavior | Needs continuous video stream | PSR possible | Command mode / partial update |

---

## 12. OLED Panel Architecture [OLED]

OLED invalidates several LCD assumptions made in earlier sections:

| LCD concept | OLED reality |
| :--- | :--- |
| Voltage-controlled LC, needs polarity inversion (POL) | **Current-controlled** diode; DC drive is normal; **no POL, no VCOM** |
| $V_{COM}$ common plane | **ELVDD** (high-side supply) and **ELVSS** (cathode return) |
| Backlight dimming | **Per-pixel emission**, dimmed by drive current and/or **emission-time (PWM) control** |
| Gate driver only | **Scan driver + EM (emission) driver** |
| Passive pixel (TFT + capacitor) | **Active pixel circuit** with several TFTs and compensation |

### 12.1 Pixel circuit
- Basic form: **2T1C** (switch TFT, drive TFT, storage capacitor). The data voltage sets the *gate* of the drive TFT, which sets the OLED current.
- Real phone panels use larger circuits (e.g., **7T1C**, LTPO variants with oxide switches) that:
  - **Compensate threshold-voltage ($V_{th}$) and mobility variation** of the drive TFT (internal compensation),
  - Reset/initialize the node each frame,
  - Gate emission time via the EM line.
- **Large-format OLED (TV/monitor)** often uses **external compensation**: sensing lines and an ADC measure each pixel's drive current/voltage so the driver can correct for TFT and OLED aging and non-uniformity.

### 12.2 Drivers and power
- **Source (data) drivers** output analog data voltages (DAC/amp similar in principle to LCD but referenced to the pixel's drive requirements); in externally compensated designs, they also include **sensing/readout** paths.
- **Scan driver** selects rows; **EM driver** controls emission window and PWM dimming; both are generally GIP.
- **Power IC** provides ELVDD, ELVSS and initialization/reference rails (boost/buck-boost/inverting converters).

### 12.3 Subpixel and aging considerations
- Subpixel layouts: RGB stripe, **WOLED** (white emitter + color filters, often with a white subpixel), **QD-OLED**, **PenTile** (phone).
- **Burn-in** comes from differential aging of emitters (not DC damage like LCD). Mitigation hardware/firmware: pixel shift, logo/static-content detection, **ABL/ASBL** (auto brightness limiting), periodic compensation/refresh routines, thermal management.

---
## 13. Worked Numbers (all re-derived)

**Does 4K 144 Hz 10-bit RGB fit uncompressed over DP 1.4?**
- Active-pixel data: $3840 \times 2160 \times 30 \times 144 \approx 35.8$ Gbit/s (blanking adds more).
- DP 1.4 HBR3 x4 payload: $32.4 \times 0.8 = 25.92$ Gbit/s.
- $35.8 > 25.92$, so **DSC is required** (e.g., ~3:1 brings it to ~12 Gbit/s). DP 2.1 UHBR20 (~77.4 Gbit/s payload) carries it uncompressed.

**Pixel rate and clock** (reduced blanking, illustrative: 3920 x 2222 total): $3920 \times 2222 \times 144 \approx 1.25$ Gpixel/s; at 4 pixels per clock ≈ 313 MHz.

**Line time**: $1/(144 \times 2222) \approx 3.1\ \mu s$ per gate line.

**Frame size**: 4K 10-bit RGB ≈ 31.1 MB; phone 1080x2400x24 ≈ 7.8 MB.

**Source-driver step**: 16 V across 1024 levels ≈ 15.6 mV per level.

---

## 14. End-to-End Journey of One Pixel (LCD monitor)

1. Cable bits arrive; ESD/AC-coupling pass them to the **PHY**; training has already set rate, lanes and equalization over **AUX/SCDC**.
2. CTLE/DFE + CDR recover bits; SIPO builds words; deskew, descramble, decode, FEC.
3. **HDCP** decrypts; **DSC** decodes if enabled; packets (HDR/VRR/audio) are split off.
4. Pixel clock and timing are regenerated; pixels leave as 2-4 per clock.
5. The **scaler** converts color, scales, tone-maps, applies LUTs, computes **overdrive** against the stored previous frame, dithers, blends the OSD, and (if Mini-LED) computes **zone backlight levels**.
6. The result is serialized (**V-by-One / eDP / LVDS**) to the **T-CON**.
7. The T-CON (optionally applying panel-side OD/demura) reorders data, drives **TP/POL** and gate timing, and sends data to **source drivers**.
8. A **gate driver** raises row $y$ to $V_{GH}$; source drivers put the **gamma-derived, polarity-selected** voltages on columns; the pixel charges within ~3 µs (4K144).
9. The row drops to $V_{GL}$; the pixel holds charge. The LC rotates over milliseconds (helped by OD).
10. Meanwhile the **LED driver** supplies the backlight (static, zoned, or strobed); polarizers turn LC rotation into brightness; color filters make RGB.
11. Next row, next frame, with polarity flipped, in a loop at the refresh rate (variable if VRR).

---

## 15. Design-Domain Taxonomy: Digital RTL vs. Analog / Mixed-Signal

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│ SYNTHESIZABLE DIGITAL (Verilog / SystemVerilog)                                           │
│ • Link layer: lane deskew, descramble, TMDS/8b10b/128b132b/16b18b decode, RS-FEC, MST     │
│ • Packet parsers: infoframes, SDP, audio ACR, EDID/DPCD register logic                    │
│ • HDCP engines (cipher/hash/AES datapaths; keys in secure memory)                         │
│ • DSC decoder, scaler (line buffers, polyphase), CSC, 1D/3D LUT, dither, HDR tone map      │
│ • Overdrive engine, VRR/LFC controller, local-dimming algorithm, OSD blender               │
│ • MCU subsystem (8051/ARM/RISC-V), memory controllers (DDR PHY digital side)               │
│ • T-CON: timing FSMs (STV/CPV/OE/TP/POL), reorder/scramble/serializer framing, demura      │
└───────────────────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│ ANALOG / MIXED-SIGNAL / HARD MACROS                                                       │
│ • SerDes PHY: CTLE, DFE, CDR, PLL/VCO, SIPO, TX driver/FFE (link and internal links)       │
│ • DDR PHY, crystal oscillators and clock PLLs                                             │
│ • Source drivers: level shifters, R-string DACs, class-AB op-amps, charge-sharing switches │
│ • Gamma buffer, VCOM driver, gate-driver level shifters, HV push-pull stages              │
│ • PMIC: bucks, boosts, charge pumps (AVDD, VGH, VGL), sequencing, protection              │
│ • LED drivers: boost + constant-current sinks, PWM dimmers                                │
│ • AC-DC and PD power stages; audio DAC / class-D amp; USB-C CC/PD analog front end        │
│ • OLED: pixel-circuit drivers, sensing ADCs, ELVDD/ELVSS converters                       │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 16. Glossary

| Term | Meaning |
| :--- | :--- |
| AUX | DP bidirectional control/side channel (~1 Mbit/s) |
| AVDD | Analog supply for source-driver DAC/buffers |
| CDR | Clock and data recovery |
| COF / COG / COP | Chip on film / glass / plastic |
| CTLE / DFE | Continuous-time linear / decision-feedback equalizer |
| DCS | DSI command set |
| DDIC | Display driver IC (single-chip) |
| DPCD | DP configuration data (sink registers via AUX) |
| DSC | VESA Display Stream Compression |
| EDID | Sink capability data block |
| ELVDD / ELVSS | OLED high/low supply rails |
| EM | OLED emission-control driver |
| FRC | Frame-rate conversion, or temporal dithering (context-dependent) |
| FRL | HDMI 2.1 Fixed Rate Link |
| GIP / GOA | Gate-in-panel / gate-on-array |
| GRAM | Graphics RAM in a DDIC |
| LFC | Low-framerate compensation (VRR) |
| OD | Overdrive / response-time compensation |
| POL | Polarity-inversion control |
| PSR | Panel self-refresh |
| SCDC | HDMI status and control channel |
| STV / CPV / OE | Gate start pulse / row clock / output enable |
| TP / LOAD / STB | Source-driver line-latch and output strobe |
| VCOM | LC common-electrode voltage |
| VGH / VGL | Gate-on / gate-off voltages |
| VRR | Variable refresh rate |

---

## 17. Corrections Relative to the Previous Draft

| Previous statement | Correction |
| :--- | :--- |
| "Complete / exhaustive" six-block chain | Backlight, AC-DC, control plane (AUX/DDC/EDID/HPD/SCDC), USB-C, audio, flash/EEPROM, level shifters, gamma buffer, panel glass and OLED were absent; now added |
| PMIC labeled both "Block 6" and "7"; panel unlabeled in text | Re-partitioned into subsystems A-I with a dedicated panel section |
| DAC steps in "micro-volts" | Millivolt-class steps (e.g., ~15 mV for 10-bit over 16 V) |
| Column lines driven "down ITO traces" | Data lines are metal; ITO is for electrodes |
| MIPI LP described as "sub-millivolt" | LP is ~1.2 V single-ended; HS is ~200 mV differential |
| HDCP = "AES-128 / SHA-256" | HDCP 1.x uses a proprietary non-AES cipher; AES/SHA belong to 2.x |
| "up to 12 GHz" | 12 Gbps/lane (HDMI FRL) is ~6 GHz Nyquist; UHBR20 is ~10 GHz |
| "Spatial de-interlacing" | De-interlacing is temporal/motion-adaptive |
| Each source driver buffers a full row | Each IC buffers only its column slice |
| OD always in the scaler | Vendor-dependent; often in the panel T-CON with its own DRAM |
| T-CON "purely digital" | Mixed-signal (PLLs, SerDes I/O) |
| Monitors "no memory / video mode only" | They have DRAM, but classic monitors cannot self-refresh on link loss; eDP PSR/Panel Replay does exist |
| Phone DDIC integrates everything incl. charge pumps | LCD often; AMOLED power usually separate PMIC; gate/EM drivers are GIP |
| Panel inversion/VCOM treated as universal | LCD-only; OLED uses ELVDD/ELVSS and current drive |
| Missing STV/CPV/OE alternative | Added GIP multi-phase clocks and TP/LOAD strobe |
| "FRC" only as frame-rate conversion | Also temporal dithering for 8-bit+FRC panels |

---

## 18. Remaining Limits of This Document

Even this version is a *system-level reference*, not a full datasheet-level spec. Not covered in depth: touch-sensor subsystems, optical film physics, thermal design and EMC compliance, USB4/Thunderbolt router internals, vendor-proprietary VRR/OD algorithms and compression schemes, specific IC part numbers, and the GPU-side display engine. Numeric ranges (rail voltages, mobilities, driver channel counts, interface rates) are representative and vary by panel generation and manufacturer. Always defer to the panel datasheet and interface specs (VESA DP/eDP/DSC/DisplayID/MCCS, HDMI Forum/CTA-861, MIPI DSI/D-PHY/C-PHY, HDCP) for design work.
