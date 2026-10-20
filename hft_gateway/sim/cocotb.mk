SIM ?= icarus
TOPLEVEL_LANG ?= verilog

#uart_util is in mk/, the model in host/
export PYTHONPATH := $(abspath ../mk):$(abspath ../host):$(PYTHONPATH)

VERILOG_SOURCES = $(abspath $(wildcard ../rtl/*.v))

#an _lse build is the same one with venue 1
BUILD := $(notdir $(SIM_BUILD))
BASE  := $(BUILD:_lse=)
ifneq ($(BASE),$(BUILD))
COMPILE_ARGS += -P$(COCOTB_TOPLEVEL).VENUE=1
export VENUE := lse
endif
ifeq ($(COCOTB_TOPLEVEL),mitch_parser)
export VENUE := lse
endif

#short debounce
ifeq ($(COCOTB_TOPLEVEL),btn_toggle)
COMPILE_ARGS += -Pbtn_toggle.HOLD=4
endif

#fast uart, short timeout
ifeq ($(COCOTB_TOPLEVEL),uart_rx)
COMPILE_ARGS += -Puart_rx.DIV=16
endif
ifeq ($(COCOTB_TOPLEVEL),mold_rx)
COMPILE_ARGS += -Pmold_rx.IDLE=50
endif

#small bucket, quick refill
ifeq ($(COCOTB_TOPLEVEL),risk_gate)
COMPILE_ARGS += -Prisk_gate.BURST=3 -Prisk_gate.REFILL=40
endif

#no refill
ifeq ($(BASE),hft_core)
COMPILE_ARGS += -Phft_core.BURST=1000 -Phft_core.REFILL=1073741824
endif
ifeq ($(BASE),hft_core_bucket)
COMPILE_ARGS += -Phft_core.BURST=3 -Phft_core.REFILL=1073741824
endif

#fast spi, short gaps
ifeq ($(COCOTB_TOPLEVEL),feed_gen)
COMPILE_ARGS += -Pfeed_gen.HALF=2 -Pfeed_gen.GAP=300 -Pfeed_gen.SCEN_GAP=100
endif
ifeq ($(BASE),top)
COMPILE_ARGS += -Ptop.UART_DIV=8 -Ptop.HALF=2 -Ptop.GAP=400000 -Ptop.SCEN_GAP=14000 \
                -Ptop.BTN_HOLD=4 -Ptop.REFILL=1073741824 -Ptop.HOST_HOLD=30000
endif

#board rates
ifeq ($(BASE),top_la)
COMPILE_ARGS += -Ptop.BTN_HOLD=4
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
