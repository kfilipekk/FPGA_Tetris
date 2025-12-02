import sys
import os
from PIL import Image

def extract_frames_from_video(video_path, num_frames=16):
    try:
        import cv2
    except ImportError:
        print("opencv-python not installed. Install with: pip install opencv-python")
        return []
    
    frames = []
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        print(f"Error: Could not open video {video_path}")
        return []
    
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    print(f"Video: {total_frames} frames @ {fps:.2f} FPS")
    
    step = max(1, total_frames // num_frames)
    
    for i in range(num_frames):
        frame_idx = i * step
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ret, frame = cap.read()
        
        if ret:
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            img = Image.fromarray(frame_rgb)
            img = img.resize((200, 150)).convert('RGB')
            frames.append(img)
            print(f"Extracted frame {i+1}/{num_frames} (video frame {frame_idx})")
        else:
            break
    
    cap.release()
    return frames

def generate_video_verilog(video_input, output_path, num_frames=16):
    frames = []
    
    # Check if input is an MP4 file
    if os.path.isfile(video_input) and video_input.lower().endswith(('.mp4', '.avi', '.mov', '.mkv')):
        print(f"Extracting frames from video: {video_input}")
        frames = extract_frames_from_video(video_input, num_frames)
    # Check if input is a directory
    elif os.path.isdir(video_input):
        frame_files = sorted([f for f in os.listdir(video_input) if f.endswith(('.png', '.jpg', '.jpeg'))])
        print(f"Found {len(frame_files)} frames in {video_input}")
        
        for i, frame_file in enumerate(frame_files[:num_frames]):
            try:
                img = Image.open(os.path.join(video_input, frame_file))
                img = img.resize((200, 150)).convert('RGB')
                frames.append(img)
                print(f"Loaded frame {i+1}/{num_frames}: {frame_file}")
            except Exception as e:
                print(f"Error loading {frame_file}: {e}")
    
    # Generate dummy frames if not enough loaded
    while len(frames) < num_frames:
        i = len(frames)
        print(f"Generating dummy frame {i+1}/{num_frames}")
        img = Image.new('RGB', (200, 150))
        for x in range(200):
            for y in range(150):
                img.putpixel((x, y), ((x+i*10) % 255, (y+i*10) % 255, (x+y+i*20) % 255))
        frames.append(img)
    
    width, height = 200, 150
    
    with open(output_path, 'w') as f:
        f.write(f"module image_rom (\n")
        f.write(f"    input wire clk,\n")
        f.write(f"    input wire [17:0] addr,\n")
        f.write(f"    input wire [3:0] frame,\n")
        f.write(f"    output reg [23:0] data\n")
        f.write(f");\n")
        f.write(f"    // Video: {num_frames} frames, {width}x{height} each\n")
        f.write(f"    (* ram_style = \"block\" *)\n")
        f.write(f"    reg [23:0] rom [0:{width*height*num_frames-1}];\n")
        f.write(f"    initial begin\n")
        
        for frame_idx, img in enumerate(frames):
            pixels = list(img.getdata())
            for i, pixel in enumerate(pixels):
                r, g, b = pixel
                hex_val = (r << 16) | (g << 8) | b
                addr = frame_idx * width * height + i
                f.write(f"        rom[{addr}] = 24'h{hex_val:06X};\n")
            print(f"Wrote frame {frame_idx+1}/{num_frames}")
                
        f.write(f"    end\n")
        f.write(f"    always @(posedge clk) begin\n")
        f.write(f"        data <= rom[addr];\n")
        f.write(f"    end\n")
        f.write(f"endmodule\n")

    print(f"Generated {output_path} with {num_frames} frames ({width}x{height})")

if __name__ == "__main__":
    video_input = "video.mp4"
    num_frames = 16
    
    if len(sys.argv) > 1:
        video_input = sys.argv[1]
    if len(sys.argv) > 2:
        num_frames = int(sys.argv[2])
    
    output_verilog = "src/image_rom.v"
    os.makedirs(os.path.dirname(output_verilog), exist_ok=True)
    
    generate_video_verilog(video_input, output_verilog, num_frames)
