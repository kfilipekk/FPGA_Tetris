//itch in, ouch out. launches on the symbol, commits only if price, fcs and risk agree
`default_nettype none

module hft_core #(
    parameter [31:0] ORDER_QTY    = 100,
    parameter        BURST        = 4,
    parameter        REFILL       = 6750000,
    parameter [31:0] PX_LO        = 1000000,
    parameter [31:0] PX_HI        = 2000000,
    parameter [15:0] MAX_QTY      = 500,
    parameter [47:0] MAX_NOTIONAL = 48'd500000000
) (
    input  wire        clk,
    input  wire        kill,
    input  wire [63:0] symbol,
    input  wire [31:0] limit,
    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_sof,
    input  wire        in_eof,
    output wire [7:0]  out_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire        spec,
    output wire        armed,
    output wire        tx_commit,
    output wire        tx_abort,
    output wire        sent,
    output wire        stomped,
    output wire        missed
);

    wire        trig, px_valid, done, ok;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [63:0] ref_num;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] shares, price;

    itch_parser u_parse (
        .clk     (clk),
        .symbol  (symbol),
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

    reg        live   = 0;
    reg        px_ok  = 0;
    reg [31:0] px     = 0;
    reg [31:0] lim    = 0;
    reg [15:0] qty    = 0;
    wire [15:0] size  = (shares < ORDER_QTY) ? shares[15:0] : ORDER_QTY[15:0];
    always @(posedge clk) begin
        if (launch) begin
            live  <= 1'b1;
            px_ok <= 1'b0;
            lim   <= limit;
            qty   <= size;
        end else if (done)
            live <= 1'b0;
        if (px_valid && live) begin
            px_ok <= price <= lim;
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

    wire decide = (done && live && !(ok && px_ok)) || grant || deny;

    wire good, bad;
    ouch_tx u_tx (
        .clk     (clk),
        .start   (launch),
        .stock   (symbol),
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
    reg f_granted = 0;
    always @(posedge clk) begin
        f_past <= 1'b1;
        if (launch)            f_granted <= 1'b0;
        else if (grant && busy) f_granted <= 1'b1;
    end

    always @* begin
        if (live && px_ok) assert (px <= lim);
        if (good) assert (f_granted);
    end

    always @(posedge clk)
        if (f_past) begin
            if (grant) assert ($past(live && ok && px_ok) && $past(px) <= $past(lim));
        end

    always @(posedge clk)
        cover (sent);
`endif

    assign spec   = busy && !good && !bad;
    assign tx_commit = good;
    assign tx_abort  = bad;

endmodule
