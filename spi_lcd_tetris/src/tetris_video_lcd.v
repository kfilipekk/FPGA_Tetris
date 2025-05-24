//Tetris video renderer for SPI LCD (320x240 RGB565)
//Renders game board and current piece to 16-bit color

module tetris_video_lcd (
  input clk,
  input reset_n,
  input [12:0] x,  // 0..319
  input [12:0] y,  // 0..239
  input pixel_req,
  //Game state
  input [2:0] cur_shape,
  input [1:0] cur_rot,
  input signed [5:0] cur_y,
  input [4:0] cur_x,
  input [3:0] cur_color,
  input [3:0] board_color,
  output reg [15:0] pixel_out  //RGB565
);

  //Board constants: 10x12 cells, 12-pixel blocks, centered on 128x160
  localparam BC = 12;  //block size in pixels (smaller for 128x160)
  localparam BOARD_W = 10 * BC;  //120
  localparam BOARD_H = 12 * BC;  //144
  localparam OFFSET_X = (128 - BOARD_W) / 2;  //4
  localparam OFFSET_Y = (160 - BOARD_H) / 2;  //8

  //Shape ROM (7 pieces × 4 rotations, 2x2 simplified for now)
  reg [15:0] shape_rom [0:27];
  initial begin
    //I piece (cyan)
    shape_rom[0]  = 16'b0100_0100_0100_0100;
    shape_rom[1]  = 16'b0000_0000_1111_0000;
    shape_rom[2]  = 16'b0100_0100_0100_0100;
    shape_rom[3]  = 16'b0000_0000_1111_0000;
    //O piece (yellow)
    shape_rom[4]  = 16'b0110_0110_0000_0000;
    shape_rom[5]  = 16'b0110_0110_0000_0000;
    shape_rom[6]  = 16'b0110_0110_0000_0000;
    shape_rom[7]  = 16'b0110_0110_0000_0000;
    //T piece (magenta)
    shape_rom[8]  = 16'b0100_1110_0000_0000;
    shape_rom[9]  = 16'b0100_0110_0100_0000;
    shape_rom[10] = 16'b0000_1110_0100_0000;
    shape_rom[11] = 16'b0100_1100_0100_0000;
    //S piece (green)
    shape_rom[12] = 16'b0110_1100_0000_0000;
    shape_rom[13] = 16'b0100_0110_0010_0000;
    shape_rom[14] = 16'b0110_1100_0000_0000;
    shape_rom[15] = 16'b0100_0110_0010_0000;
    //Z piece (red)
    shape_rom[16] = 16'b1100_0110_0000_0000;
    shape_rom[17] = 16'b0010_0110_0100_0000;
    shape_rom[18] = 16'b1100_0110_0000_0000;
    shape_rom[19] = 16'b0010_0110_0100_0000;
    //J piece (blue)
    shape_rom[20] = 16'b0100_0100_1100_0000;
    shape_rom[21] = 16'b1000_1110_0000_0000;
    shape_rom[22] = 16'b0110_0010_0010_0000;
    shape_rom[23] = 16'b0000_1110_0010_0000;
    //L piece (orange)
    shape_rom[24] = 16'b0100_0100_0110_0000;
    shape_rom[25] = 16'b0010_0010_0011_0000;
    shape_rom[26] = 16'b0000_1110_1000_0000;
    shape_rom[27] = 16'b0110_0010_0010_0000;
  end

  //RGB565 color palette
  function [15:0] color565;
    input [3:0] code;
    case (code)
      4'd0: color565 = 16'h0000; //black
      4'd1: color565 = 16'h07FF; //cyan
      4'd2: color565 = 16'hFFE0; //yellow
      4'd3: color565 = 16'hF81F; //magenta
      4'd4: color565 = 16'h07E0; //green
      4'd5: color565 = 16'hF800; //red
      4'd6: color565 = 16'h001F; //blue
      4'd7: color565 = 16'hFD20; //orange
      default: color565 = 16'h7BEF; //gray
    endcase
  endfunction

  wire in_board = (x >= OFFSET_X) && (x < OFFSET_X + BOARD_W) && 
                  (y >= OFFSET_Y) && (y < OFFSET_Y + BOARD_H);
  wire [12:0] rel_x = x - OFFSET_X;
  wire [12:0] rel_y = y - OFFSET_Y;
  wire [4:0] cell_x = rel_x / BC;
  wire [4:0] cell_y = rel_y / BC;
  wire [4:0] in_cell_x = rel_x % BC;
  wire [4:0] in_cell_y = rel_y % BC;

  //Current piece rendering
  wire signed [5:0] piece_rel_y = $signed(cell_y) - cur_y;
  wire signed [5:0] piece_rel_x = $signed(cell_x) - $signed({1'b0, cur_x});
  wire in_piece_box = (piece_rel_y >= 0) && (piece_rel_y < 4) &&
                      (piece_rel_x >= 0) && (piece_rel_x < 4);
  
  reg [15:0] cur_mask;
  reg [3:0] bit_idx;
  wire piece_bit = in_piece_box && cur_mask[bit_idx];

  always @(*) begin
    cur_mask = shape_rom[{cur_shape, cur_rot}];
    bit_idx = piece_rel_y[1:0] * 4 + piece_rel_x[1:0];
  end

  //Grid lines
  wire grid = (in_cell_x == 0) || (in_cell_y == 0);

  //Pixel output
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pixel_out <= 16'h0000;
    end else if (pixel_req) begin
      if (!in_board) begin
        pixel_out <= 16'h0000;  //black background
      end else if (piece_bit) begin
        pixel_out <= color565(cur_color);
      end else if (board_color != 4'd0) begin
        pixel_out <= color565(board_color);
      end else if (grid) begin
        pixel_out <= 16'h4208;  //dark gray grid
      end else begin
        pixel_out <= 16'h0000;  //empty cell
      end
    end
  end
endmodule
