//ouch 4.2 enter order, 49 bytes and a 4 byte fcs, sent from the moment the symbol
//matches. the price is filled in when it lands and the verdict is only needed by
//the fcs: a reject, a late verdict or a missing price sends the fcs inverted, so
//the frame is dropped at the other end
//  0 type  1 token  15 side  16 shares  20 stock  28 price  32 tif  36 firm
//  40 display  41 capacity  42 iso  43 min qty  47 cross  48 customer  49 fcs
`default_nettype none

module ouch_tx #(
    parameter [31:0] FIRM = "FPGA"
) (
    input  wire        clk,
    input  wire        start,
    input  wire [63:0] stock,
    input  wire [55:0] token,     //14 hex digits
    input  wire [31:0] qty,
    input  wire        px_valid,
    input  wire [31:0] price,
    input  wire        decide,
    input  wire        commit,
    output reg  [7:0]  data,
    output wire        valid,
    input  wire        ready,
    output reg         busy    = 0,
    output reg         good    = 0,  //accepted, the fcs will be good
    output reg         bad     = 0,  //rejected, the fcs will be stomped
    output reg         sent    = 0,  //a clock at the end of a good frame
    output reg         stomped = 0   //and of a stomped one
);

    reg [5:0]  idx = 0;
    reg [63:0] st  = 0;
    reg [55:0] tok = 0;
    reg [31:0] q   = 0;
    reg [31:0] px  = 0;
    reg        have_px = 0;
    reg        fcs_on  = 0;          //verdict frozen

    assign valid = busy;
    wire fire = busy && ready;

    wire [31:0] crc;
    crc32 u_crc (
        .clk (clk),
        .init(start && !busy),
        .en  (fire && idx < 6'd49),
        .d   (data),
        .c   (crc)
    );

    wire [31:0] pxv = have_px ? px : 32'd0;
    wire [31:0] fcs = good ? ~crc : crc;
    wire [3:0]  nib = tok[4*(14 - idx) +: 4];
    wire [7:0]  hex = (nib < 4'd10) ? "0" + {4'd0, nib} : "A" - 8'd10 + {4'd0, nib};

    always @* begin
        if (idx == 6'd0)       data = "O";
        else if (idx <= 6'd14) data = hex;
        else if (idx == 6'd15) data = "B";
        else if (idx <= 6'd19) data = q[8*(19 - idx) +: 8];
        else if (idx <= 6'd27) data = st[8*(27 - idx) +: 8];
        else if (idx <= 6'd31) data = pxv[8*(31 - idx) +: 8];
        else if (idx <= 6'd35) data = 8'd0;        //time in force 0, ioc
        else if (idx <= 6'd39) data = FIRM[8*(39 - idx) +: 8];
        else if (idx == 6'd40) data = "Y";         //display
        else if (idx == 6'd41) data = "P";         //capacity, principal
        else if (idx == 6'd42) data = "N";         //not iso
        else if (idx <= 6'd46) data = 8'd0;        //min qty
        else if (idx == 6'd47) data = "N";         //cross type
        else if (idx == 6'd48) data = "R";         //customer type
        else                   data = fcs[8*(idx - 49) +: 8];
    end

    //the verdict counts until the first fcs byte leaves
    wire take = decide && !fcs_on && !(fire && idx == 6'd49) && !good && !bad;

    always @(posedge clk) begin
        sent    <= 1'b0;
        stomped <= 1'b0;

        if (!busy) begin
            if (start) begin
                busy    <= 1'b1;
                idx     <= 0;
                st      <= stock;
                tok     <= token;
                q       <= qty;
                have_px <= 1'b0;
                fcs_on  <= 1'b0;
                good    <= 1'b0;
                bad     <= 1'b0;
            end
        end else begin
            if (px_valid && !have_px) begin
                have_px <= 1'b1;
                px      <= price;
            end

            if (take) begin
                good <= commit;
                bad  <= !commit;
            end

            if (fire) begin
                idx <= idx + 1'b1;
                //price not in by its field
                if (idx == 6'd28 && !have_px) begin
                    good <= 1'b0;
                    bad  <= 1'b1;
                end
                //no verdict by the fcs
                if (idx == 6'd49) begin
                    fcs_on <= 1'b1;
                    if (!good) bad <= 1'b1;
                end
                if (idx == 6'd52) begin
                    busy    <= 1'b0;
                    good    <= 1'b0;
                    bad     <= 1'b0;
                    sent    <= good;
                    stomped <= !good;
                end
            end
        end
    end


endmodule
