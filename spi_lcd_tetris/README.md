# SPI LCD Tetris

Tetris on a 128x160 SPI LCD (ST7789/ILI9341), using about 1-2k logic cells instead of the 5.5k of the HDMI version.

## Pins
Set in `spi_lcd.cst`, on Bank 2 (3.3 V):

| Signal | Pin |
|--------|-----|
| spi_clk | 25 |
| spi_mosi | 26 |
| spi_dc | 27 |
| spi_cs | 28 |
| lcd_rst | 29 |
| lcd_bl | 30 |

## Building
1. Open `spi_lcd_tetris.gprj` in Gowin IDE (top module `top_lcd.v`, constraints `spi_lcd.cst`).
2. Synthesise and place & route, then program the bitstream.

## Controls
- **S1** - Move left
- **S2** - Move right / rotate

## Known Limitations
`spi_lcd.v` does not send the LCD initialisation commands yet, so the display has to be initialised some other way first.
