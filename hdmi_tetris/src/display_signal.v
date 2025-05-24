//display_signal module converts a pixel clock into a hsync+vsync+disp_enable+x+y structure.
module display_signal #(
  H_RESOLUTION    = 1280,
  V_RESOLUTION    = 1024,
  H_FRONT_PORCH   = 48,
  H_SYNC          = 112,
  H_BACK_PORCH    = 248,
  V_FRONT_PORCH   = 1,
  V_SYNC          = 3,
  V_BACK_PORCH    = 38,
  H_SYNC_POLARITY = 1'b1,   //0: neg, 1: pos
  V_SYNC_POLARITY = 1'b1    //0: neg, 1: pos
)
(
  input  i_pixel_clk,
  output reg [2:0] o_hve,   //{ display_enable, vsync, hsync} . hsync is active at desired H_SYNC_POLARITY and vsync is active at desired V_SYNC_POLARITY, display_enable is active high, low in blanking
  output reg signed [12:0] o_x, //screen x coordinate (negative in blanking, nonneg in visible picture area)
  output reg signed [12:0] o_y  //screen y coordinate (negative in blanking, nonneg in visible picture area)
);
  //A horizontal scanline consists of sequence of regions: front porch -> sync -> back porch -> display visible
  //Size the localparams explicitly to match x/y width to avoid implicit 32-bit promotion warnings.
  localparam signed [12:0] H_START       = -$signed(H_BACK_PORCH[12:0]) - $signed(H_SYNC[12:0]) - $signed(H_FRONT_PORCH[12:0]);
  localparam signed [12:0] HSYNC_START   = -$signed(H_BACK_PORCH[12:0]) - $signed(H_SYNC[12:0]);
  localparam signed [12:0] HSYNC_END     = -$signed(H_BACK_PORCH[12:0]);
  localparam signed [12:0] HACTIVE_START = 13'sd0;
  localparam signed [12:0] HACTIVE_END   = $signed(H_RESOLUTION[12:0]) - 13'sd1;
  //Vertical image frame has the same structure, but counts scanlines instead of pixel clocks.
  localparam signed [12:0] V_START       = -$signed(V_BACK_PORCH[12:0]) - $signed(V_SYNC[12:0]) - $signed(V_FRONT_PORCH[12:0]);
  localparam signed [12:0] VSYNC_START   = -$signed(V_BACK_PORCH[12:0]) - $signed(V_SYNC[12:0]);
  localparam signed [12:0] VSYNC_END     = -$signed(V_BACK_PORCH[12:0]);
  localparam signed [12:0] VACTIVE_START = 13'sd0;
  localparam signed [12:0] VACTIVE_END   = $signed(V_RESOLUTION[12:0]) - 13'sd1;

  reg signed [12:0] x, y;
  //Force sync polarity parameters to 1-bit values to avoid width promotion in logic ops
  localparam [0:0] HSP = H_SYNC_POLARITY ? 1'b1 : 1'b0;
  localparam [0:0] VSP = V_SYNC_POLARITY ? 1'b1 : 1'b0;
  always @(posedge i_pixel_clk) begin
    x <= (x == HACTIVE_END) ? H_START : x + 13'sd1;
    if   (x == HACTIVE_END) y <= (y == VACTIVE_END) ? V_START : y + 13'sd1;
    o_x <= x;
    o_y <= y;
    o_hve <= { ((x >= 13'sd0) && (y >= 13'sd0)), //display enable is high when in visible picture area
               (VSP ^ ((y >= VSYNC_START) && (y < VSYNC_END))), //vsync bit (1-bit)
               (HSP ^ ((x >= HSYNC_START) && (x < HSYNC_END))) }; //hsync bit (1-bit)
  end
endmodule
