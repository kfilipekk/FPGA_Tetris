//moldudp64 style blocks, a 2 byte length then the message. a gap drops a partial one
`default_nettype none

module mold_rx #(
    parameter IDLE = 27000  //1 ms
) (
    input  wire       clk,
    input  wire       in_valid,
    input  wire [7:0] in_data,
    output reg  [7:0] data  = 0,
    output reg        valid = 0,
    output reg        sof   = 0,
    output reg        eof   = 0
);

    localparam LEN_HI = 2'd0, LEN_LO = 2'd1, BODY = 2'd2;
    localparam integer QMAX = IDLE - 1;

    reg [1:0]  st    = LEN_HI;
    reg [7:0]  hi    = 0;
    reg [15:0] left  = 0;
    reg        first = 0;
    reg        last  = 0;
    reg [$clog2(IDLE)-1:0] quiet = 0;

    always @(posedge clk) begin
        valid <= 1'b0;
        sof   <= 1'b0;
        eof   <= last;
        last  <= 1'b0;

        if (in_valid) begin
            quiet <= 0;
            case (st)
                LEN_HI: begin
                    hi <= in_data;
                    st <= LEN_LO;
                end
                LEN_LO: begin
                    left  <= {hi, in_data};
                    first <= 1'b1;
                    st    <= ({hi, in_data} == 0) ? LEN_HI : BODY;
                end
                default: begin
                    data  <= in_data;
                    valid <= 1'b1;
                    sof   <= first;
                    first <= 1'b0;
                    left  <= left - 1'b1;
                    if (left == 1) begin
                        last <= 1'b1;
                        st   <= LEN_HI;
                    end
                end
            endcase
        end else if (st != LEN_HI) begin
            if (quiet == QMAX[$clog2(IDLE)-1:0]) begin
                quiet <= 0;
                eof   <= st == BODY && !first;
                st    <= LEN_HI;
            end else
                quiet <= quiet + 1'b1;
        end
    end

endmodule
