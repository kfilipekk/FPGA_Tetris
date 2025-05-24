# HDMI Test on Tang Nano 9K — Issues Faced and How We Fixed Them

## Overview
This project adapts the HDMI demo from `hdmi_github/gowin_flipflop_drainer` for the Tang Nano 9K, building with Gowin IDE in Verilog-2001 mode. This document provides a complete technical summary of implementation issues and their resolutions.

## Hardware and Tools
- Board: Sipeed Tang Nano 9K (GW1NR-9C, GW1NR-LV9QN88PC6/I5)
- Clock: 27 MHz external oscillator on pin 52
- IDE/Tooling: Gowin IDE V1.9.11.03 Education (Verilog-2001 mode)
- Optional: OSS CAD Suite present, but final builds were done via Gowin IDE

## Final Working Configuration
- Video mode: 640×480 @ 60 Hz
  - PLL: `.FBDIV_SEL(13), .IDIV_SEL(2), .ODIV_SEL(4)` → 126 MHz 5× clock; pixel clock = 25.2 MHz via CLKDIV /5
- HDMI color pattern: 
  - R = x[7:0], G = y[7:0], B = (x ^ y)[7:0]
- Constraints (LVDS pair notation):
  - `IO_LOC "hdmi_tx_p[0]" 71,70;`
  - `IO_LOC "hdmi_tx_p[1]" 73,72;`
  - `IO_LOC "hdmi_tx_p[2]" 75,74;`
  - `IO_LOC "hdmi_tx_p[3]" 69,68;`
  - `IO_LOC "clk" 52;` with `IO_TYPE=LVCMOS33 PULL_MODE=UP`
  - `IO_LOC "led_n" 10;`
- Output buffers: ELVDS_OBUF for GW1N9 devices

## Files Changed (key points)
- `src/top.v`
  - Converted SystemVerilog-only constructs to Verilog-2001: `wire [8:0] adder_clk;` (instead of `wire adder_clk[9]`)
  - Removed SV casting like `8'(x)`; used standard slices `{x[7:0], y[7:0], (x^y)[7:0]}`
  - Declared `x`, `y`, `hve` as `wire` (module outputs), not `reg`
  - Set PLL to 640×480@60 preset; register HDMI reset to `~hdmi_clk_lock`
- `src/display_signal.v`
  - Sized math to signed 13-bit to avoid truncation: explicit `[12:0]` localparams and `13'sd` constants
  - Force sync polarity parameters to 1 bit (`HSP`, `VSP`) to avoid 65→3 truncation in the `{de, vs, hs}` concat
- `src/hdmi.v`
  - Replaced `$countones` and other SV features with Verilog-2001-friendly logic
  - Sized constants (e.g. `4'sd4`, `4'sd0`) to remove 32→4 truncation warnings
  - Prevented optimizer from sweeping encoders by adding `/* synthesis syn_keep=1 */` and `(* keep="true" *)` to TMDS nets and encoder instances (especially `encode_g` and `encode_r`)
- `src/tangnano9k.cst`
  - Correct LVDS pair pin notation (comma-separated pin-pairs in one IO_LOC line per differential signal)

## Build and Program
- Build in Gowin IDE (this project uses `hdmi_test.gprj`).
- Generated bitstream: `impl/pnr/hdmi_test.fs`
- Program via Gowin Programmer or (optionally) openFPGALoader:
  - `openFPGALoader -b tangnano9k impl/pnr/hdmi_test.fs`

## Implementation Summary
1. Objective: Adapt HDMI demo from `hdmi_github` to `hdmi_test` with consistent build configuration.
2. Initial porting caused synthesis errors due to SystemVerilog-only syntax in a Verilog-2001 flow:
   - Fixed `wire adder_clk[9]` → `wire [8:0] adder_clk`
   - Replaced `8'(x)` casts with standard slices
   - Removed `$countones`; implemented equivalent logic with sums and pipelines
3. Missing declarations and type mismatches:
   - Added `wire hdmi_clk, hdmi_clk_5x, hdmi_clk_lock`
   - Made `display_signal` outputs `wire` instead of `reg`
4. PLL/video mode and no-video issues:
   - Switched to 640×480@60 Hz (126 MHz serdes, 25.2 MHz pixel) for stable sync
   - Ensured HDMI reset deasserts on `hdmi_clk_lock`
5. Constraints wrong LVDS syntax:
   - Used comma-separated LVDS pair notation per Gowin syntax (e.g., `71,70`)
6. Encoders optimized away (swept):
   - Synthesis swept `encode_g` and `encode_r` despite dynamic data
   - Resolved by adding `syn_keep`/`keep` on TMDS nets and encoder instances so the tool preserves them
7. Truncation warnings (EX3791):
   - `display_signal.v`: 65→3 truncation in `o_hve` concat and 32→13 in coordinate math → fixed by explicit widths and 1-bit polarities
   - `hdmi.v`: 32→4 warnings in bias/eon arithmetic → fixed by sizing constants
8. Final synthesis notes:
   - `adder_pll` swept (expected — unused display test logic)
   - `TA1132`: derived clock note (informational). Optional: add a pixel clock constraint for enhanced timing analysis
9. Result: Successful HDMI output with gradient pattern. LED logic operational, monitor synchronized at 640×480@60.

## Troubleshooting Checklist
- No video or unstable sync:
  - Verify PLL settings and that `hdmi_clk_lock` is true (reset is `~hdmi_clk_lock`)
  - Confirm constraints (LVDS pairs and clock pin) match your board
  - Ensure serializers (OSER10) are clocked with `hdmi_clk` and `hdmi_clk_5x`
- Encoders missing in reports:
  - Check that `encode_b/g/r` are present; if swept, add `syn_keep`/`keep` to both nets and instances
- Truncation warnings:
  - Ensure constants and parameters are explicitly sized to the target width

## Optional Cleanups
- Remove the unused "adder" PLL and CLKDIV chain in `top.v` to silence sweep warnings
- Add a timing constraint for the derived pixel clock (`hdmi_clk`) to improve timing analysis coverage

## Example Mapping Reference
- TMDS mapping:
  - `tmds_ch0` → Blue
  - `tmds_ch1` → Green
  - `tmds_ch2` → Red
  - `tmds_ch3` → TMDS clock (via constant pattern serializer)
- Output buffers: `ELVDS_OBUF` on GW1N9 devices

## Status
- Build: PASS
- Programming: PASS
- HDMI Output: PASS (640×480@60 gradient pattern)

