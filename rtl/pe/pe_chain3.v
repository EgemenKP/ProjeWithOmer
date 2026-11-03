// ============================================================================
// pe_chain3.v -- FP stride=1 VE BP stride=1 icin ORTAK donanim (Omer Faruk'un
//   README_PE_GOLDEN.md Bolum 2'sine gore: "ayni donanim deseni" -- BP_S1
//   zaten 180-derece donduruimus agirliklarla ayni modulu kullanir, RTL
//   donduemeye gerek yok, test vektoru donduruemus agirligi dogrudan verir).
//
// 3 satir, her biri 3 MAC'lik zincir (Fig.3a: mux->+->D->+->D->+->D).
// Satir r'deki 3 MAC'e ayni deger (x_row[r]) yayinlanir (broadcast).
// Yalniz SATIR 0'in zincir girisi (ilk MAC'in partial_sum'i) ps_in'den
// gelir (PE-a2); satir 1 ve 2'de bu deger 0'a sabit.
// Cikis = 3 satirin son MAC'inin (MAC[r][2]) ciktilarinin toplami.
// ============================================================================
`timescale 1ns/1ps

module pe_chain3 (
    input  wire               clk,
    input  wire signed [7:0]  w00, w01, w02,
    input  wire signed [7:0]  w10, w11, w12,
    input  wire signed [7:0]  w20, w21, w22,
    input  wire signed [7:0]  x_row0, x_row1, x_row2,
    input  wire signed [31:0] ps_in,          // yalniz satir 0'a girer (PE-a2)
    output wire signed [31:0] psum_out
);

    wire signed [31:0] r0m0, r0m1, r0m2;
    mac u_r0c0 (.clk(clk), .rst(1'b0), .weight(w00), .activation(x_row0),
                .partial_sum(ps_in), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0m0));
    mac u_r0c1 (.clk(clk), .rst(1'b0), .weight(w01), .activation(x_row0),
                .partial_sum(r0m0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0m1));
    mac u_r0c2 (.clk(clk), .rst(1'b0), .weight(w02), .activation(x_row0),
                .partial_sum(r0m1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0m2));

    wire signed [31:0] r1m0, r1m1, r1m2;
    mac u_r1c0 (.clk(clk), .rst(1'b0), .weight(w10), .activation(x_row1),
                .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1m0));
    mac u_r1c1 (.clk(clk), .rst(1'b0), .weight(w11), .activation(x_row1),
                .partial_sum(r1m0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1m1));
    mac u_r1c2 (.clk(clk), .rst(1'b0), .weight(w12), .activation(x_row1),
                .partial_sum(r1m1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1m2));

    wire signed [31:0] r2m0, r2m1, r2m2;
    mac u_r2c0 (.clk(clk), .rst(1'b0), .weight(w20), .activation(x_row2),
                .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2m0));
    mac u_r2c1 (.clk(clk), .rst(1'b0), .weight(w21), .activation(x_row2),
                .partial_sum(r2m0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2m1));
    mac u_r2c2 (.clk(clk), .rst(1'b0), .weight(w22), .activation(x_row2),
                .partial_sum(r2m1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2m2));

    assign psum_out = r0m2 + r1m2 + r2m2;

endmodule
