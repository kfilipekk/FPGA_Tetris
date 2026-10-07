//itch 5.0 add order, 36 bytes and a 4 byte fcs per cs frame
//  0 type  1 locate  3 tracking  5 timestamp  11 order ref  19 side
//  20 shares  24 stock  32 price  36 fcs
//trig fires on the last stock byte, before the price and fcs are in
`default_nettype none

module itch_parser #(
    parameter [63:0] SYMBOL = "AAPL    "
) (
    input  wire        clk,
    input  wire        valid,
    input  wire [7:0]  data,
    input  wire        sof,
    input  wire        eof,
    output reg         trig     = 0,  //add order, sell side, our stock
    output reg  [63:0] ref_num  = 0,
    output reg  [31:0] shares   = 0,
    output reg         px_valid = 0,
    output reg  [31:0] price    = 0,
    output reg         done     = 0,  //once per trig
    output reg         ok       = 0   //with done: fcs good, frame complete
);

    reg  [5:0] idx = 0;               //index of the next byte
    wire [5:0] i   = sof ? 6'd0 : idx;
    reg        hit  = 0;              //every checked byte so far matched
    reg        open = 0;              //triggered, no verdict yet
    reg        fcs_good = 0;

    wire [31:0] crc;
    crc32 u_crc (
        .clk (clk),
        .init(sof),
        .en  (valid && i < 6'd36),
        .d   (data),
        .c   (crc)
    );

    reg [7:0] sym_b, fcs_b;
    always @* begin
        case (i[2:0])                 //24..31
            3'd0:    sym_b = SYMBOL[63:56];
            3'd1:    sym_b = SYMBOL[55:48];
            3'd2:    sym_b = SYMBOL[47:40];
            3'd3:    sym_b = SYMBOL[39:32];
            3'd4:    sym_b = SYMBOL[31:24];
            3'd5:    sym_b = SYMBOL[23:16];
            3'd6:    sym_b = SYMBOL[15:8];
            default: sym_b = SYMBOL[7:0];
        endcase
        case (i[1:0])                 //36..39, fcs low byte first
            2'd0:    fcs_b = ~crc[7:0];
            2'd1:    fcs_b = ~crc[15:8];
            2'd2:    fcs_b = ~crc[23:16];
            default: fcs_b = ~crc[31:24];
        endcase
    end

    wire in_sym = i >= 6'd24 && i <= 6'd31;
    wire in_fcs = i >= 6'd36 && i <= 6'd39;

    always @(posedge clk) begin
        trig     <= 1'b0;
        px_valid <= 1'b0;
        done     <= 1'b0;

        if (valid) begin
            idx <= (i == 6'd63) ? i : i + 1'b1;

            if (i == 6'd0)       hit <= data == "A";
            else if (i == 6'd19) hit <= hit && data == "S";
            else if (in_sym)     hit <= hit && data == sym_b;

            if (i >= 6'd11 && i <= 6'd18) ref_num <= {ref_num[55:0], data};
            if (i >= 6'd20 && i <= 6'd23) shares  <= {shares[23:0], data};
            if (i >= 6'd32 && i <= 6'd35) price   <= {price[23:0], data};

            if (i == 6'd31 && hit && data == sym_b) begin
                trig <= 1'b1;
                open <= 1'b1;
            end
            if (i == 6'd35 && open) px_valid <= 1'b1;

            if (i == 6'd36)  fcs_good <= data == fcs_b;
            else if (in_fcs) fcs_good <= fcs_good && data == fcs_b;
        end

        //verdict on the last fcs byte, or a cut short frame
        if (valid && i == 6'd39 && open) begin
            done <= 1'b1;
            ok   <= fcs_good && data == fcs_b;
            open <= 1'b0;
        end else if ((eof || sof) && open) begin
            done <= 1'b1;
            ok   <= 1'b0;
            open <= 1'b0;
        end
    end


endmodule
