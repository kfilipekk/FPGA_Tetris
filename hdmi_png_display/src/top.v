module top(
    input clk,
    output [3:0] hdmi_tx_n,
    output [3:0] hdmi_tx_p
);
    wire hdmi_clk, hdmi_clk_5x, lock;
    wire [12:0] x, y;
    wire [2:0] hve;
    wire [15:0] rom_addr;
    wire [23:0] rom_data;
    reg [23:0] rgb;
    reg [2:0] hve_d1, hve_d2;
    reg in_region_d1;

    rPLL #(.FCLKIN("27"), .IDIV_SEL(2), .FBDIV_SEL(13), .ODIV_SEL(4)) pll_inst (
        .CLKIN(clk), .CLKOUT(hdmi_clk_5x), .LOCK(lock),
        .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0), .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0)
    );
    CLKDIV #(.DIV_MODE("5"), .GSREN("false")) clk_div (.CLKOUT(hdmi_clk), .HCLKIN(hdmi_clk_5x), .RESETN(lock), .CALIB(1'b1));

    //video Timing Generator (640x480)
    reg [10:0] h_cnt;
    reg [9:0] v_cnt;
    always @(posedge hdmi_clk) begin
        h_cnt <= (h_cnt == 1047) ? 0 : h_cnt + 1;
        if (h_cnt == 1047) v_cnt <= (v_cnt == 521) ? 0 : v_cnt + 1;
    end
    
    //hSync: 688-799, VSync: 481-483. Active: <640, <480.
    assign hve = { (h_cnt < 640 && v_cnt < 480), (v_cnt >= 481 && v_cnt < 484), (h_cnt >= 688 && h_cnt < 800) };
    
    //image Logic (200x150 centered on 640x480)
    wire in_region = (h_cnt >= 220 && h_cnt < 420 && v_cnt >= 165 && v_cnt < 315);
    assign rom_addr = in_region ? ((v_cnt - 165) * 200 + (h_cnt - 220)) : 16'd0;
    
    image_rom img_rom (.clk(hdmi_clk), .addr(rom_addr), .data(rom_data));

    always @(posedge hdmi_clk) begin
        hve_d1 <= hve; hve_d2 <= hve_d1;
        in_region_d1 <= in_region;
        rgb <= in_region_d1 ? rom_data : 24'h101040;
    end

    hdmi hdmi_inst (.clk(hdmi_clk), .clk_5x(hdmi_clk_5x), .reset(~lock), .hve(hve_d2), .rgb(rgb), .out_n(hdmi_tx_n), .out_p(hdmi_tx_p));
endmodule

module hdmi(
    input clk, clk_5x, reset,
    input [2:0] hve,
    input [23:0] rgb,
    output [3:0] out_n, out_p
);
    wire [9:0] tmds[2:0];
    wire [3:0] ser;
    tmds_enc enc0 (clk, reset, rgb[7:0],   hve[1:0], hve[2], tmds[0]);
    tmds_enc enc1 (clk, reset, rgb[15:8],  2'b0,     hve[2], tmds[1]);
    tmds_enc enc2 (clk, reset, rgb[23:16], 2'b0,     hve[2], tmds[2]);

    genvar i;
    generate
        for(i=0; i<3; i=i+1) begin : ser_gen
            OSER10 #(.GSREN("false"), .LSREN("true")) ser_c (.PCLK(clk), .FCLK(clk_5x), .RESET(reset), .Q(ser[i]), 
                .D0(tmds[i][0]), .D1(tmds[i][1]), .D2(tmds[i][2]), .D3(tmds[i][3]), .D4(tmds[i][4]), 
                .D5(tmds[i][5]), .D6(tmds[i][6]), .D7(tmds[i][7]), .D8(tmds[i][8]), .D9(tmds[i][9]));
            ELVDS_OBUF obuf (.I(ser[i]), .O(out_p[i]), .OB(out_n[i]));
        end
    endgenerate
    
    wire clk_ser;
    OSER10 #(.GSREN("false"), .LSREN("true")) ser_clk (.PCLK(clk), .FCLK(clk_5x), .RESET(reset), .Q(clk_ser), 
        .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1), .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0));
    ELVDS_OBUF obuf_clk (.I(clk_ser), .O(out_p[3]), .OB(out_n[3]));
endmodule

module tmds_enc(input clk, rst, input [7:0] d, input [1:0] c, input de, output reg [9:0] q);
    reg [3:0] cnt;
    always @(posedge clk) begin
        if (rst) begin cnt <= 0; q <= 0; end else begin
            integer n1; n1 = d[0]+d[1]+d[2]+d[3]+d[4]+d[5]+d[6]+d[7];
            reg [8:0] q_m;
            q_m[0] = d[0];
            if (n1 > 4 || (n1 == 4 && d[0] == 0)) begin
                for(integer i=1; i<8; i++) q_m[i] = ~(q_m[i-1] ^ d[i]);
                q_m[8] = 0;
            end else begin
                for(integer i=1; i<8; i++) q_m[i] = q_m[i-1] ^ d[i];
                q_m[8] = 1;
            end
            
            integer n1q; n1q = q_m[0]+q_m[1]+q_m[2]+q_m[3]+q_m[4]+q_m[5]+q_m[6]+q_m[7];
            integer n0q; n0q = 8 - n1q;
            
            if (!de) begin
                cnt <= 0;
                case(c)
                    2'b00: q <= 10'b1101010100; 2'b01: q <= 10'b0010101011;
                    2'b10: q <= 10'b0101010100; 2'b11: q <= 10'b1010101011;
                endcase
            end else begin
                if (cnt == 0 || n1q == 4) begin
                    q[9] <= ~q_m[8]; q[8] <= q_m[8]; q[7:0] <= (q_m[8]) ? q_m[7:0] : ~q_m[7:0];
                    if (q_m[8] == 0) cnt <= cnt + (n0q - n1q); else cnt <= cnt + (n1q - n0q);
                end else begin
                    if ((cnt > 0 && n1q > 4) || (cnt < 0 && n1q < 4)) begin
                        q[9] <= 1; q[8] <= q_m[8]; q[7:0] <= ~q_m[7:0];
                        cnt <= cnt + (q_m[8] ? 2 : 0) + (n0q - n1q);
                    end else begin
                        q[9] <= 0; q[8] <= q_m[8]; q[7:0] <= q_m[7:0];
                        cnt <= cnt - (q_m[8] ? 0 : 2) + (n1q - n0q);
                    end
                end
            end
        end
    end
endmodule
