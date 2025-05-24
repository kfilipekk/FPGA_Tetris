//Top module for Tetris with SPI LCD display
//Tang Nano 9K with ST7789 320x240 LCD

module top_lcd (
  input clk_27mhz,   //27 MHz onboard clock
  input reset_btn,   //Reset button (active low)
  input btn1,        //Left button
  input btn2,        //Right button
  //SPI LCD interface
  output spi_clk,
  output spi_mosi,
  output spi_dc,
  output spi_cs,
  output lcd_rst,
  output lcd_bl,     //Backlight (active high)
  //Debug LED
  output led
);

  wire reset_n = reset_btn;
  wire clk = clk_27mhz;

  //Backlight always on, LCD reset always active
  assign lcd_bl = 1'b1;
  assign lcd_rst = reset_n;

  //Frame timing - generate frame_start pulse ~60Hz
  reg [19:0] frame_counter;
  wire frame_start = (frame_counter == 20'd449999);  //27MHz / 450000 = 60Hz
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) frame_counter <= 0;
    else if (frame_start) frame_counter <= 0;
    else frame_counter <= frame_counter + 1;
  end

  //SPI LCD controller - 128x160 display
  wire [12:0] x_pos, y_pos;
  wire pixel_req;
  wire [15:0] pixel_data;
  
  spi_lcd #(.H_RES(128), .V_RES(160)) lcd (
    .clk(clk),
    .reset_n(reset_n),
    .pixel_data(pixel_data),
    .frame_start(frame_start),
    .spi_clk(spi_clk),
    .spi_mosi(spi_mosi),
    .spi_dc(spi_dc),
    .spi_cs(spi_cs),
    .x_pos(x_pos),
    .y_pos(y_pos),
    .pixel_req(pixel_req)
  );

  //Game logic
  wire [2:0] cur_shape;
  wire [1:0] cur_rot;
  wire [4:0] cur_x;
  wire signed [5:0] cur_y;
  wire [3:0] cur_color;
  wire [4:0] q_x, q_y;
  wire [3:0] board_color;

  tetris_game_lcd game (
    .clk(clk),
    .reset_n(reset_n),
    .btn_left(~btn1),
    .btn_right(~btn2),
    .frame_start(frame_start),
    .q_x(q_x),
    .q_y(q_y),
    .q_color(board_color),
    .cur_shape(cur_shape),
    .cur_rot(cur_rot),
    .cur_x(cur_x),
    .cur_y(cur_y),
    .cur_color(cur_color)
  );

  //Video renderer
  tetris_video_lcd video (
    .clk(clk),
    .reset_n(reset_n),
    .x(x_pos),
    .y(y_pos),
    .pixel_req(pixel_req),
    .cur_shape(cur_shape),
    .cur_rot(cur_rot),
    .cur_y(cur_y),
    .cur_x(cur_x),
    .cur_color(cur_color),
    .board_color(board_color),
    .pixel_out(pixel_data)
  );

  //Board query - convert pixel position to cell coordinates
  //128x160 display: 10x12 board with 12-pixel blocks = 120x144
  //Offset: (128-120)/2 = 4 pixels left, (160-144)/2 = 8 pixels top
  wire in_board = (x_pos >= 4) && (x_pos < 124) && (y_pos >= 8) && (y_pos < 152);
  assign q_x = in_board ? ((x_pos - 4) / 12) : 5'd0;
  assign q_y = in_board ? ((y_pos - 8) / 12) : 5'd0;

  //Heartbeat LED
  reg [23:0] led_counter;
  always @(posedge clk) led_counter <= led_counter + 1;
  assign led = led_counter[23];

endmodule
