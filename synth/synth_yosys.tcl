# ==============================================================================
# File: synth_yosys.tcl
# Description: Automated Yosys Synthesis & PPA Characterization TCL Script
# Target: display_sink_top (Full Display Sink Master Subsystem)
# ==============================================================================

yosys -import

yosys verilog_defines -DYOSYS

yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/common/dp_ram_line_buffer.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/pattern/pattern_generator_live.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/scaler/polyphase_coeff_rom.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/scaler/horizontal_scaler.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/scaler/vertical_scaler.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/scaler/scaler_top.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/color/csc_matrix.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/color/gamma_lut.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/color/dither_frc.sv
yosys read_verilog -sv -I../rtl/color ../rtl/color/color_top.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/csr ../rtl/csr/display_sink_csr.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/tcon/tcon_timing_fsm.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/top/axis_video_rx.sv
yosys read_verilog -sv -I../rtl/common -I../rtl/color ../rtl/top/display_sink_top.sv

yosys hierarchy -check -top display_sink_top

yosys proc
yosys opt
yosys check -assert

yosys memory -nomap
yosys opt

yosys synth -top display_sink_top

yosys tee -o ppa_report.txt stat
