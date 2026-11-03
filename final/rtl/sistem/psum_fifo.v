// =============================================================================
//  psum_fifo.v — Psum FIFO: kanallar arası kısmi toplamlar (int32), ilk giren ilk çıkar
// -----------------------------------------------------------------------------
//  Adım 4, arayüz sözleşmesi A6. Shao Fig. 2'deki "Psum FIFO". Golden (sistem_golden.py,
//  yorumla()): son = 0 olan geçişin çıkışları FIFO'ya yazılır, sonraki kanalın aynı
//  (örnek, satır) geçişi ilk = 0 ise onları baştan okur. Golden her okumada baştaki
//  kaydın beklenen kayıt olduğunu kontrol ediyor; bu yüzden anahtar gerekmiyor.
//  En çok doluluk: ag1'de 128, ag2'de 144 int32 (OKUNUR.txt) -> varsayılan derinlik 256.
//  Yazan: Claude, 03.11.2026
//
//  Portlar:
//    clk, rst        : saat; eşzamanlı aktif-yüksek temizleme (İŞ_BAŞLA'da verilir)
//    yaz, yaz_veri   : 1 ise yaz_veri[31:0] sona eklenir (doluyken yok sayılır, tasma = 1)
//    oku             : 1 ise baştaki kayıt çıkarılır (boşken yok sayılır, eksik = 1)
//    bas_veri [31:0] : baştaki kayıt (saatsiz okuma; boşken anlamsız)
//    bos, dolu       : durum
//    doluluk [AW:0]  : kayıt sayısı
//    tasma, eksik    : yapışkan hata bayrakları (rst ile temizlenir); testte 0 kalmalı
//  Aynı çevrimde yaz ve oku birlikte verilebilir (boşken yazılan, o çevrim okunamaz).
// =============================================================================
`timescale 1ns/1ps

module psum_fifo #(
    parameter GENISLIK = 32,       // kayıt genişliği (final/, 04.11: dizide PE başına 128, D74)
    parameter DERINLIK = 256,
    parameter AW       = 8          // DERINLIK = 2^AW
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          yaz,
    input  wire [GENISLIK-1:0] yaz_veri,
    input  wire          oku,
    output wire [GENISLIK-1:0] bas_veri,
    output wire          bos,
    output wire          dolu,
    output reg  [AW:0]   doluluk,
    output reg           tasma,
    output reg           eksik
);

    reg [GENISLIK-1:0] mem [0:DERINLIK-1];
    reg [AW-1:0] yaz_ptr, oku_ptr;

    assign bos      = (doluluk == {(AW+1){1'b0}});
    assign dolu     = (doluluk == DERINLIK);
    assign bas_veri = mem[oku_ptr];

    wire gercek_yaz = yaz && !dolu;
    wire gercek_oku = oku && !bos;

    always @(posedge clk) begin
        if (rst) begin
            yaz_ptr <= {AW{1'b0}};
            oku_ptr <= {AW{1'b0}};
            doluluk <= {(AW+1){1'b0}};
            tasma   <= 1'b0;
            eksik   <= 1'b0;
        end else begin
            if (gercek_yaz) begin
                mem[yaz_ptr] <= yaz_veri;
                yaz_ptr      <= yaz_ptr + 1'b1;
            end
            if (gercek_oku)
                oku_ptr <= oku_ptr + 1'b1;
            if (gercek_yaz && !gercek_oku)      doluluk <= doluluk + 1'b1;
            else if (gercek_oku && !gercek_yaz) doluluk <= doluluk - 1'b1;
            if (yaz && dolu) tasma <= 1'b1;
            if (oku && bos)  eksik <= 1'b1;
        end
    end

endmodule
