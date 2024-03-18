#########################################################################################
# pre-process ARA into a single blackbox file
#########################################################################################
base_dir=$(abspath ../../../../../../..)
vsrc_dir=$(abspath .)
ara_dir=$(vsrc_dir)/ara/hardware

# name of output pre-processed verilog file
PREPROC_VERILOG = $(vsrc_dir)/ARACoreBlackbox.preprocessed.sv

.PHONY: default $(PREPROC_VERILOG)
default: $(PREPROC_VERILOG) $(BENDER)
# $(MAKE) -C $(ara_dir) update apply-patches

BENDER = $(ara_dir)/bender
$(BENDER):
	$(MAKE) -C $(ara_dir) update apply-patches

#########################################################################################
# includes and vsrcs
#########################################################################################

BENDER_CMD = $(BENDER) -d $(ara_dir)/.. sources --flatten -t fpga -t cv64a6_imafdcv_sv39 -t xilinx -t tech_cells_generic_include_tc_sram -t tech_cells_generic_include_tc_clk -t cva6_test
ARA_VSRCS_BENDER = $(BENDER_CMD) | jq -r ".[] | .files | .[]" | grep -v \\.vhd
ARA_VSRCS = \
	$(shell $(ARA_VSRCS_BENDER) | grep -e pkg) \
	$(ara_dir)/deps/cva6/corev_apu/include/traced_instr_pkg.sv \
	$(shell $(ARA_VSRCS_BENDER) | grep -v pkg)

ARA_WRAPPER = \
	$(vsrc_dir)/axi_master_connect.sv \
	$(vsrc_dir)/ARACoreBlackbox.sv

ARA_VSRCS_ALL = $(ARA_VSRCS) $(ARA_WRAPPER)

#########################################################################################
# pre-process using verilator
#########################################################################################

lookup_dirs = $(shell find -L $(ara_dir) -name target -prune -o -type d -print 2> /dev/null | grep '.*/\($(1)\)$$')
INC_DIR_NAMES ?= include inc
INC_DIRS ?= \
	$(foreach dir_name,$(INC_DIR_NAMES),$(call lookup_dirs,$(dir_name))) \
	$(shell $(BENDER_CMD) | jq -r ".[] | .include_dirs | .[]" | sort) \
	$(vsrc_dir)/include

# these flags are specific to Chipyard
EXTRA_PREPROC_DEFINES ?=
PREPROC_DEFINES ?= \
	WT_DCACHE \
	DISABLE_TRACER \
	SRAM_NO_INIT \
	VERILATOR \
	TARGET_VIVADO \
	FPGA_TARGET_XILINX \
	$(EXTRA_PREPROC_DEFINES)

PREPROC_SCRIPT = $(base_dir)/scripts/insert-includes.py

$(PREPROC_VERILOG): $(BENDER) $(ARA_VSRCS_ALL)
	mkdir -p $(dir $(PREPROC_VERILOG))

	$(foreach def,$(PREPROC_DEFINES),echo "\`define "$(def)"" >> def.v; )
	echo "\`define VLEN 2048" >> def.v
	echo "\`define RVV_ARIANE 1'b1" >> def.v
	echo "\`define ARIANE_ACCELERATOR_PORT 1'b1" >> def.v
	echo "\`define NR_LANES 2" >> def.v

	$(foreach def,$(PREPROC_DEFINES),echo "\`undef "$(def)"" >> undef.v; )
	echo "\`undef VLEN" >> undef.v
	echo "\`undef RVV_ARIANE" >> undef.v
	echo "\`undef ARIANE_ACCELERATOR_PORT" >> undef.v
	echo "\`undef NR_LANES" >> undef.v

	cat def.v $(ARA_VSRCS_ALL) undef.v > combined.sv
	sed -i '/l15.tmp.h/d' combined.sv
	sed -i '/define.tmp.h/d' combined.sv
	$(PREPROC_SCRIPT) combined.sv $@ $(INC_DIRS)
	rm -rf combined.sv def.v undef.v

clean:
	rm -rf $(PREPROC_VERILOG)
