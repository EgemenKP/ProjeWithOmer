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
//      bir grup aldığı için çıkışlar satır başına bir kayıt belleğinde (bufr) bekletilir, akıştan sonra
//      (q, şerit) sırasıyla boşaltılır. Dolguya düşen konumlar atlanır (D52). Satır i ve i+8 aynı banka
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
    parameter HMAX = 16,
    parameter WMAX = 16,
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
    input  wire [NB*72-1:0]         a_oku_veri
);

    // M_ONGET: ön-getirmenin yükleme ve akış fazları (akış = og_akis)
    localparam M_BOS = 4'd0, M_WGRST = 4'd1, M_ONGET = 4'd2, M_SON1 = 4'd4,
               M_BP2 = 4'd5, M_WG = 4'd6, M_SON = 4'd7;
    reg [3:0] durum;
    assign mesgul = (durum != M_BOS);

    // ---- komut ----
    reg [1:0] fz;  reg [3:0] ll;  reg [7:0] bb, kk0, kk1, zz;  reg ilk_k, son_k;
    reg [2:0] hedef;
    integer cin, cout, h, w, s, p, ho, wo, relu_l, relu_once;
    always @* begin
        cin  = cfg_cin [8*(ll-1) +: 8];  cout = cfg_cout[8*(ll-1) +: 8];
        h    = cfg_h   [8*(ll-1) +: 8];  w    = cfg_w   [8*(ll-1) +: 8];
        s    = cfg_s   [8*(ll-1) +: 8];  p    = cfg_p   [8*(ll-1) +: 8];
        relu_l    = cfg_relu[8*(ll-1) +: 8];
        relu_once = (ll >= 2) ? cfg_relu[8*(ll-2) +: 8] : 0;
        ho = (h + 2*p - 3) / s + 1;
        wo = (w + 2*p - 3) / s + 1;
    end

    // ---- ön-getirme ----
    wire [2:0]        og_mod;
    wire [NB*24-1:0]  og_a1, og_a2, og_a3;
    wire [NB*72-1:0]  og_w;
    wire              og_akis, og_bitti, og_mesgul;
    wire [7:0]        og_t, og_T;
    wire [NB*AW-1:0]  og_v_adr;
    reg               og_basla;
    on_getirme #(.NB(NB), .AW(AW), .LMAX(LMAX), .HMAX(HMAX), .WMAX(WMAX)) u_og (
        .clk(clk), .rst(rst), .basla(og_basla), .faz(fz), .l(ll), .b(bb), .k0(kk0), .k1(kk1), .z(zz),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s), .cfg_p(cfg_p),
        .taban_akt(taban_akt), .taban_hata(taban_hata), .taban_agr(taban_agr), .G_akt(G_akt), .G_hata(G_hata),
        .v_oku_adr(og_v_adr), .v_oku_veri(v_oku_veri), .a_oku_adr(a_oku_adr), .a_oku_veri(a_oku_veri),
        .mod(og_mod), .satir_akis1_flat(og_a1), .satir_akis2_flat(og_a2), .satir_akis3_flat(og_a3),
        .sutun_w_flat(og_w), .akis(og_akis), .t(og_t), .T(og_T), .bitti(og_bitti), .mesgul(og_mesgul));

    // ---- dizi ----
    reg  [2:0]           pe_mod, mod_k;
    reg                  pe_rst, ps_yaz, ps_oku, ps_sec, ps_temizle;
    reg  [NB*24-1:0]     pe_a1, pe_a2, pe_a3;
    reg  [NB*72-1:0]     pe_w;
    wire [NB*NB*128-1:0] cikis;
    wire [NB*NB*288-1:0] g;
    pe_dizi #(.R(NB), .C(NB), .PS_DERINLIK(PS_DERINLIK), .PS_AW(PS_AW)) u_dizi (
        .clk(clk), .rst(pe_rst), .mod(pe_mod),
        .satir_akis1_flat(pe_a1), .satir_akis2_flat(pe_a2), .satir_akis3_flat(pe_a3), .sutun_w_flat(pe_w),
        .ps_temizle(ps_temizle), .ps_yaz(ps_yaz), .ps_oku(ps_oku), .ps_sec(ps_sec),
        .cikis_flat(cikis), .g_flat(g), .ps_tasma(ps_tasma), .ps_eksik(ps_eksik), .ps_bos(ps_bos));

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

    // ---- BP s2 çıkış kayıtları ----
    localparam NQ = WMAX / 2 + 2;
    // Satır başına bir bellek (çevrimde bir yazma, saatsiz okuma -> dağıtık RAM): kayıt q = satırın 16 PE'sinin
    // 4 şeridi. (3f: tek dizide 16 yazma portu RAM'e eşlenemiyordu.)
    wire [NB*NB*128-1:0] buf_oku;               // satır i'nin dq. kaydı
    reg [7:0] dq, ds; reg dh;                   // boşaltma: q, şerit, yarı

    wire buf_yaz = (fz == 2'd1) && (s != 1) && son_k && cikis_gecerli;
    genvar gb;
    generate
        for (gb = 0; gb < NB; gb = gb + 1) begin : bufr
            reg [NB*128-1:0] mem [0:NQ-1];
            always @(posedge clk) if (buf_yaz) mem[tt - v0] <= cikis[NB*128*gb +: NB*128];
            assign buf_oku[NB*128*gb +: NB*128] = mem[dq];
        end
    endgenerate

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

    function [AW-1:0] adres;
        input integer taban, bi, n_karo, kr, H_, W_, satir, x;
        begin
            adres = taban + ((bi * n_karo + kr) * ((H_ + 15) / 16) + satir / 16) * W_ + x;
        end
    endfunction

    integer i, j, R, C, sr, xr, kanal_sec;
    always @* begin
        A_grup = {NB*512{1'b0}}; A_gec = {NB{1'b0}}; A_adr = {NB*AW{1'b0}}; A_madr = {NB*AW{1'b0}};
        A_bank = {NB*4{1'b0}};
        for (i = 0; i < NB; i = i + 1) begin
            R = 0; C = 0; sr = 0;
            if (fz == 2'd0 && son_k && cikis_gecerli && i < nr) begin                    // FP
                A_gec[i] = 1'b1; R = 16*zz + i; C = tt - v0;
                for (j = 0; j < NB; j = j + 1) if (j < nc) A_grup[512*i + 32*j +: 32] = cikis[128*(i*NB + j) +: 32];
                A_adr[AW*i +: AW] = adres(taban_akt[AW*ll +: AW], bb, (cout + 15) / 16, kk0, ho, wo, R, C);
            end else if (fz == 2'd1 && s == 1 && son_k && cikis_gecerli && i < nr) begin  // BP s1
                A_gec[i] = 1'b1; R = 16*zz + i; C = tt - v0;
                for (j = 0; j < NB; j = j + 1) if (j < nc) A_grup[512*i + 32*j +: 32] = cikis[128*(i*NB + j) +: 32];
            end else if (durum == M_BP2 && i < nr && ((i < 8) != dh)) begin             // BP s2 boşaltma
                R = 2*(16*zz + i) + ds / 2 - p; C = 2*dq + ds % 2 - p;
                if (R >= 0 && R < h && C >= 0 && C < w) begin
                    A_gec[i] = 1'b1;
                    for (j = 0; j < NB; j = j + 1) if (j < nc)
                        A_grup[512*i + 32*j +: 32] = buf_oku[NB*128*i + 128*j + 32*ds +: 32];
                end
            end else if (durum == M_WG && i < nr) begin                                   // WG
                A_gec[i] = 1'b1;
                for (j = 0; j < NB; j = j + 1) if (j < nc) A_grup[512*i + 32*j +: 32] = g[288*(i*NB + j) + 32*wq +: 32];
                A_adr[AW*i +: AW] = adres(taban_grad[AW*ll +: AW], 0, (cout + 15) / 16, kk1, cin, 9, 16*kk0 + i, wq);
            end
            if (fz == 2'd1) begin                                                          // BP: HATA[l-1] ve maske
                A_adr[AW*i +: AW]  = adres(taban_hata[AW*(ll-1) +: AW], bb, (cin + 15) / 16, kk0, h, w, R, C);
                A_madr[AW*i +: AW] = adres(taban_akt [AW*(ll-1) +: AW], bb, (cin + 15) / 16, kk0, h, w, R, C);
            end
            A_bank[4*i +: 4] = (fz == 2'd2) ? (16*kk0 + i) % 16 : R % 16;
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
    wire [NB*128-1:0] maske_gms;
    generate
        for (gi = 0; gi < NB; gi = gi + 1) begin : mgms
            gms_group16 u_g (.lms_in_flat(v_oku_veri[134*gi +: 128]), .l_in(v_oku_veri[134*gi + 128 +: 6]),
                             .G(G_akt[6*(ll-1) +: 6]), .group_out_flat(maske_gms[128*gi +: 128]), .tasma_flat());
        end
    endgenerate

    // Okuma adresi: ön-getirme meşgulken onun, değilse maske okuması (aşama A)
    integer bi_, ki;
    reg [7:0] e8, a8;
    always @* begin
        if (og_mesgul && !og_akis) v_oku_adr = og_v_adr;        // ön-getirmenin yükleme fazları
        else begin
            v_oku_adr = {NB*AW{1'b0}};
            for (bi_ = 0; bi_ < NB; bi_ = bi_ + 1)
                if (A_gec[bi_]) v_oku_adr[AW*A_bank[4*bi_ +: 4] +: AW] = A_madr[AW*bi_ +: AW];
        end
        v_yaz_en = {NB{1'b0}}; v_yaz_adr = {NB*AW{1'b0}}; v_yaz_veri = {NB*134{1'b0}};
        for (bi_ = 0; bi_ < NB; bi_ = bi_ + 1) if (B_gec[bi_]) begin
            v_yaz_en[B_bank[4*bi_ +: 4]] = 1'b1;
            v_yaz_adr[AW*B_bank[4*bi_ +: 4] +: AW] = B_adr[AW*bi_ +: AW];
            for (ki = 0; ki < 16; ki = ki + 1) begin
                e8 = B_c8[128*bi_ + 8*ki +: 8];
                a8 = maske_gms[128*B_bank[4*bi_ +: 4] + 8*ki +: 8];
                if (B_islem == 2'd1 && $signed(e8) < 0) e8 = 8'd0;                    // ReLU
                if (B_islem == 2'd2 && !($signed(a8) > 0)) e8 = 8'd0;                // ReLU-geri (D86)
                v_yaz_veri[134*B_bank[4*bi_ +: 4] + 8*ki +: 8] = e8;
            end
            v_yaz_veri[134*B_bank[4*bi_ +: 4] + 128 +: 6] = B_l[6*bi_ +: 6];
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
        if (fz != 2'd2 && !son_k && cikis_gecerli) ps_yaz = 1'b1;
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
