# =============================================================================
# Makefile for display-sink-rtl Verification & Simulation
# Supports both Verilator (lint & fast cycle-accurate sim) and QuestaSim (vlog/vsim)
# =============================================================================

SHELL := /bin/bash
SIM_DIR := $(shell pwd)
REPO_ROOT := $(SIM_DIR)/..

VERILATOR := verilator
VLOG := vlog
VSIM := vsim

.PHONY: all lint sim-questa sim-verilator wave clean help

all: lint sim-questa

help:
	@echo "Available Targets:"
	@echo "  make lint           : Run strict Verilator static linting (-Wall)"
	@echo "  make sim-questa     : Compile and run testbench with QuestaSim"
	@echo "  make wave           : Open GTKWave with simulated T-CON waveforms"
	@echo "  make clean          : Remove compilation artifacts and waveform dumps"

lint:
	@echo "==> [LINT] Running Verilator on display-sink-rtl..."
	$(VERILATOR) --lint-only -Wall \
		-Wno-DECLFILENAME \
		-Wno-WIDTHEXPAND \
		-Wno-WIDTHTRUNC \
		-Wno-UNUSEDSIGNAL \
		-f files.f \
		--top-module display_sink_top
	@echo "==> [LINT] SUCCESS: Clean lint with zero warnings!"

sim-questa:
	@echo "==> [QUESTA] Compiling design and testbench..."
	mkdir -p work
	$(VLOG) -sv -f files.f ../tb/tb_tcon.sv
	@echo "==> [QUESTA] Running T-CON simulation..."
	$(VSIM) -c -do "run -all; quit" tb_tcon

sim-scaler:
	@echo "==> [QUESTA] Compiling Scaler design and testbench..."
	mkdir -p work
	$(VLOG) -sv -f files.f ../tb/tb_scaler.sv
	@echo "==> [QUESTA] Running Scaler simulation..."
	$(VSIM) -c -do "run -all; quit" tb_scaler

sim-color:
	@echo "==> [QUESTA] Compiling Color Pipeline design and testbench..."
	mkdir -p work
	$(VLOG) -sv -f files.f ../tb/tb_color.sv
	@echo "==> [QUESTA] Running Color Pipeline simulation..."
	$(VSIM) -c -do "run -all; quit" tb_color

sim-top:
	@echo "==> [QUESTA] Compiling Master Top-Level design and testbench..."
	mkdir -p work
	$(VLOG) -sv -f files.f ../tb/tb_top.sv
	@echo "==> [QUESTA] Running Master Regression simulation..."
	$(VSIM) -c -do "run -all; quit" tb_top

wave:
	@if [ -f tcon_waves.vcd ]; then \
		gtkwave tcon_waves.vcd & \
	else \
		echo "Run 'make sim-questa' first to generate tcon_waves.vcd"; \
	fi

clean:
	rm -rf work transcript vsim.wlf tcon_waves.vcd obj_dir
