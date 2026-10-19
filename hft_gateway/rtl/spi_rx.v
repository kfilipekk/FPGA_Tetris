//spi mode 0 slave, sck under clk/4
`default_nettype none

module spi_rx (
    input  wire       clk,
    input  wire       sck,
    input  wire       mosi,
    input  wire       cs_n,
    output reg  [7:0] data  = 0,
    output reg        valid = 0,
    output reg        sof   = 0,
    output reg        eof   = 0
);

    reg [2:0] s_sck  = 0;
    reg [1:0] s_mosi = 0;
    reg [2:0] s_cs   = 3'b111;
    always @(posedge clk) begin
        s_sck  <= {s_sck[1:0], sck};
        s_mosi <= {s_mosi[0], mosi};
        s_cs   <= {s_cs[1:0], cs_n};
    end
    wire rise = s_sck[1] & ~s_sck[2];
    wire sel  = ~s_cs[1];

    reg [6:0] sh    = 0;
    reg [2:0] n     = 0;
    reg       first = 1'b1;

    always @(posedge clk) begin
        valid <= 1'b0;
        sof   <= 1'b0;
        eof   <= s_cs[1] & ~s_cs[2];
        if (!sel) begin
            n     <= 0;
            first <= 1'b1;
        end else if (rise) begin
            sh <= {sh[5:0], s_mosi[1]};
            n  <= n + 1'b1;
            if (n == 3'd7) begin
                data  <= {sh, s_mosi[1]};
                valid <= 1'b1;
                sof   <= first;
                first <= 1'b0;
            end
        end
    end

endmodule
