// ============================================================================
// pe_wg_s2.v -- WG stride=2 (Fig. 5b)
//
// WG_S1'in hata-gecikme zinciriyle (MAC[r][c] e'yi c cevrim gecikmeli gorur)
// FP_S2'nin cift/tek+gecikmeli-cift aktivasyon ayrimini birlestirir:
//   MAC[r][0]: aktivasyon=cift_r,          hata=e_r (gecikmesiz)
//   MAC[r][1]: aktivasyon=tek_r,           hata=e_r (1 cevrim gecikmeli)
//   MAC[r][2]: aktivasyon=cift_r (1 cevrim gecikmeli, "mavi D"), hata=e_r (2 cevrim gecikmeli)
// ============================================================================
`timescale 1ns/1ps

module pe_wg_s2 (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [7:0]  cift_r0, tek_r0, e_row0,
    input  wire signed [7:0]  cift_r1, tek_r1, e_row1,
    input  wire signed [7:0]  cift_r2, tek_r2, e_row2,
    output wire signed [31:0] g00, g01, g02,
    output wire signed [31:0] g10, g11, g12,
    output wire signed [31:0] g20, g21, g22
);

    // aktivasyon tarafi: mavi D (1 cevrim gecikmeli cift akis)
    reg signed [7:0] d_r0, d_r1, d_r2;
    // hata tarafi: 2 asamali gecikme zinciri
    reg signed [7:0] e0_d1, e0_d2, e1_d1, e1_d2, e2_d1, e2_d2;

    always @(posedge clk) begin
        d_r0 <= cift_r0; d_r1 <= cift_r1; d_r2 <= cift_r2;
        e0_d2 <= e0_d1; e0_d1 <= e_row0;
        e1_d2 <= e1_d1; e1_d1 <= e_row1;
        e2_d2 <= e2_d1; e2_d1 <= e_row2;
    end

    // ---- satir 0 ----
    mac u_g00 (.clk(clk), .rst(rst), .weight(cift_r0), .activation(e_row0),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g00),
               .sel(2'b10), .result(g00));
    mac u_g01 (.clk(clk), .rst(rst), .weight(tek_r0), .activation(e0_d1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g01),
               .sel(2'b10), .result(g01));
    mac u_g02 (.clk(clk), .rst(rst), .weight(d_r0), .activation(e0_d2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g02),
               .sel(2'b10), .result(g02));

    // ---- satir 1 ----
    mac u_g10 (.clk(clk), .rst(rst), .weight(cift_r1), .activation(e_row1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g10),
               .sel(2'b10), .result(g10));
    mac u_g11 (.clk(clk), .rst(rst), .weight(tek_r1), .activation(e1_d1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g11),
               .sel(2'b10), .result(g11));
    mac u_g12 (.clk(clk), .rst(rst), .weight(d_r1), .activation(e1_d2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g12),
               .sel(2'b10), .result(g12));

    // ---- satir 2 ----
    mac u_g20 (.clk(clk), .rst(rst), .weight(cift_r2), .activation(e_row2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g20),
               .sel(2'b10), .result(g20));
    mac u_g21 (.clk(clk), .rst(rst), .weight(tek_r2), .activation(e2_d1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g21),
               .sel(2'b10), .result(g21));
    mac u_g22 (.clk(clk), .rst(rst), .weight(d_r2), .activation(e2_d2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g22),
               .sel(2'b10), .result(g22));

endmodule
