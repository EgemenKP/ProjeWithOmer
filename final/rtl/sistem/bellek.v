// =============================================================================
//  bellek.v — Test sisteminin bellekleri (AKT, HATA, AGR, ETIKET) tek bir bayt dizisinde
// -----------------------------------------------------------------------------
//  Adım 4, arayüz sözleşmesi A5 ve Bölüm 4. Bölgeler taban adresleriyle ayrılır; taban
//  adresleri yapılandırmadan gelir (komut_yurutucu'nun cfg_taban_* portları).
//  Bir çevrimde bir "satır" (art arda en çok 16 bayt) okunur ya da yazılır.
//  Shao'nun çok bankalı tamponları (III-D) 16×16 diziyle birlikte Adım 5'in işi; bu modül
//  yalnızca test ağının (~1,8 KB) simülasyonu için.
//  Yazan: Claude, 03.11.2026
//
//  Portlar:
//    clk                     : saat
//    oku_a_adr [AW-1:0]      : A okuma portu, ilk baytın adresi
//    oku_a_veri[127:0]       : A portu, adres + k'daki bayt [8k +: 8] bitlerinde (k = 0..15);
//                              saatsiz (aynı çevrimde geçerli). Dizi dışı baytlar 0.
//    oku_b_adr, oku_b_veri   : B okuma portu, A ile aynı
//    yaz                     : 1 ise saat kenarında yaz_n bayt yazılır
//    yaz_adr  [AW-1:0]       : ilk baytın adresi
//    yaz_n    [4:0]          : bayt sayısı (1..16)
//    yaz_veri [127:0]        : k. bayt [8k +: 8] bitlerinde
//  Testbench belleğe hiyerarşik olarak (mem[i]) erişir: başlangıçta yükler, sonda okur.
// =============================================================================
`timescale 1ns/1ps

module bellek #(
    parameter AW    = 13,
    parameter BOYUT = 8192
) (
    input  wire            clk,
    input  wire [AW-1:0]   oku_a_adr,
    output wire [127:0]    oku_a_veri,
    input  wire [AW-1:0]   oku_b_adr,
    output wire [127:0]    oku_b_veri,
    input  wire            yaz,
    input  wire [AW-1:0]   yaz_adr,
    input  wire [4:0]      yaz_n,
    input  wire [127:0]    yaz_veri
);

    reg [7:0] mem [0:BOYUT-1];

    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin : okuma
            wire [AW:0] a = {1'b0, oku_a_adr} + k;
            wire [AW:0] b = {1'b0, oku_b_adr} + k;
            assign oku_a_veri[8*k +: 8] = (a < BOYUT) ? mem[a[AW-1:0]] : 8'd0;
            assign oku_b_veri[8*k +: 8] = (b < BOYUT) ? mem[b[AW-1:0]] : 8'd0;
        end
    endgenerate

    integer i;
    always @(posedge clk) begin
        if (yaz) begin
            for (i = 0; i < 16; i = i + 1)
                if (i < yaz_n && ({1'b0, yaz_adr} + i) < BOYUT)
                    mem[yaz_adr + i] <= yaz_veri[8*i +: 8];
        end
    end

endmodule
