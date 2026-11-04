// =============================================================================
//  veri_tamponu.v — Çok bankalı veri tamponu (Fig. 8 Input/Output Buffer, D79–D81)
// -----------------------------------------------------------------------------
//  NB bank; kelime = bir grup: 16 kanalın int8 değeri + grubun l'si (D81):
//    kelime[127:0]   : kanal k -> [8k +: 8]
//    kelime[133:128] : l (LMS kaydırması; GMS'te Δ = G − l, D78)
//  Bank = satır mod 16 (D79). Okuma yüzü ön-getirme (bank başına 1 okuma portu, eşzamanlı okuma:
//  veri bir sonraki kenarda), yazma yüzü SRU satırları / CLU / yükleme (bank başına 1 yazma portu).
//  Fig. 8'in giriş ve çıkış tamponları bu belleğin iki yüzü (D80). Sentezde BRAM'e eşlenmesi için
//  eşzamanlı okuma.
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b-3b)
// =============================================================================
`timescale 1ns/1ps

module veri_tamponu #(
    parameter NB = 16,
    parameter AW = 9,               // bank başına 2^AW kelime
    parameter KW = 134              // kelime genişliği
) (
    input  wire                 clk,
    input  wire [NB*AW-1:0]     oku_adr,
    output reg  [NB*KW-1:0]     oku_veri,
    input  wire [NB-1:0]        yaz_en,
    input  wire [NB*AW-1:0]     yaz_adr,
    input  wire [NB*KW-1:0]     yaz_veri
);

    genvar k;
    generate
        for (k = 0; k < NB; k = k + 1) begin : bank
            reg [KW-1:0] mem [0:(1<<AW)-1];
            integer a;
            initial for (a = 0; a < (1<<AW); a = a + 1) mem[a] = {KW{1'b0}};
            always @(posedge clk) begin
                if (yaz_en[k]) mem[yaz_adr[AW*k +: AW]] <= yaz_veri[KW*k +: KW];
                oku_veri[KW*k +: KW] <= mem[oku_adr[AW*k +: AW]];
            end
        end
    endgenerate

endmodule
