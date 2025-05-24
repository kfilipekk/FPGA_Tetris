//top.v - Blink all 6 LEDs at different rates
//SUCCESS! LEDs are active-LOW

module top (
    input clk,
    output [5:0] led
);
    //Counter for blinking
    reg [25:0] counter = 0;
    always @(posedge clk) begin
        counter <= counter + 1;
    end

    //Blink all 6 LEDs at different rates (active-LOW, so inverted)
    assign led[0] = ~counter[20];  //~25 Hz
    assign led[1] = ~counter[21];  //~13 Hz
    assign led[2] = ~counter[22];  //~6 Hz
    assign led[3] = ~counter[23];  //~3 Hz
    assign led[4] = ~counter[24];  //~1.6 Hz
    assign led[5] = ~counter[25];  //~0.8 Hz
    
endmodule
