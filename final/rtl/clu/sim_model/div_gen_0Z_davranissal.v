// =============================================================================
//  div_gen_0Z_davranissal.v — YALNIZCA SİMÜLASYON İÇİN: Xilinx Divider Generator 5.1
//  (div_gen_0Z) IP'sinin yerine geçen davranışsal model.
// -----------------------------------------------------------------------------
//  Gerçek IP yoksa (Icarus, ya da ip/ klasörü boşken Vivado) kullanılır. Egemen'in
//  div_stage_ip.v'sindeki ayarlara göre yazıldı: Radix2, işaretsiz, bölünen 64 bit,
//  bölen 56 bit, Remainder, Non Blocking, 66 çevrim gecikme.
//  Çıkış: m_axis_dout_tdata = {bölüm[63:0], kalan[55:0]}.
//  Bu modelle ve gerçek IP'yle Egemen'in 40 CLU vektörü geçiyor (Icarus: Claude 03.11;
//  Vivado, gerçek IP: Ömer 03.11). Sentezlenmez; donanımda gerçek IP kullanılır.
//  Yazan: Claude, 03.11.2026
// =============================================================================
`timescale 1ns/1ps
module div_gen_0Z (
    input  wire         aclk,
    input  wire         s_axis_divisor_tvalid,
    input  wire [55:0]  s_axis_divisor_tdata,
    input  wire         s_axis_dividend_tvalid,
    input  wire [63:0]  s_axis_dividend_tdata,
    output wire         m_axis_dout_tvalid,
    output wire [119:0] m_axis_dout_tdata
);
    localparam GECIKME = 66;
    reg [119:0] veri [0:GECIKME-1];
    reg         gec  [0:GECIKME-1];
    integer i;
    initial for (i = 0; i < GECIKME; i = i + 1) begin veri[i] = 0; gec[i] = 0; end
    wire [63:0] bolum = (s_axis_divisor_tdata == 0) ? 64'd0 : s_axis_dividend_tdata / s_axis_divisor_tdata;
    wire [55:0] kalan = (s_axis_divisor_tdata == 0) ? 56'd0 : s_axis_dividend_tdata % s_axis_divisor_tdata;
    always @(posedge aclk) begin
        veri[0] <= {bolum, kalan};
        gec[0]  <= s_axis_divisor_tvalid & s_axis_dividend_tvalid;
        for (i = 1; i < GECIKME; i = i + 1) begin veri[i] <= veri[i-1]; gec[i] <= gec[i-1]; end
    end
    assign m_axis_dout_tdata  = veri[GECIKME-1];
    assign m_axis_dout_tvalid = gec[GECIKME-1];
endmodule
