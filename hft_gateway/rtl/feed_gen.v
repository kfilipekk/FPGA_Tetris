//on-chip itch feed, spi mode 0 master on the same wires an outside feed would use.
//streams add orders made from a hash of the sequence number, and on go plays a
//scripted burst that walks every path through the engine. the order ref carries
//{0, kind, 0, seq} so the host can rebuild any message
`default_nettype none

module feed_gen #(
    parameter        HALF     = 16,       //sck half period in clocks, 843.75 khz
    parameter        GAP      = 2700000,  //100 ms between streamed messages
    parameter        SCEN_GAP = 135000,   //5 ms between scripted ones, an order's length
    parameter        STREAM   = 1,
    parameter [31:0] CENTER   = 1500000   //streamed prices sit around $150
) (
    input  wire clk,
    input  wire en,                   //low while the host is feeding
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

    //message being sent
    reg [31:0] seq  = 0;
    reg [7:0]  kind = 0;
    reg [47:0] ts   = 0;

    //not every hash bit is used
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
            8'd1:    price = 32'd1499000;       //good
            8'd2:    price = 32'd1501000;       //over the limit
            8'd3: begin                         //corrupt on the wire
                price = 32'd1498000;
                bad   = 1'b1;
            end
            8'd4:    price = 32'd100;           //a bad tick, outside the collar
            8'd5: begin                         //not our stock
                price = 32'd1499000;
                sym   = 2'd1;
            end
            default: price = 32'd1499500;       //good until the bucket runs dry
        endcase
    end

    wire [63:0] stock = (sym == 2'd1) ? "MSFT    " : (sym == 2'd2) ? "NVDA    " : "AAPL    ";
    wire [63:0] ref_num = {8'd0, kind, 16'd0, seq};

    reg  [5:0]  bi = 0;
    wire [31:0] crc;
    reg  [7:0]  b;
    reg  [5:0]  nb;

    wire [31:0] fcs = ~crc ^ {31'd0, bad};

    //byte nb of the message
    always @* begin
        if (nb == 6'd0)       b = "A";
        else if (nb == 6'd1)  b = 8'd0;
        else if (nb == 6'd2)  b = {6'd0, sym} + 8'd1;  //stock locate
        else if (nb <= 6'd4)  b = 8'd0;                //tracking
        else if (nb <= 6'd10) b = ts[8*(10 - nb) +: 8];
        else if (nb <= 6'd18) b = ref_num[8*(18 - nb) +: 8];
        else if (nb == 6'd19) b = side_s ? "S" : "B";
        else if (nb <= 6'd23) b = shares[8*(23 - nb) +: 8];
        else if (nb <= 6'd31) b = stock[8*(31 - nb) +: 8];
        else if (nb <= 6'd35) b = price[8*(35 - nb) +: 8];
        else                  b = fcs[8*(nb - 36) +: 8];
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
    reg [3:0]  scen = 0;               //scripted messages left
    reg        pend = 0;

    wire half = hc == HMAX[HW-1:0];
    wire load = half && (state == LEAD || (state == HIGH && bitn == 0 && bi != 6'd39));

    always @* begin
        nb = (state == LEAD) ? 6'd0 : bi + 1'b1;
    end

    crc32 u_crc (
        .clk (clk),
        .init(state == IDLE),
        .en  (load && nb < 6'd36),
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
                    state <= (bi == 6'd39) ? TAIL : LOW;
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
