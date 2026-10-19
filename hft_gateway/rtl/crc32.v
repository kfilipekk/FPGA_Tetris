//ethernet crc-32, a byte per clock, fcs is ~c low byte first
`default_nettype none

module crc32 (
    input  wire        clk,
    input  wire        init,
    input  wire        en,
    input  wire [7:0]  d,
    output reg  [31:0] c = 32'hFFFFFFFF
);

    function [31:0] step(input [31:0] cin, input [7:0] b);
        integer k;
        begin
            step = cin ^ {24'd0, b};
            for (k = 0; k < 8; k = k + 1)
                step = step[0] ? (step >> 1) ^ 32'hEDB88320 : step >> 1;
        end
    endfunction

    always @(posedge clk)
        if (en)        c <= step(init ? 32'hFFFFFFFF : c, d);
        else if (init) c <= 32'hFFFFFFFF;

endmodule
