`timescale 1ns/1ps
// =============================================================================
//  master_controller.v — Ana denetleyici (Master Controller, FSM)
// -----------------------------------------------------------------------------
//  Bir eğitim adımının komut sırasını üretir (TASARIM_FSM.md Bölüm 3-7):
//    İLERİ  katman 1..L : İŞ_BAŞLA, PE geçişleri, ÖLÇEK, SA, KOPYA'lar
//    CLU    örnek 0..B-1
//    GERİ   katman L..1 : (l > 1 ise) İŞ_BAŞLA, PE, ÖLÇEK, KOPYA'lar;
//                         sonra İŞ_BAŞLA, PE, ÖLÇEK, WU'lar
//    BİTTİ
//  Kendisi veri işlemez. Her komutu verir ve kom_bitti gelene kadar bekler (T5).
//  Döngü sırası (T1): FP o→c→b→r, BP c→o→b→p, WG o→c→b→r (k0 en dış, k3 en iç).
//
//  Portlar:
//    clk                    saat
//    rst                    eşzamanlı, aktif-yüksek reset
//    basla                  1 çevrimlik darbe; BOSTA ya da SON durumunda eğitim adımını başlatır
//    cfg_L      [3:0]       katman sayısı L (1..LMAX)
//    cfg_batch  [7:0]       örnek sayısı B (en az 1)
//    cfg_m_u    [3:0]       gradyan hedef genişliği m_u (NITI)
//    cfg_s_a0   [7:0]       giriş aktivasyonunun ölçek üssü, işaretli
//    cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p, cfg_relu, cfg_sw   [LMAX*8-1:0]
//                           katman tablosu (ag_yapilandirma.txt). Katman l'nin (1'den başlar)
//                           değeri [8*(l-1) +: 8] bitlerinde. cfg_s 1 ya da 2; cfg_relu 0/1;
//                           cfg_sw işaretli. cfg_w FSM'de kullanılmıyor (tablo bütünlüğü için).
//    maks_G     [5:0]       Max Regs'in G çıkışı; ÖLÇEK komutu bitince örneklenir
//    kom_bitti              1 çevrimlik darbe: geçerli komutun işi bitti
//    kom_gecerli            komut geçerli (seviye). Her komut için bir kez yükselir; iki komut
//                           arasında en az 1 çevrim 0 olur.
//    kom        [10*AW-1:0] komut. Alan i, [AW*i +: AW] bitlerinde, ikiye tümleyen:
//                           0 op, 1 faz, 2 katman, 3 b, 4 x, 5 y, 6 z, 7 a1, 8 a2, 9 a3
//                           (komutlar.txt ile aynı sıra). kom_gecerli 1 iken sabittir.
//    mesgul                 BOSTA ve SON dışındaki durumlarda 1
//    bitti                  BİTTİ komutu tamamlanınca 1; yeni basla'ya kadar 1 kalır
//  Parametreler: AW komut alanı genişliği, LMAX en çok katman, CW döngü sayacı genişliği,
//                HEDEF_AKT a ve e için SRU hedef genişliği.
//  Verilog-2001. Hazırlayan: Claude (Ömer'in isteğiyle), 02.11.2026
// =============================================================================
module master_controller #(
    parameter AW        = 16,
    parameter LMAX      = 8,
    parameter CW        = 8,
    parameter HEDEF_AKT = 7
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              basla,
    input  wire [3:0]        cfg_L,
    input  wire [7:0]        cfg_batch,
    input  wire [3:0]        cfg_m_u,
    input  wire [7:0]        cfg_s_a0,
    input  wire [LMAX*8-1:0] cfg_cin,
    input  wire [LMAX*8-1:0] cfg_cout,
    input  wire [LMAX*8-1:0] cfg_h,
    input  wire [LMAX*8-1:0] cfg_w,
    input  wire [LMAX*8-1:0] cfg_s,
    input  wire [LMAX*8-1:0] cfg_p,
    input  wire [LMAX*8-1:0] cfg_relu,
    input  wire [LMAX*8-1:0] cfg_sw,
    input  wire [5:0]        maks_G,
    input  wire              kom_bitti,
    output reg               kom_gecerli,
    output reg  [10*AW-1:0]  kom,
    output wire              mesgul,
    output reg               bitti
);

    // Komut kodları (komutlar.txt ile aynı)
    localparam [3:0] OP_PE = 4'd1, OP_OLCEK = 4'd2, OP_KOPYA = 4'd3, OP_SA = 4'd4,
                     OP_CLU = 4'd5, OP_WU = 4'd6, OP_BITTI = 4'd7, OP_IS_BASLA = 4'd8;
    localparam [1:0] FAZ_FP = 2'd0, FAZ_BP = 2'd1, FAZ_WG = 2'd2;
    // Durumlar
    localparam [3:0] D_BOSTA = 4'd0, D_IS_BASLA = 4'd1, D_PE = 4'd2, D_OLCEK = 4'd3,
                     D_SA = 4'd4, D_TUKET = 4'd5, D_CLU = 4'd6, D_BITTI = 4'd7, D_SON = 4'd8;

    reg [3:0]           durum;
    reg [1:0]           faz;
    reg [3:0]           katman;          // 1'den başlar
    reg [CW-1:0]        k0, k1, k2, k3;  // döngü sayaçları: k0 en dış, k3 en iç
    reg [AW-1:0]        grup;            // grup sayacı
    reg signed [AW-1:0] s_a;             // aktivasyonun ölçek üssü
    reg [5:0]           G;               // son ÖLÇEK'in G'si

    // ---- Geçerli katmanın tablo değerleri ----
    wire [3:0] li        = katman - 4'd1;
    wire [3:0] li_once   = (katman >= 4'd2) ? (katman - 4'd2) : 4'd0;   // önceki katman (BP KOPYA)
    wire [7:0] cin       = cfg_cin [8*li +: 8];
    wire [7:0] cout      = cfg_cout[8*li +: 8];
    wire [7:0] h         = cfg_h   [8*li +: 8];
    wire [7:0] s         = cfg_s   [8*li +: 8];
    wire [7:0] p         = cfg_p   [8*li +: 8];
    wire [7:0] sw        = cfg_sw  [8*li +: 8];
    wire       relu      = cfg_relu[8*li];
    wire       relu_once = cfg_relu[8*li_once];

    // Çıkış yüksekliği Ho = (h + 2p - 3)/s + 1; BP geçiş sayısı: s=1'de h, s=2'de ceil((h+p)/2) (T6)
    wire [9:0] h_2p  = {2'b00, h} + {1'b0, p, 1'b0};
    wire [9:0] ho_s1 = h_2p - 10'd2;
    wire [9:0] ho_s2 = ((h_2p - 10'd3) >> 1) + 10'd1;
    wire [7:0] ho    = (s == 8'd2) ? ho_s2[7:0] : ho_s1[7:0];
    wire [9:0] np_s2 = ({2'b00, h} + {2'b00, p} + 10'd1) >> 1;
    wire [7:0] npass = (s == 8'd2) ? np_s2[7:0] : h;

    // ---- Döngü sınırları ----
    //   PE   FP: (Cout, Cin, B, Ho)   BP: (Cin, Cout, B, npass)   WG: (Cout, Cin, B, Ho)
    //   KOPYA FP: (Cout, 1, B, Ho)    BP: (Cin, 1, B, npass)      WU: (Cout, Cin, 1, 1)
    //   CLU (1, 1, B, 1)
    //   Tüketici döngüsü, üreticinin 'son' geçişlerini aynı sırayla dolaşır.
    reg [CW-1:0] n0, n1, n2, n3;
    always @* begin
        n0 = 1; n1 = 1; n2 = 1; n3 = 1;
        case (durum)
            D_PE: begin
                n2 = cfg_batch;
                if (faz == FAZ_BP) begin
                    n0 = cin;  n1 = cout; n3 = npass;
                end else begin
                    n0 = cout; n1 = cin;  n3 = ho;
                end
            end
            D_TUKET: begin
                if (faz == FAZ_WG) begin
                    n0 = cout; n1 = cin;
                end else if (faz == FAZ_BP) begin
                    n0 = cin;  n2 = cfg_batch; n3 = npass;
                end else begin
                    n0 = cout; n2 = cfg_batch; n3 = ho;
                end
            end
            D_CLU:   n2 = cfg_batch;
            default: ;
        endcase
    end

    wire son_k0    = (k0 == n0 - 1'b1);
    wire son_k1    = (k1 == n1 - 1'b1);
    wire son_k2    = (k2 == n2 - 1'b1);
    wire son_k3    = (k3 == n3 - 1'b1);
    wire dongu_son = son_k0 & son_k1 & son_k2 & son_k3;

    // Sayaçların bir sonraki değeri (k3 en içte; döngü bitince hepsi 0'a döner)
    reg [CW-1:0] k0_s, k1_s, k2_s, k3_s;
    always @* begin
        k0_s = k0; k1_s = k1; k2_s = k2; k3_s = k3;
        if (!son_k3) k3_s = k3 + 1'b1;
        else begin
            k3_s = 0;
            if (!son_k2) k2_s = k2 + 1'b1;
            else begin
                k2_s = 0;
                if (!son_k1) k1_s = k1 + 1'b1;
                else begin
                    k1_s = 0;
                    if (!son_k0) k0_s = k0 + 1'b1;
                    else         k0_s = 0;
                end
            end
        end
    end

    // PE geçişinin bayrakları: FP/BP'de FIFO k1 boyunca, WG'de akümülatör (k2, k3) boyunca toplar
    wire pe_ilk = (faz == FAZ_WG) ? ((k2 == 0) && (k3 == 0)) : (k1 == 0);
    wire pe_son = (faz == FAZ_WG) ? (son_k2 & son_k3) : son_k1;

    // ---- Komut alanları ----
    wire [3:0]           hedef_akt = HEDEF_AKT;
    wire [3:0]           hedef     = (faz == FAZ_WG) ? cfg_m_u : hedef_akt;
    wire [1:0]           islem     = (faz == FAZ_FP) ? (relu ? 2'd1 : 2'd0)       // ReLU ileri
                                                     : (relu_once ? 2'd2 : 2'd0); // ReLU geri
    wire signed [AW-1:0] sw_g      = {{(AW-8){sw[7]}}, sw};
    wire signed [AW-1:0] s_a_yeni  = s_a + sw_g + {{(AW-6){1'b0}}, G};           // s_a + s_w + G

    reg [AW-1:0] f_op, f_faz, f_kat, f_b, f_x, f_y, f_z, f_a1, f_a2, f_a3;
    always @* begin
        f_op = 0; f_faz = 0; f_kat = 0; f_b = 0; f_x = 0; f_y = 0; f_z = 0;
        f_a1 = 0; f_a2 = 0; f_a3 = 0;
        case (durum)
            D_IS_BASLA: begin
                f_op = OP_IS_BASLA; f_faz = faz; f_kat = katman; f_x = hedef;
            end
            D_PE: begin
                f_op = OP_PE; f_faz = faz; f_kat = katman;
                f_b  = k2; f_x = k0; f_y = k1; f_z = k3;
                f_a1 = pe_ilk; f_a2 = pe_son;
                f_a3 = pe_son ? grup : {AW{1'b1}};          // son değilse -1
            end
            D_OLCEK: begin
                f_op = OP_OLCEK; f_faz = faz; f_kat = katman; f_a1 = grup;   // grup sayısı
            end
            D_SA: begin
                f_op = OP_SA; f_kat = katman; f_x = s_a_yeni;
            end
            D_TUKET: begin
                f_faz = faz; f_kat = katman; f_x = k0; f_a1 = grup;
                if (faz == FAZ_WG) begin
                    f_op = OP_WU; f_y = k1;                              // (o, c)
                end else begin
                    f_op = OP_KOPYA; f_b = k2; f_y = k3; f_z = islem;   // (kanal, b, satır)
                end
            end
            D_CLU: begin
                f_op = OP_CLU; f_kat = cfg_L; f_b = k2; f_x = s_a;
            end
            D_BITTI: f_op = OP_BITTI;
            default: ;
        endcase
    end
    wire [10*AW-1:0] kom_sonraki = {f_a3, f_a2, f_a1, f_z, f_y, f_x, f_b, f_kat, f_faz, f_op};

    assign mesgul = (durum != D_BOSTA) && (durum != D_SON);

    // ---- Durum makinesi ----
    //   kom_gecerli = 0 iken: yeni komutu ver (BOSTA/SON'da basla'yı bekle).
    //   kom_gecerli = 1 iken: kom_bitti gelince komutu indir, sayaçları ve durumu ilerlet.
    always @(posedge clk) begin
        if (rst) begin
            durum       <= D_BOSTA;
            kom_gecerli <= 1'b0;
            kom         <= {10*AW{1'b0}};
            bitti       <= 1'b0;
            faz         <= FAZ_FP;
            katman      <= 4'd1;
            k0 <= 0; k1 <= 0; k2 <= 0; k3 <= 0;
            grup        <= 0;
            s_a         <= 0;
            G           <= 6'd0;
        end else if (!kom_gecerli) begin
            if (durum == D_BOSTA || durum == D_SON) begin
                if (basla) begin
                    durum  <= D_IS_BASLA;
                    faz    <= FAZ_FP;
                    katman <= 4'd1;
                    s_a    <= {{(AW-8){cfg_s_a0[7]}}, cfg_s_a0};
                    bitti  <= 1'b0;
                    k0 <= 0; k1 <= 0; k2 <= 0; k3 <= 0;
                    grup   <= 0;
                end
            end else begin
                kom_gecerli <= 1'b1;
                kom         <= kom_sonraki;
            end
        end else if (kom_bitti) begin
            kom_gecerli <= 1'b0;
            case (durum)
                D_IS_BASLA: begin
                    durum <= D_PE;
                    grup  <= 0;
                    k0 <= 0; k1 <= 0; k2 <= 0; k3 <= 0;
                end
                D_PE: begin
                    k0 <= k0_s; k1 <= k1_s; k2 <= k2_s; k3 <= k3_s;
                    if (pe_son)    grup  <= grup + 1'b1;
                    if (dongu_son) durum <= D_OLCEK;
                end
                D_OLCEK: begin
                    G     <= maks_G;
                    grup  <= 0;
                    durum <= (faz == FAZ_FP) ? D_SA : D_TUKET;
                end
                D_SA: begin
                    s_a   <= s_a_yeni;
                    durum <= D_TUKET;
                end
                D_TUKET: begin
                    k0 <= k0_s; k1 <= k1_s; k2 <= k2_s; k3 <= k3_s;
                    grup <= grup + 1'b1;
                    if (dongu_son) begin
                        case (faz)
                            FAZ_FP:
                                if (katman == cfg_L) durum <= D_CLU;
                                else begin
                                    katman <= katman + 1'b1;
                                    durum  <= D_IS_BASLA;
                                end
                            FAZ_BP: begin                          // aynı katmanın WG'si
                                faz   <= FAZ_WG;
                                durum <= D_IS_BASLA;
                            end
                            default:                               // WG bitti
                                if (katman == 4'd1) durum <= D_BITTI;
                                else begin
                                    katman <= katman - 1'b1;
                                    faz    <= (katman > 4'd2) ? FAZ_BP : FAZ_WG;  // 1. katmanda BP yok
                                    durum  <= D_IS_BASLA;
                                end
                        endcase
                    end
                end
                D_CLU: begin
                    k0 <= k0_s; k1 <= k1_s; k2 <= k2_s; k3 <= k3_s;
                    if (dongu_son) begin                           // katman = L
                        faz   <= (cfg_L > 4'd1) ? FAZ_BP : FAZ_WG;
                        durum <= D_IS_BASLA;
                    end
                end
                D_BITTI: begin
                    durum <= D_SON;
                    bitti <= 1'b1;
                end
                default: ;
            endcase
        end
    end

endmodule
