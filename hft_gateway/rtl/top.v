//tang nano 9k: the on-chip feed goes out on the spi pins and back in through the same
//receiver an outside feed would use. orders leave on the usb uart and on ord_tx, and
//the engine's state is on the header for a logic analyser
//s1 plays the scripted burst, s2 toggles the kill switch
`default_nettype none

module top #(
    parameter ORD_DIV  = 234,      //115200 baud order port
    parameter HALF     = 16,
    parameter GAP      = 2700000,
    parameter SCEN_GAP = 135000,
    parameter BTN_HOLD = 270000,
    parameter BURST    = 4,
    parameter REFILL   = 6750000
) (
    input  wire       clk,
    input  wire       btn_s1,
    input  wire       btn_s2,
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

    wire scen_t, kill;
    btn_toggle #(.HOLD(BTN_HOLD)) u_s1 (.clk(clk), .btn(btn_s1), .state(scen_t));
    btn_toggle #(.HOLD(BTN_HOLD)) u_s2 (.clk(clk), .btn(btn_s2), .state(kill));

    reg scen_d = 0;
    always @(posedge clk)
        scen_d <= scen_t;
    wire go = scen_t != scen_d;

    feed_gen #(.HALF(HALF), .GAP(GAP), .SCEN_GAP(SCEN_GAP)) u_feed (
        .clk (clk),
        .go  (go),
        .sck (feed_sck),
        .mosi(feed_mosi),
        .cs_n(feed_cs_n)
    );

    wire [7:0] in_data;
    wire       in_valid, in_sof, in_eof;
    spi_rx u_rx (
        .clk  (clk),
        .sck  (feed_sck),
        .mosi (feed_mosi),
        .cs_n (feed_cs_n),
        .data (in_data),
        .valid(in_valid),
        .sof  (in_sof),
        .eof  (in_eof)
    );

    wire [7:0] out_data;
    wire       out_valid, out_ready, sent, stomped;
    hft_core #(.BURST(BURST), .REFILL(REFILL)) u_core (
        .clk      (clk),
        .kill     (kill),
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

    uart_tx #(.DIV(ORD_DIV)) u_tx (
        .clk  (clk),
        .data (out_data),
        .valid(out_valid),
        .ready(out_ready),
        .tx   (uart_tx)
    );
    assign ord_tx = uart_tx;

    //sent and stomped flip their leds, the rest follow the header
    reg       n_sent = 0, n_stomp = 0;
    reg [24:0] beat  = 0;
    always @(posedge clk) begin
        beat <= beat + 1'b1;
        if (sent)    n_sent  <= ~n_sent;
        if (stomped) n_stomp <= ~n_stomp;
    end

    assign led = ~{beat[24], risk_ok, n_stomp, n_sent, spec, kill};

endmodule
