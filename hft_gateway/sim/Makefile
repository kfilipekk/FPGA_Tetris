#one run per module, `make crc32` for just one

UNITS = uart_tx uart_rx btn_toggle crc32 spi_rx mold_rx cfg itch_parser mitch_parser \
        risk_gate order_tx hft_core feed_gen top
LSE   = order_tx_lse hft_core_lse feed_gen_lse top_lse

all: $(UNITS) hft_core_bucket top_la $(LSE)

$(UNITS):
	$(MAKE) -f cocotb.mk COCOTB_TOPLEVEL=$@ COCOTB_TEST_MODULES=test_$@ \
		SIM_BUILD=sim_build/$@ COCOTB_RESULTS_FILE=sim_build/$@/results.xml

#the same tests with venue 1
$(LSE):
	$(MAKE) -f cocotb.mk COCOTB_TOPLEVEL=$(@:_lse=) COCOTB_TEST_MODULES=test_$(@:_lse=) \
		SIM_BUILD=sim_build/$@ COCOTB_RESULTS_FILE=sim_build/$@/results.xml

#bucket of three
hft_core_bucket:
	$(MAKE) -f cocotb.mk COCOTB_TOPLEVEL=hft_core COCOTB_TEST_MODULES=test_$@ \
		SIM_BUILD=sim_build/$@ COCOTB_RESULTS_FILE=sim_build/$@/results.xml

#board rates
top_la:
	$(MAKE) -f cocotb.mk COCOTB_TOPLEVEL=top COCOTB_TEST_MODULES=test_$@ \
		SIM_BUILD=sim_build/$@ COCOTB_RESULTS_FILE=sim_build/$@/results.xml

clean:
	rm -rf sim_build __pycache__

.PHONY: all clean $(UNITS) $(LSE) hft_core_bucket top_la
