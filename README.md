# FPGA Tetris

Collection of FPGA projects for the Tang Nano 9K development board. Main project is the Tetris Game.

## Build

1. Open the `.gprj` file in Gowin IDE
2. Run synthesis and place & route (Process → Run All)
3. Bitstream will be generated in `impl/pnr/`

## Programming

Use Gowin Programmer to upload bitstream:
- **SRAM mode**: Temporary (lost on power cycle)
- **Flash mode**: Permanent (survives power cycle)

Each project folder contains its own README with specific details.
