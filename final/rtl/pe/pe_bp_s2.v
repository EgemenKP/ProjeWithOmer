// ============================================================================
// pe_bp_s2.v -- BP stride=2 (Fig. 4b)
//
// Her satirda IKI zincir var, ikisine de ayni e_r yayinlaniyor (broadcast,
// gecikme/ayrim yok -- FP_S2'den farkli):
//   A zinciri: MAC[r][0] -> MAC[r][1]  (2 basamak)
//   B zinciri: MAC[r][2]                (1 basamak, bagimsiz)
// Satir 0 ve 1'in A/B zincir baslarina psA/psB girer; satir 2'ye HIC psum
// girmez (her zaman 0).
//
// Cikislar (Psum FIFO'ya 4 paralel serit):
//   out0 = A(satir0) + A(satir2)
//   out1 = B(satir0) + B(satir2)
//   out2 = A(satir1)
//   out3 = B(satir1)
// ============================================================================
`timescale 1ns/1ps

module pe_bp_s2 (
    input  wire               clk,
    input  wire signed [7:0]  w00, w01, w02,
    input  wire signed [7:0]  w10, w11, w12,
    input  wire signed [7:0]  w20, w21, w22,
    input  wire signed [7:0]  e_row0, e_row1, e_row2,
    input  wire signed [31:0] psA0, psB0, psA1, psB1,
    output wire signed [31:0] out0, out1, out2, out3
);

    // ---- satir 0: A ve B zincirleri ----
    wire signed [31:0] r0A0, r0A1, r0B0;
    mac u_r0A0 (.clk(clk), .rst(1'b0), .weight(w00), .activation(e_row0),
                .partial_sum(psA0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0A0));
    mac u_r0A1 (.clk(clk), .rst(1'b0), .weight(w01), .activation(e_row0),
                .partial_sum(r0A0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0A1));
    mac u_r0B0 (.clk(clk), .rst(1'b0), .weight(w02), .activation(e_row0),
                .partial_sum(psB0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0B0));

    // ---- satir 1: A ve B zincirleri ----
    wire signed [31:0] r1A0, r1A1, r1B0;
    mac u_r1A0 (.clk(clk), .rst(1'b0), .weight(w10), .activation(e_row1),
                .partial_sum(psA1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1A0));
    mac u_r1A1 (.clk(clk), .rst(1'b0), .weight(w11), .activation(e_row1),
                .partial_sum(r1A0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1A1));
    mac u_r1B0 (.clk(clk), .rst(1'b0), .weight(w12), .activation(e_row1),
                .partial_sum(psB1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1B0));

    // ---- satir 2: A ve B zincirleri -- psum HIC girmez ----
    wire signed [31:0] r2A0, r2A1, r2B0;
    mac u_r2A0 (.clk(clk), .rst(1'b0), .weight(w20), .activation(e_row2),
                .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2A0));
    mac u_r2A1 (.clk(clk), .rst(1'b0), .weight(w21), .activation(e_row2),
                .partial_sum(r2A0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2A1));
    mac u_r2B0 (.clk(clk), .rst(1'b0), .weight(w22), .activation(e_row2),
                .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2B0));

    assign out0 = r0A1 + r2A1;
    assign out1 = r0B0 + r2B0;
    assign out2 = r1A1;
    assign out3 = r1B0;

endmodule
