SIM ?= icarus
TOPLEVEL_LANG ?= verilog

#uart_util is in mk/, the model in host/
export PYTHONPATH := $(abspath ../mk):$(abspath ../host):$(PYTHONPATH)

VERILOG_SOURCES = $(abspath $(wildcard ../rtl/*.v))

#short debounce
ifeq ($(COCOTB_TOPLEVEL),btn_toggle)
COMPILE_ARGS += -Pbtn_toggle.HOLD=4
endif

#small bucket, quick refill
ifeq ($(COCOTB_TOPLEVEL),risk_gate)
COMPILE_ARGS += -Prisk_gate.BURST=3 -Prisk_gate.REFILL=40
endif

#a bucket that never runs dry, then one of three that never refills
ifeq ($(SIM_BUILD),sim_build/hft_core)
COMPILE_ARGS += -Phft_core.BURST=1000 -Phft_core.REFILL=1073741824
endif
ifeq ($(SIM_BUILD),sim_build/hft_core_bucket)
COMPILE_ARGS += -Phft_core.BURST=3 -Phft_core.REFILL=1073741824
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
