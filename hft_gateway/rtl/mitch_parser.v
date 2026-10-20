//lse mitch add order and a 4 byte fcs, little endian
//  0 length  1 type  2 nanosecond  6 order id  14 side  15 quantity  19 instrument
//  23 reserved  25 price  33 flags  34 reserved  44 fcs
`default_nettype none

module mitch_parser (
    input  wire        clk,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [63:0] symbol,         //instrument id in the low 32 bits
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire        valid,
    input  wire [7:0]  data,
    input  wire        sof,
    input  wire        eof,
    output reg         trig     = 0,
    output reg  [63:0] ref_num  = 0,
    output reg  [31:0] shares   = 0,
    output reg         px_valid = 0,
    output reg  [63:0] price    = 0,
    output reg         done     = 0,
    output reg         ok       = 0
);

    reg  [5:0] idx = 0;
    wire [5:0] i   = sof ? 6'd0 : idx;
    reg        hit  = 0;
    reg        open = 0;
    reg        fcs_good = 0;

    wire [31:0] crc;
    crc32 u_crc (
        .clk (clk),
        .init(sof),
        .en  (valid && i < 6'd44),
        .d   (data),
        .c   (crc)
    );

    reg [7:0] sym_b, fcs_b;
    always @* begin
        case (i[1:0])
            2'd3:    sym_b = symbol[7:0];
            2'd0:    sym_b = symbol[15:8];
            2'd1:    sym_b = symbol[23:16];
            default: sym_b = symbol[31:24];
        endcase
        case (i[1:0])
            2'd0:    fcs_b = ~crc[7:0];
            2'd1:    fcs_b = ~crc[15:8];
            2'd2:    fcs_b = ~crc[23:16];
            default: fcs_b = ~crc[31:24];
        endcase
    end

    wire in_sym = i >= 6'd19 && i <= 6'd22;
    wire in_fcs = i >= 6'd44 && i <= 6'd47;

    always @(posedge clk) begin
        trig     <= 1'b0;
        px_valid <= 1'b0;
        done     <= 1'b0;

        if (valid) begin
            idx <= (i == 6'd63) ? i : i + 1'b1;

            if (i == 6'd0)       hit <= data == 8'd44;
            else if (i == 6'd1)  hit <= hit && data == "A";
            else if (i == 6'd14) hit <= hit && data == "S";
            else if (in_sym)     hit <= hit && data == sym_b;

            if (i >= 6'd6  && i <= 6'd13) ref_num <= {data, ref_num[63:8]};
            if (i >= 6'd15 && i <= 6'd18) shares  <= {data, shares[31:8]};
            if (i >= 6'd25 && i <= 6'd32) price   <= {data, price[63:8]};

            if (i == 6'd22 && hit && data == sym_b) begin
                trig <= 1'b1;
                open <= 1'b1;
            end
            if (i == 6'd32 && open) px_valid <= 1'b1;

            if (i == 6'd44)  fcs_good <= data == fcs_b;
            else if (in_fcs) fcs_good <= fcs_good && data == fcs_b;
        end

        if (valid && i == 6'd47 && open) begin
            done <= 1'b1;
            ok   <= fcs_good && data == fcs_b;
            open <= 1'b0;
        end else if ((eof || sof) && open) begin
            done <= 1'b1;
            ok   <= 1'b0;
            open <= 1'b0;
        end
    end

`ifdef FORMAL
    always @* begin
        assume (!sof || valid);
        assume (!(valid && eof));
    end

    reg  [5:0]  f_i    = 0;
    reg         f_head = 0;
    reg  [31:0] f_rx   = 0;
    reg         f_past = 0;
    wire [5:0]  f_j    = sof ? 6'd0 : f_i;
    wire [31:0] f_crc;
    crc32 f_u_crc (
        .clk (clk),
        .init(sof),
        .en  (valid && f_j < 6'd44),
        .d   (data),
        .c   (f_crc)
    );
    wire [31:0] f_sym = symbol[31:0] >> (8 * (f_j - 19));

    always @(posedge clk) begin
        f_past <= 1'b1;
        if (valid) begin
            f_i <= (f_j == 6'd63) ? f_j : f_j + 1'b1;
            if (f_j == 0)                       f_head <= data == 8'd44;
            if (f_j == 1 && data != 8'h41)      f_head <= 1'b0;
            if (f_j == 14 && data != 8'h53)     f_head <= 1'b0;
            if (f_j >= 19 && f_j <= 22 && data != f_sym[7:0]) f_head <= 1'b0;
            if (f_j >= 44 && f_j <= 47)         f_rx <= {data, f_rx[31:8]};
        end
    end

    always @* begin
        assert (idx == f_i);
        assert (crc == f_crc);
        assert (hit == f_head);
        if (open) assert (f_i >= 6'd23 && f_i <= 6'd47 && hit && f_head);
        if (open && f_i == 6'd45) assert (fcs_good == (f_rx[31:24] == ~crc[7:0]));
        if (open && f_i == 6'd46) assert (fcs_good == (f_rx[31:16] == ~crc[15:0]));
        if (open && f_i == 6'd47) assert (fcs_good == (f_rx[31:8]  == ~crc[23:0]));
        if (trig) assert (f_i == 6'd23 && f_head);
        if (px_valid) assert (f_i == 6'd33 && open);
        if (done && ok) assert (f_i == 6'd48 && f_head && f_rx == ~f_crc);
    end

    always @(posedge clk)
        if (f_past) begin
            if (done) assert ($past(open));
            if ($past(open) && !done) assert (open);
        end

    always @(posedge clk) begin
        cover (done && ok);
        cover (done && !ok && f_i == 6'd48);
    end
`endif

endmodule
