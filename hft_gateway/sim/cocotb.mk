SIM ?= icarus
TOPLEVEL_LANG ?= verilog

#uart_util is in mk/
export PYTHONPATH := $(abspath ../mk):$(PYTHONPATH)

VERILOG_SOURCES = $(abspath $(wildcard ../rtl/*.v))

#short debounce
ifeq ($(COCOTB_TOPLEVEL),btn_toggle)
COMPILE_ARGS += -Pbtn_toggle.HOLD=4
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
