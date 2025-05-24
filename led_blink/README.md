# LED Blinker

Six onboard LEDs blinking at different rates from a 26-bit counter, as a first test of the Tang Nano 9K.

## Hardware
- **Clock** - 27 MHz oscillator on pin 52 (Bank 1, LVCMOS33)
- **LEDs** - Pins 10, 11, 13, 14, 15, 16 (Bank 3, LVCMOS18), active-low
- **Rates** - Counter bits 20 to 25, about 25 Hz down to 0.8 Hz

## Building
1. Open `led_blink.gprj` in Gowin IDE and run synthesis and place & route.
2. Program `impl/pnr/led_blink.fs` with Gowin Programmer (SRAM to test, Flash to keep).

Bank 3 must be set to 1.8 V or the LEDs stay dark.
