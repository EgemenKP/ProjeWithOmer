// =============================================================================
//  pe_birlesik.v — Shao Fig. 2'nin tek PE'si: 9 MAC, 6 mod (FP/BP/WG x stride 1/2)
// -----------------------------------------------------------------------------
//  Kaynak: Shao ISVLSI 2021, III-A ve Fig. 2 (s. 256): "nine multiply-accumulate units
//  (MACs), several multiplexers, and a partial sum (Psum) FIFO queue". Önceki sarmalayıcı
//  (rtl/sistem/pe_sarmalayici.v) Egemen'in beş ayrı devresini (45 MAC) seçiyordu; bu modül
//  aynı altı deseni AYNI 9 MAC'le, Fig. 2'deki port etiketleriyle yapar (D69).
//
//  Her MAC (mac.v, değişmedi) Fig. 2'deki gibi:
//    port 1  (weight)           : Weights/Errors   — FP/BP'de w[r][c], WG'de e (c çevrim gecikmeli)
//    port 2  (activation)       : Activations/Errors — FP/BP s1, BP s2, WG s1'de akis1[r];
//                                 FP s2 / WG s2'de c=0 çift, c=1 tek, c=2 gecikmeli çift ("mavi D")
//    port 3  (partial_sum)      : Psum FIFO'dan kısmi toplam — zincir başı (FP: r0c0; BP s2: A ve B
//                                 zincirlerinin satır 0/1 başları)
//    port 4  (passed_value / 0) : soldaki MAC'in sonucu ya da 0 (satır 1-2'nin başı, BP s2'nin
//                                 satır 2 başları)
//    port 5  (accumulated_value): kendi sonucu (WG, çıktı-durağan)
//  sel kodlaması mac.v'deki gibi (D13): 00 port 3, 01 port 4, 10 port 5.
//
//  Çıkış tarafı Fig. 2'deki iki toplayıcı + mux ile:
//    FP / BP s1 : psum_out = (m02 + m12) + m22
//    BP s2      : out0 = m01 + m21, out1 = m02 + m22, out2 = m11, out3 = m12  (Egemen'in pe_bp_s2'si)
//    toplayıcı 1 = (bp2 ? m01 : m02) + (bp2 ? m21 : m12);  toplayıcı 2 = (bp2 ? m02 : t1) + m22
//
//  Davranış Egemen'in beş devresiyle aynı (pe_chain3, pe_fp_s2, pe_bp_s2, pe_wg_s1, pe_wg_s2):
//  aynı çarpımlar, aynı zincirler, aynı gecikmeler; çıkış gecikmeleri değişmedi (D16).
//  Fark (D69): register'lar modlar arasında ortak. Mod değişince zincir ve gecikme register'ları
//  önceki modun değerini taşır; 3 çevrim (zincir boyu) 0 girişle temizlenir. PE motoru her
//  komuttan önce en az 4 çevrim 0 akış veriyor (D_AGIRLIK + D_SATIR), WG akümülatörleri yalnızca
//  aynı WG işinin komutları arasında (araya başka mod girmeden) korunuyor; eski sarmalayıcıyla
//  sistem düzeyinde aynı sonuç (tb_pe_birlesik, tb_veriyolu, tb_sistem).
//  mod 6/7 (boşta): bütün MAC'ler port 5'i seçer, port 1/2 = 0 → akümülatörler değişmez.
//
//  Portlar pe_sarmalayici.v ile birebir aynı (yerine doğrudan takılır):
//    clk, rst      : saat; rst eşzamanlı, aktif-yüksek; yalnızca WG modlarında MAC'lere gider
//    mod     [2:0] : 0 FP s1, 1 FP s2, 2 BP s1, 3 BP s2, 4 WG s1, 5 WG s2 (6, 7: boşta)
//    w_flat  [71:0]: 9 ağırlık, w[i][j] = w_flat[(3i+j)*8 +: 8]
//    akis1/2/3     : satır r'nin akışları ([8r +: 8]), sarmalayıcıdaki anlamlarıyla
//    ps_flat [127:0]: FP/BP s1: k=0 ps_in; BP s2: k=0 psA0, 1 psB0, 2 psA1, 3 psB1
//    cikis_flat[127:0], g_flat[287:0]: sarmalayıcıdaki gibi (seçili olmayan modda 0)
//  Yazan: Claude, 03.11.2026 (final/, Adım 5 öncesi)
// =============================================================================
`timescale 1ns/1ps

module pe_birlesik (
    input  wire          clk,
    input  wire          rst,
    input  wire [2:0]    mod,
    input  wire [71:0]   w_flat,
    input  wire [23:0]   akis1,
    input  wire [23:0]   akis2,
    input  wire [23:0]   akis3,
    input  wire [127:0]  ps_flat,
    output wire [127:0]  cikis_flat,
    output wire [287:0]  g_flat
);

    localparam FP_S1 = 3'd0, FP_S2 = 3'd1, BP_S1 = 3'd2, BP_S2 = 3'd3, WG_S1 = 3'd4, WG_S2 = 3'd5;

    wire s_zincir = (mod == FP_S1) || (mod == BP_S1) || (mod == FP_S2);   // tek zincir, ağırlık-durağan
    wire s_bp2    = (mod == BP_S2);
    wire s_wg     = (mod == WG_S1) || (mod == WG_S2);
    wire s_cifttek = (mod == FP_S2) || (mod == WG_S2);                     // çift/tek akış + mavi D
    wire s_wsabit = s_zincir || s_bp2;                                      // port 1 = ağırlık

    // ---- Satır başına gecikme register'ları (Fig. 3b / 5) ----
    // mavi D: çift akışın 1 çevrim gecikmelisi (FP s2, WG s2)
    // hata gecikme zinciri: MAC[r][c] e'yi c çevrim gecikmeli görür (WG)
    reg signed [7:0] d_cift [0:2];
    reg signed [7:0] e_d1   [0:2];
    reg signed [7:0] e_d2   [0:2];
    integer k;
    initial begin
        for (k = 0; k < 3; k = k + 1) begin d_cift[k] = 8'sd0; e_d1[k] = 8'sd0; e_d2[k] = 8'sd0; end
    end

    // WG'de hata akışı: s1'de akis2, s2'de akis3
    wire [23:0] e_akis = (mod == WG_S1) ? akis2 : (mod == WG_S2) ? akis3 : 24'd0;

    always @(posedge clk) begin
        for (k = 0; k < 3; k = k + 1) begin
            d_cift[k] <= s_cifttek ? akis1[8*k +: 8] : 8'sd0;
            e_d1[k]   <= s_wg      ? e_akis[8*k +: 8] : 8'sd0;
            e_d2[k]   <= e_d1[k];
        end
    end

    // ---- 9 MAC ----
    wire signed [31:0] m [0:8];          // m[3r+c]: MAC[r][c]'nin sonucu

    genvar r, c;
    generate
        for (r = 0; r < 3; r = r + 1) begin : satir
            for (c = 0; c < 3; c = c + 1) begin : sutun
                // port 1: ağırlık ya da (WG) c çevrim gecikmeli hata
                wire signed [7:0] e_c  = (c == 0) ? e_akis[8*r +: 8] : (c == 1) ? e_d1[r] : e_d2[r];
                wire signed [7:0] p1   = s_wsabit ? w_flat[8*(3*r+c) +: 8] :
                                         s_wg     ? e_c : 8'sd0;
                // port 2: aktivasyon / hata
                wire signed [7:0] ct   = (c == 0) ? akis1[8*r +: 8] : (c == 1) ? akis2[8*r +: 8] : d_cift[r];
                wire signed [7:0] p2   = (s_wsabit || s_wg) ? (s_cifttek ? ct : akis1[8*r +: 8]) : 8'sd0;
                // port 3: Psum FIFO'dan kısmi toplam (yalnızca zincir başlarında kullanılır)
                wire signed [31:0] p3  = (r == 0 && c == 0) ? ps_flat[0  +: 32] :
                                         (r == 0 && c == 2) ? ps_flat[32 +: 32] :
                                         (r == 1 && c == 0) ? ps_flat[64 +: 32] :
                                         (r == 1 && c == 2) ? ps_flat[96 +: 32] : 32'sd0;
                // port 4: soldaki MAC'in sonucu ya da 0. BP s2'de c=2 ayrı (B) zincir: 0
                wire signed [31:0] p4  = (c == 0) ? 32'sd0 :
                                         (c == 1) ? m[3*r] :
                                         (s_bp2 ? 32'sd0 : m[3*r+1]);
                // sel: 00 port 3, 01 port 4, 10 port 5
                wire ps_basi = s_zincir ? (r == 0 && c == 0) :
                               s_bp2    ? (r < 2 && c != 1) : 1'b0;
                wire [1:0] sel = (s_zincir || s_bp2) ? (ps_basi ? 2'b00 : 2'b01) : 2'b10;

                mac u_mac (
                    .clk(clk), .rst(rst & s_wg),
                    .weight(p1), .activation(p2),
                    .partial_sum(p3), .passed_value(p4), .accumulated_value(m[3*r+c]),
                    .sel(sel), .result(m[3*r+c])
                );
            end
        end
    endgenerate

    // ---- Çıkış: iki toplayıcı + mux (Fig. 2) ----
    wire signed [31:0] top1 = (s_bp2 ? m[1] : m[2]) + (s_bp2 ? m[7] : m[5]);
    wire signed [31:0] top2 = (s_bp2 ? m[2] : top1) + m[8];

    assign cikis_flat = s_zincir ? {96'd0, top2} :
                        s_bp2    ? {m[5], m[4], top2, top1} :
                                   128'd0;

    genvar q;
    generate
        for (q = 0; q < 9; q = q + 1) begin : g_cikis
            assign g_flat[32*q +: 32] = s_wg ? m[q] : 32'd0;
        end
    endgenerate

endmodule
