// =============================================================================
//  pe_motoru.v — Bir PE komutunu (bir PE geçişini) yürüten motor:
//                ön-getirme (Fig. 8 Input/Weight Prefetch) + PE + Psum FIFO + grup toplayıcı
// -----------------------------------------------------------------------------
//  Adım 4, Paket 2. Arayüz sözleşmesi Bölüm 3 (PE satırı) ve A6.
//  Golden: sistem_golden.py, yorumla() içindeki OP_PE dalı ve pe_golden.py'nin geçiş
//  fonksiyonları. Egemen'in PE devreleri golden'ın çevrim modeliyle çevrim çevrim aynı:
//  t. çevrimde verilen girişin çıkışı, t. saat kenarından sonraki çevrimde okunur (D16'daki
//  "kayma 2/1", Egemen'in testbench'lerinin kendi indekslemesi; ölçüldü, 03.11).
//  Yazan: Claude, 03.11.2026
//  final/ (03.11.2026, D69): PE artik rtl/pe/pe_birlesik.v (Shao Fig. 2, 9 MAC); eski
//  pe_sarmalayici (5 devre, 45 MAC) yalnizca tb_pe_blok ve tb_pe_birlesik icin referans.
//
//  Bir geçişin aşamaları:
//    1) AĞIRLIK : AGR[l][o][c]'den 9 bayt; BP s1'de 180° döndürülür, BP s2'de satır başına
//                 [w2, w0, w1] (Fig. 4(b)); WG'de ağırlık kullanılmaz (0).
//    2) SATIR   : 3 kaynak satır, dolgu yerleştirilerek satır tamponlarına alınır
//                 (+ WG'de hata satırı). Kaynaklar:
//                   FP/WG : AKT[l-1][b][c], dolgulu satır s·z + i (i = 0..2), sütun kayması p
//                   BP s1 : HATA[l][b][o], (2 - p) dolgulu satır z + i, sütun kayması 2 - p
//                   BP s2 : PE satırı 0 ve 1'e E[z], 2'ye E[z-1] (PE-a6); başta ve sonda 0
//                   WG    : hata satırı HATA[l][b][o][z], sonu 0 ile dolu
//    3) PSUM    : ilk = 0 ise (FP/BP) kısmi toplamlar Psum FIFO'dan alınır; ilk = 1 ise 0
//                 (WG'de ilk = 1 ise PE'nin akümülatörleri 1 çevrim rst ile sıfırlanır)
//    4) AKIŞ    : t = 0..T-1 boyunca akışlar PE'ye verilir; geçerli çıkışlar (s1/s2'de
//                 t >= 2, BP s2'de t >= 1) bir sonraki çevrimde çıkış tamponuna alınır
//    5) SAKLA   : son = 0 ise çıkışlar Psum FIFO'ya yazılır; son = 1 ise grup kurulur
//                 (BP s2'de şeritler dX koordinatlarına yerleştirilir, dolgu kırpılır;
//                 WG'de 9 akümülatör) ve grup_gecerli verilir
//  Psum FIFO tek bir int32 FIFO (A6). BP s2'de 4 şerit FIFO'da şerit şerit art arda durur
//  (şerit 0'ın n değeri, sonra şerit 1, 2, 3); okuma da aynı sırayla.
//
//  Portlar (boyutlar 8 bit işaretsiz, veriler işaretli):
//    clk, rst            : saat; eşzamanlı aktif-yüksek reset
//    fifo_temizle        : Psum FIFO'yu boşaltır (İŞ_BAŞLA'da, 1 çevrim)
//    basla               : 1 çevrimlik darbe; aşağıdaki alanlar bitti'ye kadar sabit kalmalı
//    faz [1:0]           : 0 FP, 1 BP, 2 WG
//    kb, kx, ky, kz      : komut alanları b, x, y, z (FP: o c r, BP: c o p, WG: o c r)
//    ilk, son            : komutun a1, a2 alanları
//    cin, cout, h, w     : katmanın giriş/çıkış kanalı ve giriş boyutu
//    s, p                : stride (1 ya da 2) ve dolgu
//    ho, wo              : çıkış boyutu
//    taban_akt [AW-1:0]  : AKT[l-1]'in taban adresi (katmanın girişi)
//    taban_hata[AW-1:0]  : HATA[l]'nin taban adresi
//    taban_agr [AW-1:0]  : AGR[l]'nin taban adresi
//    oku_adr, oku_veri   : belleğin A okuma portu (yalnızca mesgul = 1 iken kullanılır)
//    mesgul              : basla'dan bitti'ye kadar 1
//    bitti               : 1 çevrimlik darbe
//    grup_gecerli        : bitti ile birlikte, son = 1 ise 1
//    grup_flat [16*32]   : grup, k. eleman [32k +: 32]; grup_n eleman sayısı
//    psum_tasma, psum_eksik : Psum FIFO hata bayrakları (testte 0 kalmalı)
//  Sınırlar (testbench kontrol eder): w, wo <= 16; w + 2p <= 30; grup <= 16 eleman;
//  bir geçişin kısmi toplamı <= 64 kelime.
// =============================================================================
`timescale 1ns/1ps

module pe_motoru #(
    parameter AW = 13
) (
    input  wire           clk,
    input  wire           rst,
    input  wire           fifo_temizle,
    input  wire           basla,
    input  wire [1:0]     faz,
    input  wire [7:0]     kb, kx, ky, kz,
    input  wire           ilk, son,
    input  wire [7:0]     cin, cout, h, w, s, p, ho, wo,
    input  wire [AW-1:0]  taban_akt, taban_hata, taban_agr,
    output wire [AW-1:0]  oku_adr,
    input  wire [127:0]   oku_veri,
    output wire           mesgul,
    output reg            bitti,
    output reg            grup_gecerli,
    output reg  [511:0]   grup_flat,
    output reg  [4:0]     grup_n,
    output wire           psum_tasma,
    output wire           psum_eksik
);

    localparam RB = 32;          // satır tamponu genişliği (bayt)
    localparam PS = 64;          // kısmi toplam / çıkış tamponu (kelime)

    localparam FAZ_FP = 2'd0, FAZ_BP = 2'd1, FAZ_WG = 2'd2;
    localparam M_FP1 = 3'd0, M_FP2 = 3'd1, M_BP1 = 3'd2, M_BP2 = 3'd3, M_WG1 = 3'd4, M_WG2 = 3'd5, M_YOK = 3'd7;

    localparam [3:0] D_BOSTA = 4'd0, D_AGIRLIK = 4'd1, D_SATIR = 4'd2, D_ESATIR = 4'd3,
                     D_PSUM = 4'd4, D_WGRST = 4'd5, D_AKIS = 4'd6, D_SAKLA = 4'd7,
                     D_YAZ = 4'd8, D_BITTI = 4'd9;

    reg [3:0] durum;
    assign mesgul = (durum != D_BOSTA);

    // ------------------------------------------------------------------
    // Mod ve boyutlar
    // ------------------------------------------------------------------
    wire s2 = (s == 8'd2);
    wire [2:0] mod_k = (faz == FAZ_FP) ? (s2 ? M_FP2 : M_FP1) :
                       (faz == FAZ_BP) ? (s2 ? M_BP2 : M_BP1) :
                                         (s2 ? M_WG2 : M_WG1);
    reg  [2:0] pe_mod;                                    // PE'ye giden mod (boşta M_YOK)

    wire [8:0] wp_fp  = {1'b0, w} + {1'b0, p, 1'b0};            // w + 2p
    wire [8:0] wp_bp1 = {1'b0, wo} + 9'd4 - {1'b0, p, 1'b0};    // wo + 2(2 - p)
    reg  [8:0] T;                                          // akış uzunluğu
    reg  [8:0] K;                                          // şerit başına çıkış sayısı
    reg  [1:0] v0;                                         // ilk geçerli çıkışın çevrimi
    always @* begin
        case (mod_k)
            M_FP1:   begin T = wp_fp;                           K = {1'b0, wo};          v0 = 2'd2; end
            M_FP2:   begin T = ((wp_fp + 9'd1) >> 1) + 9'd1;    K = {1'b0, wo};          v0 = 2'd2; end
            M_BP1:   begin T = wp_bp1;                          K = {1'b0, w};           v0 = 2'd2; end
            M_BP2:   begin T = {1'b0, wo} + 9'd2;               K = {1'b0, wo} + 9'd1;   v0 = 2'd1; end
            M_WG1:   begin T = wp_fp;                           K = 9'd0;                v0 = 2'd2; end
            default: begin T = ((wp_fp + 9'd1) >> 1) + 9'd1;    K = 9'd0;                v0 = 2'd2; end
        endcase
    end
    wire [8:0] NW = (mod_k == M_BP2) ? {K[6:0], 2'b00} : K;    // FIFO kelime sayısı

    // ------------------------------------------------------------------
    // Adresler
    // ------------------------------------------------------------------
    wire [7:0] k_o = (faz == FAZ_BP) ? ky : kx;            // çıkış kanalı
    wire [7:0] k_c = (faz == FAZ_BP) ? kx : ky;            // giriş kanalı
    // AKT[l-1][b][c] ve HATA[l][b][o]'nun ilk satırı
    wire [31:0] akt_harita  = ((kb * cin + k_c) * h) * w;
    wire [31:0] hata_harita = ((kb * cout + k_o) * ho) * wo;
    wire [31:0] agr_ofs     = (k_o * cin + k_c) * 9;

    // Satır seçimi: PE satırı i için kaynak satır (işaretli) ve sütun kayması
    reg  [1:0]  sat_i;                                     // yüklenen PE satırı
    reg  signed [10:0] kaynak_satir;
    reg  [4:0]  kayma;
    reg  [7:0]  uzunluk;                                   // kaynak satırın bayt sayısı
    reg  [7:0]  kaynak_yukseklik;
    reg         kaynak_hata;                               // 1: HATA[l], 0: AKT[l-1]
    always @* begin
        kaynak_hata = 1'b0;
        kaynak_yukseklik = h;
        uzunluk = w;
        kayma = p[4:0];
        kaynak_satir = $signed({3'b000, s2 ? {kz[6:0], 1'b0} : kz}) + $signed({9'd0, sat_i}) - $signed({3'b000, p});
        case (mod_k)
            M_BP1: begin
                kaynak_hata = 1'b1; kaynak_yukseklik = ho; uzunluk = wo;
                kayma = 5'd2 - p[4:0];
                kaynak_satir = $signed({3'b000, kz}) + $signed({9'd0, sat_i}) - $signed(11'd2) + $signed({3'b000, p});
            end
            M_BP2: begin
                kaynak_hata = 1'b1; kaynak_yukseklik = ho; uzunluk = wo;
                kayma = 5'd1;
                kaynak_satir = (sat_i == 2'd2) ? $signed({3'b000, kz}) - $signed(11'd1) : $signed({3'b000, kz});
            end
            default: ;
        endcase
    end
    wire satir_gecerli = (kaynak_satir >= 0) && (kaynak_satir < $signed({3'b000, kaynak_yukseklik}));
    wire [31:0] satir_adr32 = kaynak_hata ?
        ({{AW{1'b0}}, taban_hata} + hata_harita + kaynak_satir[9:0] * wo) :
        ({{AW{1'b0}}, taban_akt}  + akt_harita  + kaynak_satir[9:0] * w);
    wire [31:0] esatir_adr32 = {{AW{1'b0}}, taban_hata} + hata_harita + kz * wo;
    wire [31:0] agr_adr32    = {{AW{1'b0}}, taban_agr} + agr_ofs;

    // ------------------------------------------------------------------
    // Tamponlar
    // ------------------------------------------------------------------
    reg [7:0]  rb [0:3*RB-1];                              // satır tamponları: rb[i*RB + j]
    reg [7:0]  eb [0:RB-1];                                // WG hata satırı
    reg [31:0] psb [0:PS-1];                               // kısmi toplam girişleri
    reg [31:0] ob  [0:PS-1];                               // çıkışlar
    reg [71:0] w_r;                                        // PE'ye yüklenen ağırlıklar

    reg [8:0] t;                                           // AKIŞ'ta çevrim sayacı
    reg [8:0] idx;                                         // PSUM / YAZ sayacı
    integer   j;

    // Ağırlık dönüşümü (saatsiz, okunan 9 bayttan)
    reg [71:0] w_yeni;
    always @* begin
        for (j = 0; j < 9; j = j + 1) w_yeni[8*j +: 8] = oku_veri[8*j +: 8];      // FP, WG
        case (mod_k)
            M_BP1: for (j = 0; j < 9; j = j + 1) w_yeni[8*j +: 8] = oku_veri[8*(8-j) +: 8];
            M_BP2: for (j = 0; j < 3; j = j + 1) begin
                       w_yeni[8*(3*j+0) +: 8] = oku_veri[8*(3*j+2) +: 8];
                       w_yeni[8*(3*j+1) +: 8] = oku_veri[8*(3*j+0) +: 8];
                       w_yeni[8*(3*j+2) +: 8] = oku_veri[8*(3*j+1) +: 8];
                   end
            M_WG1, M_WG2: w_yeni = 72'd0;
            default: ;
        endcase
    end

    // ------------------------------------------------------------------
    // Akışlar (saatsiz): t. çevrimde PE'ye verilenler
    // ------------------------------------------------------------------
    wire akis_gecerli = (durum == D_AKIS) && (t < T);
    reg  [23:0]  pe_a1, pe_a2, pe_a3;
    reg  [127:0] pe_ps;
    reg  [9:0]   i_t, i_2t, i_2t1;
    integer r;
    always @* begin
        pe_a1 = 24'd0; pe_a2 = 24'd0; pe_a3 = 24'd0; pe_ps = 128'd0;
        r     = 0;                                         // döngü değişkeni her yolda atanır (latch yok)
        i_t   = {1'b0, t};
        i_2t  = {t, 1'b0};
        i_2t1 = {t, 1'b0} - 10'd1;
        if (akis_gecerli) begin
            for (r = 0; r < 3; r = r + 1) begin
                case (mod_k)
                    M_FP1, M_BP1, M_BP2: begin
                        if (i_t < RB) pe_a1[8*r +: 8] = rb[r*RB + i_t];
                    end
                    M_FP2, M_WG2: begin
                        if (i_2t < RB) pe_a1[8*r +: 8] = rb[r*RB + i_2t];
                        if (t != 0 && i_2t1 < RB) pe_a2[8*r +: 8] = rb[r*RB + i_2t1];
                        if (mod_k == M_WG2 && i_t < RB) pe_a3[8*r +: 8] = eb[i_t];
                    end
                    M_WG1: begin
                        if (i_t < RB) pe_a1[8*r +: 8] = rb[r*RB + i_t];
                        if (i_t < RB) pe_a2[8*r +: 8] = eb[i_t];
                    end
                    default: ;
                endcase
            end
            if (mod_k == M_BP2) begin
                if (t < K) begin
                    pe_ps[0  +: 32] = psb[0*K + t];                 // psA0
                    pe_ps[64 +: 32] = psb[2*K + t];                 // psA1
                end
                if (t >= 1 && t <= K) begin
                    pe_ps[32 +: 32] = psb[1*K + t - 1];             // psB0
                    pe_ps[96 +: 32] = psb[3*K + t - 1];             // psB1
                end
            end else if (mod_k != M_WG1 && mod_k != M_WG2) begin
                if (t + 9'd2 < T) pe_ps[0 +: 32] = psb[t];          // ps(t) = psum[t], t < T - 2
            end
        end
    end

    wire pe_rst = (durum == D_WGRST);                      // WG akümülatörlerini sıfırla (saatsiz)
    wire [127:0] pe_cikis;
    wire [287:0] pe_g;
    pe_birlesik u_pe (                                     // D69: tek PE, 9 MAC (final/)
        .clk(clk), .rst(pe_rst), .mod(pe_mod), .w_flat(w_r),
        .akis1(pe_a1), .akis2(pe_a2), .akis3(pe_a3), .ps_flat(pe_ps),
        .cikis_flat(pe_cikis), .g_flat(pe_g)
    );

    // Çıkış yakalama: AKIŞ'ın t. çevriminde, (t-1). figür çevriminin çıkışı geçerli
    // (WG'de çıkış yok: sonuç PE'nin akümülatörlerinde)
    wire       wg_mod   = (mod_k == M_WG1) || (mod_k == M_WG2);
    wire [8:0] fig      = t - 9'd1;
    wire       cikis_yakala = (durum == D_AKIS) && !wg_mod && (t >= 9'd1) && (fig >= {7'd0, v0}) && (fig < T);
    wire [8:0] cikis_j  = fig - {7'd0, v0};                // şerit içindeki çıkış sırası

    // ------------------------------------------------------------------
    // Psum FIFO
    // ------------------------------------------------------------------
    // FIFO kontrolleri saatsiz: PSUM'da okunan kelime aynı kenarda çıkarılır, YAZ'da yazılır
    wire        psum_aktif = (mod_k != M_WG1) && (mod_k != M_WG2) && !ilk;
    wire        f_oku  = (durum == D_PSUM) && psum_aktif && (idx < NW);
    wire        f_yaz  = (durum == D_YAZ) && (idx < NW);
    wire [31:0] f_veri = ob[idx];
    wire [31:0] f_bas;
    wire        f_bos, f_dolu;
    wire [8:0]  f_doluluk;
    psum_fifo #(.DERINLIK(256), .AW(8)) u_psum (
        .clk(clk), .rst(rst | fifo_temizle), .yaz(f_yaz), .yaz_veri(f_veri), .oku(f_oku),
        .bas_veri(f_bas), .bos(f_bos), .dolu(f_dolu), .doluluk(f_doluluk),
        .tasma(psum_tasma), .eksik(psum_eksik)
    );

    // ------------------------------------------------------------------
    // Grup (saatsiz): son = 1 geçişinde SAKLA'da kurulur
    // ------------------------------------------------------------------
    wire signed [10:0] R0 = $signed({2'b00, kz, 1'b0}) - $signed({3'b000, p});   // 2z - p
    wire signed [10:0] R1 = R0 + 11'sd1;
    wire g0 = (R0 >= 0) && (R0 < $signed({3'b000, h}));
    wire g1 = (R1 >= 0) && (R1 < $signed({3'b000, h}));
    reg  [511:0] grup_c;
    reg  [4:0]   grup_n_c;
    reg  [8:0]   gC, gC0, gq;
    reg  [1:0]   gs;
    reg          gsat;
    integer      gk;
    always @* begin
        grup_c = 512'd0;
        grup_n_c = 5'd0;
        gC = 9'd0; gC0 = 9'd0; gq = 9'd0; gs = 2'd0; gsat = 1'b0;
        gk = 0;                                            // döngü değişkeni her yolda atanır (latch yok)
        case (mod_k)
            M_WG1, M_WG2: begin
                grup_c[0 +: 288] = pe_g;
                grup_n_c = 5'd9;
            end
            M_BP2: begin
                grup_n_c = (g0 + g1) * w[4:0];
                for (gk = 0; gk < 16; gk = gk + 1) begin
                    if (gk < grup_n_c) begin
                        // gk. eleman: önce geçerli R0 satırı (w eleman), sonra R1
                        if (g0 && gk < w) begin gsat = 1'b0; gC = gk; end
                        else if (g0)       begin gsat = 1'b1; gC = gk - w; end
                        else               begin gsat = 1'b1; gC = gk; end
                        gC0 = gC + p;
                        gs  = {gsat, gC0[0]};                       // şerit: (R0 ? 0 : 2) + C0 % 2
                        gq  = gC0 >> 1;
                        grup_c[32*gk +: 32] = ob[gs * K + gq];
                    end
                end
            end
            default: begin                                           // FP s1/s2, BP s1
                grup_n_c = K[4:0];
                for (gk = 0; gk < 16; gk = gk + 1)
                    if (gk < K) grup_c[32*gk +: 32] = ob[gk];
            end
        endcase
    end

    // ------------------------------------------------------------------
    // Durum makinesi
    // ------------------------------------------------------------------
    integer q, qk;
    always @(posedge clk) begin
        if (rst) begin
            durum <= D_BOSTA;
            bitti <= 1'b0;
            grup_gecerli <= 1'b0;
            grup_flat <= 512'd0;
            grup_n <= 5'd0;
            pe_mod <= M_YOK;
            t <= 9'd0; idx <= 9'd0; sat_i <= 2'd0;
            w_r <= 72'd0;
        end else begin
            bitti <= 1'b0;
            grup_gecerli <= 1'b0;
            case (durum)
                D_BOSTA: begin
                    if (basla) begin
                        pe_mod  <= mod_k;
                        for (q = 0; q < PS; q = q + 1) psb[q] <= 32'd0;
                        durum   <= D_AGIRLIK;
                    end
                end
                D_AGIRLIK: begin                                 // oku_veri = 9 ağırlık
                    w_r   <= w_yeni;
                    sat_i <= 2'd0;
                    durum <= D_SATIR;
                end
                D_SATIR: begin                                   // PE satırı sat_i'nin kaynağı (oku_adr = satır adresi)
                    for (q = 0; q < RB; q = q + 1) begin
                        qk = q - kayma;
                        rb[sat_i*RB + q] <= (satir_gecerli && qk >= 0 && qk < uzunluk && qk < 16)
                                            ? oku_veri[8*qk +: 8] : 8'd0;
                    end
                    if (sat_i == 2'd2) begin
                        durum <= (mod_k == M_WG1 || mod_k == M_WG2) ? D_ESATIR : D_PSUM;
                        idx   <= 9'd0;
                    end
                    sat_i <= sat_i + 2'd1;
                end
                D_ESATIR: begin                                  // WG hata satırı
                    for (q = 0; q < RB; q = q + 1)
                        eb[q] <= (q < wo && q < 16) ? oku_veri[8*(q & 15) +: 8] : 8'd0;   // q & 15: dizin hep sınır içinde
                    durum <= D_PSUM;
                end
                D_PSUM: begin
                    if (mod_k == M_WG1 || mod_k == M_WG2) begin
                        durum <= ilk ? D_WGRST : D_AKIS;
                        t     <= 9'd0;
                    end else if (ilk || idx >= NW) begin
                        durum <= D_AKIS;
                        t     <= 9'd0;
                    end else begin
                        psb[idx] <= f_bas;                       // f_oku aynı çevrimde 1 (saatsiz)
                        idx      <= idx + 9'd1;
                        if (idx + 9'd1 >= NW) begin durum <= D_AKIS; t <= 9'd0; end
                    end
                end
                D_WGRST: begin                                   // pe_rst = 1 (saatsiz): akümülatörler sıfırlanır
                    durum  <= D_AKIS;
                    t      <= 9'd0;
                end
                D_AKIS: begin
                    if (cikis_yakala) begin
                        if (mod_k == M_BP2) begin
                            ob[0*K + cikis_j] <= pe_cikis[0  +: 32];
                            ob[1*K + cikis_j] <= pe_cikis[32 +: 32];
                            ob[2*K + cikis_j] <= pe_cikis[64 +: 32];
                            ob[3*K + cikis_j] <= pe_cikis[96 +: 32];
                        end else begin
                            ob[cikis_j] <= pe_cikis[0 +: 32];
                        end
                    end
                    if (t == T) durum <= D_SAKLA;
                    t <= t + 9'd1;
                end
                D_SAKLA: begin
                    if (son) begin
                        grup_flat    <= grup_c;
                        grup_n       <= grup_n_c;
                        grup_gecerli <= 1'b1;
                        bitti        <= 1'b1;
                        pe_mod       <= M_YOK;
                        durum        <= D_BOSTA;
                    end else if (mod_k == M_WG1 || mod_k == M_WG2) begin
                        bitti  <= 1'b1;                          // akümülatörler PE'de kalır
                        pe_mod <= M_YOK;
                        durum  <= D_BOSTA;
                    end else begin
                        idx   <= 9'd0;
                        durum <= D_YAZ;
                    end
                end
                D_YAZ: begin                                     // f_yaz = 1, f_veri = ob[idx] (saatsiz)
                    idx    <= idx + 9'd1;
                    if (idx + 9'd1 >= NW) durum <= D_BITTI;
                end
                D_BITTI: begin
                    bitti  <= 1'b1;
                    pe_mod <= M_YOK;
                    durum  <= D_BOSTA;
                end
                default: durum <= D_BOSTA;
            endcase
        end
    end

    // Okuma adresi (saatsiz): AĞIRLIK'ta ağırlık, SATIR'da sat_i'nin kaynak satırı, ESATIR'da hata satırı.
    // Bellek okuması saatsiz olduğu için veri aynı çevrimde gelir ve kenarda tampona yazılır.
    assign oku_adr = (durum == D_SATIR)  ? satir_adr32[AW-1:0] :
                     (durum == D_ESATIR) ? esatir_adr32[AW-1:0] :
                                           agr_adr32[AW-1:0];

endmodule
