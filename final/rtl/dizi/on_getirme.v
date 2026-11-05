// =============================================================================
//  on_getirme.v — Giriş ve ağırlık ön-getirme modülü (Fig. 8 Input/Weight Prefetch Module, D84)
// -----------------------------------------------------------------------------
//  Shao III-A: ön-getirme "arranges the input data in an appropriate manner according to the
//  computation patterns"; FP s2'de çift/tek ayırma (Fig. 3b), BP s2'de sıfır ekleme (Fig. 4b), WG s2'de
//  çift/tek (Fig. 5b). III-B / Fig. 6: GMS tampondan PE'ye giderken (D78): her okunan kelime kendi l'si ve
//  bölgenin G'siyle `gms_group16`'dan (Egemen'in SRU'sunun GMS alt modülü) geçer.
//
//  Bir DİZİ komutu (D85: faz, l, b, k0, k1, z) için:
//    1) AGR: sütun hattının ağırlıkları. FP: 16 bank paralel, 1 okuma (bank j = o0 + j, D82).
//            BP: hepsi bank (o mod 16)'da, 16 ardışık okuma; s1'de 180° döndürülür, s2'de Fig. 4(b)
//            yüklemesi ([w2, w0, w1] her satırda). WG'de ağırlık yok.
//    2) SATIR: FP/BP'de okunan kanalın bütün haritası (H <= HMAX, W <= WMAX) satır register'larına;
//            banklar paralel (bank k: satır 16·tur + k). WG'de giriş kanalı karosunun 3 satırı (her kelime
//            16 PE satırının 16 kanalını birden verir) ve hata satırı (16 sütunun 16 kanalı).
//    3) AKIŞ: T çevrim; PE satırı i'nin akis1/2/3'ü ve sütun j'nin hattı (FP/BP: ağırlık; WG: alt 24 bit
//            hata, D73) satır register'larından, dolgu / çift-tek / sıfır ekleme burada yapılarak.
//            Akışın t. çevriminde golden'ın t. çevrim girişi (D66). Etkin olmayan satır/sütun 0.
//  Golden: dizi_sistem_golden.py (onget_izi.txt). Sınır: W <= WMAX = 32 (D97; önceden H, W <= 16, D84/D90).
//
//  Yapılandırma (katman li = l − 1): cfg_cin, cfg_cout [16*li +: 16] (D103: 512 kanal), cfg_h, cfg_w, cfg_s,
//  cfg_p [8*li +: 8]. Komutun k1'i (FP/BP: kanal, WG: o-karo) 16 bit (D103), b, k0, z 8 bit.
//  Bölge tabanları ve G'ler (indis l = 0..LMAX): taban_akt/taban_hata/taban_agr [AW*l +: AW],
//  G_akt/G_hata [6*l +: 6]. Adres (D81): taban + ((b·n_karo + karo)·⌈H/16⌉ + satır/16)·W + x.
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b-3b)
// =============================================================================
`timescale 1ns/1ps

module on_getirme #(
    parameter NB   = 16,
    parameter AW   = 13,           // D103 (önceden 9)
    parameter LMAX = 15,           // D103 (önceden 4)
    parameter HMAX = 32,           // D97: yalnızca belge (pencere H'den bağımsız)
    parameter WMAX = 32            // D97 (önceden 16)
) (
    input  wire                     clk,
    input  wire                     rst,
    // komut
    input  wire                     basla,
    input  wire [1:0]               faz,          // 0 FP, 1 BP, 2 WG
    input  wire [3:0]               l,
    input  wire [7:0]               b, k0, z,
    input  wire [15:0]              k1,
    // yapılandırma
    input  wire [LMAX*16-1:0]       cfg_cin, cfg_cout,
    input  wire [LMAX*8-1:0]        cfg_h, cfg_w, cfg_s, cfg_p,
    input  wire [(LMAX+1)*AW-1:0]   taban_akt, taban_hata, taban_agr,
    input  wire [(LMAX+1)*6-1:0]    G_akt, G_hata,
    // tamponlar (eşzamanlı okuma: veri bir sonraki kenarda)
    output reg  [NB*AW-1:0]         v_oku_adr,
    input  wire [NB*134-1:0]        v_oku_veri,
    output reg  [NB*AW-1:0]         a_oku_adr,
    input  wire [NB*72-1:0]         a_oku_veri,
    // D100: Fig. 6'nın tek GMS'i (bank başına bir). Tamponun okuma portunu bir önceki çevrimde başka bir birim
    // kullandıysa (motorun ReLU-geri maskesi, yürütücünün CLU / WU okuması) bu çevrimin verisi onun: G = dis_G.
    input  wire                     dis_G_sec,
    input  wire [5:0]               dis_G,
    output wire [NB*128-1:0]        gms_flat,
    // diziye
    output reg  [2:0]               mod,
    output reg  [NB*24-1:0]         satir_akis1_flat, satir_akis2_flat, satir_akis3_flat,
    output reg  [NB*72-1:0]         sutun_w_flat,
    output wire                     akis,          // 1: bu çevrim akışın t. çevrimi
    output reg  [7:0]               t,
    output reg  [7:0]               T,
    output reg                      bitti,         // akış bitince 1 çevrim
    output wire                     mesgul
);

    localparam D_BOS = 3'd0, D_AGR = 3'd1, D_SATIR = 3'd2, D_HATA = 3'd3, D_AKIS = 3'd4, D_BEKLE = 3'd5;
    // D_BEKLE: son okumanın yakalanması için 1 çevrim (yakalama sırasında bölge ve G değişmesin)
    reg [2:0] durum;
    assign akis   = (durum == D_AKIS);
    assign mesgul = (durum != D_BOS);

    // ---- komut ve katman boyutları ----
    // D95 (Adım 5c-a): katmanın boyutları, etkin satır/sütun sayıları ve akış boyu basla'da komut girişlerinden
    // bir kez hesaplanıp register'da tutulur; s ∈ {1, 2} olduğundan "/ s" bir kaydırma (önceden her çevrim
    // 32 bit değişkene bölme). Değerler öncekiyle aynı (geçerli komutlar için).
    reg [1:0]  fz;
    reg [3:0]  ll;
    reg [7:0]  bb, kk0, zz;
    reg [15:0] kk1;
    wire [3:0]  g_li   = l - 4'd1;
    wire [15:0] g_cin  = cfg_cin [16*g_li +: 16];
    wire [15:0] g_cout = cfg_cout[16*g_li +: 16];
    wire [7:0]  g_h    = cfg_h   [8*g_li +: 8];
    wire [7:0]  g_w    = cfg_w   [8*g_li +: 8];
    wire        g_s2   = (cfg_s  [8*g_li +: 8] == 8'd2);
    wire [7:0]  g_p    = cfg_p   [8*g_li +: 8];
    wire [11:0] g_h2p  = {4'd0, g_h} + {3'd0, g_p, 1'b0};
    wire [11:0] g_w2p  = {4'd0, g_w} + {3'd0, g_p, 1'b0};
    wire [11:0] g_ho   = g_s2 ? (((g_h2p - 12'd3) >> 1) + 12'd1) : (g_h2p - 12'd2);
    wire [11:0] g_wo   = g_s2 ? (((g_w2p - 12'd3) >> 1) + 12'd1) : (g_w2p - 12'd2);
    wire [11:0] g_np   = ({4'd0, g_h} + {4'd0, g_p} + 12'd1) >> 1;
    wire [11:0] g_Tfw  = g_s2 ? (((g_w2p + 12'd1) >> 1) + 12'd1) : g_w2p;          // FP / WG
    wire [11:0] g_Tb   = g_s2 ? (g_wo + 12'd2) : (g_wo + 12'd4 - {3'd0, g_p, 1'b0});  // BP
    reg  [11:0] g_nr, g_nc, g_T;
    always @* begin
        case (faz)
            2'd0:    begin g_nr = g_ho - {z, 4'd0};                  g_nc = g_cout - {k0, 4'd0}; g_T = g_Tfw; end
            2'd1:    begin g_nr = (g_s2 ? g_np : g_h) - {z, 4'd0};   g_nc = g_cin  - {k0, 4'd0}; g_T = g_Tb;  end
            default: begin g_nr = g_cin - {k0, 4'd0};                g_nc = g_cout - {k1, 4'd0}; g_T = g_Tfw; end
        endcase
    end
    reg [15:0] r_cin, r_cout;
    reg [7:0] r_h, r_w, r_p, r_ho, r_wo, r_T;
    reg       r_s2;
    reg [4:0] r_nr, r_nc;
    always @(posedge clk) if (durum == D_BOS && basla) begin
        r_cin <= g_cin; r_cout <= g_cout; r_h <= g_h; r_w <= g_w; r_p <= g_p; r_s2 <= g_s2;
        r_ho <= g_ho[7:0]; r_wo <= g_wo[7:0]; r_T <= g_T[7:0];
        r_nr <= (g_nr > 12'd16) ? 5'd16 : g_nr[4:0];
        r_nc <= (g_nc > 12'd16) ? 5'd16 : g_nc[4:0];
    end
    integer cin, cout, h, w, s, p, ho, wo, nr, nc, T_hesap;
    always @* begin
        cin = r_cin; cout = r_cout; h = r_h; w = r_w; p = r_p; ho = r_ho; wo = r_wo;
        s = r_s2 ? 2 : 1;
        nr = r_nr; nc = r_nc; T_hesap = r_T;
    end

    // ---- Okunan bölge: FP/WG-aktivasyon AKT[l-1], BP/WG-hata HATA[l] ----
    reg        hata_bolgesi;        // 1: HATA[l], 0: AKT[l-1]
    integer    RH, RW, RC, karo, kanal;
    reg [AW-1:0] R_taban;
    reg [5:0]  R_G;
    always @* begin
        if (hata_bolgesi) begin
            RH = ho; RW = wo; RC = cout;
            R_taban = taban_hata[AW*ll +: AW];
            R_G     = G_hata[6*ll +: 6];
        end else begin
            RH = h;  RW = w;  RC = cin;
            R_taban = taban_akt[AW*(ll-1) +: AW];
            R_G     = G_akt[6*(ll-1) +: 6];
        end
        // FP: kanal c = k1; BP: kanal o = k1; WG aktivasyon: karo k0; WG hata: karo k1
        case (fz)
            2'd0, 2'd1: begin kanal = kk1; karo = kk1 / 16; end
            default:    begin kanal = 0;   karo = (durum == D_HATA) ? kk1 : kk0; end
        endcase
    end

    // ---- D96 (Adım 5c-b): okuma adresleri ----
    // Adres (D81) = taban + ((b·n_karo + karo)·⌈H/16⌉ + satır/16)·W + x, AW bitte sarar. Çarpımlar yalnızca basla'da,
    // bir kez (bölge tabanı, WG'nin 3 satırının ve hata satırının satır payı); akışta toplama ve sayaç:
    //   FP/BP SATIR: 16 bankın adresi aynı (satır 16·tur + k, k < 16 -> satır/16 = tur) = taban + o_say, o_say her
    //   SATIR çevriminde +1 (tur·W + x ardışık). WG SATIR: taban + q_pay[q] + x. HATA: taban + h_pay + x.
    function [11:0] karo_n;                          // ceil(n / 16)
        input [11:0] n;
        begin karo_n = (n + 12'd15) >> 4; end
    endfunction
    wire [AW-1:0] g_karo_akt  = (faz == 2'd2) ? k0 : (k1 >> 4);
    wire [AW-1:0] g_karo_hata = (faz == 2'd2) ? k1 : (k1 >> 4);
    wire [AW-1:0] g_bas_akt   = taban_akt[AW*g_li +: AW]
                              + ((b * karo_n(g_cin[11:0]) + g_karo_akt) * karo_n({4'd0, g_h})) * g_w;
    wire [AW-1:0] g_bas_hata  = taban_hata[AW*l +: AW]
                              + ((b * karo_n(g_cout[11:0]) + g_karo_hata) * karo_n(g_ho)) * g_wo[7:0];
    wire [AW-1:0] g_agr_fp    = taban_agr[AW*l +: AW] + k0 * g_cin + k1;
    wire [AW-1:0] g_agr_bp    = taban_agr[AW*l +: AW] + (k1 >> 4) * g_cin + {k0, 4'd0};
    reg  [AW-1:0] r_bas_akt, r_bas_hata, r_agr, r_h_pay, o_say;
    reg  [AW-1:0] r_q_pay [0:2];
    reg  [3:0]    r_q_bank [0:2];
    reg  [2:0]    r_q_gec;
    integer gq, g_ra;
    always @(posedge clk) begin
        if (durum == D_BOS && basla) begin
            r_bas_akt  <= g_bas_akt;
            r_bas_hata <= g_bas_hata;
            r_agr      <= (faz == 2'd0) ? g_agr_fp : g_agr_bp;
            r_h_pay    <= (z >> 4) * g_wo[7:0];
            o_say      <= {AW{1'b0}};
            for (gq = 0; gq < 3; gq = gq + 1) begin   // WG: aktivasyon satırı ra = s·z + q − p
                g_ra = (g_s2 ? 2*z : z) + gq - g_p;
                r_q_gec[gq]  <= (g_ra >= 0) && (g_ra < g_h);
                r_q_bank[gq] <= g_ra[3:0];
                r_q_pay[gq]  <= (g_ra >> 4) * g_w;
            end
        end else if (durum == D_SATIR)
            o_say <= o_say + 1'b1;
    end

    // ---- GMS: bank başına bir gms_group16 (D78); sistemin tek GMS takımı (D100) ----
    wire [NB*128-1:0] gms_cikis;
    wire [5:0]        gms_G = dis_G_sec ? dis_G : R_G;
    assign gms_flat = gms_cikis;
    genvar gk;
    generate
        for (gk = 0; gk < NB; gk = gk + 1) begin : gms
            gms_group16 u_gms (
                .lms_in_flat(v_oku_veri[134*gk +: 128]),
                .l_in(v_oku_veri[134*gk + 128 +: 6]),
                .G(gms_G),
                .group_out_flat(gms_cikis[128*gk +: 128]),
                .tasma_flat()
            );
        end
    endgenerate

    // ---- Okuma sayaçları ve yakalama boru hattı (okuma verisi 1 çevrim sonra) ----
    reg [7:0] sx, stur;                 // x ve tur (FP/BP: satır grubu; AGR: sıra)
    reg       yak_gec;                  // bu çevrim yakalanacak veri var
    reg [2:0] yak_durum;
    reg [7:0] yak_x, yak_tur;
    integer   kk, rr, xx, ii, jj, idx;

    // ---- D97 (Adım 5c-c): line buffer ----
    // FP/BP: haritanın tamamı yerine geçişin ihtiyaç duyduğu satır penceresi tutulur: yerel satır K = harita satırı
    // − taban_satir (komut sabiti). Her yerel satır kendi küçük belleğinde (W kelime × 8 bit, dağıtık RAM; bir
    // yazma, iki okuma portu). Akışta PE satırı i'nin 3 tap'i sabit yerel satırlardan okunur (FP/BP s1: i + q,
    // FP s2: 2i + q, BP s2: q = 2 ? i : i + 1); okunan sütun t'den (iki port: s2'de çift ve tek sütun).
    // Pencere dışı / harita dışı satır (r_satir_gec) ve harita dışı sütun 0 verir. Önceden harita H×W'lık bir
    // yazmaç dizisindeydi ve her tap 256'ya 1 mux'tan okunuyordu (H, W <= 16).
    // WG: 3 aktivasyon satırı (q) ve hata satırı da birer bellek (W × 128 bit).
    localparam LP = 33;                                       // pencere: FP s2'de 2·15 + 2 + 1 satır
    reg signed [12:0] g_taban_satir, r_taban_satir;
    reg [LP-1:0]      g_satir_gec, r_satir_gec;
    reg [11:0]        g_RH;
    integer gk3, g_g;
    always @* begin
        case ({faz == 2'd1, g_s2})
            2'b00:   g_taban_satir = $signed({1'b0, z, 4'd0}) - $signed({1'b0, g_p});            // FP s1
            2'b01:   g_taban_satir = $signed({1'b0, z, 5'd0}) - $signed({1'b0, g_p});            // FP s2
            2'b10:   g_taban_satir = $signed({1'b0, z, 4'd0}) - 13'sd2 + $signed({1'b0, g_p}); // BP s1
            default: g_taban_satir = $signed({1'b0, z, 4'd0}) - 13'sd1;                          // BP s2
        endcase
        g_RH = (faz == 2'd1) ? g_ho : {4'd0, g_h};
        for (gk3 = 0; gk3 < LP; gk3 = gk3 + 1) begin
            g_g = g_taban_satir + gk3;
            g_satir_gec[gk3] = (g_g >= 0) && (g_g < $signed({1'b0, g_RH}));
        end
    end
    always @(posedge clk) if (durum == D_BOS && basla) begin
        r_taban_satir <= g_taban_satir;
        r_satir_gec   <= g_satir_gec;
    end

    // yakalanan SATIR kelimesinden pencereye yazma: bank kk = harita satırı 16·tur + kk -> K = 16·tur + kk − taban
    reg [8*NB-1:0] kb;                                        // bank başına kanalın baytı
    reg [LP-1:0]   lb_yaz;
    reg [8*LP-1:0] lb_veri;
    integer kw, dw;
    always @* begin
        for (kw = 0; kw < NB; kw = kw + 1) kb[8*kw +: 8] = gms_cikis[128*kw + 8*kk1[3:0] +: 8];
        lb_yaz = {LP{1'b0}}; lb_veri = {8*LP{1'b0}};
        if (yak_gec && yak_durum == D_SATIR && fz != 2'd2)
            for (kw = 0; kw < LP; kw = kw + 1) begin
                dw = r_taban_satir + kw - $signed({1'b0, yak_tur, 4'd0});
                if (dw >= 0 && dw < 16 && r_satir_gec[kw]) begin
                    lb_yaz[kw] = 1'b1;
                    lb_veri[8*kw +: 8] = kb[8*dw[3:0] +: 8];
                end
            end
    end

    reg  [7:0]        lb_a1, lb_a2;                           // akışın okuduğu sütunlar
    wire [8*LP-1:0]   lb_o1, lb_o2;
    wire [3*128-1:0]  lw_o1, lw_o2;
    wire [127:0]      le_o;
    wire lw_yaz = yak_gec && yak_durum == D_SATIR && fz == 2'd2;
    wire le_yaz = yak_gec && yak_durum == D_HATA;
    genvar gl;
    generate
        for (gl = 0; gl < LP; gl = gl + 1) begin : lb
            reg [7:0] m [0:WMAX-1];
            integer a0;
            initial for (a0 = 0; a0 < WMAX; a0 = a0 + 1) m[a0] = 8'd0;
            always @(posedge clk) if (lb_yaz[gl]) m[yak_x] <= lb_veri[8*gl +: 8];
            assign lb_o1[8*gl +: 8] = m[lb_a1];
            assign lb_o2[8*gl +: 8] = m[lb_a2];
        end
        for (gl = 0; gl < 3; gl = gl + 1) begin : lw
            reg [127:0] m [0:WMAX-1];
            integer a0;
            initial for (a0 = 0; a0 < WMAX; a0 = a0 + 1) m[a0] = 128'd0;
            always @(posedge clk) if (lw_yaz)
                m[yak_x] <= r_q_gec[gl] ? gms_cikis[128*r_q_bank[gl] +: 128] : 128'd0;
            assign lw_o1[128*gl +: 128] = m[lb_a1];
            assign lw_o2[128*gl +: 128] = m[lb_a2];
        end
    endgenerate
    reg [127:0] le_m [0:WMAX-1];
    integer a1;
    initial for (a1 = 0; a1 < WMAX; a1 = a1 + 1) le_m[a1] = 128'd0;
    always @(posedge clk) if (le_yaz) le_m[yak_x] <= gms_cikis[128*zz[3:0] +: 128];
    assign le_o = le_m[t];

    reg [71:0]  WR  [0:15];            // sütun ağırlıkları (PE'ye yüklenen hâli)
    integer q;
    initial for (q = 0; q < 16; q = q + 1) WR[q] = 72'd0;

    // Okuma adresleri (saatsiz; D96: çarpım yok)
    integer ka, qa;
    wire [AW-1:0] R_bas = hata_bolgesi ? r_bas_hata : r_bas_akt;
    always @* begin
        v_oku_adr = {NB*AW{1'b0}};
        a_oku_adr = {NB*AW{1'b0}};
        case (durum)
            D_AGR: begin
                if (fz == 2'd0) begin
                    for (ka = 0; ka < NB; ka = ka + 1) a_oku_adr[AW*ka +: AW] = r_agr;
                end else begin
                    // BP: o = k1 sabit, sütun stur = c0 + stur, bank o mod 16
                    a_oku_adr[AW*kk1[3:0] +: AW] = r_agr + stur;
                end
            end
            D_SATIR: begin
                if (fz != 2'd2) begin
                    for (ka = 0; ka < NB; ka = ka + 1)
                        if ({stur, 4'd0} + ka < RH) v_oku_adr[AW*ka +: AW] = R_bas + o_say;
                end else begin
                    for (qa = 0; qa < 3; qa = qa + 1)
                        if (r_q_gec[qa]) v_oku_adr[AW*r_q_bank[qa] +: AW] = R_bas + r_q_pay[qa] + sx;
                end
            end
            D_HATA: v_oku_adr[AW*zz[3:0] +: AW] = R_bas + r_h_pay + sx;
            default: ;
        endcase
    end

    // Ağırlık dönüşümü: BP s1 180°, BP s2 Fig. 4(b) yüklemesi
    function [71:0] w_donustur;
        input [71:0] wv;
        input integer fz_, s_;
        integer a;
        begin
            w_donustur = wv;
            if (fz_ == 1 && s_ == 1)
                for (a = 0; a < 9; a = a + 1) w_donustur[8*a +: 8] = wv[8*(8 - a) +: 8];
            else if (fz_ == 1)
                for (a = 0; a < 3; a = a + 1) begin
                    w_donustur[8*(3*a)   +: 8] = wv[8*(3*a+2) +: 8];
                    w_donustur[8*(3*a+1) +: 8] = wv[8*(3*a)   +: 8];
                    w_donustur[8*(3*a+2) +: 8] = wv[8*(3*a+1) +: 8];
                end
        end
    endfunction

    // ---- Durum makinesi ----
    always @(posedge clk) begin
        bitti <= 1'b0;
        if (rst) begin
            durum <= D_BOS; yak_gec <= 1'b0; t <= 8'd0;
        end else begin
            // 1) bir önceki çevrimin okumasını yakala
            if (yak_gec) begin
                case (yak_durum)
                    D_AGR: begin
                        if (fz == 2'd0) begin
                            for (jj = 0; jj < 16; jj = jj + 1)
                                WR[jj] <= (jj < nc) ? a_oku_veri[72*jj +: 72] : 72'd0;
                        end else begin
                            if (yak_tur < nc) WR[yak_tur] <= w_donustur(a_oku_veri[72*(kk1 % 16) +: 72], 1, s);
                        end
                    end
                    // D_SATIR / D_HATA: line buffer yazmaları ayrı bloklarda (lb, lw, le_m)
                    default: ;
                endcase
            end
            yak_gec <= 1'b0;

            // 2) okuma sırası
            case (durum)
                D_BOS: if (basla) begin
                    fz <= faz; ll <= l; bb <= b; kk0 <= k0; kk1 <= k1; zz <= z;
                    sx <= 8'd0; stur <= 8'd0;
                    hata_bolgesi <= (faz == 2'd1);
                    for (jj = 0; jj < 16; jj = jj + 1) WR[jj] <= 72'd0;
                    durum <= (faz == 2'd2) ? D_SATIR : D_AGR;
                end
                D_AGR: begin
                    yak_gec <= 1'b1; yak_durum <= D_AGR; yak_tur <= stur;
                    if (fz == 2'd0 || stur == 8'd15) begin
                        stur <= 8'd0; durum <= D_SATIR;
                    end else stur <= stur + 8'd1;
                end
                D_SATIR: begin
                    yak_gec <= 1'b1; yak_durum <= D_SATIR; yak_x <= sx; yak_tur <= stur;
                    if (sx + 1 < RW) sx <= sx + 8'd1;
                    else begin
                        sx <= 8'd0;
                        if (fz != 2'd2 && 16*(stur + 1) < RH) stur <= stur + 8'd1;
                        else begin
                            stur <= 8'd0;
                            durum <= D_BEKLE;
                        end
                    end
                end
                D_HATA: begin
                    yak_gec <= 1'b1; yak_durum <= D_HATA; yak_x <= sx;
                    if (sx + 1 < RW) sx <= sx + 8'd1;
                    else begin sx <= 8'd0; durum <= D_BEKLE; end
                end
                D_BEKLE: begin                 // son okuma bu çevrim yakalanıyor
                    if (fz == 2'd2 && !hata_bolgesi) begin durum <= D_HATA; hata_bolgesi <= 1'b1; end
                    else begin durum <= D_AKIS; t <= 8'd0; T <= T_hesap; end
                end
                D_AKIS: begin
                    if (t + 1 >= T) begin durum <= D_BOS; bitti <= 1'b1; end
                    t <= t + 8'd1;
                end
                default: durum <= D_BOS;
            endcase
        end
    end

    // ---- Akış (saatsiz, t'den; D97: okunan sütunlar ve sabit kablolu tap'ler) ----
    integer ti, c1, c2, cw;
    reg     c1g, c2g;
    always @* begin
        ti = t;
        c2 = -1;
        case ({fz, r_s2})
            3'b000:  c1 = ti - p;                                   // FP s1
            3'b001:  begin c1 = 2*ti - p; c2 = 2*ti - 1 - p; end    // FP s2 (çift, tek)
            3'b010:  c1 = ti - (2 - p);                             // BP s1
            3'b011:  c1 = ti - 1;                                   // BP s2
            3'b100:  c1 = ti - p;                                   // WG s1
            default: begin c1 = 2*ti - p; c2 = 2*ti - 1 - p; end    // WG s2
        endcase
        cw  = (fz == 2'd2) ? w : RW;
        c1g = (c1 >= 0) && (c1 < cw);
        c2g = (c2 >= 0) && (c2 < cw);
        lb_a1 = c1[7:0];
        lb_a2 = c2[7:0];
    end

    function integer yerel;             // PE satırı i'nin q. tap'inin yerel satırı
        input [2:0] md;
        input integer i_, q_;
        begin
            case (md)
                3'd1:    yerel = 2*i_ + q_;
                3'd3:    yerel = (q_ == 2) ? i_ : i_ + 1;
                default: yerel = i_ + q_;
            endcase
        end
    endfunction

    integer is_, js_, qs, kq;
    reg [7:0] ev;
    always @* begin
        satir_akis1_flat = {NB*24{1'b0}};
        satir_akis2_flat = {NB*24{1'b0}};
        satir_akis3_flat = {NB*24{1'b0}};
        sutun_w_flat     = {NB*72{1'b0}};
        mod = 3'd6;
        if (durum == D_AKIS) begin
            case (fz)
                2'd0: mod = (s == 1) ? 3'd0 : 3'd1;
                2'd1: mod = (s == 1) ? 3'd2 : 3'd3;
                default: mod = (s == 1) ? 3'd4 : 3'd5;
            endcase
            for (is_ = 0; is_ < 16; is_ = is_ + 1) if (is_ < nr) begin
                for (qs = 0; qs < 3; qs = qs + 1) begin
                    if (fz != 2'd2) begin
                        kq = yerel(mod, is_, qs);
                        if (c1g && r_satir_gec[kq]) satir_akis1_flat[24*is_ + 8*qs +: 8] = lb_o1[8*kq +: 8];
                        if (c2g && r_satir_gec[kq]) satir_akis2_flat[24*is_ + 8*qs +: 8] = lb_o2[8*kq +: 8];
                    end else begin
                        if (c1g) satir_akis1_flat[24*is_ + 8*qs +: 8] = lw_o1[128*qs + 8*is_ +: 8];
                        if (c2g) satir_akis2_flat[24*is_ + 8*qs +: 8] = lw_o2[128*qs + 8*is_ +: 8];
                    end
                end
            end
            for (js_ = 0; js_ < 16; js_ = js_ + 1) if (js_ < nc) begin
                if (fz != 2'd2) sutun_w_flat[72*js_ +: 72] = WR[js_];
                else begin
                    ev = (t < wo) ? le_o[8*js_ +: 8] : 8'd0;
                    sutun_w_flat[72*js_ +: 24] = {ev, ev, ev};
                end
            end
        end
    end

endmodule
