//settings frame from the host: 'C', symbol, limit, kill, fcs
`default_nettype none

module cfg #(
    parameter [63:0] SYMBOL = "AAPL    ",
    parameter [31:0] LIMIT  = 1500000
) (
    input  wire        clk,
    input  wire        valid,
    input  wire [7:0]  data,
    input  wire        sof,
    input  wire        eof,
    output reg  [63:0] symbol = SYMBOL,
    output reg  [31:0] limit  = LIMIT,
    output reg         kill   = 0,
    output reg         loaded = 0
);

    reg  [5:0]  idx = 0;
    wire [5:0]  i   = sof ? 6'd0 : idx;
    reg         is_c = 0, fcs_good = 0;
    reg  [63:0] sym_n = 0;
    reg  [31:0] lim_n = 0;
    reg         kill_n = 0;

    wire [31:0] crc;
    crc32 u_crc (
        .clk (clk),
        .init(sof),
        .en  (valid && i < 6'd14),
        .d   (data),
        .c   (crc)
    );

    reg [7:0] fcs_b;
    always @*
        case (i)
            6'd14:   fcs_b = ~crc[7:0];
            6'd15:   fcs_b = ~crc[15:8];
            6'd16:   fcs_b = ~crc[23:16];
            default: fcs_b = ~crc[31:24];
        endcase

    always @(posedge clk) begin
        loaded <= 1'b0;
        if (valid) begin
            idx <= (i == 6'd63) ? i : i + 1'b1;
            if (i == 6'd0)                 is_c   <= data == "C";
            if (i >= 6'd1 && i <= 6'd8)    sym_n  <= {sym_n[55:0], data};
            if (i >= 6'd9 && i <= 6'd12)   lim_n  <= {lim_n[23:0], data};
            if (i == 6'd13)                kill_n <= data[0];
            if (i == 6'd14)                fcs_good <= data == fcs_b;
            else if (i >= 6'd15 && i <= 6'd17) fcs_good <= fcs_good && data == fcs_b;
        end
        if (eof && idx == 6'd18 && is_c && fcs_good) begin
            symbol <= sym_n;
            limit  <= lim_n;
            kill   <= kill_n;
            loaded <= 1'b1;
        end
    end

endmodule
