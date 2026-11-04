`timescale 1ns/1ps
// =============================================================================
//  master_controller_dizi.v — Ana denetleyici, 16x16 dizi için (Adım 5b-3d, D85)
// -----------------------------------------------------------------------------
//  Adım 4'ün master_controller.v'sinin (değişmeden duruyor) dizi komut setiyle hâli. Bir eğitim adımı:
//    İLERİ  katman 1..L : İŞ_BAŞLA, DİZİ geçişleri, ÖLÇEK, SA
//    CLU    örnek 0..B-1
//    GERİ   katman L..1 : (l > 1 ise) İŞ_BAŞLA, DİZİ, ÖLÇEK; sonra İŞ_BAŞLA, DİZİ, ÖLÇEK, WU'lar
//    BİTTİ
//  Fark (D78, D85): KOPYA yok (GMS ön-getirmede); PE komutunun yerine DİZİ geçiş komutu, karo döngüleri:
//    FP: o-karo -> c -> b -> r-karo      BP: c-karo -> o -> b -> m/p-karo      WG: c-karo -> o-karo -> b -> r
//    WU: o-karo -> c (bir komut 9 kelime)
//  Karo sayısı ceil(n / 16). Komut alanları (komutlar_dizi.txt ile aynı sıra):
//    0 op, 1 faz, 2 katman, 3 b, 4 x, 5 y, 6 z, 7 a1, 8 a2, 9 a3
//    İŞ_BAŞLA (8): faz, l, x = hedef        DİZİ (1): faz, l, b, x = k0, y = k1, z = k3, a1 = ilk, a2 = son
//    ÖLÇEK (2): faz, l                      SA (4): l, x = s_a        CLU (5): L, b, x = s_a
//    WU (6): faz = WG, l, x = o-karo, y = c BİTTİ (7)
//  Portlar ve el sıkışma master_controller.v ile aynı (kom_gecerli / kom_bitti, maks_G ÖLÇEK'te örneklenir).
//  Golden: dizi_sistem_golden.py, komut_sablonu(). Yazan: Claude, 04.11.2026 (final/, Adım 5b-3d)
// =============================================================================
module master_controller_dizi #(
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

    localparam [3:0] OP_DIZI = 4'd1, OP_OLCEK = 4'd2, OP_SA = 4'd4,
                     OP_CLU = 4'd5, OP_WU = 4'd6, OP_BITTI = 4'd7, OP_IS_BASLA = 4'd8;
    localparam [1:0] FAZ_FP = 2'd0, FAZ_BP = 2'd1, FAZ_WG = 2'd2;
    localparam [3:0] D_BOSTA = 4'd0, D_IS_BASLA = 4'd1, D_DIZI = 4'd2, D_OLCEK = 4'd3,
                     D_SA = 4'd4, D_WU = 4'd5, D_CLU = 4'd6, D_BITTI = 4'd7, D_SON = 4'd8;

    reg [3:0]           durum;
    reg [1:0]           faz;
    reg [3:0]           katman;
    reg [CW-1:0]        k0, k1, k2, k3;
    reg signed [AW-1:0] s_a;
    reg [5:0]           G;

    // ---- Katman tablosu ----
    wire [3:0] li   = katman - 4'd1;
    wire [7:0] cin  = cfg_cin [8*li +: 8];
    wire [7:0] cout = cfg_cout[8*li +: 8];
    wire [7:0] h    = cfg_h   [8*li +: 8];
    wire [7:0] s    = cfg_s   [8*li +: 8];
    wire [7:0] p    = cfg_p   [8*li +: 8];
    wire [7:0] sw   = cfg_sw  [8*li +: 8];

    wire [9:0] h_2p  = {2'b00, h} + {1'b0, p, 1'b0};
    wire [9:0] ho_s1 = h_2p - 10'd2;
    wire [9:0] ho_s2 = ((h_2p - 10'd3) >> 1) + 10'd1;
    wire [7:0] ho    = (s == 8'd2) ? ho_s2[7:0] : ho_s1[7:0];
    wire [9:0] np_s2 = ({2'b00, h} + {2'b00, p} + 10'd1) >> 1;
    wire [7:0] nbp   = (s == 8'd2) ? np_s2[7:0] : h;          // BP: s1'de dX satırı, s2'de geçiş (D51)

    function [7:0] karo;                                       // ceil(n / 16)
        input [7:0] n;
        begin karo = (n + 8'd15) >> 4; end
    endfunction

    // ---- Döngü sınırları ----
    reg [CW-1:0] n0, n1, n2, n3;
    always @* begin
        n0 = 1; n1 = 1; n2 = 1; n3 = 1;
        case (durum)
            D_DIZI: begin
                n2 = cfg_batch;
                case (faz)
                    FAZ_FP:  begin n0 = karo(cout); n1 = cin;        n3 = karo(ho);  end
                    FAZ_BP:  begin n0 = karo(cin);  n1 = cout;       n3 = karo(nbp); end
                    default: begin n0 = karo(cin);  n1 = karo(cout); n3 = ho;        end
                endcase
            end
            D_WU:    begin n0 = karo(cout); n1 = cin; end
            D_CLU:   n2 = cfg_batch;
            default: ;
        endcase
    end

    wire son_k0    = (k0 == n0 - 1'b1);
    wire son_k1    = (k1 == n1 - 1'b1);
    wire son_k2    = (k2 == n2 - 1'b1);
    wire son_k3    = (k3 == n3 - 1'b1);
    wire dongu_son = son_k0 & son_k1 & son_k2 & son_k3;

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

    // FP/BP: Psum FIFO k1 (kanal) boyunca toplar; WG: akümülatör (b, r) boyunca
    wire g_ilk = (faz == FAZ_WG) ? ((k2 == 0) && (k3 == 0)) : (k1 == 0);
    wire g_son = (faz == FAZ_WG) ? (son_k2 & son_k3) : son_k1;

    wire [3:0]           hedef    = (faz == FAZ_WG) ? cfg_m_u : HEDEF_AKT;
    wire signed [AW-1:0] sw_g     = {{(AW-8){sw[7]}}, sw};
    wire signed [AW-1:0] s_a_yeni = s_a + sw_g + {{(AW-6){1'b0}}, G};      // D32

    reg [AW-1:0] f_op, f_faz, f_kat, f_b, f_x, f_y, f_z, f_a1, f_a2, f_a3;
    always @* begin
        f_op = 0; f_faz = 0; f_kat = 0; f_b = 0; f_x = 0; f_y = 0; f_z = 0;
        f_a1 = 0; f_a2 = 0; f_a3 = 0;
        case (durum)
            D_IS_BASLA: begin f_op = OP_IS_BASLA; f_faz = faz; f_kat = katman; f_x = hedef; end
            D_DIZI: begin
                f_op = OP_DIZI; f_faz = faz; f_kat = katman;
                f_b = k2; f_x = k0; f_y = k1; f_z = k3; f_a1 = g_ilk; f_a2 = g_son;
            end
            D_OLCEK: begin f_op = OP_OLCEK; f_faz = faz; f_kat = katman; end
            D_SA:    begin f_op = OP_SA; f_kat = katman; f_x = s_a_yeni; end
            D_WU:    begin f_op = OP_WU; f_faz = FAZ_WG; f_kat = katman; f_x = k0; f_y = k1; end
            D_CLU:   begin f_op = OP_CLU; f_kat = cfg_L; f_b = k2; f_x = s_a; end
            D_BITTI: f_op = OP_BITTI;
            default: ;
        endcase
    end
    wire [10*AW-1:0] kom_sonraki = {f_a3, f_a2, f_a1, f_z, f_y, f_x, f_b, f_kat, f_faz, f_op};

    assign mesgul = (durum != D_BOSTA) && (durum != D_SON);

    always @(posedge clk) begin
        if (rst) begin
            durum <= D_BOSTA; kom_gecerli <= 1'b0; kom <= {10*AW{1'b0}}; bitti <= 1'b0;
            faz <= FAZ_FP; katman <= 4'd1; k0 <= 0; k1 <= 0; k2 <= 0; k3 <= 0; s_a <= 0; G <= 6'd0;
        end else if (!kom_gecerli) begin
            if (durum == D_BOSTA || durum == D_SON) begin
                if (basla) begin
                    durum <= D_IS_BASLA; faz <= FAZ_FP; katman <= 4'd1;
                    s_a <= {{(AW-8){cfg_s_a0[7]}}, cfg_s_a0};
                    bitti <= 1'b0; k0 <= 0; k1 <= 0; k2 <= 0; k3 <= 0;
                end
            end else begin
                kom_gecerli <= 1'b1;
                kom         <= kom_sonraki;
            end
        end else if (kom_bitti) begin
            kom_gecerli <= 1'b0;
            case (durum)
                D_IS_BASLA: begin durum <= D_DIZI; k0 <= 0; k1 <= 0; k2 <= 0; k3 <= 0; end
                D_DIZI: begin
                    k0 <= k0_s; k1 <= k1_s; k2 <= k2_s; k3 <= k3_s;
                    if (dongu_son) durum <= D_OLCEK;
                end
                D_OLCEK: begin
                    G <= maks_G;
                    k0 <= 0; k1 <= 0; k2 <= 0; k3 <= 0;
                    case (faz)
                        FAZ_FP:  durum <= D_SA;
                        FAZ_BP:  begin faz <= FAZ_WG; durum <= D_IS_BASLA; end   // aynı katmanın WG'si
                        default: durum <= D_WU;
                    endcase
                end
                D_SA: begin
                    s_a <= s_a_yeni;
                    if (katman == cfg_L) durum <= D_CLU;
                    else begin katman <= katman + 1'b1; durum <= D_IS_BASLA; end
                end
                D_WU: begin
                    k0 <= k0_s; k1 <= k1_s; k2 <= k2_s; k3 <= k3_s;
                    if (dongu_son) begin
                        if (katman == 4'd1) durum <= D_BITTI;
                        else begin
                            katman <= katman - 1'b1;
                            faz    <= (katman > 4'd2) ? FAZ_BP : FAZ_WG;           // 1. katmanda BP yok
                            durum  <= D_IS_BASLA;
                        end
                    end
                end
                D_CLU: begin
                    k0 <= k0_s; k1 <= k1_s; k2 <= k2_s; k3 <= k3_s;
                    if (dongu_son) begin
                        faz   <= (cfg_L > 4'd1) ? FAZ_BP : FAZ_WG;
                        durum <= D_IS_BASLA;
                    end
                end
                D_BITTI: begin durum <= D_SON; bitti <= 1'b1; end
                default: ;
            endcase
        end
    end

endmodule
