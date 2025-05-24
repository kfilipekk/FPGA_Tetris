# Tang Nano 9K - LED Blinker

LED blinker implementation for the Tang Nano 9K FPGA board. All 6 onboard LEDs blink at different rates to create a cascading visual effect.

## Status

Successfully tested and verified on Tang Nano 9K hardware.

## Project Overview

This project demonstrates:
- Tang Nano 9K LED polarity (active-LOW)
- Bank voltage requirements (1.8V for Bank 3)
- Open-source vs vendor toolchain differences
- FPGA programming workflows

## Hardware Configuration

**FPGA Board**: Tang Nano 9K
- **FPGA Chip**: Gowin GW1NR-LV9QN88PC6/I5
- **Device ID**: 0x1100481B
- **Clock**: 27 MHz external oscillator (pin 52, Bank 1, LVCMOS33)
- **LEDs**: 6 onboard LEDs (pins 10, 11, 13, 14, 15, 16, Bank 3, LVCMOS18)
- **LED Polarity**: **ACTIVE-LOW** (0 = ON, 1 = OFF) ⚠️

## LED Blink Rates

Each LED blinks at a different rate using different bits of a 26-bit counter:

| LED | Pin | Counter Bit | Frequency | Description |
|-----|-----|-------------|-----------|-------------|
| 0   | 10  | bit[20]     | ~25 Hz    | Fastest blink |
| 1   | 11  | bit[21]     | ~13 Hz    | |
| 2   | 13  | bit[22]     | ~6 Hz     | |
| 3   | 14  | bit[23]     | ~3 Hz     | |
| 4   | 15  | bit[24]     | ~1.6 Hz   | |
| 5   | 16  | bit[25]     | ~0.8 Hz   | Slowest blink |

**Calculation**: Frequency = 27,000,000 Hz ÷ (2^n) where n is the counter bit number

## Quick Start

### Option 1: Gowin IDE (Recommended for Final Bitstream)

1. Open `led_blink.gprj` in Gowin IDE
2. Run synthesis and place & route (Process → Run All)
3. Open Gowin Programmer
4. Load bitstream: `impl/pnr/led_blink.fs`
5. Select programming mode (SRAM for testing, Flash for permanent)
6. Click "Program/Configure"
7. Verify LED operation

### Option 2: OSS CAD Suite (Development)

```powershell
cd led_blink
.\build_powershell.ps1
```

**Note**: OSS CAD Suite generates bitstreams with device ID mismatch. Use Gowin IDE for final bitstream that works on hardware.

## Files

- `top.v` - LED blinker Verilog code
- `tangnano9k.cst` - Pin constraints with correct voltage levels
- `led_blink.gprj` - Gowin IDE project file
- `build_powershell.ps1` - OSS CAD Suite build script
- `upload.ps1` - Programming instructions
- `README.md` - This file

## Key Technical Details

### Critical Implementation Details

1. **Active-LOW LEDs**: Tang Nano 9K LEDs require inverted logic
   ```verilog
   assign led[0] = ~counter[20];  //NOT operator is required
   ```

2. **Bank 3 Voltage**: Bank 3 is hardwired to 1.8V (due to HDMI connector)
   - Must use `LVCMOS18` for all Bank 3 pins
   - Using `LVCMOS33` causes build errors

3. **Device ID Mismatch**: OSS CAD Suite generates bitstreams with wrong device ID
   - OSS tools: Use for development/testing
   - Gowin IDE: Required for final bitstream that works on hardware

4. **Flash Auto-Boot**: Flash memory auto-boots on power-up
   - Can override SRAM programming
   - Solution: Erase flash before SRAM testing

## The Code Explained

### top.v Structure

