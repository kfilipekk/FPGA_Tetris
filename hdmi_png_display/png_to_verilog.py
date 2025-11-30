import sys
import os
from PIL import Image

def generate_verilog(image_path, output_path):
    try:
        img = Image.open(image_path)
        print(f"Opened image: {image_path}")
    except Exception as e:
        print(f"Error opening image: {e}")
        ##create a dummy image if not found
        print("Creating a dummy pattern image...")
        img = Image.new('RGB', (200, 150), color = 'red')
        for x in range(200):
            for y in range(150):
                img.putpixel((x, y), (x % 255, y % 255, (x+y) % 255))
    
    width = 200
    height = 150
    img = img.resize((width, height))
    img = img.convert('RGB')
    
    with open(output_path, 'w') as f:
        f.write(f"module image_rom (\n")
        f.write(f"    input wire clk,\n")
        f.write(f"    input wire [15:0] addr,\n")
        f.write(f"    output reg [23:0] data\n")
        f.write(f");\n")
        f.write(f"    // Image size: {width}x{height}\n")
        f.write(f"    (* ram_style = \"block\" *)\n")
        f.write(f"    reg [23:0] rom [0:{width*height-1}];\n")
        f.write(f"    initial begin\n")
        
        pixels = list(img.getdata())
        for i, pixel in enumerate(pixels):
            r, g, b = pixel
            hex_val = (r << 16) | (g << 8) | b
            f.write(f"        rom[{i}] = 24'h{hex_val:06X};\n")
            
        f.write(f"    end\n")
        f.write(f"    always @(posedge clk) begin\n")
        f.write(f"        data <= rom[addr];\n")
        f.write(f"    end\n")
        f.write(f"endmodule\n")

    print(f"Generated {output_path} from {image_path} (Resized to {width}x{height})")

if __name__ == "__main__":
    input_img = "image.png"
    if len(sys.argv) > 1:
        input_img = sys.argv[1]
    
    output_verilog = "src/image_rom.v"
    ##ensure src directory exists
    os.makedirs(os.path.dirname(output_verilog), exist_ok=True)
    
    generate_verilog(input_img, output_verilog)
