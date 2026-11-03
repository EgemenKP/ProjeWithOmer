`timescale 1ns/1ps
// =============================================================================
//  maks_reg.v — Max Regs: grupların yerel maksimumlarını saklayan register dosyası
// -----------------------------------------------------------------------------
//  Shao III-B ve Fig. 6 (s. 257): PE'nin ürettiği her grubun yerel maksimumu bir register
//  dosyasında saklanır; katmanın bütün çıktıları bitince global maksimum, yerel
//  maksimumlar arasından bulunur; GMS, global ile yerel maksimum arasındaki farka göre
//  kaydırır. Fig. 6'da Max Regs, PE'den "local max" alıp iki SRU aşamasına bilgi veren
//  ayrı bir blok.
//  Kaydırma miktarlarının hesabı (B, l, G, Δ) iki kaynakta da blok düzeyinde
//  tanımlanmamış; burada yapılması tasarım kararı (T4, TASARIM_FSM.md Bölüm 9):
//    B(m) = m'yi yazmak için gereken bit sayısı (D28); m = 0 ise 0
//    l    = max(0, B(M_yerel)  - hedef)    LMS kaydırması
//    G    = max(0, B(M_global) - hedef)    katmanın toplam kaydırması
//    Δ    = G - l_grup                     GMS kaydırması (SRU-a8)
//  Global maksimum, gruplar geldikçe güncellenen bir register'da tutulur; sonuç,
//  katman sonunda register dosyasını taramakla aynıdır.
//
//  Portlar:
//    clk, rst               saat, eşzamanlı aktif-yüksek reset
//    kom_gecerli, kom       FSM'in komut yolu (yalnızca dinler). Alanlar master_controller'daki
//                           gibi [AW*i +: AW]. İŞ_BAŞLA: hedef <- x, global maksimum <- 0.
//                           KOPYA/WU: a1 alanındaki grubun Δ'sı gms_kaydirma'ya verilir.
//    yerel_gecerli          1 çevrim: yerel_grup numaralı grubun yerel maksimumu hazır
//    yerel_grup [AW-1:0]    grup numarası (alttaki AD biti adres olarak kullanılır)
//    yerel_maks [31:0]      grubun mutlak değerlerinin en büyüğü (işaretsiz)
//    lms_kaydirma [5:0]     yerel_gecerli iken l (SRU'nun LMS kaydırma girişine); değilse 0
//    G [5:0]                max(0, B(global maksimum) - hedef); FSM ÖLÇEK'te örnekler
//    gms_kaydirma [5:0]     KOPYA/WU geçerliyken o grubun Δ'sı (SRU'nun GMS girişine); değilse 0
//  Parametreler: AW komut alanı genişliği, AD adres genişliği (derinlik 2^AD grup).
//  Verilog-2001. Hazırlayan: Claude (Ömer'in isteğiyle), 02.11.2026
// =============================================================================
module maks_reg #(
    parameter AW = 16,
    parameter AD = 6
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             kom_gecerli,
    input  wire [10*AW-1:0] kom,
    input  wire             yerel_gecerli,
    input  wire [AW-1:0]    yerel_grup,
    input  wire [31:0]      yerel_maks,
    output wire [5:0]       lms_kaydirma,
    output wire [5:0]       G,
    output wire [5:0]       gms_kaydirma
);

    localparam [3:0] OP_KOPYA = 4'd3, OP_WU = 4'd6, OP_IS_BASLA = 4'd8;

    wire [AW-1:0] k_op = kom[0    +: AW];
    wire [AW-1:0] k_x  = kom[4*AW +: AW];
    wire [AW-1:0] k_a1 = kom[7*AW +: AW];

    reg [31:0] M [0:(1<<AD)-1];      // yerel maksimumlar (register dosyası)
    reg [31:0] M_global;
    reg [5:0]  hedef;

    // B(m): en soldaki 1'in konumu + 1 (öncelik kodlayıcı); m = 0 ise 0
    function [5:0] bit_sayisi;
        input [31:0] m;
        integer i;
        begin
            bit_sayisi = 6'd0;
            for (i = 0; i < 32; i = i + 1)
                if (m[i]) bit_sayisi = i + 1;
        end
    endfunction

    // max(0, B(m) - h)
    function [5:0] kaydirma;
        input [31:0] m;
        input [5:0]  h;
        reg   [5:0]  b;
        begin
            b        = bit_sayisi(m);
            kaydirma = (b > h) ? (b - h) : 6'd0;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            M_global <= 32'd0;
            hedef    <= 6'd7;
        end else if (kom_gecerli && (k_op == OP_IS_BASLA)) begin
            hedef    <= k_x[5:0];
            M_global <= 32'd0;
        end else if (yerel_gecerli && (yerel_maks > M_global)) begin
            M_global <= yerel_maks;
        end
    end

    always @(posedge clk)
        if (yerel_gecerli)
            M[yerel_grup[AD-1:0]] <= yerel_maks;

    wire        tuketici = kom_gecerli && ((k_op == OP_KOPYA) || (k_op == OP_WU));
    wire [31:0] M_sec    = M[k_a1[AD-1:0]];

    assign lms_kaydirma = yerel_gecerli ? kaydirma(yerel_maks, hedef) : 6'd0;
    assign G            = kaydirma(M_global, hedef);
    assign gms_kaydirma = tuketici ? (G - kaydirma(M_sec, hedef)) : 6'd0;

endmodule
