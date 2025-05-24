# Tetris for SPI LCD Display

Tetris implementation for SPI LCD displays (ST7789/ILI9341).

## Features

- **Much simpler than HDMI** - no TMDS encoding, no high-speed serialization
- **Lower resource usage** - ~1-2k logic cells (vs 5.5k for HDMI version)
- **Same game logic** - 10x12 board, 7 tetromino shapes, 8 colors
- **128x160 RGB565 output** - configured for 1.8" TFT displays (ST7789 compatible)
- **12-pixel blocks** - optimized for small display

## ⚠️ Known Limitations

**LCD Initialization Not Implemented:** The current `spi_lcd.v` module skips LCD initialization commands and goes straight to pixel mode. This works IF:
1. Your LCD module has hardware initialization (some modules auto-init on power-up)
2. OR you've pre-initialized the LCD with another device/Arduino

**For full compatibility**, the `spi_lcd` module needs initialization code to send setup commands (SLPOUT, COLMOD, DISPON, etc.) before entering pixel mode. This is a known TODO.

## Hardware Requirements

### Option 1: Tang Nano 9K + LCD Addon
- Sipeed Tang Nano 9K
- Tang Nano LCD addon (available from Sipeed)
- Update pin constraints in `spi_lcd.cst` to match your LCD pinout

### Option 2: Any Board with SPI LCD
- Update `top_lcd.v` clock frequency to match your board
- Update `spi_lcd.cst` pin assignments

## ⚠️ Pin Configuration (CRITICAL!)

**BEFORE BUILDING:** You MUST verify the SPI LCD pins in `spi_lcd.cst` match your LCD module!

The current pins are configured for a typical Tang Nano 9K LCD addon on Bank 2 (3.3V):
- `spi_clk` - Pin 25 - SPI clock
- `spi_mosi` - Pin 26 - SPI data (MOSI/SDI)
- `spi_dc` - Pin 27 - Data/Command select (DC/RS)
- `spi_cs` - Pin 28 - Chip select (active low)
- `lcd_rst` - Pin 29 - LCD reset
- `lcd_bl` - Pin 30 - Backlight enable

**How to find your LCD pinout:**
1. Check your LCD addon documentation/schematic
2. Look for silkscreen labels on the PCB
3. Search for "[Your LCD Module] Tang Nano 9K pinout"
4. Update `spi_lcd.cst` with correct pin numbers

**Bank Voltage Notes (Tang Nano 9K):**
- Bank 0: 3.3V (LVCMOS33) - Available for general use
- Bank 1: 1.8V (LVCMOS18) - Locked by board design ⚠️
- Bank 2: 3.3V (LVCMOS33) - Used for LCD pins in this design
- Bank 3: 1.8V (LVCMOS18) - Locked by HDMI connector ⚠️

**Important:** Only Bank 0 and Bank 2 support 3.3V on Tang Nano 9K!

## Building

1. Open Gowin IDE
2. Create new project or open existing
3. Add all `.v` files from `src/`
4. Set `top_lcd.v` as top module
5. Import `spi_lcd.cst` constraints
6. Synthesize (F10) and Place & Route (F11)

## Advantages Over HDMI Version

| Feature | HDMI | SPI LCD |
|---------|------|---------|
| Logic cells | ~5.5k | ~1-2k |
| Clock speed | 252 MHz | 27 MHz |
| Complexity | High (TMDS, serialization) | Low (simple shift register) |
| Pins required | 8 (4 LVDS pairs) | 6 (SPI + control) |
| External hardware | HDMI cable + monitor | LCD module only |
| Debugging | Difficult (timing critical) | Easy (slow clock) |

## Controls

- **S1 Button** - Move left
- **S2 Button** - Move right / Rotate

## License

Same as original HDMI Tetris project.
