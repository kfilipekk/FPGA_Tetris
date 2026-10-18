//8n1, DIV clocks per bit, a strobe per byte. a bad start or stop bit drops it
`default_nettype none

module uart_rx #(
    parameter DIV = 234  //115200 baud
) (
    input  wire       clk,
    input  wire       rx,
    output reg  [7:0] data  = 0,
    output reg        valid = 0
);

    localparam W = $clog2(DIV);
    localparam integer FULL = DIV - 1;
    localparam integer MID  = DIV / 2 - 1;

    reg [1:0]   s    = 2'b11;
    reg [W-1:0] baud = 0;
    reg [3:0]   bits = 0;  //0 idle, 1 start, 2-9 data, 10 stop
    reg [7:0]   sh   = 0;

    always @(posedge clk) begin
        s     <= {s[0], rx};
        valid <= 1'b0;
        if (bits == 0) begin
            if (!s[1]) begin
                bits <= 4'd1;
                baud <= MID[W-1:0];     //to the middle of the start bit
            end
        end else if (baud != 0) begin
            baud <= baud - 1'b1;
        end else begin
            baud <= FULL[W-1:0];
            if (bits == 4'd1) begin
                bits <= s[1] ? 4'd0 : 4'd2;
            end else if (bits == 4'd10) begin
                bits  <= 0;
                data  <= sh;
                valid <= s[1];
            end else begin
                sh   <= {s[1], sh[7:1]};
                bits <= bits + 1'b1;
            end
        end
    end

endmodule
