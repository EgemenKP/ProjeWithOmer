// ============================================================================
// pe_wg_s1.v -- WG stride=1 (Fig. 5a), CIKTI-DURAGAN
//
// Her MAC[r][c] kendi akumulatorunde a*e biriktiriyor (accumulated_value
// girisi KENDI ciktisina baglanmis -- sel=10). Aktivasyon a_row satirin 3
// MAC'ine ayni cevrimde yayinlanir (gecikme yok). Hata e_row ise satir
// icinde bir D zincirinden geciyor: MAC[r][0] e'yi ayni cevrimde,
// MAC[r][1] 1 cevrim, MAC[r][2] 2 cevrim gecikmeli gorur.
//
// Akumulatorler CASE basinda sifirlanmali (testbench, ilk cevrimden once
// yeterince sifir besleyerek ya da mac.v'nin kendi initial=0 degeriyle
// saglar) -- GECIS basina DEGIL, tum case boyunca birikir.
// ============================================================================
`timescale 1ns/1ps

module pe_wg_s1 (
    input  wire               clk,
    input  wire               rst,           // case basinda akumulatorleri sifirlamak icin
    input  wire signed [7:0]  a_row0, e_row0,
    input  wire signed [7:0]  a_row1, e_row1,
    input  wire signed [7:0]  a_row2, e_row2,
    output wire signed [31:0] g00, g01, g02,
    output wire signed [31:0] g10, g11, g12,
    output wire signed [31:0] g20, g21, g22
);

    // her satirin hata gecikme zinciri (2 D register)
    reg signed [7:0] e0_d1, e0_d2, e1_d1, e1_d2, e2_d1, e2_d2;
    always @(posedge clk) begin
        e0_d2 <= e0_d1; e0_d1 <= e_row0;
        e1_d2 <= e1_d1; e1_d1 <= e_row1;
        e2_d2 <= e2_d1; e2_d1 <= e_row2;
    end

    // ---- satir 0 ----
    mac u_g00 (.clk(clk), .rst(rst), .weight(a_row0), .activation(e_row0),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g00),
               .sel(2'b10), .result(g00));
    mac u_g01 (.clk(clk), .rst(rst), .weight(a_row0), .activation(e0_d1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g01),
               .sel(2'b10), .result(g01));
    mac u_g02 (.clk(clk), .rst(rst), .weight(a_row0), .activation(e0_d2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g02),
               .sel(2'b10), .result(g02));

    // ---- satir 1 ----
    mac u_g10 (.clk(clk), .rst(rst), .weight(a_row1), .activation(e_row1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g10),
               .sel(2'b10), .result(g10));
    mac u_g11 (.clk(clk), .rst(rst), .weight(a_row1), .activation(e1_d1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g11),
               .sel(2'b10), .result(g11));
    mac u_g12 (.clk(clk), .rst(rst), .weight(a_row1), .activation(e1_d2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g12),
               .sel(2'b10), .result(g12));

    // ---- satir 2 ----
    mac u_g20 (.clk(clk), .rst(rst), .weight(a_row2), .activation(e_row2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g20),
               .sel(2'b10), .result(g20));
    mac u_g21 (.clk(clk), .rst(rst), .weight(a_row2), .activation(e2_d1),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g21),
               .sel(2'b10), .result(g21));
    mac u_g22 (.clk(clk), .rst(rst), .weight(a_row2), .activation(e2_d2),
               .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(g22),
               .sel(2'b10), .result(g22));

endmodule