```verilog
module top (
    input clk,           // 27 MHz clock from pin 52
    output [5:0] led     // 6-bit output for LEDs
);
    reg [25:0] counter = 0;  // 26-bit counter
    
    always @(posedge clk) begin
        counter <= counter + 1;  // Increment every clock cycle
    end
    
    // Active-LOW assignments (inverted with ~)
    assign led[0] = ~counter[20];  // Fastest
    assign led[1] = ~counter[21];
    assign led[2] = ~counter[22];
    assign led[3] = ~counter[23];
    assign led[4] = ~counter[24];
    assign led[5] = ~counter[25];  // Slowest
endmodule
```

**Operation**:
1. Counter increments at 27 MHz (27 million times/second)
2. Each bit of the counter toggles at half the frequency of the previous bit
3. Bit 20 toggles every 2^20 clock cycles = ~25 Hz
4. Bit 25 toggles every 2^25 clock cycles = ~0.8 Hz
5. NOT operator (~) inverts the signal because LEDs are active-LOW

### Pin Constraints (tangnano9k.cst)

```
// Clock on Bank 1 (3.3V)
IO_LOC "clk" 52;
IO_PORT "clk" IO_TYPE=LVCMOS33;

// LEDs on Bank 3 (1.8V - locked by HDMI connector)
IO_LOC "led[0]" 10;
IO_PORT "led[0]" IO_TYPE=LVCMOS18;  // Must be LVCMOS18!
// ... (repeat for led[1] through led[5])
```

## Toolchain Workflow

### Development Cycle (OSS CAD Suite)

1. **Synthesis** (Yosys): Converts Verilog to netlist
   ```bash
   yosys -p "read_verilog top.v; synth_gowin -top top -json top.v.json"
   ```

2. **Place & Route** (nextpnr-himbaechel): Maps netlist to physical FPGA
   ```bash
   nextpnr-himbaechel --json top.v.json --write top.v_pnr.json \
       --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C \
       --vopt cst=tangnano9k.cst
   ```

3. **Bitstream Generation** (gowin_pack): Creates .fs file
   ```bash
   gowin_pack -d GW1N-9C -o top.fs top.v_pnr.json
   ```

**Limitation**: Generated bitstream has device ID mismatch and won't program correctly.

### Production (Gowin IDE)

1. Open project in Gowin IDE
2. Run synthesis and P&R
3. Generate bitstream (correct device ID)
4. Program with Gowin Programmer

## Debugging Journey

This simple LED blinker required solving 10 major problems:

### Problem 1: OSS CAD Suite Setup
- **Issue**: No pre-built Windows binaries for nextpnr-himbaechel
- **Solution**: Found OSS CAD Suite with all tools included

### Problem 2: Device Naming
- **Issue**: Wrong device strings caused errors
- **Solution**: Researched correct naming: `GW1NR-LV9QN88PC6/I5` for nextpnr, `GW1N-9C` for gowin_pack

### Problem 3: MSYS2 vs Native Binaries
- **Issue**: MSYS2 bash scripts failed with path issues
- **Solution**: Switched to PowerShell with native Windows binaries

### Problem 4: Pin Conflicts
- **Issue**: LED pins 11 and 15 overlap with HDMI Blue/Green channels
- **Solution**: Initially removed conflicting LEDs, later understood we can use all 6 for LED-only design

### Problem 5: Bank Voltage Mismatch
- **Issue**: `CT1136: Bank 3 vccio(1.8) locked... conflicting LVCMOS33`
- **Solution**: Changed all Bank 3 pins from LVCMOS33 → LVCMOS18

### Problem 6: Gowin IDE Project Configuration
- **Issue**: Needed correct device part number for IDE
- **Solution**: `GW1NR-LV9QN88PC6/I5` (found in chip markings)

### Problem 7: Bitstream Device ID Mismatch
- **Issue**: OSS CAD Suite bitstreams had wrong device ID (0x0900281B vs 0x1100481B)
- **Solution**: Use Gowin IDE for final bitstream generation

### Problem 8: USB Driver Conflicts
- **Issue**: openFPGALoader didn't work reliably
- **Solution**: Use Gowin Programmer with FTDI VCP drivers

