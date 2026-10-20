//on-chip feed over spi: a hashed stream, and a scripted burst on go
//venue 0 itch add orders, 1 mitch add orders. order ref is {0, kind, 0, seq}
`default_nettype none

module feed_gen #(
    parameter        VENUE    = 0,
    parameter        HALF     = 16,       //843.75 khz sck
    parameter        GAP      = 2700000,  //100 ms
    parameter        SCEN_GAP = 135000,   //5 ms
    parameter        STREAM   = 1,
    parameter [31:0] CENTER   = 1500000
) (
    input  wire clk,
    input  wire en,
    input  wire go,
    output reg  sck  = 0,
    output reg  mosi = 0,
    output reg  cs_n = 1'b1
);

    function [31:0] xs(input [31:0] x);
        reg [31:0] y;
        begin
            y  = x ^ (x << 13);
            y  = y ^ (y >> 17);
            xs = y ^ (y << 5);
        end
    endfunction

    reg [47:0] now  = 0;
    always @(posedge clk)
        now <= now + 1'b1;

    reg [31:0] seq  = 0;
    reg [7:0]  kind = 0;
    reg [47:0] ts   = 0;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] r1 = xs(seq ^ 32'h9E3779B9);
    wire [31:0] r2 = xs(r1);
    /* verilator lint_on UNUSEDSIGNAL */

    reg        side_s, bad;
    reg [1:0]  sym;                 //aapl msft nvda
    reg [31:0] shares, price;
    always @* begin
        side_s = 1'b1;
        sym    = 2'd0;
        shares = 32'd100;
        bad    = 1'b0;
        case (kind)
            8'd0: begin
                side_s = r1[0];
                sym    = (r1[2:1] == 2'd3) ? 2'd2 : (r1[2:1] == 2'd2) ? 2'd1 : 2'd0;
                shares = 32'd50 + {22'd0, r1[12:3]};
                price  = (r1[17:13] == 5'd0) ? 32'd100 : CENTER - 32'd2048 + {20'd0, r2[11:0]};
                bad    = r2[15:12] == 4'd0;
            end
            8'd1:    price = 32'd1499000;
            8'd2:    price = 32'd1501000;
            8'd3: begin
                price = 32'd1498000;
                bad   = 1'b1;
            end
            8'd4:    price = 32'd100;
            8'd5: begin
                price = 32'd1499000;
                sym   = 2'd1;
            end
            default: price = 32'd1499500;
        endcase
    end

    wire [63:0] stock = (sym == 2'd1) ? "MSFT    " : (sym == 2'd2) ? "NVDA    " : "AAPL    ";
    wire [63:0] ref_num = {8'd0, kind, 16'd0, seq};

    reg  [5:0]  bi = 0;
    wire [31:0] crc;
    reg  [7:0]  b;
    reg  [5:0]  nb;

    wire [31:0] fcs = ~crc ^ {31'd0, bad};
    wire [31:0] inst = 32'd1001 + {30'd0, sym};
    wire [63:0] px8  = {32'd0, price} * 64'd10000;   //8 decimals

    localparam [5:0] FS   = VENUE ? 6'd44 : 6'd36;   //first fcs byte
    localparam [5:0] LASTB = FS + 6'd3;

    reg [7:0] b_itch, b_mitch;
    always @* begin
        if (nb == 6'd0)       b_itch = "A";
        else if (nb == 6'd1)  b_itch = 8'd0;
        else if (nb == 6'd2)  b_itch = {6'd0, sym} + 8'd1;
        else if (nb <= 6'd4)  b_itch = 8'd0;
        else if (nb <= 6'd10) b_itch = ts[8*(10 - nb) +: 8];
        else if (nb <= 6'd18) b_itch = ref_num[8*(18 - nb) +: 8];
        else if (nb == 6'd19) b_itch = side_s ? "S" : "B";
        else if (nb <= 6'd23) b_itch = shares[8*(23 - nb) +: 8];
        else if (nb <= 6'd31) b_itch = stock[8*(31 - nb) +: 8];
        else                  b_itch = price[8*(35 - nb) +: 8];

        if (nb == 6'd0)       b_mitch = 8'd44;
        else if (nb == 6'd1)  b_mitch = "A";
        else if (nb <= 6'd5)  b_mitch = ts[8*(nb - 2) +: 8];
        else if (nb <= 6'd13) b_mitch = ref_num[8*(nb - 6) +: 8];
        else if (nb == 6'd14) b_mitch = side_s ? "S" : "B";
        else if (nb <= 6'd18) b_mitch = shares[8*(nb - 15) +: 8];
        else if (nb <= 6'd22) b_mitch = inst[8*(nb - 19) +: 8];
        else if (nb <= 6'd24) b_mitch = 8'd0;
        else if (nb <= 6'd32) b_mitch = px8[8*(nb - 25) +: 8];
        else if (nb == 6'd33) b_mitch = 8'd0;
        else                  b_mitch = " ";

        if (nb >= FS)  b = fcs[8*(nb - FS) +: 8];
        else if (VENUE) b = b_mitch;
        else           b = b_itch;
    end

    localparam IDLE = 3'd0, LEAD = 3'd1, LOW = 3'd2, HIGH = 3'd3, TAIL = 3'd4;
    localparam [3:0] NSCEN = 10;
    reg [2:0]  state = IDLE;
    localparam HW = $clog2(HALF);
    localparam integer HMAX = HALF - 1;
    reg [HW-1:0] hc = 0;
    reg [31:0] gap  = 1000;
    reg [2:0]  bitn = 0;
    reg [7:0]  sh   = 0;
    reg [3:0]  scen = 0;
    reg        pend = 0;

    wire half = hc == HMAX[HW-1:0];
    wire load = half && (state == LEAD || (state == HIGH && bitn == 0 && bi != LASTB));

    always @* begin
        nb = (state == LEAD) ? 6'd0 : bi + 1'b1;
    end

    crc32 u_crc (
        .clk (clk),
        .init(state == IDLE),
        .en  (load && nb < FS),
        .d   (b),
        .c   (crc)
    );

    always @(posedge clk) begin
        hc <= half ? 0 : hc + 1'b1;
        if (go && scen == 0 && en) pend <= 1'b1;

        if (load) begin
            bi   <= nb;
            sh   <= b;
            mosi <= b[7];
            bitn <= 3'd7;
        end

        case (state)
            IDLE: begin
                hc <= 0;
                if (gap != 0) gap <= gap - 1'b1;
                if (!en) begin
                    pend <= 1'b0;
                    scen <= 0;
                end else if (pend && scen == 0) begin
                    scen <= NSCEN;
                    pend <= 1'b0;
                    gap  <= 0;
                end else if (gap == 0 && (STREAM || scen != 0)) begin
                    kind  <= (scen != 0) ? {4'd0, NSCEN - scen} + 8'd1 : 8'd0;
                    if (scen != 0) scen <= scen - 1'b1;
                    ts    <= now;
                    cs_n  <= 1'b0;
                    state <= LEAD;
                end
            end
            LEAD: if (half) state <= LOW;
            LOW:  if (half) begin
                sck   <= 1'b1;
                state <= HIGH;
            end
            HIGH: if (half) begin
                sck <= 1'b0;
                if (bitn != 0) begin
                    bitn  <= bitn - 1'b1;
                    sh    <= sh << 1;
                    mosi  <= sh[6];
                    state <= LOW;
                end else
                    state <= (bi == LASTB) ? TAIL : LOW;
            end
            default: if (half) begin
                cs_n  <= 1'b1;
                seq   <= seq + 1'b1;
                gap   <= (scen != 0) ? SCEN_GAP : GAP;
                state <= IDLE;
            end
        endcase
    end

endmodule
