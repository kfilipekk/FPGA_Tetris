//feed bytes in, orders out. an order is launched on the symbol match, priced when
//the price lands and let through only if the strategy, the feed fcs and the risk
//gate all agree. anything else, or a verdict too late, goes out stomped
`default_nettype none

module hft_core #(
    parameter [63:0] SYMBOL       = "AAPL    ",
    parameter [31:0] LIMIT        = 1500000,       //buy at or under $150.0000
    parameter [31:0] ORDER_QTY    = 100,
    parameter        BURST        = 4,
    parameter        REFILL       = 6750000,
    parameter [31:0] PX_LO        = 1000000,
    parameter [31:0] PX_HI        = 2000000,
    parameter [15:0] MAX_QTY      = 500,
    parameter [47:0] MAX_NOTIONAL = 48'd500000000
) (
    input  wire       clk,
    input  wire       kill,
    input  wire       in_valid,
    input  wire [7:0] in_data,
    input  wire       in_sof,
    input  wire       in_eof,
    output wire [7:0] out_data,
    output wire       out_valid,
    input  wire       out_ready,
    output wire       spec,      //order on the wire, verdict pending
    output wire       armed,     //risk gate has a token and no kill
    output wire       tx_commit,
    output wire       tx_abort,
    output wire       sent,
    output wire       stomped,
    output wire       missed     //a match while the last order was still going
);

    wire        trig, px_valid, done, ok;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [63:0] ref_num;               //the token takes the low 56 bits
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] shares, price;

    itch_parser #(.SYMBOL(SYMBOL)) u_parse (
        .clk     (clk),
        .valid   (in_valid),
        .data    (in_data),
        .sof     (in_sof),
        .eof     (in_eof),
        .trig    (trig),
        .ref_num (ref_num),
        .shares  (shares),
        .px_valid(px_valid),
        .price   (price),
        .done    (done),
        .ok      (ok)
    );

    wire busy;
    wire launch = trig && !busy;
    assign missed = trig && busy;

    //the order on the wire belongs to the frame being parsed
    reg        live   = 0;
    reg        px_ok  = 0;
    reg [31:0] px     = 0;
    reg [15:0] qty    = 0;
    wire [15:0] size  = (shares < ORDER_QTY) ? shares[15:0] : ORDER_QTY[15:0];
    always @(posedge clk) begin
        if (launch) begin
            live  <= 1'b1;
            px_ok <= 1'b0;
            qty   <= size;
        end else if (done)
            live <= 1'b0;
        if (px_valid && live) begin
            px_ok <= price <= LIMIT;
            px    <= price;
        end
    end

    wire want = done && live && ok && px_ok;
    wire grant, deny;

    risk_gate #(
        .BURST(BURST), .REFILL(REFILL), .PX_LO(PX_LO), .PX_HI(PX_HI),
        .MAX_QTY(MAX_QTY), .MAX_NOTIONAL(MAX_NOTIONAL)
    ) u_risk (
        .clk   (clk),
        .kill  (kill),
        .check (want),
        .price (px),
        .qty   (qty),
        .grant (grant),
        .deny  (deny),
        .armed (armed),
        /* verilator lint_off PINCONNECTEMPTY */
        .tokens()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    //a bad fcs or price is rejected on the spot, a clean one waits a clock for risk
    wire decide = (done && live && !(ok && px_ok)) || grant || deny;

    wire good, bad;
    ouch_tx u_tx (
        .clk     (clk),
        .start   (launch),
        .stock   (SYMBOL),
        .token   (ref_num[55:0]),
        .qty     ({16'd0, size}),
        .px_valid(px_valid && live),
        .price   (price),
        .decide  (decide),
        .commit  (grant),
        .data    (out_data),
        .valid   (out_valid),
        .ready   (out_ready),
        .busy    (busy),
        .good    (good),
        .bad     (bad),
        .sent    (sent),
        .stomped (stomped)
    );

`ifdef FORMAL
    reg f_past    = 0;
    reg f_granted = 0;               //the gate passed the order on the wire
    always @(posedge clk) begin
        f_past <= 1'b1;
        if (launch)            f_granted <= 1'b0;
        else if (grant && busy) f_granted <= 1'b1;
    end

    always @* begin
        if (live && px_ok) assert (px <= LIMIT);
        //a good fcs needs the gate
        if (good) assert (f_granted);
    end

    always @(posedge clk)
        if (f_past) begin
            //and the gate only sees clean, in-limit orders for the live frame
            if (grant) assert ($past(live && ok && px_ok) && $past(px) <= LIMIT);
        end

    always @(posedge clk)
        cover (sent);
`endif

    assign spec   = busy && !good && !bad;
    assign tx_commit = good;
    assign tx_abort  = bad;

endmodule
