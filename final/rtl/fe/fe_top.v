// =============================================================================
//  fe_top.v — Fonksiyon motoru üst modülü (Adım 3.4): ReLU + ağırlık güncelleme + CLU
// -----------------------------------------------------------------------------
//  Kaynak  : Shao vd., ISVLSI 2021, Fig. 8 ve III-D (s. 258): "The CLU was integrated
//            into the function engine, which contains units for other functions, such
//            as ReLU, pooling, and weight update." Pooling yok (D39).
//  Alt bloklar:
//    relu_unit.v, wu_unit.v : Ömer (fe_rtl, Vivado'da geçti), değişmedi
//    clu_top.v (+ epu, teu, adder_tree, max_tree, div_stage_ip): Egemen, değişmedi
//  Kararlar:
//    D8 = (a) (Ömer, 03.11): CLU'nun son >>4'ü en yakına yuvarlanır (Egemen'in CLU'su).
//    D62 (Ömer, 03.11): CLU'nun "hazır" sinyali Egemen'in koduna dokunmadan bu modülde
//      sabit gecikme sayılarak üretilir. CLU'nun valid'i ilk dolumdan sonra hep 1 kaldığı
//      için kullanılmaz.
//  Yazan   : Claude, 03.11.2026
//
//  ---- 1) Akış yolu (kombinasyonel, gecikme 0): SRU'nun GMS çıkışına bağlanır ----
//    mod        : 2 bit   0 = geçir (ReLU'suz katman), 1 = ReLU ileri, 2 = ReLU geri,
//                         3 = ağırlık güncelleme (w - g8, ±127 doyma, D41)
//    veri_flat  : N*8     SRU'dan gelen grup: mod 0/1'de a, mod 2'de e, mod 3'te g8
//    maske_flat : N*8     mod 2: maskenin kaynağı olan saklı aktivasyon a (a > 0 ise e geçer)
//    w_flat     : N*8     mod 3: mevcut ağırlıklar
//    cikis_flat : N*8     mod 0: veri | 1: max(0, a) | 2: a > 0 ? e : 0 | 3: doyur(w - g8)
//    Şerit i'nin verisi [8*i +: 8] bitlerinde; hepsi işaretli int8.
//
//  ---- 2) CLU yolu (saatli): son katman aktivasyonlarından hata ----
//    clu_basla    : 1 bit   1 çevrimlik darbe; girişler bu kenarda içeri alınır.
//                           clu_mesgul = 1 iken gelen darbe yok sayılır.
//    clu_a_flat   : 10*8    son katman aktivasyonları a0..a9 (int8)
//    clu_sa       : 8       aktivasyon ölçek üssü s_a (int8)
//    clu_y_onehot : 10      doğru sınıf (one-hot)
//    clu_e_flat   : 10*8    hata e0..e9 (int8), clu_bitti'den sonra sonraki clu_basla'ya
//                           kadar sabit
//    clu_bitti    : 1 bit   1 çevrimlik darbe: clu_e_flat bu kenardan sonra geçerli
//    clu_mesgul   : 1 bit   clu_basla'dan clu_bitti'ye kadar 1
//    Gecikme: clu_basla kenarından clu_bitti'nin 1 olduğu kenara CLU_BEKLEME çevrim.
//
//  CLU_BEKLEME = N_SINIF + DIV_LATENCY + 1 = 10 + 66 + 1 = 77 (varsayılan).
//    Neden: CLU'da bölücüden önceki her şey kombinasyonel. Girişler kenar 0'da alınınca
//    bölücü her kenarda bir kanalın payını alıyor (chan_cnt sürekli dönüyor); 10 kanal
//    kenar 1..10'da örneklenir. Kanal k'nın sonucu 66 kenar sonra gi2_reg'e yazılır, yani
//    en geç kenar 76'da. Kenar 77'de çıkışlar içeri alınır ve clu_bitti verilir.
//    Ölçüldü (tb_fe_top, Icarus + davranışsal bölücü): 77 ile 1940 vektörün hepsi doğru,
//    76 ile hatalı sonuç çıkıyor; yani 77 en küçük doğru değer.
//    Bu sayı Egemen'in clu_top.v'sindeki DIV_LATENCY = 66'ya ve bölücü IP'sinin 66
//    çevrimlik gecikmesine bağlı; IP ayarı değişirse ikisi birlikte değişmeli.
// =============================================================================
`timescale 1ns/1ps

module fe_top #(
    parameter N           = 16,   // akış yolu şerit sayısı (SRU grup genişliği)
    parameter CLU_BEKLEME = 77    // clu_basla -> clu_bitti (çevrim)
) (
    input  wire              clk,
    input  wire              rst,          // eşzamanlı, aktif-yüksek; yalnızca CLU sayacını sıfırlar

    // 1) akış yolu
    input  wire [1:0]        mod,
    input  wire [N*8-1:0]    veri_flat,
    input  wire [N*8-1:0]    maske_flat,
    input  wire [N*8-1:0]    w_flat,
    output wire [N*8-1:0]    cikis_flat,

    // 2) CLU yolu
    input  wire              clu_basla,
    input  wire [10*8-1:0]   clu_a_flat,
    input  wire [7:0]        clu_sa,
    input  wire [9:0]        clu_y_onehot,
    output reg  [10*8-1:0]   clu_e_flat,
    output reg               clu_bitti,
    output wire              clu_mesgul
);

    localparam MOD_GECIR = 2'd0;
    localparam MOD_ILERI = 2'd1;
    localparam MOD_GERI  = 2'd2;
    localparam MOD_WU    = 2'd3;

    // ------------------------------------------------------------------------
    // 1) Akış yolu
    // ------------------------------------------------------------------------
    // ReLU: ileri modda a = veri, geri modda maske = saklı a, e = veri
    wire [N*8-1:0] relu_a = (mod == MOD_GERI) ? maske_flat : veri_flat;
    wire [N*8-1:0] relu_y;
    relu_unit #(.N(N)) u_relu (
        .geri   (mod == MOD_GERI),
        .a_flat (relu_a),
        .e_flat (veri_flat),
        .y_flat (relu_y)
    );

    wire [N*8-1:0] wu_y;
    wu_unit #(.N(N)) u_wu (
        .w_flat      (w_flat),
        .g_flat      (veri_flat),
        .w_yeni_flat (wu_y)
    );

    assign cikis_flat = (mod == MOD_GECIR) ? veri_flat :
                        (mod == MOD_WU)    ? wu_y      :
                                             relu_y;     // ileri ya da geri

    // ------------------------------------------------------------------------
    // 2) CLU yolu: girişleri tut, sabit gecikmeyi say, çıkışları yakala
    // ------------------------------------------------------------------------
    reg [10*8-1:0] a_r;
    reg [7:0]      sa_r;
    reg [9:0]      y_r;
    reg [7:0]      sayac;     // CLU_BEKLEME <= 255 olmalı
    reg            mesgul_r;

    assign clu_mesgul = mesgul_r;

    wire signed [7:0] e0, e1, e2, e3, e4, e5, e6, e7, e8, e9;
    wire              clu_valid_kullanilmiyor;   // D62: bkz. üst açıklama

    clu_top #(.N(10)) u_clu (
        .clk(clk),
        .a0(a_r[0*8 +: 8]), .a1(a_r[1*8 +: 8]), .a2(a_r[2*8 +: 8]), .a3(a_r[3*8 +: 8]),
        .a4(a_r[4*8 +: 8]), .a5(a_r[5*8 +: 8]), .a6(a_r[6*8 +: 8]), .a7(a_r[7*8 +: 8]),
        .a8(a_r[8*8 +: 8]), .a9(a_r[9*8 +: 8]),
        .sa(sa_r),
        .y_onehot(y_r),
        .e0(e0), .e1(e1), .e2(e2), .e3(e3), .e4(e4),
        .e5(e5), .e6(e6), .e7(e7), .e8(e8), .e9(e9),
        .valid(clu_valid_kullanilmiyor)
    );

    always @(posedge clk) begin
        if (rst) begin
            a_r        <= {10*8{1'b0}};
            sa_r       <= 8'd0;
            y_r        <= 10'd0;
            sayac      <= 8'd0;
            mesgul_r   <= 1'b0;
            clu_bitti  <= 1'b0;
            clu_e_flat <= {10*8{1'b0}};
        end else begin
            clu_bitti <= 1'b0;
            if (!mesgul_r) begin
                if (clu_basla) begin
                    a_r      <= clu_a_flat;
                    sa_r     <= clu_sa;
                    y_r      <= clu_y_onehot;
                    sayac    <= 8'd1;
                    mesgul_r <= 1'b1;
                end
            end else if (sayac == CLU_BEKLEME) begin
                clu_e_flat <= {e9, e8, e7, e6, e5, e4, e3, e2, e1, e0};
                clu_bitti  <= 1'b1;
                mesgul_r   <= 1'b0;
                sayac      <= 8'd0;
            end else begin
                sayac <= sayac + 8'd1;
            end
        end
    end

endmodule
