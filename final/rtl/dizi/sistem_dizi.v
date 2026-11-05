// =============================================================================
//  sistem_dizi.v — 16x16 dizili tam sistem (Shao Fig. 8; Adım 5b-3e, D93)
// -----------------------------------------------------------------------------
//  Bloklar (Fig. 8):
//    Master Controller : master_controller_dizi (D92)
//    PE dizisi + ön-getirme + SRU'lar (LMS) : dizi_motoru (D91)
//    Input/Output Buffer : veri_tamponu (D80, D81) — tek tampon, iki yüz
//    Weight Buffer : agirlik_tamponu (D82)
//    Function Engine : fe_top'un CLU'su (Egemen'in CLU'su, D60, D62) ve wu_unit (D41); ReLU / ReLU-geri
//                      motorun yazma yolunda (D83, D86)
//  Komut yürütücü (bu modülde): FSM'in komutlarını alt bloklara yaptırır, bitince kom_bitti (D50).
//    İŞ_BAŞLA : motora is_basla (hedef)
//    DİZİ     : motor
//    ÖLÇEK    : motorun G'si işin yazdığı bölgenin G register'ına (FP l: AKT[l], BP l: HATA[l-1], WG l: GRAD[l])
//    SA       : yalnızca bitti (s_a FSM'de)
//    CLU      : AKT[L] kelimesi (b) GMS'ten geçer -> CLU (s_a, etiket[b]) -> HATA[L] kelimesi (l = 0; HATA[L]'nin G'si 0)
//    WU       : sütun bankalarından 16 ağırlık kelimesi, bank (c mod 16)'dan 9 GRAD kelimesi (GMS, hedef m_u), 9 wu_unit,
//               16 bankaya geri yazma (D41: ±127)
//    BİTTİ    : yalnızca bitti
//  Tamponların dış portları (dis_aktif = 1 iken): testbench yükler ve sonuçları okur.
//  Golden: dizi_sistem_golden.py. Yazan: Claude, 04.11.2026 (final/, Adım 5b-3e)
// =============================================================================
`timescale 1ns/1ps

module sistem_dizi #(
    parameter NB   = 16,
    // D103: VGG16-like ölçeği (14 katman, 512 kanal, batch 256); AW 13: tampon bank başına 8192 kelime
    parameter AW   = 13,
    parameter LMAX = 15,
    parameter BMAX = 256
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     basla,
    output wire                     bitti,
    output wire                     mesgul,
    // yapılandırma
    input  wire [3:0]               cfg_L,
    input  wire [15:0]              cfg_batch,                 // D103: 16 bit
    input  wire [3:0]               cfg_m_u,
    input  wire [7:0]               cfg_s_a0,
    input  wire [LMAX*16-1:0]       cfg_cin, cfg_cout,         // D103: katman başına 16 bit
    input  wire [LMAX*8-1:0]        cfg_h, cfg_w, cfg_s, cfg_p, cfg_relu, cfg_sw,
    input  wire [(LMAX+1)*AW-1:0]   taban_akt, taban_hata, taban_grad, taban_agr,
    input  wire [BMAX*4-1:0]        cfg_etiket,
    // bölge G'leri (izleme)
    output reg  [(LMAX+1)*6-1:0]    G_akt, G_hata, G_grad,
    output wire                     ps_tasma, ps_eksik,
    // tamponların dış portları
    input  wire                     dis_aktif,
    input  wire [NB*AW-1:0]         dis_v_oku_adr,
    output wire [NB*134-1:0]        dis_v_oku_veri,
    input  wire [NB-1:0]            dis_v_yaz_en,
    input  wire [NB*AW-1:0]         dis_v_yaz_adr,
    input  wire [NB*134-1:0]        dis_v_yaz_veri,
    input  wire [NB*AW-1:0]         dis_a_oku_adr,
    output wire [NB*72-1:0]         dis_a_oku_veri,
    input  wire [NB-1:0]            dis_a_yaz_en,
    input  wire [NB*AW-1:0]         dis_a_yaz_adr,
    input  wire [NB*72-1:0]         dis_a_yaz_veri
);

    localparam KAW = 16;
    // ---- FSM ----
    wire              kom_gecerli;
    wire [10*KAW-1:0] kom;
    reg               kom_bitti;
    wire [5:0]        G_motor;
    master_controller_dizi #(.AW(KAW), .LMAX(LMAX), .CW(16)) u_fsm (
        .clk(clk), .rst(rst), .basla(basla), .cfg_L(cfg_L), .cfg_batch(cfg_batch), .cfg_m_u(cfg_m_u),
        .cfg_s_a0(cfg_s_a0), .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s),
        .cfg_p(cfg_p), .cfg_relu(cfg_relu), .cfg_sw(cfg_sw), .maks_G(G_motor), .kom_bitti(kom_bitti),
        .kom_gecerli(kom_gecerli), .kom(kom), .mesgul(mesgul), .bitti(bitti));

    wire [3:0] k_op  = kom[0 +: 4];
    wire [1:0] k_faz = kom[KAW*1 +: 2];
    wire [3:0] k_l   = kom[KAW*2 +: 4];
    wire [7:0] k_b   = kom[KAW*3 +: 8];
    wire [7:0] k_x   = kom[KAW*4 +: 8];
    wire [15:0] k_y  = kom[KAW*5 +: 16];               // D103: kanal (≤ 511)
    wire [7:0] k_z   = kom[KAW*6 +: 8];
    wire       k_a1  = kom[KAW*7];
    wire       k_a2  = kom[KAW*8];

    // ---- tamponlar ----
    wire [NB*AW-1:0]  m_v_adr, m_v_yaz_adr, m_a_adr;
    wire [NB-1:0]     m_v_yaz_en;
    wire [NB*134-1:0] m_v_yaz_veri, v_veri;
    wire [NB*72-1:0]  a_veri;
    reg  [NB*AW-1:0]  y_v_adr, y_a_adr, y_v_yaz_adr, y_a_yaz_adr;
    reg  [NB-1:0]     y_v_yaz_en, y_a_yaz_en;
    reg  [NB*134-1:0] y_v_yaz_veri;
    reg  [NB*72-1:0]  y_a_yaz_veri;
    wire              m_mesgul;

    veri_tamponu #(.NB(NB), .AW(AW)) u_vt (.clk(clk),
        .oku_adr (dis_aktif ? dis_v_oku_adr  : m_mesgul ? m_v_adr      : y_v_adr),
        .oku_veri(v_veri),
        .yaz_en  (dis_aktif ? dis_v_yaz_en   : m_mesgul ? m_v_yaz_en   : y_v_yaz_en),
        .yaz_adr (dis_aktif ? dis_v_yaz_adr  : m_mesgul ? m_v_yaz_adr  : y_v_yaz_adr),
        .yaz_veri(dis_aktif ? dis_v_yaz_veri : m_mesgul ? m_v_yaz_veri : y_v_yaz_veri));
    agirlik_tamponu #(.NB(NB), .AW(AW)) u_at (.clk(clk),
        .oku_adr (dis_aktif ? dis_a_oku_adr  : m_mesgul ? m_a_adr : y_a_adr),
        .oku_veri(a_veri),
        .yaz_en  (dis_aktif ? dis_a_yaz_en   : y_a_yaz_en),
        .yaz_adr (dis_aktif ? dis_a_yaz_adr  : y_a_yaz_adr),
        .yaz_veri(dis_aktif ? dis_a_yaz_veri : y_a_yaz_veri));
    assign dis_v_oku_veri = v_veri;
    assign dis_a_oku_veri = a_veri;

    // ---- GMS (yürütücünün okumaları: CLU'nun AKT[L]'si, WU'nun GRAD'ı) ----
    // D100: ayrı bir takım yok; ön-getirmedeki tek GMS takımı (Fig. 6), G = y_G. Okuma portunu bir önceki çevrimde
    // yürütücü kullandıysa (dış port ve motor boştaysa) bu çevrimin verisi onun.
    reg  [5:0]        y_G;
    wire [NB*128-1:0] y_gms;
    reg               y_sahip_r;
    initial y_sahip_r = 1'b0;
    always @(posedge clk) y_sahip_r <= !dis_aktif && !m_mesgul;

    // ---- dizi motoru ----
    reg m_is_basla, m_basla;
    wire m_bitti;
    dizi_motoru #(.NB(NB), .AW(AW), .LMAX(LMAX)) u_motor (
        .clk(clk), .rst(rst), .is_basla(m_is_basla), .hedef_in(k_x[2:0]), .basla(m_basla), .faz(k_faz),
        .l(k_l), .b(k_b), .k0(k_x), .k1(k_y), .z(k_z), .ilk(k_a1), .son(k_a2), .bitti(m_bitti),
        .mesgul(m_mesgul), .G_out(G_motor), .ps_tasma(ps_tasma), .ps_eksik(ps_eksik), .ps_bos(),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s), .cfg_p(cfg_p),
        .cfg_relu(cfg_relu), .taban_akt(taban_akt), .taban_hata(taban_hata), .taban_grad(taban_grad),
        .taban_agr(taban_agr), .G_akt(G_akt), .G_hata(G_hata),
        .v_oku_adr(m_v_adr), .v_oku_veri(v_veri), .v_yaz_en(m_v_yaz_en), .v_yaz_adr(m_v_yaz_adr),
        .v_yaz_veri(m_v_yaz_veri), .a_oku_adr(m_a_adr), .a_oku_veri(a_veri),
        .sis_G_sec(y_sahip_r), .sis_G(y_G), .gms_flat(y_gms));


    // ---- CLU (fe_top'un CLU yolu) ----
    reg          clu_basla;
    reg  [79:0]  clu_a;
    wire [79:0]  clu_e;
    wire         clu_bitti;
    fe_top #(.N(16), .CLU_BEKLEME(77)) u_fe (
        .clk(clk), .rst(rst), .mod(2'd0), .veri_flat(128'd0), .maske_flat(128'd0), .w_flat(128'd0), .cikis_flat(),
        .clu_basla(clu_basla), .clu_a_flat(clu_a), .clu_sa(k_x), .clu_y_onehot(10'd1 << cfg_etiket[4*k_b +: 4]),
        .clu_e_flat(clu_e), .clu_bitti(clu_bitti), .clu_mesgul());

    // ---- WU ----
    reg  [71:0]  wu_w [0:NB-1];            // sütun j'nin (o = 16·karo + j) 9 ağırlığı
    reg  [127:0] wu_g [0:8];               // GMS'li gradyan: q -> 16 çıkış kanalı
    wire [127:0] wu_yeni [0:8];
    genvar gq, gj;
    generate
        for (gq = 0; gq < 9; gq = gq + 1) begin : wu
            wire [127:0] wq;
            for (gj = 0; gj < NB; gj = gj + 1) begin : w
                assign wq[8*gj +: 8] = wu_w[gj][8*gq +: 8];
            end
            wu_unit #(.N(16)) u_wu (.w_flat(wq), .g_flat(wu_g[gq]), .w_yeni_flat(wu_yeni[gq]));
        end
    endgenerate

    // ---- katman boyutları (yürütücü) ----
    integer cin, cout, L, no;
    always @* begin
        cin  = cfg_cin [16*(k_l-1) +: 16];
        cout = cfg_cout[16*(k_l-1) +: 16];
        L    = cfg_L;
        no   = cout - 16*k_x;
        if (no > 16) no = 16;
    end

    // D96 (Adım 5c-b): adresler (D81, AW bitte sarar). CLU: AKT[L] / HATA[L] (1×1 harita, tek karo) -> taban + b.
    // WU: ağırlık taban + o-karo·cin + c; GRAD[l] taban + (o-karo·⌈cin/16⌉ + c/16)·9 + q. Komut boyunca sabit
    // (kom register'ı), tek çarpım kopyası.
    wire [15:0]   cin8      = cfg_cin[16*(k_l-1) +: 16];      // (ad tarihsel; D103'ten beri 16 bit)
    wire [AW-1:0] clu_a_adr = taban_akt [AW*cfg_L +: AW] + k_b;
    wire [AW-1:0] clu_e_adr = taban_hata[AW*cfg_L +: AW] + k_b;
    wire [AW-1:0] wu_a_adr  = taban_agr[AW*k_l +: AW] + k_x * cin8 + k_y;
    wire [AW-1:0] wu_g_bas  = taban_grad[AW*k_l +: AW] + (k_x * ((cin8 + 16'd15) >> 4) + (k_y >> 4)) * 4'd9;

    // ---- yürütücü ----
    localparam Y_BOS = 4'd0, Y_DIZI = 4'd1, Y_CLU_OKU = 4'd2, Y_CLU_AL = 4'd3, Y_CLU_BEKLE = 4'd4,
               Y_WU = 4'd5, Y_WU_YAZ = 4'd6, Y_BITTI = 4'd7, Y_BEKLE = 4'd8;
    reg [3:0] yd;
    reg [3:0] wq_say;                       // WU: okunan GRAD kelimesi (0..9)
    integer   jj, qq;

    // okuma / yazma adresleri (saatsiz)
    always @* begin
        y_v_adr = {NB*AW{1'b0}}; y_a_adr = {NB*AW{1'b0}};
        y_v_yaz_en = {NB{1'b0}}; y_v_yaz_adr = {NB*AW{1'b0}}; y_v_yaz_veri = {NB*134{1'b0}};
        y_a_yaz_en = {NB{1'b0}}; y_a_yaz_adr = {NB*AW{1'b0}}; y_a_yaz_veri = {NB*72{1'b0}};
        case (yd)
            Y_CLU_OKU: y_v_adr[0 +: AW] = clu_a_adr;
            Y_WU: begin
                for (jj = 0; jj < NB; jj = jj + 1)
                    y_a_adr[AW*jj +: AW] = wu_a_adr;
                if (wq_say < 9)
                    y_v_adr[AW*k_y[3:0] +: AW] = wu_g_bas + wq_say;
            end
            Y_WU_YAZ: begin
                for (jj = 0; jj < NB; jj = jj + 1) if (jj < no) begin
                    y_a_yaz_en[jj] = 1'b1;
                    y_a_yaz_adr[AW*jj +: AW] = wu_a_adr;
                    for (qq = 0; qq < 9; qq = qq + 1) y_a_yaz_veri[72*jj + 8*qq +: 8] = wu_yeni[qq][8*jj +: 8];
                end
            end
            Y_CLU_BEKLE: if (clu_bitti) begin
                y_v_yaz_en[0] = 1'b1;
                y_v_yaz_adr[0 +: AW] = clu_e_adr;
                y_v_yaz_veri[0 +: 134] = {6'd0, 48'd0, clu_e};
            end
            default: ;
        endcase
        // GMS'in G'si: CLU'da AKT[L], WU'da GRAD[l]
        y_G = (yd == Y_WU) ? G_grad[6*k_l +: 6] : G_akt[6*L +: 6];
    end

    always @(posedge clk) begin
        kom_bitti <= 1'b0; m_is_basla <= 1'b0; m_basla <= 1'b0; clu_basla <= 1'b0;
        if (rst) begin
            yd <= Y_BOS; G_akt <= 0; G_hata <= 0; G_grad <= 0;
        end else begin
            if (basla) begin G_akt <= 0; G_hata <= 0; G_grad <= 0; end
            case (yd)
                Y_BOS: if (kom_gecerli) begin
                    case (k_op)
                        4'd8: begin m_is_basla <= 1'b1; yd <= Y_BITTI; end
                        4'd1: begin m_basla <= 1'b1; yd <= Y_DIZI; end
                        4'd2: begin
                            case (k_faz)
                                2'd0:    G_akt [6*k_l +: 6]       <= G_motor;
                                2'd1:    G_hata[6*(k_l - 1) +: 6] <= G_motor;
                                default: G_grad[6*k_l +: 6]       <= G_motor;
                            endcase
                            yd <= Y_BITTI;
                        end
                        4'd5: yd <= Y_CLU_OKU;
                        4'd6: begin yd <= Y_WU; wq_say <= 4'd0; end
                        default: yd <= Y_BITTI;                 // SA, BİTTİ
                    endcase
                end
                Y_DIZI: if (m_bitti) yd <= Y_BITTI;
                Y_CLU_OKU: yd <= Y_CLU_AL;                         // okuma verisi bir sonraki çevrimde
                Y_CLU_AL: begin
                    clu_a <= y_gms[79:0]; clu_basla <= 1'b1; yd <= Y_CLU_BEKLE;
                end
                Y_CLU_BEKLE: if (clu_bitti) yd <= Y_BITTI;           // yazma bu çevrimde (saatsiz)
                Y_WU: begin                                          // çevrim t: GRAD q = t okunur, t-1 yakalanır
                    if (wq_say == 4'd1)
                        for (jj = 0; jj < NB; jj = jj + 1) wu_w[jj] <= (jj < no) ? a_veri[72*jj +: 72] : 72'd0;
                    if (wq_say >= 4'd1) wu_g[wq_say - 1] <= y_gms[128*(k_y % 16) +: 128];
                    if (wq_say == 4'd9) yd <= Y_WU_YAZ;
                    wq_say <= wq_say + 4'd1;
                end
                Y_WU_YAZ: yd <= Y_BITTI;                             // yazma bu çevrimde
                Y_BITTI: begin kom_bitti <= 1'b1; yd <= Y_BEKLE; end
                Y_BEKLE: yd <= Y_BOS;                                // FSM kom_gecerli'yi indiriyor
                default: yd <= Y_BOS;
            endcase
        end
    end

endmodule
