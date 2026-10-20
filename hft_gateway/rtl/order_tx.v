//the order, sent from the trigger. fcs goes out inverted unless a commit beat it
//venue 0, ouch 4.2 enter order
//  0 type  1 token  15 side  16 shares  20 stock  28 price  32 tif  36 firm
//  40 display  41 capacity  42 iso  43 min qty  47 cross  48 customer  49 fcs
//venue 1, lse native new order, little endian
//  0 start  1 length  3 type  4 client order id  24 trader  35 account  45 clearing
//  46 instrument  50 mifid  51 party role  52 type  53 tif  54 expiry  58 side
//  59 qty  63 display qty  67 price  75 capacity  76 auto cancel  77..124 0  125 fcs
`default_nettype none

module order_tx #(
    parameter        VENUE = 0,
    parameter [31:0] FIRM  = "FPGA"
) (
    input  wire        clk,
    input  wire        start,
    input  wire [63:0] stock,
    input  wire [63:0] token,
    input  wire [31:0] qty,
    input  wire        px_valid,
    input  wire [63:0] price,
    input  wire        decide,
    input  wire        commit,
    output reg  [7:0]  data,
    output wire        valid,
    input  wire        ready,
    output reg         busy    = 0,
    output reg         good    = 0,
    output reg         bad     = 0,
    output reg         sent    = 0,
    output reg         stomped = 0
);

    localparam [7:0] LEN  = VENUE ? 8'd125 : 8'd49;
    localparam [7:0] PXI  = VENUE ? 8'd67  : 8'd28;
    localparam [7:0] LAST = LEN + 8'd3;

    reg [7:0]  idx = 0;
    reg [63:0] st  = 0;
    reg [63:0] tok = 0;
    reg [31:0] q   = 0;
    reg [63:0] px  = 0;
    reg        have_px = 0;
    reg        fcs_on  = 0;

    assign valid = busy;
    wire fire = busy && ready;

    wire [31:0] crc;
    crc32 u_crc (
        .clk (clk),
        .init(start && !busy),
        .en  (fire && idx < LEN),
        .d   (data),
        .c   (crc)
    );

    wire [63:0] pxv = have_px ? px : 64'd0;
    wire [31:0] fcs = good ? ~crc : crc;

    function [7:0] hex(input [3:0] n);
        hex = (n < 4'd10) ? "0" + {4'd0, n} : "A" - 8'd10 + {4'd0, n};
    endfunction

    reg [7:0] b_ouch, b_lse;
    always @* begin
        if (idx == 8'd0)       b_ouch = "O";
        else if (idx <= 8'd14) b_ouch = hex(tok[4*(14 - idx) +: 4]);
        else if (idx == 8'd15) b_ouch = "B";
        else if (idx <= 8'd19) b_ouch = q[8*(19 - idx) +: 8];
        else if (idx <= 8'd27) b_ouch = st[8*(27 - idx) +: 8];
        else if (idx <= 8'd31) b_ouch = pxv[8*(31 - idx) +: 8];
        else if (idx <= 8'd35) b_ouch = 8'd0;        //ioc
        else if (idx <= 8'd39) b_ouch = FIRM[8*(39 - idx) +: 8];
        else if (idx == 8'd40) b_ouch = "Y";
        else if (idx == 8'd41) b_ouch = "P";
        else if (idx == 8'd42) b_ouch = "N";
        else if (idx <= 8'd46) b_ouch = 8'd0;
        else if (idx == 8'd47) b_ouch = "N";
        else                   b_ouch = "R";

        if (idx == 8'd0)       b_lse = 8'h02;
        else if (idx == 8'd1)  b_lse = 8'd122;       //length from the type on
        else if (idx == 8'd2)  b_lse = 8'd0;
        else if (idx == 8'd3)  b_lse = "D";
        else if (idx <= 8'd19) b_lse = hex(tok[4*(19 - idx) +: 4]);
        else if (idx <= 8'd44) b_lse = 8'd0;
        else if (idx == 8'd45) b_lse = 8'd3;         //house
        else if (idx <= 8'd49) b_lse = st[8*(idx - 46) +: 8];
        else if (idx == 8'd50) b_lse = 8'h04;        //algo
        else if (idx == 8'd51) b_lse = 8'd0;
        else if (idx == 8'd52) b_lse = 8'd2;         //limit
        else if (idx == 8'd53) b_lse = 8'd3;         //ioc
        else if (idx <= 8'd57) b_lse = 8'd0;
        else if (idx == 8'd58) b_lse = 8'd1;         //buy
        else if (idx <= 8'd62) b_lse = q[8*(idx - 59) +: 8];
        else if (idx <= 8'd66) b_lse = q[8*(idx - 63) +: 8];
        else if (idx <= 8'd74) b_lse = pxv[8*(idx - 67) +: 8];
        else if (idx == 8'd75) b_lse = 8'd2;         //dealing on own account
        else if (idx == 8'd76) b_lse = 8'd1;
        else                   b_lse = 8'd0;

        if (idx >= LEN)  data = fcs[8*(idx - LEN) +: 8];
        else if (VENUE)  data = b_lse;
        else             data = b_ouch;
    end

    wire take = decide && !fcs_on && !(fire && idx == LEN) && !good && !bad;

    always @(posedge clk) begin
        sent    <= 1'b0;
        stomped <= 1'b0;

        if (!busy) begin
            if (start) begin
                busy    <= 1'b1;
                idx     <= 0;
                st      <= stock;
                tok     <= token;
                q       <= qty;
                have_px <= 1'b0;
                fcs_on  <= 1'b0;
                good    <= 1'b0;
                bad     <= 1'b0;
            end
        end else begin
            if (px_valid && !have_px) begin
                have_px <= 1'b1;
                px      <= price;
            end

            if (take) begin
                good <= commit;
                bad  <= !commit;
            end

            if (fire) begin
                idx <= idx + 1'b1;
                if (idx == PXI && !have_px) begin
                    good <= 1'b0;
                    bad  <= 1'b1;
                end
                if (idx == LEN) begin
                    fcs_on <= 1'b1;
                    if (!good) bad <= 1'b1;
                end
                if (idx == LAST) begin
                    busy    <= 1'b0;
                    good    <= 1'b0;
                    bad     <= 1'b0;
                    sent    <= good;
                    stomped <= !good;
                end
            end
        end
    end

`ifdef FORMAL
    reg [7:0] f_n      = 0;
    reg       f_px     = 0;
    reg       f_poison = 0;
    reg       f_dec    = 0;
    reg       f_commit = 0;
    reg       f_late   = 0;
    reg       f_past   = 0;
    wire      f_good   = f_dec && f_commit && !f_poison;

    always @(posedge clk) begin
        f_past <= 1'b1;
        if (!busy) begin
            if (start) begin
                f_n      <= 0;
                f_px     <= 1'b0;
                f_poison <= 1'b0;
                f_dec    <= 1'b0;
                f_commit <= 1'b0;
                f_late   <= 1'b0;
            end
        end else begin
            if (px_valid) f_px <= 1'b1;
            if (decide && !f_dec && !f_poison && f_n <= LEN && !(fire && f_n == LEN)) begin
                f_dec    <= 1'b1;
                f_commit <= commit;
            end
            if (fire) begin
                f_n <= f_n + 1'b1;
                if (f_n == PXI && !f_px)  f_poison <= 1'b1;
                if (f_n == LEN && !f_good) f_late   <= 1'b1;
            end
        end
    end

    always @* begin
        assert (valid == busy);
        if (busy) begin
            assert (idx == f_n && idx <= LAST);
            assert (!f_poison || f_n > PXI);
            assert (!f_late || f_n > LEN);
            assert (have_px == f_px);
            assert (fcs_on == (f_n > LEN));
            assert (good == f_good);
            assert (bad == ((f_dec && !f_commit) || f_poison || f_late));
            if (idx >= LEN)
                assert (fcs == (f_good ? ~crc : crc));
        end else
            assert (!good && !bad);
    end

    always @(posedge clk)
        if (f_past) begin
            if ($past(busy && !(fire && idx == LAST))) assert (busy);
            if ($past(busy && fire && idx == LAST))    assert (!busy);
            assert (sent    == $past(busy && fire && idx == LAST && good));
            assert (stomped == $past(busy && fire && idx == LAST && !good));
        end

    always @(posedge clk) begin
        cover (sent);
        cover (stomped && $past(f_poison));
        cover (stomped && $past(f_late));
        cover (stomped && $past(f_dec && !f_commit));
    end
`endif

endmodule
