//pre-trade risk in one clock: kill switch, price collar, size, notional and a token
//bucket of BURST orders, one token back every REFILL clocks
`default_nettype none

module risk_gate #(
    parameter        BURST        = 4,
    parameter        REFILL       = 6750000,        //250 ms, 4 orders a second sustained
    parameter [31:0] PX_LO        = 1000000,        //$100.0000, prices carry 4 decimals
    parameter [31:0] PX_HI        = 2000000,        //$200.0000
    parameter [15:0] MAX_QTY      = 500,
    parameter [47:0] MAX_NOTIONAL = 48'd500000000   //$50,000
) (
    input  wire        clk,
    input  wire        kill,
    input  wire        check,
    input  wire [31:0] price,
    input  wire [15:0] qty,
    output reg         grant = 0,
    output reg         deny  = 0,
    output wire        armed,    //a clean order would pass now
    output reg  [$clog2(BURST+1)-1:0] tokens = BURST
);

    localparam TW = $clog2(BURST + 1);
    localparam [TW-1:0] FULL = BURST;

    reg [$clog2(REFILL)-1:0] tick = 0;
    wire refill = tick == REFILL - 1;

    wire [47:0] notional = price * qty;
    wire limits = price >= PX_LO && price <= PX_HI &&
                  qty != 0 && qty <= MAX_QTY && notional <= MAX_NOTIONAL;

    assign armed = !kill && tokens != 0;
    wire pass = check && armed && limits;

    wire [TW:0] t_next = {1'b0, tokens} - {{TW{1'b0}}, pass} + {{TW{1'b0}}, refill};

    always @(posedge clk) begin
        tick   <= refill ? 0 : tick + 1'b1;
        grant  <= pass;
        deny   <= check && !pass;
        tokens <= (t_next > {1'b0, FULL}) ? FULL : t_next[TW-1:0];
    end

`ifdef FORMAL
    //grants over the last REFILL clocks, keep REFILL small here
    reg [REFILL-1:0] f_hist = 0;
    reg              f_past = 0;
    always @(posedge clk) begin
        f_past <= 1'b1;
        f_hist <= {f_hist[REFILL-2:0], pass};
    end

    integer   f_k;
    reg [7:0] f_cnt;
    always @* begin
        f_cnt = 0;
        for (f_k = 0; f_k < REFILL; f_k = f_k + 1)
            f_cnt = f_cnt + {7'd0, f_hist[f_k]};
    end

    always @* begin
        assert (tokens <= BURST);
        assert (tick < REFILL);
        //never more than the bucket and one refill in any window
        assert (f_cnt <= BURST + 1);
    end

    always @(posedge clk)
        if (f_past) begin
            //only a clean check, with a token and no kill, gets through
            assert (grant == $past(check && !kill && tokens != 0 && limits));
            assert (deny == ($past(check) && !grant));
            if (grant) assert ($past(price) >= PX_LO && $past(price) <= PX_HI);
            if (grant) assert ($past(qty) <= MAX_QTY && $past(notional) <= MAX_NOTIONAL);
        end

    always @(posedge clk) begin
        cover (f_cnt == BURST + 1);
        cover (f_past && $past(check && armed) && deny);
    end
`endif

endmodule
