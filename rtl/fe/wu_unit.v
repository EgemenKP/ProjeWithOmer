// =============================================================================
//  wu_unit.v — Ağırlık güncelleme (Weight Update) birimi, N paralel şerit
// -----------------------------------------------------------------------------
//  Kaynak  : Shao vd., ISVLSI 2021, Fig. 8 ve III-D (s. 258): Weight Update
//            fonksiyon motorunda. Davranış NITI'den (Shao sessiz -> NITI):
//            Alg. 1 satır 14: w <- w - g;  ti_torch.py 21 ve 71-72: int8_clip(±127).
//  Kararlar: K2b (Ömer, 31.10): sonuç ±127'ye doyurulur (-128 üretilmez, D9).
//            g8 bu birime gelmeden önce SRU'dan hedef m_u ile ve GMS'ten geçmiş
//            olmalı (K2a, K3); o kısım SRU'nun işi, bu birimde değil.
//  Golden  : fe_golden.py (agirlik_guncelle); vektör: fe_vektorleri/wu_cikarma.hex
//  Yazan   : Claude, 31.10.2026
//
//  Portlar (tüm veriler işaretli int8, ikiye tümleyen):
//    w_flat     : N*8 bit      mevcut ağırlıklar w
//    g_flat     : N*8 bit      SRU'dan gelen gradyan g8 (|g8| <= 2^m_u)
//    w_yeni_flat: N*8 bit      doyur(w - g8) ∈ [-127, 127]
//  Şerit i'nin verisi [8*i +: 8] bitlerinde (düz veri yolu, DEVIATIONS araç tuzağı 2).
//
//  Zamanlama: saatsiz (kombinasyonel), gecikme 0. Ağırlık tamponuna okuma-yazma
//  ve boru hattı, arayüz sözleşmesinde (Adım 4.0) belirlenecek.
// =============================================================================
`timescale 1ns/1ps

module wu_unit #(
    parameter N = 16                    // şerit sayısı
) (
    input  wire [N*8-1:0] w_flat,
    input  wire [N*8-1:0] g_flat,
    output wire [N*8-1:0] w_yeni_flat
);

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : serit
            // Dilimler işaretli wire'lara atanıyor; böylece çıkarmada iki işlenen de
            // işaretli olur ve 9 bite işaret genişletilir. Birleştirme ({...}) yok:
            // birleştirme her zaman işaretsizdir (DEVIATIONS araç tuzağı 1).
            wire signed [7:0] w = w_flat[8*i +: 8];
            wire signed [7:0] g = g_flat[8*i +: 8];

            // w - g, -255..255 aralığında: 9 bit işaretli yeter.
            wire signed [8:0] fark = w - g;

            // ±127'ye doyurma. 127 ve -127 tamsayı sabitleri işaretli olduğu için
            // karşılaştırmalar işaretli yapılır.
            wire ust_tasma = (fark >  127);
            wire alt_tasma = (fark < -127);

            assign w_yeni_flat[8*i +: 8] = ust_tasma ? 8'h7F :      // +127
                                           alt_tasma ? 8'h81 :      // -127
                                           fark[7:0];
        end
    endgenerate

endmodule
