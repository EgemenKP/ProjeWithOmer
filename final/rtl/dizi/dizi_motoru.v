// =============================================================================
//  dizi_motoru.v — 16x16 dizinin komut yürütücüsü (Adım 5b-3c, D91)
// -----------------------------------------------------------------------------
//  Bir DİZİ komutunu (D85) baştan sona yürütür:
//    ön-getirme (on_getirme, GMS'li, D78/D84/D90) -> pe_dizi (16x16, PE içi Psum FIFO, D74) ->
//    (son = 1 ise) grup (D76) -> satır başına LMS (Egemen'in lms_group16'sı; B -> paylaşılan
//    global_max_reducer16) -> ReLU (FP) / ReLU-geri (BP; maske = AKT[l-1]'in GMS'li kelimesi, D86) ->
//    veri tamponuna kelime + l (D81, D83).
//  İŞ_BAŞLA (is_basla): hedef (7 ya da m_u) tutulur, G toplayıcı ve Psum FIFO'lar sıfırlanır.
//  G (G_out): işin son grubundan sonra geçerli; ÖLÇEK bunu bölgenin G register'ına yazar (3e).
//
//  Zamanlama (D66'nın dizi hâli): akışın t. çevriminde golden'ın t. adım girişi; golden'ın t. adım çıkışı
//  t + 1. çevrimde (pe_dizi'nin cikis_flat'ı). Geçerli çıkış adımları: FP/BP s1 ve FP s2'de t >= 2, BP s2'de
//  t >= 1, son adım T − 1; bu yüzden akıştan sonra 1 yakalama çevrimi (mod tutulur, girişler 0).
//    - Psum: ilk = 0 ise t < Np çevrimlerinde FIFO okunur ve A şeritlerine verilir (Np = T − 2; BP s2'de
//      T − 1); B şeritlerinin 1 çevrim gecikmesi pe_dizi'de. son = 0 ise geçerli çıkışlar FIFO'ya yazılır.
//    - son = 1, FP / BP s1: her geçerli çıkış çevriminde satır başına bir grup (şerit 0) -> LMS.
//    - son = 1, BP s2: bir çevrimde 4 şerit = satır başına 4 grup; LMS ve tampon çevrim başına satır başına
//      bir grup aldığı için çıkışlar PE'lerin kendi Psum FIFO'sunda bekletilir (D98; önceden ayrı bir kayıt
//      belleği, bufr, 448 RAMB36), akıştan sonra (q, şerit) sırasıyla FIFO başından boşaltılır. Dolguya düşen konumlar atlanır (D52). Satır i ve i+8 aynı banka
//      yazar (dX satırı 2p + δ − p); 8'den fazla satır etkinse her adım iki yarıda (D83).
//    - son = 1, WG: akıştan sonra mod tutulur (girişler 0, akümülatörler sabit), 9 çevrimde
//      akümülatör q (= 3ki + kj) grubu -> GRAD[l].
//  LMS'ten sonra 2 aşama: A) LMS + (BP'de) maske okuması, B) maske GMS'i, ReLU / ReLU-geri, yazma.
//  Golden: dizi_sistem_golden.py. Yazan: Claude, 04.11.2026 (final/, Adım 5b-3c)
// =============================================================================
`timescale 1ns/1ps

module dizi_motoru #(
    parameter NB   = 16,
    parameter AW   = 9,
    parameter LMAX = 4,
    parameter HMAX = 32,           // D97
    parameter WMAX = 32,           // D97 (önceden 16)
    parameter PS_DERINLIK = 64,
    parameter PS_AW = 6
) (
    input  wire                     clk,
    input  wire                     rst,
    // komutlar
    input  wire                     is_basla,
    input  wire [2:0]               hedef_in,
    input  wire                     basla,
    input  wire [1:0]               faz,
    input  wire [3:0]               l,
    input  wire [7:0]               b, k0, k1, z,
    input  wire                     ilk, son,
    output reg                      bitti,
    output wire                     mesgul,
    output wire [5:0]               G_out,
    output wire                     ps_tasma, ps_eksik, ps_bos,
    // yapılandırma
    input  wire [LMAX*8-1:0]        cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p, cfg_relu,
    input  wire [(LMAX+1)*AW-1:0]   taban_akt, taban_hata, taban_grad, taban_agr,
    input  wire [(LMAX+1)*6-1:0]    G_akt, G_hata,
    // tamponlar
    output reg  [NB*AW-1:0]         v_oku_adr,
    input  wire [NB*134-1:0]        v_oku_veri,
    output reg  [NB-1:0]            v_yaz_en,
    output reg  [NB*AW-1:0]         v_yaz_adr,
    output reg  [NB*134-1:0]        v_yaz_veri,
    output wire [NB*AW-1:0]         a_oku_adr,
    input  wire [NB*72-1:0]         a_oku_veri,
    // D100: tek GMS takımı (ön-getirmede). sis_G_sec: bu çevrimin okuma verisi yürütücünün (G = sis_G)
    input  wire                     sis_G_sec,
    input  wire [5:0]               sis_G,
    output wire [NB*128-1:0]        gms_flat
);

    // M_ONGET: ön-getirmenin yükleme ve akış fazları (akış = og_akis)
    localparam M_BOS = 4'd0, M_WGRST = 4'd1, M_ONGET = 4'd2, M_SON1 = 4'd4,
               M_BP2 = 4'd5, M_WG = 4'd6, M_SON = 4'd7;
    reg [3:0] durum;
    assign mesgul = (durum != M_BOS);

    // ---- komut ----
    reg [1:0] fz;  reg [3:0] ll;  reg [7:0] bb, kk0, kk1, zz;  reg ilk_k, son_k;
    reg [2:0] hedef;
    // D95 (Adım 5c-a): katmanın boyutları basla'da komut girişlerinden bir kez hesaplanıp register'da tutulur;
    // s ∈ {1, 2} -> "/ s" bir kaydırma (önceden her çevrim 32 bit değişkene bölme).
    wire [3:0]  g_li  = l - 4'd1;
    wire [7:0]  g_h   = cfg_h[8*g_li +: 8], g_w = cfg_w[8*g_li +: 8], g_p = cfg_p[8*g_li +: 8];
    wire        g_s2  = (cfg_s[8*g_li +: 8] == 8'd2);
    wire [11:0] g_h2p = {4'd0, g_h} + {3'd0, g_p, 1'b0};
    wire [11:0] g_w2p = {4'd0, g_w} + {3'd0, g_p, 1'b0};
    wire [11:0] g_ho  = g_s2 ? (((g_h2p - 12'd3) >> 1) + 12'd1) : (g_h2p - 12'd2);
    wire [11:0] g_wo  = g_s2 ? (((g_w2p - 12'd3) >> 1) + 12'd1) : (g_w2p - 12'd2);
    reg [7:0] r_cin, r_cout, r_h, r_w, r_p, r_ho, r_wo;
    reg       r_s2, r_relu, r_relu_once;
    always @(posedge clk) if (durum == M_BOS && basla) begin
        r_cin <= cfg_cin[8*g_li +: 8]; r_cout <= cfg_cout[8*g_li +: 8];
        r_h <= g_h; r_w <= g_w; r_p <= g_p; r_s2 <= g_s2; r_ho <= g_ho[7:0]; r_wo <= g_wo[7:0];
        r_relu      <= (cfg_relu[8*g_li +: 8] != 8'd0);
        r_relu_once <= (l >= 4'd2) ? (cfg_relu[8*(l-4'd2) +: 8] != 8'd0) : 1'b0;
    end
    integer cin, cout, h, w, s, p, ho, wo, relu_l, relu_once;
    always @* begin
        cin = r_cin; cout = r_cout; h = r_h; w = r_w; p = r_p; ho = r_ho; wo = r_wo;
        s = r_s2 ? 2 : 1;
        relu_l = r_relu; relu_once = r_relu_once;
    end

    // ---- ön-getirme ----
    wire [2:0]        og_mod;
    wire [NB*24-1:0]  og_a1, og_a2, og_a3;
    wire [NB*72-1:0]  og_w;
    wire              og_akis, og_bitti, og_mesgul;
    wire [7:0]        og_t, og_T;
    wire [NB*AW-1:0]  og_v_adr;
    reg               og_basla;
    // D100: okuma portunu bu çevrim ön-getirme mi (yükleme fazları) yoksa motorun maske okuması mı kullanıyor;
    // veri bir sonraki çevrimde geldiği için sahip bir çevrim register'da.
    reg               maske_sahip_r;
    wire [NB*128-1:0] og_gms;
    initial maske_sahip_r = 1'b1;
    always @(posedge clk) maske_sahip_r <= !(og_mesgul && !og_akis);
    assign gms_flat = og_gms;
    on_getirme #(.NB(NB), .AW(AW), .LMAX(LMAX), .HMAX(HMAX), .WMAX(WMAX)) u_og (
        .clk(clk), .rst(rst), .basla(og_basla), .faz(fz), .l(ll), .b(bb), .k0(kk0), .k1(kk1), .z(zz),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s), .cfg_p(cfg_p),
        .taban_akt(taban_akt), .taban_hata(taban_hata), .taban_agr(taban_agr), .G_akt(G_akt), .G_hata(G_hata),
        .v_oku_adr(og_v_adr), .v_oku_veri(v_oku_veri), .a_oku_adr(a_oku_adr), .a_oku_veri(a_oku_veri),
        .dis_G_sec(sis_G_sec | maske_sahip_r), .dis_G(sis_G_sec ? sis_G : G_akt[6*(ll-1) +: 6]), .gms_flat(og_gms),
        .mod(og_mod), .satir_akis1_flat(og_a1), .satir_akis2_flat(og_a2), .satir_akis3_flat(og_a3),
        .sutun_w_flat(og_w), .akis(og_akis), .t(og_t), .T(og_T), .bitti(og_bitti), .mesgul(og_mesgul));

    // ---- dizi ----
    reg  [2:0]           pe_mod, mod_k;
    reg                  pe_rst, ps_yaz, ps_oku, ps_sec, ps_temizle;
    reg  [NB*24-1:0]     pe_a1, pe_a2, pe_a3;
    reg  [NB*72-1:0]     pe_w;
    wire [NB*NB*128-1:0] cikis;
    wire [NB*NB*288-1:0] g;
    wire [NB*NB*128-1:0] ps_bas;                // PE'lerin FIFO başları (D98)
    pe_dizi #(.R(NB), .C(NB), .PS_DERINLIK(PS_DERINLIK), .PS_AW(PS_AW)) u_dizi (
        .clk(clk), .rst(pe_rst), .mod(pe_mod),
        .satir_akis1_flat(pe_a1), .satir_akis2_flat(pe_a2), .satir_akis3_flat(pe_a3), .sutun_w_flat(pe_w),
        .ps_temizle(ps_temizle), .ps_yaz(ps_yaz), .ps_oku(ps_oku), .ps_sec(ps_sec),
        .cikis_flat(cikis), .g_flat(g), .ps_tasma(ps_tasma), .ps_eksik(ps_eksik), .ps_bos(ps_bos),
        .ps_bas_flat(ps_bas));

    // ---- geçiş sayıları ----
    integer nr, nc, npass, v0, Np, c_say, tt;
    always @* begin
        npass = (h + p + 1) / 2;
        case (fz)
            2'd0:    begin nr = ho - 16*zz; nc = cout - 16*kk0; end
            2'd1:    begin nr = ((s == 1) ? h : npass) - 16*zz; nc = cin - 16*kk0; end
            default: begin nr = cin - 16*kk0; nc = cout - 16*kk1; end
        endcase
        if (nr > 16) nr = 16;
        if (nc > 16) nc = 16;
        v0 = (mod_k == 3'd3) ? 1 : 2;
        Np = (mod_k == 3'd3) ? (og_T - 1) : (og_T - 2);
    end

    // çevrim sayacı: AKIŞ'ta t, yakalama çevriminde T
    reg [7:0] cs;
    always @* begin
        c_say = og_akis ? og_t : cs;
        tt    = c_say - 1;                      // bu çevrimde görünen çıkışın golden adımı
    end
    wire cikis_gecerli = (og_akis || (durum == M_SON1)) && (tt >= v0) && (tt <= og_T - 1);

    // ---- BP s2 son geçiş: çıkışlar PE'nin Psum FIFO'sunda (D98) ----
    // Shao III-A (Fig. 4(b)): "The Psum FIFO queue receives four partial sums in parallel". Son geçişin q. çıkışı
    // (4 şerit) ara geçişlerdeki gibi FIFO'ya yazılır; boşaltmada FIFO başı (ps_bas) kayıt q'dur ve q'nun 4 şeridi
    // (ve 2 yarısı) bitince çıkarılır. FIFO'da bir geçişten fazlası beklemez (D94), derinlik 64 yeter (T − 1 ≤ 17).
    reg [7:0] dq, ds; reg dh;                   // boşaltma: q, şerit, yarı
    wire bp2_son = (fz == 2'd1) && (s != 1) && son_k;
    wire bp2_cikar = (durum == M_BP2) && !(!dh && nr > 8) && (ds == 8'd3);

    // ---- WG boşaltma ----
    reg [3:0] wq;

    // ---- Aşama A: satır başına grup seçimi + LMS ----
    reg  [NB*512-1:0] A_grup;
    reg  [NB-1:0]     A_gec;
    reg  [NB*AW-1:0]  A_adr;                    // yazılacak bölgede adres
    reg  [NB*AW-1:0]  A_madr;                   // maske (AKT[l-1]) adresi
    reg  [NB*4-1:0]   A_bank;
    wire [NB*128-1:0] lms_c8;
    wire [NB*6-1:0]   lms_l, lms_B;

    // D96 (Adım 5c-b): yazma ve maske adresleri. Adres (D81) = taban + ((b·n_karo + karo)·⌈H/16⌉ + satır/16)·W + x
    // (AW bitte sarar). 16 satırın satır/16'sı FP'de, BP s1'de ve WG'de aynı (satır = 16·z + i, i < 16); BP s2'de
    // 2z − 1, 2z ya da 2z + 1. Çarpımlar yalnızca basla'da bir kez; akışta taban + (BP s2: ±W) + sütun.
    function [11:0] karo_n;                          // ceil(n / 16)
        input [11:0] n;
        begin karo_n = (n + 12'd15) >> 4; end
    endfunction
    wire [7:0]    g_cin  = cfg_cin[8*g_li +: 8], g_cout = cfg_cout[8*g_li +: 8];
    wire [AW-1:0] g_bp_ic = ((b * karo_n({4'd0, g_cin}) + k0) * karo_n({4'd0, g_h}) + (g_s2 ? 2*z : z)) * g_w;
    reg  [AW-1:0] g_yaz_bas;
    always @* begin
        case (faz)
            2'd0:    g_yaz_bas = taban_akt[AW*l +: AW]
                               + ((b * karo_n({4'd0, g_cout}) + k0) * karo_n(g_ho) + z) * g_wo[7:0];
            2'd1:    g_yaz_bas = taban_hata[AW*g_li +: AW] + g_bp_ic;
            default: g_yaz_bas = taban_grad[AW*l +: AW] + (k1 * karo_n({4'd0, g_cin}) + k0) * 4'd9;
        endcase
    end
    reg [AW-1:0] r_yaz_bas, r_mask_bas;
    always @(posedge clk) if (durum == M_BOS && basla) begin
        r_yaz_bas  <= g_yaz_bas;
        r_mask_bas <= taban_akt[AW*g_li +: AW] + g_bp_ic;
    end

    // D99: değişken indisli parça seçimleri yalnızca geçerli değerler kadar mux olsun. Önceden ps_bas'ın şeridi
    // 8 bitlik ds ile ve WG akümülatörü 4 bitlik wq ile çarpılarak seçiliyordu: sentez her PE için tüm vektör
    // üzerinde 256'ya 1 (ve 16'ya 1) seçici kuruyordu.
    function [31:0] akum_sec;                        // PE'nin 9 akümülatöründen q.
        input [287:0] gv;
        input [3:0]   q;
        begin
            case (q)
                4'd0: akum_sec = gv[0 +: 32];   4'd1: akum_sec = gv[32 +: 32];  4'd2: akum_sec = gv[64 +: 32];
                4'd3: akum_sec = gv[96 +: 32];  4'd4: akum_sec = gv[128 +: 32]; 4'd5: akum_sec = gv[160 +: 32];
                4'd6: akum_sec = gv[192 +: 32]; 4'd7: akum_sec = gv[224 +: 32]; default: akum_sec = gv[256 +: 32];
            endcase
        end
    endfunction

    integer i, j, R, C, sr, xr, kanal_sec, e;
    reg [AW-1:0] satir_pay;
    always @* begin
        A_grup = {NB*512{1'b0}}; A_gec = {NB{1'b0}}; A_adr = {NB*AW{1'b0}}; A_madr = {NB*AW{1'b0}};
        A_bank = {NB*4{1'b0}};
        for (i = 0; i < NB; i = i + 1) begin
            R = 0; C = 0; sr = 0;
            if (fz == 2'd0 && son_k && cikis_gecerli && i < nr) begin                    // FP
                A_gec[i] = 1'b1; R = 16*zz + i; C = tt - v0;
                for (j = 0; j < NB; j = j + 1) if (j < nc) A_grup[512*i + 32*j +: 32] = cikis[128*(i*NB + j) +: 32];
                A_adr[AW*i +: AW] = r_yaz_bas + C;
            end else if (fz == 2'd1 && s == 1 && son_k && cikis_gecerli && i < nr) begin  // BP s1
                A_gec[i] = 1'b1; R = 16*zz + i; C = tt - v0;
                for (j = 0; j < NB; j = j + 1) if (j < nc) A_grup[512*i + 32*j +: 32] = cikis[128*(i*NB + j) +: 32];
            end else if (durum == M_BP2 && i < nr && ((i < 8) != dh)) begin             // BP s2 boşaltma
                R = 2*(16*zz + i) + ds / 2 - p; C = 2*dq + ds % 2 - p;
                if (R >= 0 && R < h && C >= 0 && C < w) begin
                    A_gec[i] = 1'b1;
                    for (j = 0; j < NB; j = j + 1) if (j < nc)
                        A_grup[512*i + 32*j +: 32] = ps_bas[NB*128*i + 128*j + 32*ds[1:0] +: 32];  // D99: 4'e 1
                end
            end else if (durum == M_WG && i < nr) begin                                   // WG
                A_gec[i] = 1'b1;
                for (j = 0; j < NB; j = j + 1) if (j < nc) A_grup[512*i + 32*j +: 32] = akum_sec(g[288*(i*NB + j) +: 288], wq);
                A_adr[AW*i +: AW] = r_yaz_bas + wq;
            end
            if (fz == 2'd1) begin                                                          // BP: HATA[l-1] ve maske
                // satır R'nin 16'lık bloğu: s1'de z, s2'de 2z + (−1 | 0 | +1) (e = R − 32z)
                e = R - 32*zz;
                satir_pay = (s == 1 || (e >= 0 && e < 16)) ? {AW{1'b0}} : (e < 0) ? -w : w;
                A_adr[AW*i +: AW]  = r_yaz_bas  + satir_pay + C;
                A_madr[AW*i +: AW] = r_mask_bas + satir_pay + C;
            end
            A_bank[4*i +: 4] = (fz == 2'd2) ? i[3:0] : R[3:0];
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < NB; gi = gi + 1) begin : lms
            lms_group16 u_lms (.group_in_flat(A_grup[512*gi +: 512]), .hedef(hedef),
                               .group_out_flat(lms_c8[128*gi +: 128]), .tasma_flat(),
                               .l_out(lms_l[6*gi +: 6]), .B_out(lms_B[6*gi +: 6]));
        end
    endgenerate

    // paylaşılan G (Egemen'in global_max_reducer16'sı); İŞ_BAŞLA'da sıfırlanır
    global_max_reducer16 u_G (.clk(clk), .rst(rst | is_basla), .push(A_gec), .B_flat(lms_B),
                              .hedef(hedef), .B_max(), .G(G_out));

    // ---- Aşama B (A'nın bir çevrim sonrası) ----
    reg  [NB-1:0]     B_gec;
    reg  [NB*128-1:0] B_c8;
    reg  [NB*6-1:0]   B_l;
    reg  [NB*AW-1:0]  B_adr;
    reg  [NB*4-1:0]   B_bank;
    reg  [1:0]        B_islem;                  // 0 yok, 1 ReLU, 2 ReLU-geri
    // Maske (AKT[l-1]) GMS'i: ayrı bir takım yerine ön-getirmenin GMS'i, G = G_akt[l-1] (D100)
    wire [NB*128-1:0] maske_gms = og_gms;

    // Okuma adresi: ön-getirme meşgulken onun, değilse maske okuması (aşama A)
    integer bi_, ki, kb_;
    reg [7:0] e8, a8;
    reg [3:0] ysec; reg yvar;
    always @* begin
        if (og_mesgul && !og_akis) v_oku_adr = og_v_adr;        // ön-getirmenin yükleme fazları
        else begin
            v_oku_adr = {NB*AW{1'b0}};
            for (bi_ = 0; bi_ < NB; bi_ = bi_ + 1)
                if (A_gec[bi_]) v_oku_adr[AW*A_bank[4*bi_ +: 4] +: AW] = A_madr[AW*bi_ +: AW];
        end
        // D99: yazma, bank (hedef) tarafından kurulur. Bank kb için kaynak satır = B_bank'ı kb olan son geçerli
        // satır (önceki yazımın "son yazan kazanır"ıyla aynı); veri 16'ya 1 seçilir, maske kb'nin kendi GMS
        // çıkışı (maske aynı banktan okundu). Önceden kaynak tarafından yazılıyordu (her satır değişken indisle
        // her banka): sentez ~1M LUT kuruyordu (05.11 ölçümü, `v_yaz_veri`).
        v_yaz_en = {NB{1'b0}}; v_yaz_adr = {NB*AW{1'b0}}; v_yaz_veri = {NB*134{1'b0}};
        for (kb_ = 0; kb_ < NB; kb_ = kb_ + 1) begin
            yvar = 1'b0; ysec = 4'd0;
            for (bi_ = 0; bi_ < NB; bi_ = bi_ + 1)
                if (B_gec[bi_] && B_bank[4*bi_ +: 4] == kb_) begin yvar = 1'b1; ysec = bi_; end
            if (yvar) begin
                v_yaz_en[kb_] = 1'b1;
                v_yaz_adr[AW*kb_ +: AW] = B_adr[AW*ysec +: AW];
                for (ki = 0; ki < 16; ki = ki + 1) begin
                    e8 = B_c8[128*ysec + 8*ki +: 8];
                    a8 = maske_gms[128*kb_ + 8*ki +: 8];
                    if (B_islem == 2'd1 && $signed(e8) < 0) e8 = 8'd0;                    // ReLU
                    if (B_islem == 2'd2 && !($signed(a8) > 0)) e8 = 8'd0;                // ReLU-geri (D86)
                    v_yaz_veri[134*kb_ + 8*ki +: 8] = e8;
                end
                v_yaz_veri[134*kb_ + 128 +: 6] = B_l[6*ysec +: 6];
            end
        end
    end

    // ---- Dizi girişleri ve Psum kontrolü (saatsiz) ----
    always @* begin
        pe_mod = 3'd6; pe_rst = 1'b0;
        pe_a1 = {NB*24{1'b0}}; pe_a2 = {NB*24{1'b0}}; pe_a3 = {NB*24{1'b0}}; pe_w = {NB*72{1'b0}};
        ps_oku = 1'b0; ps_sec = 1'b0; ps_yaz = 1'b0; ps_temizle = rst | is_basla;
        case (durum)
            M_WGRST: begin pe_mod = mod_k; pe_rst = 1'b1; end
            M_SON1, M_WG: pe_mod = mod_k;
            default: ;
        endcase
        if (og_akis) begin                                  // akış: ön-getirmenin t. çevrimi
            pe_mod = og_mod; pe_a1 = og_a1; pe_a2 = og_a2; pe_a3 = og_a3; pe_w = og_w;
            if (fz != 2'd2 && !ilk_k && og_t < Np) begin ps_oku = 1'b1; ps_sec = 1'b1; end
        end
        if (fz != 2'd2 && (!son_k || bp2_son) && cikis_gecerli) ps_yaz = 1'b1;
        if (bp2_cikar) ps_oku = 1'b1;           // D98: boşaltmada kayıt q bitti
    end

    // ---- Durum makinesi ----
    integer bq;
    always @(posedge clk) begin
        bitti <= 1'b0; og_basla <= 1'b0;
        // aşama A -> B
        B_gec <= A_gec; B_c8 <= lms_c8; B_l <= lms_l; B_adr <= A_adr; B_bank <= A_bank;
        B_islem <= (fz == 2'd0 && relu_l) ? 2'd1 : (fz == 2'd1 && relu_once) ? 2'd2 : 2'd0;
        if (is_basla) hedef <= hedef_in;
        // BP s2 son geçişinde çıkışları kaydet
        if (rst) begin
            durum <= M_BOS; B_gec <= {NB{1'b0}};
        end else case (durum)
            M_BOS: if (basla) begin
                fz <= faz; ll <= l; bb <= b; kk0 <= k0; kk1 <= k1; zz <= z; ilk_k <= ilk; son_k <= son;
                durum <= M_ONGET; og_basla <= 1'b1;
                if (faz == 2'd2) begin
                    mod_k <= (cfg_s[8*(l-1) +: 8] == 1) ? 3'd4 : 3'd5;
                    if (ilk) begin durum <= M_WGRST; og_basla <= 1'b0; end
                end
            end
            M_WGRST: begin durum <= M_ONGET; og_basla <= 1'b1; end
            M_ONGET: if (og_akis) begin
                if (og_t == 8'd0) mod_k <= og_mod;
                if (og_t + 1 >= og_T) begin
                cs <= og_T;
                if (fz == 2'd2) begin
                    if (son_k) begin durum <= M_WG; wq <= 4'd0; end
                    else durum <= M_SON;
                end else durum <= M_SON1;
                end
            end
            M_SON1: begin
                if (fz == 2'd1 && s != 1 && son_k) begin durum <= M_BP2; dq <= 8'd0; ds <= 8'd0; dh <= 1'b0; end
                else durum <= M_SON;
            end
            M_BP2: begin                                         // (q, şerit, yarı) sırası
                if (!dh && nr > 8) dh <= 1'b1;
                else begin
                    dh <= 1'b0;
                    if (ds < 3) ds <= ds + 8'd1;
                    else begin
                        ds <= 8'd0;
                        if (dq + 1 < og_T - 1) dq <= dq + 8'd1;
                        else durum <= M_SON;
                    end
                end
            end
            M_WG: if (wq == 4'd8) durum <= M_SON; else wq <= wq + 4'd1;
            M_SON: begin durum <= M_BOS; bitti <= 1'b1; end        // aşama B bu çevrimde yazıyor
            default: durum <= M_BOS;
        endcase
    end

endmodule
