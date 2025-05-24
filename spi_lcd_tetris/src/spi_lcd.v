//Simple SPI LCD controller for ST7789/ILI9341 displays
//Supports 320x240 or 480x320 displays with 16-bit RGB565 color
//Much simpler than HDMI - just shift out pixels serially

module spi_lcd #(
  parameter H_RES = 320,
  parameter V_RES = 240
)(
  input wire clk,           //System clock (e.g., 27 MHz)
  input wire reset_n,       //Active low reset
  input wire [15:0] pixel_data,  //RGB565 pixel data
  input wire frame_start,   //Pulse to start a new frame
  output reg spi_clk,       //SPI clock output
  output reg spi_mosi,      //SPI data output
  output reg spi_dc,        //Data/Command select (0=cmd, 1=data)
  output reg spi_cs,        //Chip select (active low)
  output reg [12:0] x_pos,  //Current X position
  output reg [12:0] y_pos,  //Current Y position
  output wire pixel_req     //Request next pixel
);

  localparam IDLE = 3'd0;
  localparam SEND_CMD = 3'd1;
  localparam SEND_DATA = 3'd2;
  localparam PIXEL_MODE = 3'd3;
  
  reg [2:0] state;
  reg [4:0] bit_count;
  reg [15:0] shift_reg;
  reg pixel_ready;
  
  //Divide clock for SPI (divide by 2 for simplicity)
  reg clk_div;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) clk_div <= 0;
    else clk_div <= ~clk_div;
  end
  
  //Request pixel when we're ready for next one
  assign pixel_req = (state == PIXEL_MODE && bit_count == 0 && clk_div);
  
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state <= IDLE;
      spi_cs <= 1'b1;
      spi_dc <= 1'b1;
      spi_clk <= 1'b0;
      spi_mosi <= 1'b0;
      x_pos <= 0;
      y_pos <= 0;
      bit_count <= 0;
      pixel_ready <= 0;
    end else if (clk_div) begin
      case (state)
        IDLE: begin
          spi_cs <= 1'b1;
          if (frame_start) begin
            state <= PIXEL_MODE;
            spi_cs <= 1'b0;
            spi_dc <= 1'b1; //Data mode
            x_pos <= 0;
            y_pos <= 0;
            pixel_ready <= 1;
          end
        end
        
        PIXEL_MODE: begin
          if (bit_count == 0) begin
            //Load next pixel
            shift_reg <= pixel_data;
            bit_count <= 16;
          end else begin
            //Shift out bits
            spi_clk <= ~spi_clk;
            if (spi_clk) begin
              //On falling edge, shift data
              spi_mosi <= shift_reg[15];
              shift_reg <= {shift_reg[14:0], 1'b0};
              bit_count <= bit_count - 1;
              
              if (bit_count == 1) begin
                //Move to next pixel
                if (x_pos == H_RES - 1) begin
                  x_pos <= 0;
                  if (y_pos == V_RES - 1) begin
                    y_pos <= 0;
                    state <= IDLE;
                  end else begin
                    y_pos <= y_pos + 1;
                  end
                end else begin
                  x_pos <= x_pos + 1;
                end
              end
            end
          end
        end
      endcase
    end
  end
endmodule
