// ============================================================================
// lms_group16.v -- Local Maximum Scaling, en fazla 16 elemanlik grup
//   (sru_katman.txt'deki en buyuk grup boyutuna gore N=16 yapildi;
//   kucuk gruplar 0 ile doldurulur).
// stochastic_round.v'nin GUNCEL (Omer Faruk'un resmi kararlarina gore
// duzeltilmis) halini kullanir.
// ============================================================================
// ----------------------------------------------------------------------------
// DEGISIKLIK (Claude, 03.11.2026; Omer'in istegiyle, D40/D61): Egemen'in dosyasinin
//   kopyasi. Sabit 7 yerine `hedef` girisi eklendi (a ve e icin 7, g icin m_u).
//   hedef: 3 bit, 1..7 olmali (0 verilirse l 32'ye cikabilir, bp 5 bite sigmaz).
//   hedef bir is (LMS + GMS) boyunca sabit tutulmali. Baska satir degismedi.
// ----------------------------------------------------------------------------
// BIRLESTIRME (final/, 03.11.2026, D70): rtl/sru_hedefli ve rtl/sru_64 kopyalari kaldirildi;
//   tek SRU bu klasorde (hedef girisi + 64 grup). Egemen'in 16 gruplu asli: ../../../rtl/sru/.
`timescale 1ns/1ps

module lms_group16 (
    input  wire signed [16*32-1:0] group_in_flat,
    input  wire        [2:0]       hedef,      // 7 (a, e) ya da m_u (g)
    output wire signed [16*8-1:0]  group_out_flat,
    output wire        [15:0]      tasma_flat,
    output wire [5:0]              l_out,
    output wire [5:0]              B_out
);

    wire signed [31:0] gin [0:15];
    wire        [31:0] gabs[0:15];
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : unpack
            assign gin[i]  = group_in_flat[i*32 +: 32];
            assign gabs[i] = gin[i][31] ? (~gin[i] + 32'd1) : gin[i];
        end
    endgenerate

    // D71 (final/, 03.11.2026): mutlak degerler 33 bite sifirla genisletilip isaretli
    // max_tree'ye veriliyor. 32 bitte |-2^31| = 2^31 negatif gorunuyor ve B yanlis cikiyordu
    // (arac tuzagi 9: [-2^31, 5] grubunda B = 3, olmasi gereken 32).
    wire signed [16*33-1:0] gabs_flat;
    generate
        for (i = 0; i < 16; i = i + 1) begin : pack_abs
            assign gabs_flat[i*33 +: 33] = {1'b0, gabs[i]};
        end
    endgenerate

    wire signed [32:0] max_abs;
    max_tree #(.N(16), .W(33)) u_max (.data_flat(gabs_flat), .max_val(max_abs));

    wire [5:0] B;
    bit_length32 u_bl (.m(max_abs[31:0]), .b(B));
    assign B_out = B;
    assign l_out = (B > {3'b000, hedef}) ? (B - {3'b000, hedef}) : 6'd0;

    wire signed [7:0] gout [0:15];
    wire              gtasma[0:15];
    generate
        for (i = 0; i < 16; i = i + 1) begin : round_inst
            stochastic_round u_sr (.q32(gin[i]), .bp(l_out[4:0]),
                                    .q_out(gout[i]), .tasma(gtasma[i]));
            assign group_out_flat[i*8 +: 8] = gout[i];
            assign tasma_flat[i] = gtasma[i];
        end
    endgenerate

endmodule
