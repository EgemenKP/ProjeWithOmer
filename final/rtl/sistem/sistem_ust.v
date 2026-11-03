// =============================================================================
//  sistem_ust.v — Adım 4 üst modülü: master controller (FSM) + veri yolu (Paket 3)
// -----------------------------------------------------------------------------
//  ARAYUZ_SOZLESMESI.md Bölüm 1:
//    - FSM değişmedi (A1). maks_reg çıkarıldı; FSM'in maks_G girişi SRU'nun G_out'u.
//    - FSM'in komutları (kom, kom_gecerli) komut yürütücüsüne gider; kom_bitti'yi yalnızca
//      yürütücü verir (A2).
//  Bir eğitim adımı: yapılandırma ve bellek hazırken basla'ya 1 çevrimlik darbe; adım
//  bitince bitti = 1 (yeni basla'ya kadar).
//  Yazan: Claude, 03.11.2026
//
//  Parametreler:
//    AW    : bellek adres genişliği (bayt adresi)
//    BOYUT : bellek boyutu (bayt)
//    LMAX  : en çok katman
//  Komut alanı genişliği 16 bit sabit (FSM'in AW'si; yürütücünün kom girişi 10 × 16 bit).
//
//  Portlar:
//    clk, rst                       : saat; eşzamanlı, aktif-yüksek reset
//    basla                          : 1 çevrimlik darbe, eğitim adımını başlatır
//    cfg_L [3:0], cfg_batch [7:0]   : katman sayısı, örnek sayısı
//    cfg_m_u [3:0]                  : gradyan hedef genişliği (NITI m_u)
//    cfg_s_a0 [7:0]                 : giriş aktivasyonunun ölçek üssü (işaretli)
//    cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p, cfg_relu, cfg_sw [LMAX*8-1:0]
//                                   : katman tablosu; katman l, [8*(l-1) +: 8] bitlerinde
//    cfg_taban_akt, cfg_taban_hata, cfg_taban_agr [(LMAX+1)*AW-1:0]
//                                   : AKT[l], HATA[l], AGR[l] taban adresleri, [AW*l +: AW]
//    cfg_taban_etiket [AW-1:0]      : ETIKET taban adresi
//    mesgul, bitti                  : FSM'in durum çıkışları
//    hata [5:0]                     : yürütücünün yapışkan hata bayrakları (komut_yurutucu.v)
//  Bellek sistem_veriyolu içindeki bellek.v; testbench u_vy.u_bellek.mem'e hiyerarşik erişir.
// =============================================================================
`timescale 1ns/1ps

module sistem_ust #(
    parameter AW    = 13,
    parameter BOYUT = 8192,
    parameter LMAX  = 8
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    basla,
    input  wire [3:0]              cfg_L,
    input  wire [7:0]              cfg_batch,
    input  wire [3:0]              cfg_m_u,
    input  wire [7:0]              cfg_s_a0,
    input  wire [LMAX*8-1:0]       cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p, cfg_relu, cfg_sw,
    input  wire [(LMAX+1)*AW-1:0]  cfg_taban_akt, cfg_taban_hata, cfg_taban_agr,
    input  wire [AW-1:0]           cfg_taban_etiket,
    output wire                    mesgul,
    output wire                    bitti,
    output wire [5:0]              hata
);

    localparam KW = 16;                 // komut alanı genişliği

    wire [10*KW-1:0] kom;
    wire             kom_gecerli;
    wire             kom_bitti;
    wire [5:0]       maks_G;

    master_controller #(.AW(KW), .LMAX(LMAX), .CW(8), .HEDEF_AKT(7)) u_fsm (
        .clk(clk), .rst(rst), .basla(basla),
        .cfg_L(cfg_L), .cfg_batch(cfg_batch), .cfg_m_u(cfg_m_u), .cfg_s_a0(cfg_s_a0),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_s(cfg_s), .cfg_p(cfg_p), .cfg_relu(cfg_relu), .cfg_sw(cfg_sw),
        .maks_G(maks_G), .kom_bitti(kom_bitti),
        .kom_gecerli(kom_gecerli), .kom(kom), .mesgul(mesgul), .bitti(bitti)
    );

    sistem_veriyolu #(.AW(AW), .BOYUT(BOYUT), .LMAX(LMAX)) u_vy (
        .clk(clk), .rst(rst),
        .kom(kom), .kom_gecerli(kom_gecerli), .kom_bitti(kom_bitti), .maks_G(maks_G),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_s(cfg_s), .cfg_p(cfg_p),
        .cfg_taban_akt(cfg_taban_akt), .cfg_taban_hata(cfg_taban_hata), .cfg_taban_agr(cfg_taban_agr),
        .cfg_taban_etiket(cfg_taban_etiket), .hata(hata)
    );

endmodule
