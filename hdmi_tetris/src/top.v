`include "board_config.v"

module top(
  input clk,
  input btn1,        // S1 button (active low)
  input btn2,        // S2 button (active low)
  output led_n,
  output [3:0] hdmi_tx_n,
  output [3:0] hdmi_tx_p
);
  //Drive status LED directly from the main clock using the flipflop_drainer.
  flipflop_drainer flipflop_drainer(.clk(clk), .out(led_n));

  //Generate a video signal: this part is completely separate from the above nonsense adders.
  wire hdmi_clk, hdmi_clk_5x, hdmi_clk_lock;
  pll #(
.FBDIV_SEL(13), .IDIV_SEL(2), .ODIV_SEL(4) // 126.00 MHz:   640x480@60Hz @  25.20 MHz pixel clock: does not lose video sync, but produces (infrequent) single pixel flickering color glitches
//.FBDIV_SEL(36), .IDIV_SEL(4), .ODIV_SEL(4) // 199.80 MHz:   800x600@60Hz @  39.96 MHz pixel clock: does not lose video sync, but produces (moderate) single pixel flickering color glitches
//.FBDIV_SEL(7),  .IDIV_SEL(0), .ODIV_SEL(2) // 216.00 MHz:   768x576@73Hz @  43.20 MHz pixel clock: does not lose video sync, no(!) observed single pixel flickering
//.FBDIV_SEL(58), .IDIV_SEL(6), .ODIV_SEL(2) // 227.57 MHz:   768x576@75Hz @  45.51 MHz pixel clock: no video sync
//.FBDIV_SEL(36), .IDIV_SEL(3), .ODIV_SEL(2) // 249.75 MHz:   800x600@72Hz @  49.95 MHz pixel clock: no video sync
//.FBDIV_SEL(11), .IDIV_SEL(0), .ODIV_SEL(2) // 324.00 MHz:  1024x768@60Hz @  64.80 MHz pixel clock: no video sync
//.FBDIV_SEL(30), .IDIV_SEL(1), .ODIV_SEL(2) // 418.50 MHz:  1280x800@60Hz @  83.70 MHz pixel clock: no video sync
//.FBDIV_SEL(19), .IDIV_SEL(0), .ODIV_SEL(2) // 540.00 MHz: 1280x1024@60Hz @ 108.00 MHz pixel clock: no video sync
//.FBDIV_SEL(21), .IDIV_SEL(0), .ODIV_SEL(2) // 594.00 MHz: 1600x1200@57Hz @ 118.80 MHz pixel clock: no video sync, not even if using adder_clk[8] above, but must edit src/flipflop_drainer.v
) hdmi_pll(.CLKIN(clk), .CLKOUT(hdmi_clk_5x), .LOCK(hdmi_clk_lock));
  //Divide 5:1 serdes clock by five for HDMI pixel clock signal.
  CLKDIV #(.DIV_MODE("5"), .GSREN("false")) hdmi_clock_div(.CLKOUT(hdmi_clk), .HCLKIN(hdmi_clk_5x), .RESETN(hdmi_clk_lock), .CALIB(1'b1));
  wire [12:0] x, y;
  wire [2:0] hve;
  display_signal #(
/*  640x480@60Hz*/     .H_RESOLUTION( 640),.V_RESOLUTION( 480),.H_FRONT_PORCH(16),.H_SYNC( 96),.H_BACK_PORCH( 48),.V_FRONT_PORCH(10),.V_SYNC(2),.V_BACK_PORCH(33),.H_SYNC_POLARITY(0),.V_SYNC_POLARITY(0)
/*  800x600@60Hz*/   //.H_RESOLUTION( 800),.V_RESOLUTION( 600),.H_FRONT_PORCH(40),.H_SYNC(128),.H_BACK_PORCH( 88),.V_FRONT_PORCH( 1),.V_SYNC(4),.V_BACK_PORCH(23),.H_SYNC_POLARITY(1),.V_SYNC_POLARITY(1)
/*  768x576@73Hz*/   //.H_RESOLUTION( 768),.V_RESOLUTION( 576),.H_FRONT_PORCH(32),.H_SYNC( 80),.H_BACK_PORCH(112),.V_FRONT_PORCH( 1),.V_SYNC(3),.V_BACK_PORCH(21),.H_SYNC_POLARITY(0),.V_SYNC_POLARITY(1)
/*  768x576@75Hz*/   //.H_RESOLUTION( 768),.V_RESOLUTION( 576),.H_FRONT_PORCH(40),.H_SYNC( 80),.H_BACK_PORCH(120),.V_FRONT_PORCH( 1),.V_SYNC(3),.V_BACK_PORCH(22),.H_SYNC_POLARITY(0),.V_SYNC_POLARITY(1)
/*  800x600@72Hz*/   //.H_RESOLUTION( 800),.V_RESOLUTION( 600),.H_FRONT_PORCH(56),.H_SYNC(120),.H_BACK_PORCH( 64),.V_FRONT_PORCH(37),.V_SYNC(6),.V_BACK_PORCH(23),.H_SYNC_POLARITY(1),.V_SYNC_POLARITY(1)
/* 1024x768@60Hz*/   //.H_RESOLUTION(1024),.V_RESOLUTION( 768),.H_FRONT_PORCH(24),.H_SYNC(136),.H_BACK_PORCH(160),.V_FRONT_PORCH( 3),.V_SYNC(6),.V_BACK_PORCH(29),.H_SYNC_POLARITY(0),.V_SYNC_POLARITY(0)
/* 1280x800@60Hz*/   //.H_RESOLUTION(1280),.V_RESOLUTION( 800),.H_FRONT_PORCH(64),.H_SYNC(136),.H_BACK_PORCH(200),.V_FRONT_PORCH( 1),.V_SYNC(3),.V_BACK_PORCH(24),.H_SYNC_POLARITY(0),.V_SYNC_POLARITY(1)
/*1280x1024@60Hz*/   //.H_RESOLUTION(1280),.V_RESOLUTION(1024),.H_FRONT_PORCH(48),.H_SYNC(112),.H_BACK_PORCH(248),.V_FRONT_PORCH( 1),.V_SYNC(3),.V_BACK_PORCH(38),.H_SYNC_POLARITY(1),.V_SYNC_POLARITY(1)
/*1600x1200@57.4Hz*/ //.H_RESOLUTION(1600),.V_RESOLUTION(1200),.H_FRONT_PORCH( 8),.H_SYNC( 32),.H_BACK_PORCH( 40),.V_FRONT_PORCH(19),.V_SYNC(8),.V_BACK_PORCH( 6),.H_SYNC_POLARITY(1),.V_SYNC_POLARITY(0)
  )ds(.i_pixel_clk(hdmi_clk), .o_hve(hve), .o_x(x), .o_y(y)); //Produce video sync signal
  //Tetris game state and video
  wire reset_n = hdmi_clk_lock; //active high lock -> active low reset_n
  //Game state wires
  wire [2:0] cur_shape;
  wire [1:0] cur_rot;
  wire [4:0] cur_x;
  wire signed [5:0] cur_y;
  wire [3:0] cur_color;
  //Board query handshake wires
  wire [4:0] req_bx, req_by;
  wire [3:0] q_color;
  tetris_game game(
    .clk(hdmi_clk), .reset_n(reset_n), 
    .btn_left(~btn1), .btn_right(~btn2),  //buttons are active low, invert to active high
    .vis_x(x), .vis_y(y), .hve(hve),
    .q_x(req_bx), .q_y(req_by), .q_color(q_color),
    .cur_shape(cur_shape), .cur_rot(cur_rot), .cur_x(cur_x), .cur_y(cur_y), .cur_color(cur_color)
  );
  wire [23:0] rgb;
  tetris_video video(
    .clk(hdmi_clk), .reset_n(reset_n), .x(x), .y(y), .hve(hve),
    .req_bx(req_bx), .req_by(req_by), .req_color(q_color),
    .cur_shape(cur_shape), .cur_rot(cur_rot), .cur_x(cur_x), .cur_y(cur_y), .cur_color(cur_color),
    .rgb(rgb)
  );
  hdmi hdmi_out(.reset(~hdmi_clk_lock), .hdmi_clk(hdmi_clk), .hdmi_clk_5x(hdmi_clk_5x), .hve(hve), .rgb(rgb), .hdmi_tx_n(hdmi_tx_n), .hdmi_tx_p(hdmi_tx_p));
endmodule
