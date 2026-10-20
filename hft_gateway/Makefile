TOP     = top
SOURCES = rtl/top.v rtl/feed_gen.v rtl/spi_rx.v rtl/uart_rx.v rtl/mold_rx.v rtl/cfg.v \
          rtl/itch_parser.v rtl/mitch_parser.v rtl/crc32.v \
          rtl/risk_gate.v rtl/order_tx.v rtl/hft_core.v rtl/uart_tx.v rtl/btn_toggle.v
CST_EXTRA = hft.cst

include mk/gowin.mk

#lse: mitch in, native new order out
lse:
	$(MAKE) BUILD=build_lse PARAMS="chparam -set VENUE 1 top"

flash-lse: lse
	openFPGALoader -b $(BOARD) build_lse/$(TOP).fs

lint-lse:
	verilator --lint-only -Wall -Wno-PROCASSINIT --top-module $(TOP) -GVENUE=1 $(SOURCES)

.PHONY: lse flash-lse lint-lse
