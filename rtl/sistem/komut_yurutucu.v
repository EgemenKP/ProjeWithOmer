// =============================================================================
//  komut_yurutucu.v — FSM'in komutlarını yürüten blok (Adım 4, arayüz sözleşmesi A2)
// -----------------------------------------------------------------------------
//  FSM (master_controller) her komutu kom_gecerli ile verir; bu blok komutu ilgili alt bloğa
//  yaptırır ve 1 çevrimlik kom_bitti verir (D50). Alt bloklar:
//    pe_motoru  : PE komutu (ön-getirme + PE + Psum FIFO + grup toplayıcı)
//    sru_top    : Egemen'in SRU'su (hedef girişi D61, 64 grup D63)
//    grup_fifo  : SRU'nun GMS akışı (A3)
//    fe_top     : ReLU / geçir / ağırlık güncelleme akış yolu ve CLU (Adım 3, D62)
//  Bellek bu bloğun dışında (bellek.v); A portunu PE motoru meşgulken motor, değilse bu blok
//  kullanır; B portu CLU'nun etiket okuması içindir; yazma portu yalnızca bu bloktadır.
//  Golden: sistem_golden.py, yorumla(). Yazan: Claude, 03.11.2026
//
//  Komutlar (TASARIM_FSM.md Bölüm 3; alanlar kom[16k +: 16], k = 0 op, 1 faz, 2 katman, 3 b,
//  4 x, 5 y, 6 z, 7 a1, 8 a2, 9 a3):
//    8 İŞ_BAŞLA : hedef <- x; SRU rst; GMS FIFO ve Psum FIFO boşaltılır; bekleyen grup silinir
//    1 PE       : PE motoru; son = 1 ise grup bekleyen kayda girer, önceki bekleyen SRU'ya itilir (A4)
//    2 ÖLÇEK    : bekleyen grup last_group = 1 ile itilir; SRU layer_done verince bitti (A4)
//    4 SA       : yalnızca bitti (s_a FSM'de)
//    3 KOPYA    : GMS FIFO'dan bir grup; FP: AKT[l][b][x][y] <- (z = 1 ise ReLU) grup;
//                 BP: HATA[l-1][b][x][satır(lar)] <- (z = 2 ise ReLU-geri, maske AKT[l-1]) grup
//    5 CLU      : AKT[L][b] (10 değer), s_a = x, ETIKET[b] -> CLU -> HATA[L][b]
//    6 WU       : GMS FIFO'dan bir grup (9 g8); AGR[l][x][y] <- doyur(AGR - g8)
//    7 BİTTİ    : yalnızca bitti
//  kom_bitti'den sonra bir çevrim daha beklenir, sonra yeni komut kabul edilir (FSM
//  kom_gecerli'yi kom_bitti'yi gördüğü kenarda indiriyor).
//
//  Yapılandırma portları (FSM'inkilerle aynı paketleme, katman li = l - 1 [8*li +: 8]):
//    cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p [LMAX*8-1:0]
//    cfg_taban_akt  [(LMAX+1)*AW-1:0] : AKT[l] tabanı, l = 0..LMAX, [AW*l +: AW]
//    cfg_taban_hata [(LMAX+1)*AW-1:0] : HATA[l] tabanı, l = 1..LMAX
//    cfg_taban_agr  [(LMAX+1)*AW-1:0] : AGR[l] tabanı, l = 1..LMAX
//    cfg_taban_etiket [AW-1:0]        : ETIKET tabanı
//  Diğer portlar:
//    maks_G [5:0]   : SRU'nun G'si, FSM'in maks_G girişine (A1)
//    hata [5:0]     : yapışkan hata bayrakları {ölçekte bekleyen grup yok, tüketicide FIFO boş,
//                     GMS FIFO eksik, GMS FIFO taşma, Psum FIFO eksik, Psum FIFO taşma}; testte 0
// =============================================================================
`timescale 1ns/1ps

module komut_yurutucu #(
    parameter AW   = 13,
    parameter LMAX = 8
) (
    input  wire                    clk,
    input  wire                    rst,
    // FSM arayüzü
    input  wire [159:0]            kom,
    input  wire                    kom_gecerli,
    output reg                     kom_bitti,
    output wire [5:0]              maks_G,
    // yapılandırma
    input  wire [LMAX*8-1:0]       cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p,
    input  wire [(LMAX+1)*AW-1:0]  cfg_taban_akt, cfg_taban_hata, cfg_taban_agr,
    input  wire [AW-1:0]           cfg_taban_etiket,
    // bellek
    output wire [AW-1:0]           oku_a_adr,
    input  wire [127:0]            oku_a_veri,
    output wire [AW-1:0]           oku_b_adr,
    input  wire [127:0]            oku_b_veri,
    output reg                     yaz,
    output reg  [AW-1:0]           yaz_adr,
    output reg  [4:0]              yaz_n,
    output reg  [127:0]            yaz_veri,
    // durum
    output wire [5:0]              hata
);

    localparam [3:0] OP_PE = 4'd1, OP_OLCEK = 4'd2, OP_KOPYA = 4'd3, OP_SA = 4'd4,
                     OP_CLU = 4'd5, OP_WU = 4'd6, OP_BITTI = 4'd7, OP_IS_BASLA = 4'd8;
    localparam [1:0] FAZ_FP = 2'd0, FAZ_BP = 2'd1, FAZ_WG = 2'd2;

    localparam [3:0] Y_BOSTA = 4'd0, Y_ISB = 4'd1, Y_PE_BASLA = 4'd2, Y_PE_BEKLE = 4'd3,
                     Y_PE_IT = 4'd4, Y_OLCEK_IT = 4'd5, Y_OLCEK_BEKLE = 4'd6, Y_KOPYA = 4'd7,
                     Y_CLU_BASLA = 4'd8, Y_CLU_BEKLE = 4'd9, Y_CLU_YAZ = 4'd10, Y_WU = 4'd11,
                     Y_SON = 4'd12, Y_ARA = 4'd13;

    reg [3:0] durum;

    // ------------------------------------------------------------------
    // Komut alanları (Y_BOSTA'da tutulur)
    // ------------------------------------------------------------------
    reg [159:0] k_r;
    wire [3:0]  k_op  = k_r[0   +: 4];
    wire [1:0]  k_faz = k_r[16  +: 2];
    wire [3:0]  k_l   = k_r[32  +: 4];
    wire [7:0]  k_b   = k_r[48  +: 8];
    wire [7:0]  k_x   = k_r[64  +: 8];
    wire [7:0]  k_y   = k_r[80  +: 8];
    wire [7:0]  k_z   = k_r[96  +: 8];
    wire        k_ilk = k_r[112];
    wire        k_son = k_r[128];

    // Katman boyutları (li = l - 1)
    wire [3:0] li   = k_l - 4'd1;
    wire [7:0] cin  = cfg_cin [8*li +: 8];
    wire [7:0] cout = cfg_cout[8*li +: 8];
    wire [7:0] h    = cfg_h   [8*li +: 8];
    wire [7:0] w    = cfg_w   [8*li +: 8];
    wire [7:0] s    = cfg_s   [8*li +: 8];
    wire [7:0] p    = cfg_p   [8*li +: 8];
    wire [9:0] h_2p = {2'b00, h} + {1'b0, p, 1'b0};
    wire [9:0] w_2p = {2'b00, w} + {1'b0, p, 1'b0};
    wire [7:0] ho   = (s == 8'd2) ? (((h_2p - 10'd3) >> 1) + 10'd1) : (h_2p - 10'd2);
    wire [7:0] wo   = (s == 8'd2) ? (((w_2p - 10'd3) >> 1) + 10'd1) : (w_2p - 10'd2);

    wire [AW-1:0] t_akt_l   = cfg_taban_akt [AW*k_l +: AW];          // AKT[l]
    wire [AW-1:0] t_akt_g   = cfg_taban_akt [AW*li  +: AW];          // AKT[l-1]
    wire [AW-1:0] t_hata_l  = cfg_taban_hata[AW*k_l +: AW];          // HATA[l]
    wire [AW-1:0] t_hata_g  = cfg_taban_hata[AW*li  +: AW];          // HATA[l-1]
    wire [AW-1:0] t_agr_l   = cfg_taban_agr [AW*k_l +: AW];          // AGR[l]

    // ------------------------------------------------------------------
    // PE motoru
    // ------------------------------------------------------------------
    wire          is_temizle = (durum == Y_ISB);
    wire          m_basla    = (durum == Y_PE_BASLA);
    wire [AW-1:0] m_oku_adr;
    wire          m_mesgul, m_bitti, m_grup_gecerli;
    wire [511:0]  m_grup;
    wire [4:0]    m_grup_n;
    wire          psum_tasma, psum_eksik;
    pe_motoru #(.AW(AW)) u_motor (
        .clk(clk), .rst(rst), .fifo_temizle(is_temizle), .basla(m_basla),
        .faz(k_faz), .kb(k_b), .kx(k_x), .ky(k_y), .kz(k_z), .ilk(k_ilk), .son(k_son),
        .cin(cin), .cout(cout), .h(h), .w(w), .s(s), .p(p), .ho(ho), .wo(wo),
        .taban_akt(t_akt_g), .taban_hata(t_hata_l), .taban_agr(t_agr_l),
        .oku_adr(m_oku_adr), .oku_veri(oku_a_veri),
        .mesgul(m_mesgul), .bitti(m_bitti), .grup_gecerli(m_grup_gecerli),
        .grup_flat(m_grup), .grup_n(m_grup_n),
        .psum_tasma(psum_tasma), .psum_eksik(psum_eksik)
    );

    // ------------------------------------------------------------------
    // SRU ve bekleyen grup (A4)
    // ------------------------------------------------------------------
    reg  [2:0]   hedef_r;
    reg  [511:0] bek_grup;
    reg  [4:0]   bek_n;
    reg          bek_var;
    wire         sru_push = (durum == Y_PE_IT) || (durum == Y_OLCEK_IT && bek_var);
    wire         sru_last = (durum == Y_OLCEK_IT);
    wire         sru_out_valid, sru_layer_done, sru_busy;
    wire [127:0] sru_out;
    wire [4:0]   sru_out_n;
    sru_top #(.MAX_GROUPS(64), .PW(7)) u_sru (
        .clk(clk), .rst(rst | is_temizle), .hedef(hedef_r),
        .push_group(sru_push), .group_in_flat(bek_grup), .group_n(bek_n), .last_group(sru_last),
        .group_out_valid(sru_out_valid), .group_out_flat(sru_out), .group_out_n(sru_out_n),
        .layer_done(sru_layer_done), .G_out(maks_G), .busy(sru_busy)
    );

    // ------------------------------------------------------------------
    // GMS çıkış FIFO'su (A3)
    // ------------------------------------------------------------------
    wire         tuketici = (durum == Y_KOPYA) || (durum == Y_WU);
    wire [127:0] g_veri;
    wire [4:0]   g_n;
    wire         g_bos, g_tasma, g_eksik;
    wire [6:0]   g_doluluk;
    grup_fifo #(.DERINLIK(64), .AW(6)) u_gfifo (
        .clk(clk), .rst(rst | is_temizle),
        .yaz(sru_out_valid), .yaz_veri(sru_out), .yaz_n(sru_out_n),
        .oku(tuketici), .bas_veri(g_veri), .bas_n(g_n), .bos(g_bos), .doluluk(g_doluluk),
        .tasma(g_tasma), .eksik(g_eksik)
    );

    // ------------------------------------------------------------------
    // Tüketicilerin adresleri
    // ------------------------------------------------------------------
    // KOPYA FP: AKT[l][b][x][y], boyutlar (cout, ho, wo)
    wire [31:0] kopya_fp_ofs = ((k_b * cout + k_x) * ho + k_y) * wo;
    // KOPYA BP: HATA[l-1][b][x][R], boyutlar (cin, h, w); stride 2'de geçerli ilk satır
    wire signed [10:0] R0 = $signed({2'b00, k_y, 1'b0}) - $signed({3'b000, p});
    wire signed [10:0] R_s2 = (R0 >= 0) ? R0 : R0 + 11'sd1;              // R0 geçersizse R1 = R0 + 1
    wire [7:0]  R_ilk  = (s == 8'd2) ? R_s2[7:0] : k_y;
    wire [31:0] kopya_bp_ofs = ((k_b * cin + k_x) * h + R_ilk) * w;
    // WU: AGR[l][x][y]
    wire [31:0] wu_ofs  = (k_x * cin + k_y) * 9;
    // CLU: AKT[L][b] ve HATA[L][b] (son katmanda ho = wo = 1, cout = 10 kanal art arda)
    wire [31:0] clu_ofs = k_b * cout * ho * wo;

    reg [AW-1:0] y_oku_a_adr;
    always @* begin
        case (durum)
            Y_KOPYA:     y_oku_a_adr = t_akt_g + kopya_bp_ofs[AW-1:0];   // BP maskesi (FP'de kullanılmaz)
            Y_WU:        y_oku_a_adr = t_agr_l + wu_ofs[AW-1:0];
            default:     y_oku_a_adr = t_akt_l + clu_ofs[AW-1:0];        // CLU aktivasyonları
        endcase
    end
    assign oku_a_adr = m_mesgul ? m_oku_adr : y_oku_a_adr;
    assign oku_b_adr = cfg_taban_etiket + k_b;

    // ------------------------------------------------------------------
    // Fonksiyon motoru
    // ------------------------------------------------------------------
    reg  [1:0]  fe_mod;
    always @* begin
        fe_mod = 2'd0;
        if (durum == Y_WU)
            fe_mod = 2'd3;
        else if (durum == Y_KOPYA) begin
            if (k_faz == FAZ_FP && k_z == 8'd1)      fe_mod = 2'd1;   // ReLU ileri
            else if (k_faz == FAZ_BP && k_z == 8'd2) fe_mod = 2'd2;   // ReLU geri
        end
    end
    wire [127:0] fe_cikis;
    wire [79:0]  clu_e;
    wire         clu_bitti, clu_mesgul;
    wire [3:0]   etiket = oku_b_veri[3:0];
    fe_top #(.N(16), .CLU_BEKLEME(77)) u_fe (
        .clk(clk), .rst(rst),
        .mod(fe_mod), .veri_flat(g_veri), .maske_flat(oku_a_veri), .w_flat(oku_a_veri),
        .cikis_flat(fe_cikis),
        .clu_basla(durum == Y_CLU_BASLA), .clu_a_flat(oku_a_veri[79:0]), .clu_sa(k_x),
        .clu_y_onehot(10'd1 << etiket), .clu_e_flat(clu_e),
        .clu_bitti(clu_bitti), .clu_mesgul(clu_mesgul)
    );

    // ------------------------------------------------------------------
    // Hata bayrakları
    // ------------------------------------------------------------------
    reg h_olcek, h_tuketici;
    assign hata = {h_olcek, h_tuketici, g_eksik, g_tasma, psum_eksik, psum_tasma};

    // ------------------------------------------------------------------
    // Durum makinesi
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            durum <= Y_BOSTA;
            kom_bitti <= 1'b0;
            k_r <= 160'd0;
            hedef_r <= 3'd7;
            bek_grup <= 512'd0; bek_n <= 5'd0; bek_var <= 1'b0;
            yaz <= 1'b0; yaz_adr <= {AW{1'b0}}; yaz_n <= 5'd0; yaz_veri <= 128'd0;
            h_olcek <= 1'b0; h_tuketici <= 1'b0;
        end else begin
            kom_bitti <= 1'b0;
            yaz <= 1'b0;
            case (durum)
                Y_BOSTA: begin
                    if (kom_gecerli) begin
                        k_r <= kom;
                        case (kom[3:0])
                            OP_IS_BASLA: durum <= Y_ISB;
                            OP_PE:       durum <= Y_PE_BASLA;
                            OP_OLCEK:    durum <= Y_OLCEK_IT;
                            OP_KOPYA:    durum <= Y_KOPYA;
                            OP_CLU:      durum <= Y_CLU_BASLA;
                            OP_WU:       durum <= Y_WU;
                            default:     durum <= Y_SON;              // SA, BİTTİ
                        endcase
                    end
                end
                Y_ISB: begin                                         // SRU, GMS FIFO, Psum FIFO temizlenir
                    hedef_r <= k_x[2:0];
                    bek_var <= 1'b0;
                    durum   <= Y_SON;
                end
                Y_PE_BASLA: durum <= Y_PE_BEKLE;                     // motor basla'yı bu çevrimde gördü
                Y_PE_BEKLE: begin
                    if (m_bitti) begin
                        if (m_grup_gecerli && bek_var) durum <= Y_PE_IT;
                        else begin
                            if (m_grup_gecerli) begin
                                bek_grup <= m_grup; bek_n <= m_grup_n; bek_var <= 1'b1;
                            end
                            durum <= Y_SON;
                        end
                    end
                end
                Y_PE_IT: begin                                       // eski bekleyen SRU'ya (sru_push = 1)
                    bek_grup <= m_grup; bek_n <= m_grup_n; bek_var <= 1'b1;
                    durum <= Y_SON;
                end
                Y_OLCEK_IT: begin                                    // bekleyen grup last_group = 1 ile itilir
                    bek_var <= 1'b0;
                    if (bek_var) durum <= Y_OLCEK_BEKLE;
                    else begin                                       // itilecek grup yok: hata, takılmadan bitir
                        h_olcek <= 1'b1;
                        durum   <= Y_SON;
                    end
                end
                Y_OLCEK_BEKLE: begin                                 // GMS akışı FIFO'ya yazılıyor
                    if (sru_layer_done) durum <= Y_SON;
                end
                Y_KOPYA: begin                                       // GMS FIFO'dan bir grup (tuketici = 1)
                    if (g_bos) h_tuketici <= 1'b1;
                    yaz      <= 1'b1;
                    yaz_n    <= g_n;
                    yaz_veri <= fe_cikis;
                    yaz_adr  <= (k_faz == FAZ_FP) ? t_akt_l + kopya_fp_ofs[AW-1:0]
                                                  : t_hata_g + kopya_bp_ofs[AW-1:0];
                    durum    <= Y_SON;
                end
                Y_CLU_BASLA: durum <= Y_CLU_BEKLE;                   // fe_top girişleri bu kenarda tuttu
                Y_CLU_BEKLE: begin
                    if (clu_bitti) durum <= Y_CLU_YAZ;
                end
                Y_CLU_YAZ: begin
                    yaz      <= 1'b1;
                    yaz_n    <= 5'd10;
                    yaz_veri <= {48'd0, clu_e};
                    yaz_adr  <= t_hata_l + clu_ofs[AW-1:0];
                    durum    <= Y_SON;
                end
                Y_WU: begin                                          // GMS FIFO'dan 9 g8 (tuketici = 1)
                    if (g_bos) h_tuketici <= 1'b1;
                    yaz      <= 1'b1;
                    yaz_n    <= 5'd9;
                    yaz_veri <= fe_cikis;
                    yaz_adr  <= t_agr_l + wu_ofs[AW-1:0];
                    durum    <= Y_SON;
                end
                Y_SON: begin                                         // kom_bitti darbesi
                    kom_bitti <= 1'b1;
                    durum     <= Y_ARA;
                end
                Y_ARA: durum <= Y_BOSTA;                             // FSM kom_gecerli'yi bu kenarda indirir
                default: durum <= Y_BOSTA;
            endcase
        end
    end

endmodule
