# HDMI Tetris

Tetris on a 640x480 @ 60 Hz HDMI output, built on the HDMI test project.

## Design
- **tetris_game.v** - 10x20 board and the falling piece, with a read port the renderer queries per pixel
- **tetris_video.v** - Maps each pixel to a board cell, overlays the falling piece and outputs RGB
- **top.v** - Connects the game to the renderer and the HDMI encoder

Line clearing scans and shifts one row per clock tick. Doing it in a single tick unrolled into too much logic for the device.

## Resource Usage
| Resource | Used |
|----------|------|
| Logic | 5274 / 8640 (62%) |
| Registers | 4416 / 6693 (66%) |

## Building
1. Open `hdmi_test.gprj` in Gowin IDE and build.
2. Program `impl/pnr/hdmi_test.fs`.

Clocking and pins are the same as `hdmi_test_working`.
