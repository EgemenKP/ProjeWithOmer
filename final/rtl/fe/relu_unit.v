// =============================================================================
//  relu_unit.v — ReLU birimi (fonksiyon motoru), N paralel şerit
// -----------------------------------------------------------------------------
//  Kaynak  : Shao vd., ISVLSI 2021, Fig. 8 ve III-D (s. 258): ReLU fonksiyon
//            motorunda, SRU'dan sonra. Davranış NITI'den (Shao sessiz -> NITI):
//            ti_torch.py TiReLU (268-290): ileri max(a, 0), geri act > 0 ? e : 0.
//  Golden  : fe_golden.py (relu_ileri, relu_geri); vektör: fe_vektorleri/relu.hex
//  Yazan   : Claude, 31.10.2026
//
//  Portlar (tüm veriler işaretli int8, ikiye tümleyen):
//    geri       : 1 bit        0 = ileri (FP), 1 = geri (BP)
//    a_flat     : N*8 bit      ileri: aktivasyon a | geri: maskenin kaynağı a
//                              (ReLU girişi ya da çıkışı; ikisi aynı sonucu verir)
//    e_flat     : N*8 bit      geri: gelen hata e (ileri modda kullanılmaz)
//    y_flat     : N*8 bit      ileri: max(0, a) | geri: a > 0 ise e, değilse 0
//  Şerit i'nin verisi [8*i +: 8] bitlerinde (XSIM dizi portu kabul etmediği için
//  düz veri yolu, DEVIATIONS araç tuzağı 2).
//
//  Zamanlama: saatsiz (kombinasyonel), gecikme 0. Boru hattı register'ı ve el
//  sıkışma, arayüz sözleşmesinde (Adım 4.0) fonksiyon motoru üst modülüne eklenecek.
//  Ölçek üssü s_a değişmez; bu birim üssü görmez.
// =============================================================================
`timescale 1ns/1ps

module relu_unit #(
    parameter N = 16                    // şerit sayısı (Fig. 8: PE satırı başına 1 SRU)
) (
    input  wire           geri,
    input  wire [N*8-1:0] a_flat,
    input  wire [N*8-1:0] e_flat,
    output wire [N*8-1:0] y_flat
);

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : serit
            wire [7:0] a = a_flat[8*i +: 8];
            wire [7:0] e = e_flat[8*i +: 8];

            // a > 0  <=>  işaret biti 0 ve a sıfır değil
            // (bit düzeyinde; işaretli karşılaştırma tuzağına girmemek için)
            wire pozitif = ~a[7] & (|a);

            wire [7:0] ileri_cikis = pozitif ? a : 8'd0;   // max(0, a)
            wire [7:0] geri_cikis  = pozitif ? e : 8'd0;   // a > 0 ? e : 0

            assign y_flat[8*i +: 8] = geri ? geri_cikis : ileri_cikis;
        end
    endgenerate

endmodule
