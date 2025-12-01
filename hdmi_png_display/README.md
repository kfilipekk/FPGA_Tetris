# HDMI PNG Display

My project displays a PNG image on an HDMI monitor using the Tang Nano 9K FPGA.

## How to use

1.  **Prepare your image:**
    Place the PNG image in this folder and name it `image.png` (or any other name).

2.  **Generate Verilog ROM:**
    Run the Python script to convert the image to a Verilog ROM file.
    ```bash
    python png_to_verilog.py image.png
    ```
    This will generate `src/image_rom.v`. The image will be resized to 200x150 to fit in the FPGA's Block RAM.

3.  **Open in Gowin IDE:**
    Open `hdmi_png_display.gprj` in the Gowin FPGA Designer.

4.  **Synthesize and Program:**
    Run Synthesis, Place & Route, and then program the FPGA.

## Project Structure

*   `src/`: Verilog source files.
*   `png_to_verilog.py`: Python script to convert PNG to Verilog.
*   `tangnano9k.cst`: Pin constraints for Tang Nano 9K.
*   `hdmi_png_display.gprj`: Gowin project file.

## Notes

*   The image is centered on a 640x480 screen.
*   The background color is set to dark blue in `src/top.v`.
*   The image size is hardcoded to 200x150 in the Python script and `src/top.v`. If you change it in the script, make sure to update `IMG_W` and `IMG_H` in `src/top.v`.
