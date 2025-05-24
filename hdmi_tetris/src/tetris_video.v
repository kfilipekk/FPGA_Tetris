//Renders Tetris board + current piece into RGB
//Board origin X0=200, block size = 32, grid 10x20 -> 320x640 area (simplified for synthesis)

module tetris_video (
  input         clk,           //pixel clock
  input         reset_n,
  input  [12:0] x,
  input  [12:0] y,
  input  [2:0]  hve,           //{de, vs, hs}
  //Board color query handshake
  output [4:0]  req_bx,
  output [4:0]  req_by,
  input  [3:0]  req_color,
  //Game state
  input  [2:0] cur_shape,
  input  [1:0] cur_rot,
  input  [4:0] cur_x,
  input  signed [5:0] cur_y,
  input  [3:0] cur_color,
  output reg [23:0] rgb
);
  localparam integer X0 = 200;
  localparam integer BC = 32; //block size coarse
  localparam [12:0] X0_13 = 13'd200;

  //Shape ROM: 16-bit mask per shape/rotation combo
  reg [15:0] shape_rom [0:27];
  initial begin
    //I piece
    shape_rom[0] = 16'b0000_1111_0000_0000;
    shape_rom[1] = 16'b0010_0010_0010_0010;
    shape_rom[2] = 16'b0000_0000_1111_0000;
    shape_rom[3] = 16'b0001_0001_0001_0001;
    //O piece
    shape_rom[4] = 16'b0000_0110_0110_0000;
    shape_rom[5] = 16'b0000_0110_0110_0000;
    shape_rom[6] = 16'b0000_0110_0110_0000;
    shape_rom[7] = 16'b0000_0110_0110_0000;
    //T piece
    shape_rom[8] = 16'b0000_1110_0100_0000;
    shape_rom[9] = 16'b0010_0110_0010_0000;
    shape_rom[10] = 16'b0000_0100_1110_0000;
    shape_rom[11] = 16'b0010_0110_0010_0000;
    //S piece
    shape_rom[12] = 16'b0000_0110_1100_0000;
    shape_rom[13] = 16'b0100_0110_0010_0000;
    shape_rom[14] = 16'b0000_0110_1100_0000;
    shape_rom[15] = 16'b0100_0110_0010_0000;
    //Z piece
    shape_rom[16] = 16'b0000_1100_0110_0000;
    shape_rom[17] = 16'b0010_0110_0100_0000;
    shape_rom[18] = 16'b0000_1100_0110_0000;
    shape_rom[19] = 16'b0010_0110_0100_0000;
    //J piece
    shape_rom[20] = 16'b0000_1000_1110_0000;
    shape_rom[21] = 16'b0110_0100_0100_0000;
    shape_rom[22] = 16'b0000_1110_0010_0000;
    shape_rom[23] = 16'b0010_0010_0110_0000;
    //L piece
    shape_rom[24] = 16'b0000_0010_1110_0000;
    shape_rom[25] = 16'b0010_0010_0011_0000;
    shape_rom[26] = 16'b0000_1110_1000_0000;
    shape_rom[27] = 16'b0110_0010_0010_0000;
  end
  
  //8-color palette (24-bit RGB)
  function [23:0] color24;
    input [3:0] code;
    case (code)
      4'd0: color24 = 24'h000000; //black
      4'd1: color24 = 24'h00FFFF; //cyan (I)
      4'd2: color24 = 24'hFFFF00; //yellow (O)
      4'd3: color24 = 24'hFF00FF; //magenta (T)
      4'd4: color24 = 24'h00FF00; //green (S)
      4'd5: color24 = 24'hFF0000; //red (Z)
      4'd6: color24 = 24'h0000FF; //blue (J)
      4'd7: color24 = 24'hFF8000; //orange (L)
      default: color24 = 24'h808080; //gray
    endcase
  endfunction

  //Grid and board drawing: 10x12 cells at 32 pixels each
  wire de = hve[2];
  wire in_board = (x >= X0) && (x < X0 + 10*BC) && (y < 12*BC);
  wire [12:0] x_in = x - X0_13;
  //Simple shift-based grid (divide by 32 = >>5)
  wire [4:0]  bx = x_in[9:5]; //x/32
  wire [4:0]  px = x_in[4:0];

  wire [4:0]  by = y[9:5]; //y/32
  wire [4:0]  py = y[4:0];

  //Issue board color requests
  assign req_bx = bx;
  assign req_by = by;

  //Overlay current piece with ROM-based shape mask (pipelined for timing)
  wire signed [6:0] rel_y = $signed(by) - cur_y;
  wire signed [6:0] rel_x = $signed(bx) - $signed(cur_x);
  
  //Pipeline stage 1: fetch mask
  reg [15:0] cur_mask_r;
  reg signed [6:0] rel_y_r, rel_x_r;
  reg [3:0] cur_color_r;
  always @(posedge clk) begin
    cur_mask_r <= shape_rom[{cur_shape, cur_rot}];
    rel_y_r <= rel_y;
    rel_x_r <= rel_x;
    cur_color_r <= cur_color;
  end
  
  //Stage 2: compute mask bit
  wire in_bounds = (rel_x_r >= 0 && rel_x_r < 4 && rel_y_r >= 0 && rel_y_r < 4);
  wire [3:0] mask_idx = {rel_y_r[1:0], rel_x_r[1:0]};
  wire piece_bit = in_bounds && cur_mask_r[mask_idx];

  //Cell color from game via query port
  wire [3:0] cell_col = req_color;

  //Draw grid lines
  wire grid = (px == 0) || (py == 0);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      rgb <= 24'h0;
    end else if (!de) begin
      rgb <= 24'h000000;
    end else if (!in_board) begin
      rgb <= 24'h101018;
    end else begin
      //Color palette lookup
      if (piece_bit) begin
        rgb <= color24(cur_color_r);
      end else if (cell_col != 4'd0) begin
        rgb <= color24(cell_col);
      end else if (grid) begin
        rgb <= 24'h202030;
      end else begin
        rgb <= 24'h0a0a10;
      end
    end
  end
endmodule
