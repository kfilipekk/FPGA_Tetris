//tang nano 9k. s1 plays the burst, s2 toggles kill. venue 0 nasdaq, 1 lse
`default_nettype none

module top #(
    parameter        VENUE     = 0,
    parameter        UART_DIV  = 234,       //115200
    parameter        HALF      = 16,
    parameter        GAP       = 2700000,
    parameter        SCEN_GAP  = 0,         //0: an order's length for the venue
    parameter        BTN_HOLD  = 270000,
    parameter        BURST     = 4,
    parameter        REFILL    = 6750000,
    parameter        HOST_HOLD = 27000000   //1 s
) (
    input  wire       clk,
    input  wire       btn_s1,
    input  wire       btn_s2,
    input  wire       uart_rx,
    output wire [5:0] led,
    output wire       uart_tx,
    output wire       feed_sck,
    output wire       feed_mosi,
    output wire       feed_cs_n,
    output wire       ord_tx,
    output wire       spec,
    output wire       risk_ok,
    output wire       tx_commit,
    output wire       tx_abort
);

    //lse prices carry 8 decimals, nasdaq 4
    localparam [63:0] SYMBOL = VENUE ? 64'd1001 : "AAPL    ";
    localparam [63:0] LIMIT  = VENUE ? 64'd15000000000  : 64'd1500000;
    localparam integer SGAP  = SCEN_GAP != 0 ? SCEN_GAP : VENUE ? 340000 : 135000;

    wire scen_t, btn_kill;
    btn_toggle #(.HOLD(BTN_HOLD)) u_s1 (.clk(clk), .btn(btn_s1), .state(scen_t));
    btn_toggle #(.HOLD(BTN_HOLD)) u_s2 (.clk(clk), .btn(btn_s2), .state(btn_kill));

    reg scen_d = 0;
    always @(posedge clk)
        scen_d <= scen_t;
    wire go = scen_t != scen_d;

    wire [7:0] rx_data;
    wire       rx_valid;
    uart_rx #(.DIV(UART_DIV)) u_urx (.clk(clk), .rx(uart_rx), .data(rx_data), .valid(rx_valid));

    wire [7:0] h_data;
    wire       h_valid, h_sof, h_eof;
    mold_rx u_mold (
        .clk     (clk),
        .in_valid(rx_valid),
        .in_data (rx_data),
        .data    (h_data),
        .valid   (h_valid),
        .sof     (h_sof),
        .eof     (h_eof)
    );

    reg [$clog2(HOST_HOLD)-1:0] hold = 0;
    wire host = hold != 0;
    always @(posedge clk)
        if (rx_valid)  hold <= HOST_HOLD - 1;
        else if (host) hold <= hold - 1'b1;

    feed_gen #(.VENUE(VENUE), .HALF(HALF), .GAP(GAP), .SCEN_GAP(SGAP)) u_feed (
        .clk (clk),
        .en  (!host),
        .go  (go),
        .sck (feed_sck),
        .mosi(feed_mosi),
        .cs_n(feed_cs_n)
    );

    wire [7:0] s_data;
    wire       s_valid, s_sof, s_eof;
    spi_rx u_srx (
        .clk  (clk),
        .sck  (feed_sck),
        .mosi (feed_mosi),
        .cs_n (feed_cs_n),
        .data (s_data),
        .valid(s_valid),
        .sof  (s_sof),
        .eof  (s_eof)
    );

    wire [7:0] in_data  = host ? h_data  : s_data;
    wire       in_valid = host ? h_valid : s_valid;
    wire       in_sof   = host ? h_sof   : s_sof;
    wire       in_eof   = host ? h_eof   : s_eof;

    wire [63:0] symbol;
    wire [63:0] limit;
    wire        host_kill;
    cfg #(.SYMBOL(SYMBOL), .LIMIT(LIMIT)) u_cfg (
        .clk   (clk),
        .valid (in_valid),
        .data  (in_data),
        .sof   (in_sof),
        .eof   (in_eof),
        .symbol(symbol),
        .limit (limit),
        .kill  (host_kill),
        /* verilator lint_off PINCONNECTEMPTY */
        .loaded()
        /* verilator lint_on PINCONNECTEMPTY */
    );
    wire kill = btn_kill || host_kill;

    wire [7:0] out_data;
    wire       out_valid, out_ready, sent, stomped;
    hft_core #(.VENUE(VENUE), .BURST(BURST), .REFILL(REFILL)) u_core (
        .clk      (clk),
        .kill     (kill),
        .symbol   (symbol),
        .limit    (limit),
        .in_valid (in_valid),
        .in_data  (in_data),
        .in_sof   (in_sof),
        .in_eof   (in_eof),
        .out_data (out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .spec     (spec),
        .armed    (risk_ok),
        .tx_commit(tx_commit),
        .tx_abort (tx_abort),
        .sent     (sent),
        .stomped  (stomped),
        /* verilator lint_off PINCONNECTEMPTY */
        .missed   ()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    uart_tx #(.DIV(UART_DIV)) u_tx (
        .clk  (clk),
        .data (out_data),
        .valid(out_valid),
        .ready(out_ready),
        .tx   (uart_tx)
    );
    assign ord_tx = uart_tx;

    reg        n_sent = 0, n_stomp = 0;
    reg [24:0] beat   = 0;
    always @(posedge clk) begin
        beat <= beat + 1'b1;
        if (sent)    n_sent  <= ~n_sent;
        if (stomped) n_stomp <= ~n_stomp;
    end

    assign led = ~{host | beat[24], risk_ok, n_stomp, n_sent, spec, kill};

endmodule
