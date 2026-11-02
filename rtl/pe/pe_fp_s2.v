// ============================================================================
// pe_fp_s2.v -- FP stride=2 (Fig. 3b)
//
// Her satirda: MAC[r][0] cift akisini, MAC[r][1] tek akisini alir.
// MAC[r][2] ise cift akisinin 1 CEVRIM GECIKMELI halini (mavi D register,
// MAC disinda, benim kendi dff'im) alir.
// Zincir (partial_sum) baglantisi pe_chain3 ile ayni: MAC0->MAC1->MAC2,
// yalniz satir 0'in ilk MAC'i ps_in alir.
// ============================================================================
`timescale 1ns/1ps

module pe_fp_s2 (
    input  wire               clk,
    input  wire signed [7:0]  w00, w01, w02,
    input  wire signed [7:0]  w10, w11, w12,
    input  wire signed [7:0]  w20, w21, w22,
    input  wire signed [7:0]  cift_r0, tek_r0,
    input  wire signed [7:0]  cift_r1, tek_r1,
    input  wire signed [7:0]  cift_r2, tek_r2,
    input  wire signed [31:0] ps_in,
    output wire signed [31:0] psum_out
);

    // her satirin "mavi D" register'i: bir onceki cevrimin cift degeri
    reg signed [7:0] d_r0, d_r1, d_r2;
    always @(posedge clk) begin
        d_r0 <= cift_r0;
        d_r1 <= cift_r1;
        d_r2 <= cift_r2;
    end

    wire signed [31:0] r0m0, r0m1, r0m2;
    mac u_r0c0 (.clk(clk), .rst(1'b0), .weight(w00), .activation(cift_r0),
                .partial_sum(ps_in), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0m0));
    mac u_r0c1 (.clk(clk), .rst(1'b0), .weight(w01), .activation(tek_r0),
                .partial_sum(r0m0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0m1));
    mac u_r0c2 (.clk(clk), .rst(1'b0), .weight(w02), .activation(d_r0),
                .partial_sum(r0m1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r0m2));

    wire signed [31:0] r1m0, r1m1, r1m2;
    mac u_r1c0 (.clk(clk), .rst(1'b0), .weight(w10), .activation(cift_r1),
                .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1m0));
    mac u_r1c1 (.clk(clk), .rst(1'b0), .weight(w11), .activation(tek_r1),
                .partial_sum(r1m0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1m1));
    mac u_r1c2 (.clk(clk), .rst(1'b0), .weight(w12), .activation(d_r1),
                .partial_sum(r1m1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r1m2));

    wire signed [31:0] r2m0, r2m1, r2m2;
    mac u_r2c0 (.clk(clk), .rst(1'b0), .weight(w20), .activation(cift_r2),
                .partial_sum(32'sd0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2m0));
    mac u_r2c1 (.clk(clk), .rst(1'b0), .weight(w21), .activation(tek_r2),
                .partial_sum(r2m0), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2m1));
    mac u_r2c2 (.clk(clk), .rst(1'b0), .weight(w22), .activation(d_r2),
                .partial_sum(r2m1), .passed_value(32'sd0), .accumulated_value(32'sd0),
                .sel(2'b00), .result(r2m2));

    assign psum_out = r0m2 + r1m2 + r2m2;

endmodule
