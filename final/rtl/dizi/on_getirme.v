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
//  Golden: dizi_sistem_golden.py (onget_izi.txt). Sınır: H <= HMAX, W <= WMAX (D84, test ağı).
//
//  Yapılandırma (katman li = l − 1, [8*li +: 8]): cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p.
//  Bölge tabanları ve G'ler (indis l = 0..LMAX): taban_akt/taban_hata/taban_agr [AW*l +: AW],
//  G_akt/G_hata [6*l +: 6]. Adres (D81): taban + ((b·n_karo + karo)·⌈H/16⌉ + satır/16)·W + x.
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b-3b)
// =============================================================================
`timescale 1ns/1ps

module on_getirme #(
    parameter NB   = 16,
    parameter AW   = 9,
    parameter LMAX = 4,
    parameter HMAX = 16,
    parameter WMAX = 16
) (
    input  wire                     clk,
    input  wire                     rst,
    // komut
    input  wire                     basla,
    input  wire [1:0]               faz,          // 0 FP, 1 BP, 2 WG
    input  wire [3:0]               l,
    input  wire [7:0]               b, k0, k1, z,
    // yapılandırma
    input  wire [LMAX*8-1:0]        cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p,
    input  wire [(LMAX+1)*AW-1:0]   taban_akt, taban_hata, taban_agr,
    input  wire [(LMAX+1)*6-1:0]    G_akt, G_hata,
    // tamponlar (eşzamanlı okuma: veri bir sonraki kenarda)
    output reg  [NB*AW-1:0]         v_oku_adr,
    input  wire [NB*134-1:0]        v_oku_veri,
    output reg  [NB*AW-1:0]         a_oku_adr,
    input  wire [NB*72-1:0]         a_oku_veri,
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
    reg [7:0]  bb, kk0, kk1, zz;
    wire [3:0]  g_li   = l - 4'd1;
    wire [7:0]  g_cin  = cfg_cin [8*g_li +: 8];
    wire [7:0]  g_cout = cfg_cout[8*g_li +: 8];
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
    reg [7:0] r_cin, r_cout, r_h, r_w, r_p, r_ho, r_wo, r_T;
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
                              + ((b * karo_n({4'd0, g_cin}) + g_karo_akt) * karo_n({4'd0, g_h})) * g_w;
    wire [AW-1:0] g_bas_hata  = taban_hata[AW*l +: AW]
                              + ((b * karo_n({4'd0, g_cout}) + g_karo_hata) * karo_n(g_ho)) * g_wo[7:0];
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

    // ---- GMS: bank başına bir gms_group16 (D78) ----
    wire [NB*128-1:0] gms_cikis;
    genvar gk;
    generate
        for (gk = 0; gk < NB; gk = gk + 1) begin : gms
            gms_group16 u_gms (
                .lms_in_flat(v_oku_veri[134*gk +: 128]),
                .l_in(v_oku_veri[134*gk + 128 +: 6]),
                .G(R_G),
                .group_out_flat(gms_cikis[128*gk +: 128]),
                .tasma_flat()
            );
        end
    endgenerate

    // ---- Satır register'ları ----
    reg [7:0]   LR  [0:HMAX*WMAX-1];   // FP/BP: kanalın haritası
    reg [127:0] LRW [0:3*WMAX-1];      // WG: 3 aktivasyon satırı, x başına 16 kanal (PE satırları)
    reg [127:0] LE  [0:WMAX-1];        // WG: hata satırı, x başına 16 kanal (sütunlar)
    reg [71:0]  WR  [0:15];            // sütun ağırlıkları (PE'ye yüklenen hâli)
    integer q;
    initial begin
        for (q = 0; q < HMAX*WMAX; q = q + 1) LR[q] = 8'd0;
        for (q = 0; q < 3*WMAX; q = q + 1)    LRW[q] = 128'd0;
        for (q = 0; q < WMAX; q = q + 1)      LE[q] = 128'd0;
        for (q = 0; q < 16; q = q + 1)        WR[q] = 72'd0;
    end

    // ---- Okuma sayaçları ve yakalama boru hattı (okuma verisi 1 çevrim sonra) ----
    reg [7:0] sx, stur;                 // x ve tur (FP/BP: satır grubu; AGR: sıra)
    reg       yak_gec;                  // bu çevrim yakalanacak veri var
    reg [2:0] yak_durum;
    reg [7:0] yak_x, yak_tur;
    integer   kk, rr, xx, ii, jj, idx;

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
                    D_SATIR: begin
                        if (fz != 2'd2) begin
                            for (kk = 0; kk < NB; kk = kk + 1) begin
                                rr = 16*yak_tur + kk;
                                if (rr < RH) LR[rr*WMAX + yak_x] <= gms_cikis[128*kk + 8*(kanal % 16) +: 8];
                            end
                        end else begin
                            for (q = 0; q < 3; q = q + 1) begin
                                rr = (r_s2 ? 2*zz : zz) + q - p;
                                LRW[q*WMAX + yak_x] <= (rr >= 0 && rr < RH) ? gms_cikis[128*(rr % 16) +: 128] : 128'd0;
                            end
                        end
                    end
                    D_HATA: LE[yak_x] <= gms_cikis[128*(zz % 16) +: 128];
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

    // ---- Akış (saatsiz, t'den) ----
    function [7:0] lr_oku;              // dolgu dışı / harita dışı -> 0
        input integer satir, sutun, H_, W_;
        begin
            if (satir >= 0 && satir < H_ && sutun >= 0 && sutun < W_) lr_oku = LR[satir*WMAX + sutun];
            else lr_oku = 8'd0;
        end
    endfunction

    function [7:0] lrw_oku;             // WG: satır q, sütun, kanal (PE satırı) ch
        input integer qq, sutun, W_, ch;
        reg [127:0] k;
        begin
            if (sutun >= 0 && sutun < W_) begin k = LRW[qq*WMAX + sutun]; lrw_oku = k[8*ch +: 8]; end
            else lrw_oku = 8'd0;
        end
    endfunction

    integer ti, ri, pi, is_, js_, qs;
    reg [7:0] ev;
    always @* begin
        satir_akis1_flat = {NB*24{1'b0}};
        satir_akis2_flat = {NB*24{1'b0}};
        satir_akis3_flat = {NB*24{1'b0}};
        sutun_w_flat     = {NB*72{1'b0}};
        mod = 3'd6;
        if (durum == D_AKIS) begin
            ti = t;
            case (fz)
                2'd0: mod = (s == 1) ? 3'd0 : 3'd1;
                2'd1: mod = (s == 1) ? 3'd2 : 3'd3;
                default: mod = (s == 1) ? 3'd4 : 3'd5;
            endcase
            for (is_ = 0; is_ < 16; is_ = is_ + 1) if (is_ < nr) begin
                for (qs = 0; qs < 3; qs = qs + 1) begin
                    case (mod)
                        3'd0: begin ri = 16*zz + is_;
                            satir_akis1_flat[24*is_ + 8*qs +: 8] = lr_oku(ri + qs - p, ti - p, RH, RW); end
                        3'd1: begin ri = 16*zz + is_;
                            satir_akis1_flat[24*is_ + 8*qs +: 8] = lr_oku(2*ri + qs - p, 2*ti - p, RH, RW);
                            if (ti >= 1) satir_akis2_flat[24*is_ + 8*qs +: 8] = lr_oku(2*ri + qs - p, 2*ti - 1 - p, RH, RW); end
                        3'd2: begin ri = 16*zz + is_;
                            satir_akis1_flat[24*is_ + 8*qs +: 8] = lr_oku(ri + qs - (2 - p), ti - (2 - p), RH, RW); end
                        3'd3: begin pi = 16*zz + is_;
                            satir_akis1_flat[24*is_ + 8*qs +: 8] = lr_oku((qs == 2) ? pi - 1 : pi, ti - 1, RH, RW); end
                        3'd4: satir_akis1_flat[24*is_ + 8*qs +: 8] = lrw_oku(qs, ti - p, w, is_);
                        default: begin
                            satir_akis1_flat[24*is_ + 8*qs +: 8] = lrw_oku(qs, 2*ti - p, w, is_);
                            if (ti >= 1) satir_akis2_flat[24*is_ + 8*qs +: 8] = lrw_oku(qs, 2*ti - 1 - p, w, is_);
                        end
                    endcase
                end
            end
            for (js_ = 0; js_ < 16; js_ = js_ + 1) if (js_ < nc) begin
                if (fz != 2'd2) sutun_w_flat[72*js_ +: 72] = WR[js_];
                else begin
                    ev = (ti < wo) ? LE[ti][8*js_ +: 8] : 8'd0;
                    sutun_w_flat[72*js_ +: 24] = {ev, ev, ev};
                end
            end
        end
    end

endmodule
