// ============================================================================
// epu.v -- Exponential Unit (Fig. 7, sag-alt detay kutusu)
//
// ai * 0xB8 (=184) >> 7   ->  log2(e)*ai yaklasik degeri   (D4 karari:
//   Algoritma 2 metnindeki 47274/2^15 YERINE, Fig.7'de cizilen donanim
//   sabiti 184/2^7 kullaniliyor -- makalenin kendi ic tutarsizligi,
//   donanim semasina sadik kalindi)
// sonra sa'ya gore IKI YONLU kaydirma (D2 karari, NITI kodundan
//   dogrulandi: sa>=0 -> sola, sa<0 -> saga)
//
// Cikis genisligi (SCALED_W) parametrik -- EPU dalinin kendi basina
// tasma riski dusuk (ai int8, sabit carpan kucuk), ama TEU ile ayni
// ortak veri yoluna (gi) girecegi icin genis tutuldu.
// ============================================================================
`timescale 1ns/1ps

module epu #(
    parameter SCALED_W = 48
) (
    input  wire signed [7:0]            ai,
    input  wire signed [7:0]            sa,
    output wire signed [SCALED_W-1:0]   scaled
);

    // ai * 184 -- 8-bit * 9-bit (184 unsigned, 8 bit sigar) carpimi,
    // guvenli genislik icin ara sinyal genis tutuluyor
    wire signed [17:0] mul_result;
    assign mul_result = ai * 9'sd184;

    // >>7 (sabit kaydirma, aritmetik)
    wire signed [17:0] base;
    assign base = mul_result >>> 7;

    // iki yonlu degisken kaydirma (barrel shifter) -- D2
    // sa pozitifse sola, negatifse saga (mutlak deger kadar)
    wire [7:0] sa_mag;
    assign sa_mag = sa[7] ? (~sa + 8'd1) : sa;   // |sa|

    assign scaled = sa[7] ? ($signed({{(SCALED_W-18){base[17]}}, base}) >>> sa_mag)
                           : ($signed({{(SCALED_W-18){base[17]}}, base}) <<< sa_mag);

endmodule
