// =============================================================================
//  grup_fifo.v — GMS çıkış FIFO'su: SRU'nun GMS akışından gelen grupları tutar
// -----------------------------------------------------------------------------
//  Adım 4, arayüz sözleşmesi A3 (D64): Egemen'in SRU'su ÖLÇEK'te son grup itilir itilmez
//  GMS sonuçlarını her çevrimde bir grup olacak şekilde durdurulamadan verir. Bu FIFO o
//  akışı yakalar; her KOPYA ve WU komutu baştan bir grup alır. Golden'da tüketici sırası
//  grup sırasıyla aynı olduğu için (sablon_kontrol) anahtar gerekmiyor.
//  Yazan: Claude, 03.11.2026
//
//  Portlar:
//    clk, rst          : saat; eşzamanlı aktif-yüksek temizleme (İŞ_BAŞLA'da)
//    yaz               : SRU group_out_valid
//    yaz_veri [127:0]  : SRU group_out_flat (16 × int8)
//    yaz_n    [4:0]    : SRU group_out_n (eleman sayısı)
//    oku               : 1 ise baştaki grup çıkarılır
//    bas_veri, bas_n   : baştaki grup (saatsiz)
//    bos, doluluk      : durum
//    tasma, eksik      : yapışkan hata bayrakları (doluyken yazma / boşken okuma)
// =============================================================================
`timescale 1ns/1ps

module grup_fifo #(
    parameter DERINLIK = 64,
    parameter AW       = 6
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          yaz,
    input  wire [127:0]  yaz_veri,
    input  wire [4:0]    yaz_n,
    input  wire          oku,
    output wire [127:0]  bas_veri,
    output wire [4:0]    bas_n,
    output wire          bos,
    output reg  [AW:0]   doluluk,
    output reg           tasma,
    output reg           eksik
);

    reg [127:0]  veri [0:DERINLIK-1];
    reg [4:0]    adet [0:DERINLIK-1];
    reg [AW-1:0] yaz_ptr, oku_ptr;

    wire dolu = (doluluk == DERINLIK);
    assign bos      = (doluluk == {(AW+1){1'b0}});
    assign bas_veri = veri[oku_ptr];
    assign bas_n    = adet[oku_ptr];

    wire g_yaz = yaz && !dolu;
    wire g_oku = oku && !bos;

    always @(posedge clk) begin
        if (rst) begin
            yaz_ptr <= {AW{1'b0}};
            oku_ptr <= {AW{1'b0}};
            doluluk <= {(AW+1){1'b0}};
            tasma   <= 1'b0;
            eksik   <= 1'b0;
        end else begin
            if (g_yaz) begin
                veri[yaz_ptr] <= yaz_veri;
                adet[yaz_ptr] <= yaz_n;
                yaz_ptr       <= yaz_ptr + 1'b1;
            end
            if (g_oku) oku_ptr <= oku_ptr + 1'b1;
            if (g_yaz && !g_oku)      doluluk <= doluluk + 1'b1;
            else if (g_oku && !g_yaz) doluluk <= doluluk - 1'b1;
            if (yaz && dolu) tasma <= 1'b1;
            if (oku && bos)  eksik <= 1'b1;
        end
    end

endmodule
