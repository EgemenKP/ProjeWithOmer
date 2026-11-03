// ============================================================================
// sru_array.v -- Fig.8'deki 16 PE satirinin her birine bir SRU: 16 paralel
//   sru_channel.v + TEK paylasilan global_max_reducer16.v.
//
// Varsayim (D30 ile baglantili, acik): 16 satir AYNI ANDA (lockstep)
// calisiyor -- yani her cevrimde ya hic kanal push etmez, ya da push eden
// kanallarin hepsi AYNI grup indeksinde olur, ve last_group hepsinde
// AYNI cevrimde gelir. Bu, sistolik PE dizisinin dogal calisma seklidir
// (butun satirlar birlikte adim atar) -- ama makale bunu acikca YAZMIYOR,
// mimari cikarimdir [Cikarim].
//
// Port'lar 16 kanal icin duz (flat) demetler halinde -- Vivado XSIM'in
// dizi-port kisitina takilmamak icin (CLU'da ogrendigimiz ders).
// ============================================================================
// ----------------------------------------------------------------------------
// DEGISIKLIK (Claude, 03.11.2026; Omer'in istegiyle, D40/D61): Egemen'in dosyasinin
//   kopyasi. Sabit 7 yerine `hedef` girisi eklendi (a ve e icin 7, g icin m_u).
//   hedef: 3 bit, 1..7 olmali (0 verilirse l 32'ye cikabilir, bp 5 bite sigmaz).
//   hedef bir is (LMS + GMS) boyunca sabit tutulmali. Baska satir degismedi.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

module sru_array (
    input  wire         clk,
    input  wire         rst,
    input  wire [2:0]   hedef,      // 7 (a, e) ya da m_u (g); is boyunca sabit

    input  wire [15:0]             push_group_all,
    input  wire [16*16*32-1:0]     group_in_flat_all,   // kanal basina 16*32 bit
    input  wire [16*5-1:0]         group_n_all,
    input  wire [15:0]             last_group_all,

    output wire [15:0]             group_out_valid_all,
    output wire [16*16*8-1:0]      group_out_flat_all,  // kanal basina 16*8 bit
    output wire [16*5-1:0]         group_out_n_all,
    output wire [15:0]             layer_done_all,
    output wire [15:0]             busy_all,

    output wire [5:0]              G_shared   // bilgi amacli: katmanin tek G'si
);

    wire [15:0]      B_out_valid;
    wire [16*6-1:0]  B_out_flat;

    global_max_reducer16 u_reducer (
        .clk(clk), .rst(rst),
        .push(B_out_valid), .B_flat(B_out_flat), .hedef(hedef),
        .B_max(), .G(G_shared)
    );

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : ch
            wire B_out_valid_i;
            wire [5:0] B_out_i;
            assign B_out_valid[i] = B_out_valid_i;
            assign B_out_flat[i*6 +: 6] = B_out_i;

            sru_channel u_sru (
                .clk(clk), .rst(rst), .hedef(hedef),
                .push_group(push_group_all[i]),
                .group_in_flat(group_in_flat_all[i*16*32 +: 16*32]),
                .group_n(group_n_all[i*5 +: 5]),
                .last_group(last_group_all[i]),
                .B_out_valid(B_out_valid_i),
                .B_out(B_out_i),
                .G(G_shared),
                .group_out_valid(group_out_valid_all[i]),
                .group_out_flat(group_out_flat_all[i*16*8 +: 16*8]),
                .group_out_n(group_out_n_all[i*5 +: 5]),
                .layer_done(layer_done_all[i]),
                .busy(busy_all[i])
            );
        end
    endgenerate

endmodule
