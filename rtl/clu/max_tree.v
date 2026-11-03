// ============================================================================
// max_tree.v -- Fig. 7 "Max Tree" bloğu
//
// N adet isaretli sayi arasindan en buyugunu bulur. Ikili agac (tree)
// yapisinda, generate ile kurulu -- gercek bir karsilastirici agaci,
// davranissal $max fonksiyonu degil.
//
// Shao'nun semasinda Max Tree, EPU ciktilarinin (scaled a_i) max'ini
// buluyor (bkz. clu_top.v).
// ============================================================================
`timescale 1ns/1ps

module max_tree #(
    parameter N = 10,
    parameter W = 48
) (
    // NOT: Vivado XSIM port olarak tanimlanmis diziyi (unpacked array
    // port) kabul etmiyor ("port must not be declared to be an array").
    // Bu yuzden port duz/tek-parca bir veri yolu (flattened bus):
    // data_flat[0 +: W] = data[0], data_flat[W +: W] = data[1], ...
    input  wire signed [N*W-1:0] data_flat,
    output wire signed [W-1:0]   max_val
);

    // Agac derinligi: bir sonraki 2'nin kuvvetine tamamla
    localparam LEVELS = $clog2(N);
    localparam PAD_N  = 1 << LEVELS;   // 2'nin kuvvetine tamamlanmis boyut

    // flat bus'i ic dizi haline getir (bu bir PORT degil, serbest)
    wire signed [W-1:0] data [0:N-1];
    genvar u;
    generate
        for (u = 0; u < N; u = u + 1) begin : unpack
            assign data[u] = data_flat[u*W +: W];
        end
    endgenerate

    // Her seviye icin genisligi PAD_N olan bir sinyal dizisi
    genvar lvl, idx;
    generate
        // seviye 0: girisleri kopyala, eksik kalanlari -sonsuz ile doldur
        wire signed [W-1:0] stage [0:LEVELS][0:PAD_N-1];

        for (idx = 0; idx < PAD_N; idx = idx + 1) begin : init_stage
            if (idx < N) begin
                assign stage[0][idx] = data[idx];
            end else begin
                // kullanilmayan girisler: en kucuk deger (etkisiz eleman)
                assign stage[0][idx] = {1'b1, {(W-1){1'b0}}}; // en negatif deger
            end
        end

        for (lvl = 0; lvl < LEVELS; lvl = lvl + 1) begin : tree_level
            localparam CUR_N = PAD_N >> lvl;
            for (idx = 0; idx < CUR_N/2; idx = idx + 1) begin : pair_cmp
                assign stage[lvl+1][idx] =
                    (stage[lvl][2*idx] > stage[lvl][2*idx+1]) ?
                     stage[lvl][2*idx] : stage[lvl][2*idx+1];
            end
        end

        assign max_val = stage[LEVELS][0];
    endgenerate

endmodule