### Problem 9: Flash Auto-Boot
- **Issue**: Flash memory auto-boots on power-up, overriding SRAM programming
- **Solution**: Erase flash before SRAM testing: Operations → Erase Flash in Gowin Programmer

### Problem 10: LEDs Not Blinking (The Big One!)
- **Issue**: After successful programming, LEDs remained dark
- **7 Debugging Attempts**:
  1. ❌ HDMI + LEDs design → No output
  2. ❌ Removed conflicting pins → Still dark
  3. ❌ Tried internal oscillator → Still dark
  4. ❌ Tried active-LOW (constant) → Still dark
  5. ✅ Fixed bank voltage to LVCMOS18 → Build works but still dark
  6. ❌ Erased flash, reprogrammed → Still dark
  7. ✅ **Solution**: Simplified to single LED with `~counter[23]` → Successful operation

**Root Causes**:
- LEDs are **ACTIVE-LOW** - need `~signal`, not `signal`
- Bank 3 must use **LVCMOS18**, not LVCMOS33
- Over-complexity hid the fundamental issues
- Simplification revealed the problems

## Key Lessons Learned

1. **Simplify to Debug**: Strip everything down to the absolute minimum
2. **Active-LOW vs Active-HIGH**: Check LED polarity in schematics
3. **Bank Voltage Matters**: Each bank can have different voltage levels
4. **Device ID Mismatch**: Open-source tools may not generate vendor-compatible bitstreams
5. **Flash vs SRAM**: Understand non-volatile vs volatile programming modes
6. **Pin Conflicts**: Check for shared pins between peripherals
7. **USB Driver Ecosystem**: Vendor tools often have better driver support
8. **PowerShell > MSYS2**: Native Windows binaries work better than POSIX emulation
9. **Read Vendor Docs**: Community tutorials are great, but vendor docs have critical details
10. **Persistence Pays Off**: 7 debugging attempts, but we got there!

## Hardware Facts

- **Tang Nano 9K LEDs**: Active-LOW (0=ON, 1=OFF)
- **Bank 3 Voltage**: 1.8V (locked by HDMI connector on board)
- **Bank 1 Voltage**: 3.3V (for clock and other peripherals)
- **Device ID**: 0x1100481B (production chips)
- **Clock Frequency**: 27 MHz external oscillator
- **Flash Programming**: Survives power cycles, auto-boots on startup
- **SRAM Programming**: Lost on power cycle, erased by flash auto-boot

## Resources

- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) - Open-source FPGA toolchain
- [Gowin IDE](http://www.gowinsemi.com/en/support/download_eda/) - Vendor IDE (required for final bitstream)
- [Tang Nano 9K Schematics](https://dl.sipeed.com/shareURL/TANG/Nano%209K) - Official hardware documentation
- [nextpnr-himbaechel](https://github.com/YosysHQ/nextpnr/tree/master/himbaechel) - Gowin FPGA support in nextpnr
- [Tang Nano 9K LED Tutorial](https://wiki.sipeed.com/hardware/en/tang/tang-nano-9k/examples/led.html) - Official LED example

## Credits

This project documents a complete journey from initial setup through extensive debugging to final success. Key discoveries include:

- **Active-LOW LED polarity** on Tang Nano 9K
- **Bank 3 voltage** locked to 1.8V by HDMI connector
- **Device ID mismatch** in OSS CAD Suite bitstreams
- **Flash auto-boot** behavior and SRAM programming conflicts
- **Complete OSS CAD Suite workflow** with PowerShell on Windows
- **Hybrid toolchain approach**: OSS for development, Gowin IDE for production

The debugging process (especially the "LEDs not blinking" challenge with 7 attempts) demonstrates the importance of systematic troubleshooting and simplification when facing complex problems.

**Hardware Status**: Verified working - all 6 LEDs blinking in cascade pattern.

---

**Platform**: Gowin GW1NR-9C FPGA • OSS CAD Suite • PowerShell
