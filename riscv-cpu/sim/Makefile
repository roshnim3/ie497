SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

PKG_SRCS  := $(PWD)/../pkg/types.sv
HDL_SRCS  := $(shell find $(PWD)/../hdl -name '*.sv')
COMM_HVL  := $(shell find $(PWD)/../hvl/common                -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VCS_HVL   := $(COMM_HVL) $(shell find $(PWD)/../hvl/vcs       -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VER_HVL   := $(COMM_HVL) $(shell find $(PWD)/../hvl/verilator -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so' -o -name '*.cpp')
SRAM_SRCS := $(shell find $(PWD)/../sram/output -name '*.v')
HDRS      := $(shell find $(PWD)/../hvl -name '*.svh') $(PWD)/../hvl/common/rvfi_reference.json
DW_IP     := $(shell python3 $(PWD)/../bin/get_options.py dw_ip)
VCS_SRCS  := $(PKG_SRCS) $(HDL_SRCS) $(VCS_HVL) $(SRAM_SRCS) $(DW_IP)
VER_SRCS  := $(PKG_SRCS) $(HDL_SRCS) $(VER_HVL) $(SRAM_SRCS) $(DW_IP)

TIMEOUT   ?= 10000000

ECE411_NO_FLOAT = $(shell python3 $(PWD)/../bin/get_options.py no_float)

export VCS_ARCH_OVERRIDE=linux
COMMON_FLAGS = +incdir+$(PWD)/../hvl/common  $(ECE411_NO_FLOAT) +define+DW_SUPPRESS_WARN +incdir+$(DW)/sim_ver
VCS_FLAGS    = $(COMMON_FLAGS) +incdir+$(PWD)/../hvl/vcs -licqueue -full64 -lca -sverilog -timescale=1ps/1ps -debug_acc+all -kdb -suppress=LCA_FEATURES_ENABLED -msg_config=../vcs_warn.config -xprop=../xprop.config -xprop=flowctrl -assert svaext
VER_FLAGS    = $(COMMON_FLAGS) +incdir+$(PWD)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir build -O3 -CFLAGS "-Ofast -march=native" --x-assign fast --x-initial fast --noassert --cc --exe ../verilator_warn.vlt --trace-fst --trace-structs --trace-max-array 1048576 --trace-max-width 1048576 +define+ECE411_VERILATOR

vcs/top_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 8 $(ECE411_NO_FLOAT)
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top top_tb -o top_tb
	bash check_compile_error.sh

.PHONY: run_vcs_top_tb
run_vcs_top_tb: vcs/top_tb $(PROG)
	mkdir -p spike
	python3 ../bin/generate_memory_file.py -32 $(PROG)
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd vcs && ./top_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" \
		+ELF_ECE411="$(PWD)/bin/spike_dpi.elf"

verilator/build/Vtop_tb: $(VER_SRCS) $(HDRS)
	mkdir -p verilator/build
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 8 $(ECE411_NO_FLOAT)
	cd verilator ;\
	verilator $(VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee build/compile.log
	cd verilator/build ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_verilator_top_tb
run_verilator_top_tb: verilator/build/Vtop_tb $(PROG)
	mkdir -p spike
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -32 $(PROG)
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd verilator && ./build/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" \
		+ELF_ECE411="$(PWD)/bin/spike_dpi.elf" \
		|& tee simulation.log

.PHONY: covrep
covrep: vcs/top_tb.vdb
	cd vcs && urg -dir top_tb.vdb

.PHONY: verdi
verdi:
	mkdir -p verdi
	cd verdi && timeout $(ECE411_GUI_TIMEOUT) $(VERDI_HOME)/bin/verdi -ssf $(PWD)/vcs/dump.fsdb

.PHONY: spike
spike: $(ELF)
	mkdir -p spike
	spike --isa=$(shell python3 $(PWD)/../bin/get_options.py arch) -m0xaaaaa000:0x55556000 --log-commits $(ELF) |& tail -n +6 > spike/spike.log

.PHONY: interactive_spike
interactive_spike: $(ELF)
	spike --isa=$(shell python3 $(PWD)/../bin/get_options.py arch) -m0xaaaaa000:0x55556000 --log-commits -d $(ELF)

.PHONY: clean
clean:
	rm -rf bin vcs verdi verilator spike

########## Queue Testbench ##########
vcs/queue_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top queue_tb -o queue_tb
# 	bash check_compile_error.sh

.PHONY: run_vcs_queue_tb
run_vcs_queue_tb: vcs/queue_tb $(PROG)
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./queue_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \

########## Cache Testbench ##########
vcs/cache_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top cache_tb -o cache_tb
	bash check_compile_error.sh

.PHONY: run_vcs_cache_tb
run_vcs_cache_tb: vcs/cache_tb $(MEM)
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./cache_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+MEMLST_ECE411="$(shell readlink -f $(MEM))"
######################################

########## PPCache Testbench ##########
vcs/ppcache_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -ignore initializer_driver_checks -l compile.log -top ppcache_tb -o ppcache_tb
# 	bash check_compile_error.sh

.PHONY: run_vcs_ppcache_tb
run_vcs_ppcache_tb: vcs/ppcache_tb $(MEM)
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./ppcache_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+MEMLST_ECE411="$(shell readlink -f $(MEM))"
######################################

########## Adapter Testbench ##########
vcs/adapter_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top adapter_tb -o adapter_tb
# 	bash check_compile_error.sh

.PHONY: run_vcs_adapter_tb
run_vcs_adapter_tb: vcs/adapter_tb $(MEM)
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./adapter_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+MEMLST_ECE411="$(shell readlink -f $(MEM))"
#######################################

########## Arbiter Testbench ##########
vcs/arbiter_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top arbiter_tb -o arbiter_tb

.PHONY: run_vcs_arbiter_tb
run_vcs_arbiter_tb: vcs/arbiter_tb
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./arbiter_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" 

########## Arbiter Dual Testbench ##########
vcs/arbiter_dual_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top arbiter_dual_tb -o arbiter_dual_tb

.PHONY: run_vcs_arbiter_dual_tb
run_vcs_arbiter_dual_tb: vcs/arbiter_dual_tb
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./arbiter_dual_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" 
#######################################

########## Branch Predictor Testbench ##########
vcs/bp_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top bp_tb -o bp_tb

.PHONY: run_vcs_bp_tb
run_vcs_bp_tb: vcs/bp_tb
	rm -f vcs/bp_dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./bp_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock)
#######################################

######### Fetch Testbench ##########
vcs/fetch_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top fetch_tb -o fetch_tb

.PHONY: run_vcs_fetch_tb
run_vcs_fetch_tb: vcs/fetch_tb
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./fetch_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) 
#####################################

########## CP1 Testbench ##########
vcs/cp1_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top cp1_tb -o cp1_tb

.PHONY: run_vcs_cp1_tb
run_vcs_cp1_tb: vcs/cp1_tb $(PROG)
	rm -f vcs/dump.fsdb
	python3 ../bin/generate_memory_file.py -32 $(PROG)
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd vcs && ./cp1_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" \
		+PROG_ECE411="$(PROG)"
###################################

########## Freelist Testbench ##########
vcs/freelist_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top freelist_tb -o freelist_tb

.PHONY: run_vcs_freelist_tb
run_vcs_freelist_tb: vcs/freelist_tb
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./freelist_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock)
###################################

########## Decode/Rename Testbench ##########
vcs/decode_rename_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top decode_rename_tb -o decode_rename_tb

.PHONY: run_vcs_decode_rename_tb
run_vcs_decode_rename_tb: vcs/decode_rename_tb $(PROG)
	rm -f vcs/dump.fsdb
	python3 ../bin/generate_memory_file.py -32 $(PROG)
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd vcs && ./decode_rename_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" \
		+PROG_ECE411="$(PROG)"
###################################

########## PHT SRAM Testbench ##########
vcs/pht_sram_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top pht_sram_tb -o pht_sram_tb

.PHONY: run_vcs_pht_sram_tb
run_vcs_pht_sram_tb: vcs/pht_sram_tb
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./pht_sram_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock)
###################################

########## Stack Testbench ##########
vcs/stack_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top stack_tb -o stack_tb

.PHONY: run_vcs_stack_tb
run_vcs_stack_tb: vcs/stack_tb
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./stack_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock)
###################################

########## RAS Testbench ##########
vcs/ras_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top ras_tb -o ras_tb

.PHONY: run_vcs_ras_tb
run_vcs_ras_tb: vcs/ras_tb
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	cd vcs && ./ras_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock)
###################################