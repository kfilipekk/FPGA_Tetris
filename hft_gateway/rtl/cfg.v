//settings frame from the host: 'C', symbol (8), limit (8), kill, fcs
`default_nettype none

module cfg #(
    parameter [63:0] SYMBOL = "AAPL    ",
    parameter [63:0] LIMIT  = 1500000
) (
    input  wire        clk,
    input  wire        valid,
    input  wire [7:0]  data,
    input  wire        sof,
    input  wire        eof,
    output reg  [63:0] symbol = SYMBOL,
    output reg  [63:0] limit  = LIMIT,
    output reg         kill   = 0,
    output reg         loaded = 0
);

    reg  [5:0]  idx = 0;
    wire [5:0]  i   = sof ? 6'd0 : idx;
    reg         is_c = 0, fcs_good = 0;
    reg  [63:0] sym_n = 0;
    reg  [63:0] lim_n = 0;
    reg         kill_n = 0;

    wire [31:0] crc;
    crc32 u_crc (
        .clk (clk),
        .init(sof),
        .en  (valid && i < 6'd18),
        .d   (data),
        .c   (crc)
    );

    reg [7:0] fcs_b;
    always @*
        case (i)
            6'd18:   fcs_b = ~crc[7:0];
            6'd19:   fcs_b = ~crc[15:8];
            6'd20:   fcs_b = ~crc[23:16];
            default: fcs_b = ~crc[31:24];
        endcase

    always @(posedge clk) begin
        loaded <= 1'b0;
        if (valid) begin
            idx <= (i == 6'd63) ? i : i + 1'b1;
            if (i == 6'd0)                 is_c   <= data == "C";
            if (i >= 6'd1 && i <= 6'd8)    sym_n  <= {sym_n[55:0], data};
            if (i >= 6'd9 && i <= 6'd16)   lim_n  <= {lim_n[55:0], data};
            if (i == 6'd17)                kill_n <= data[0];
            if (i == 6'd18)                fcs_good <= data == fcs_b;
            else if (i >= 6'd19 && i <= 6'd21) fcs_good <= fcs_good && data == fcs_b;
        end
        if (eof && idx == 6'd22 && is_c && fcs_good) begin
            symbol <= sym_n;
            limit  <= lim_n;
            kill   <= kill_n;
            loaded <= 1'b1;
        end
    end

endmodule
