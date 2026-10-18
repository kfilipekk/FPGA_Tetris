#one run per module, `make crc32` for just one

UNITS = uart_tx uart_rx btn_toggle crc32 spi_rx mold_rx cfg itch_parser risk_gate \
        ouch_tx hft_core feed_gen top

all: $(UNITS) hft_core_bucket

$(UNITS):
	$(MAKE) -f cocotb.mk COCOTB_TOPLEVEL=$@ COCOTB_TEST_MODULES=test_$@ \
		SIM_BUILD=sim_build/$@ COCOTB_RESULTS_FILE=sim_build/$@/results.xml

#the engine with a bucket of three
hft_core_bucket:
	$(MAKE) -f cocotb.mk COCOTB_TOPLEVEL=hft_core COCOTB_TEST_MODULES=test_$@ \
		SIM_BUILD=sim_build/$@ COCOTB_RESULTS_FILE=sim_build/$@/results.xml

clean:
	rm -rf sim_build __pycache__

.PHONY: all clean $(UNITS) hft_core_bucket
