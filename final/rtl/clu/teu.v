// ============================================================================
// teu.v -- Taylor Expansion Unit (Fig. 7, gri kutu)
//
// Algoritma 2 satir 6: gi <- 2^(1-2sa) + ai*2^(1-sa) + ai*ai
// (sa <= -7 oldugunda kullanilan dal)
//
// NOT (test sirasinda bulundu): bu dalin urettigi gi degerleri EPU
// dalindan COK buyuk (sa=-10 civarinda ~2 milyon). GI_W parametresi
// bu yuzden genis tutuluyor -- ortak gi veri yoluyla (mux sonrasi)
// paylasilan genislikle (GI_W, clu_top.v'de EPU ciktisiyla AYNI
// olmali) tutarli olmak zorunda.
// ============================================================================
`timescale 1ns/1ps

module teu #(
    parameter GI_W = 48
) (
    input  wire signed [7:0]      ai,
    input  wire signed [7:0]      sa,
    output wire signed [GI_W-1:0] gi
);

    // 1-2*sa ve 1-sa kaydirma miktarlari (sa negatif oldugu icin bu
    // degerler pozitif ve potansiyel olarak buyuk olabilir)
    wire signed [8:0] shift1 = 9'sd1 - (sa <<< 1);   // 1-2sa
    wire signed [8:0] shift2 = 9'sd1 - sa;            // 1-sa

    // ONEMLI: concatenation ({...}) Verilog'da HER ZAMAN unsigned sonuc
    // uretir -- $signed() sarmalamadan ai (signed) ile carpilirsa, TUM
    // ifade unsigned'a doner ve negatif ai yanlis yorumlanir (bulundu:
    // testbench'te ai=-1, sa=-8 icin yanlis sonuc veriyordu). Bu yuzden
    // 2^x terimleri acikca $signed() ile isaretli.
    wire signed [GI_W-1:0] pow_shift1 = $signed({{(GI_W-1){1'b0}}, 1'b1}) <<< shift1;
    wire signed [GI_W-1:0] pow_shift2 = $signed({{(GI_W-1){1'b0}}, 1'b1}) <<< shift2;

    wire signed [GI_W-1:0] term1;
    wire signed [GI_W-1:0] term2;
    wire signed [GI_W-1:0] term3;

    assign term1 = pow_shift1;           // 2^(1-2sa)
    assign term2 = ai * pow_shift2;      // ai*2^(1-sa)
    assign term3 = ai * ai;               // ai*ai

    assign gi = term1 + term2 + term3;

endmodule
