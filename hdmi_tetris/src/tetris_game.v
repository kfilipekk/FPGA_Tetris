//Simple Tetris core with auto-play (no external inputs)
//Board: 10x20, cell color 4-bit (0=empty)
//Updates on a slow tick derived from frame start; intended for ~640x480@60Hz

module tetris_game (
  input         clk,           //pixel clock (25.2 MHz)
  input         reset_n,       //active low
  input         btn_left,      //button for left move
  input         btn_right,     //button for right/rotate
  input  [12:0] vis_x,         //visible x from display_signal
  input  [12:0] vis_y,         //visible y from display_signal
  input  [2:0]  hve,           //{de, vs, hs}
  //board query port for renderer
  input  [4:0]  q_x,
  input  [4:0]  q_y,
  output [3:0]  q_color,
  output reg [2:0] cur_shape,  //0..6
  output reg [1:0] cur_rot,    //0..3
  output reg [4:0] cur_x,      //0..9 (left position of 4x4 bbox)
  output reg signed [5:0] cur_y, //-3..19 (top of 4x4 bbox)
  output reg [3:0] cur_color   //display color index
);
  //Loop variable for shift operation (declare at module scope for Verilog-2001)
  integer x_shift;
  //Frame start pulse at first visible pixel (x==0 && y==0 && de==1)
  wire frame_start = (hve[2] == 1'b1) && (vis_x == 13'd0) && (vis_y == 13'd0);

  //Game tick: advance every 15 frames (~4Hz at 60fps)
  reg [7:0] frame_div;
  wire tick = (frame_div == 8'd0) && frame_start;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) frame_div <= 8'd0;
    else if (frame_start) begin
      if (frame_div == 8'd15) frame_div <= 8'd0;
      else frame_div <= frame_div + 8'd1;
    end
  end

  //LFSR for pseudo-random pieces/colors
  reg [15:0] lfsr;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) lfsr <= 16'hACE1;
    else if (frame_start) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end
  
  //No button controls for now - keep it simple

  //Board storage (flattened 10x12): board[y*10 + x]
  (* syn_ramstyle="block_ram" *) reg [3:0] board [0:119];
  //Progressive clear state to avoid multiple writers
  reg clearing;
  reg [6:0] clr_ptr; //0..119

  //Simple collision: just check bottom boundary for now
  wire at_bottom = (cur_y >= 10);

  //(tasks removed; replaced by sequential FSM states below)

  //Game FSM with minimal states
  localparam [1:0] S_PLAY = 2'd0, S_LOCK = 2'd1, S_SPAWN = 2'd2;
  reg [1:0] state;

  //Main state update on ticks (single writer to board)
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      cur_shape <= 3'd0; cur_rot <= 2'd0; cur_x <= 5'd3; cur_y <= -6'sd2; cur_color <= 4'h9;
      clearing  <= 1'b1;
      clr_ptr   <= 7'd0;
      state     <= S_PLAY;
    end else if (clearing) begin
      board[clr_ptr] <= 4'd0;
      if (clr_ptr == 7'd119) begin
        clearing <= 1'b0;
      end else begin
        clr_ptr <= clr_ptr + 9'd1;
      end
    end else if (tick) begin
      //Game logic (auto-play only, no buttons for now)
      begin
        case (state)
          S_PLAY: begin
            if (at_bottom) begin
              state   <= S_LOCK;
            end else begin
              //Gravity
              cur_y <= cur_y + 6'sd1;
            end
          end
        S_LOCK: begin
          //Lock 2x2 block in single tick (4 writes)
          if (cur_y >= 0 && cur_y <= 11 && cur_x <= 9) begin
            board[cur_y*10 + cur_x] <= cur_color;
          end
          if (cur_y >= 0 && cur_y <= 11 && cur_x + 1 <= 9) begin
            board[cur_y*10 + (cur_x + 1)] <= cur_color;
          end
          if (cur_y + 1 <= 11 && cur_x <= 9) begin
            board[(cur_y + 1)*10 + cur_x] <= cur_color;
          end
          if (cur_y + 1 <= 11 && cur_x + 1 <= 9) begin
            board[(cur_y + 1)*10 + (cur_x + 1)] <= cur_color;
          end
          state <= S_SPAWN;
        end
          S_SPAWN: begin
            cur_shape <= (lfsr[2:0] == 3'd7) ? 3'd6 : lfsr[2:0];
            cur_rot   <= lfsr[4:3];
            cur_x     <= 5'd3; //fixed x position for now
            cur_y     <= -6'sd3;  //spawn higher so pieces enter from top
            cur_color <= (lfsr[2:0] == 3'd0) ? 4'd1 : {1'b0, lfsr[2:0]}; //1-7
            state     <= S_PLAY;
          end
        endcase
      end
    end
  end

  //Combinational read port for renderer
  assign q_color = (q_y <= 5'd11 && q_x <= 5'd9) ? board[q_y*10 + q_x] : 4'd0;
endmodule
