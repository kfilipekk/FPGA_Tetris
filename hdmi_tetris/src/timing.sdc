# timing.sdc — minimal timing constraints for HDMI clocks on Tang Nano 9K

# Primary reference clock (27 MHz board oscillator)
create_clock -name CLK27 -period 37.037 [get_ports {clk}]

# Note: Gowin toolchain doesn't handle fractional multiply_by well for generated clocks
# Relying on auto-derived clocks from PLL and CLKDIV primitives instead
