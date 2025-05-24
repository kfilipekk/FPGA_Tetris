# HDMI Test

A 640x480 @ 60 Hz colour pattern over HDMI on the Tang Nano 9K.

## Configuration
- **Clock** - 27 MHz on pin 52; the PLL (`FBDIV_SEL=13`, `IDIV_SEL=2`, `ODIV_SEL=4`) gives 126 MHz, divided by 5 for the 25.2 MHz pixel clock
- **Pattern** - R = x[7:0], G = y[7:0], B = (x ^ y)[7:0]
- **Outputs** - ELVDS_OBUF pairs on pins 71/70, 73/72, 75/74 and 69/68 (clock)

## Building
1. Open `hdmi_test.gprj` in Gowin IDE and build.
2. Program `impl/pnr/hdmi_test.fs` with Gowin Programmer, or:
   ```bash
   openFPGALoader -b tangnano9k impl/pnr/hdmi_test.fs
   ```
