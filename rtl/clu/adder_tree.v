// ============================================================================
// adder_tree.v -- Fig. 7 "Adder Tree" bloğu (iki kez kullaniliyor:
//   1) gi degerlerinin toplami (sum1, Algoritma2 satir 8)
//   2) bolme sonrasi gi2 degerlerinin toplami (sum2, Algoritma2 satir 10)
//
// N adet isaretli sayiyi ikili agac yapisinda toplar (davranissal
// for-dongusu toplami degil, gercek bir toplayici agaci).
//
// IN_W  : giris genisligi
// OUT_W : cikis genisligi -- cagiran modul tasma olmayacak kadar genis
//         secmeli (en az IN_W + ceil(log2(N)))
// ============================================================================
`timescale 1ns/1ps

module adder_tree #(
    parameter N     = 10,
    parameter IN_W  = 48,
    parameter OUT_W = 56
) (
    // NOT: max_tree.v'deki ile ayni sebep -- port duz veri yolu
    // (flattened bus) olarak tanimlaniyor, Vivado XSIM dizi-port
    // kabul etmiyor.
    input  wire signed [N*IN_W-1:0] data_flat,
    output wire signed [OUT_W-1:0]  sum
);

    localparam LEVELS = $clog2(N);
    localparam PAD_N  = 1 << LEVELS;

    // flat bus'i ic diziye cevir
    wire signed [IN_W-1:0] data [0:N-1];
    genvar u;
    generate
        for (u = 0; u < N; u = u + 1) begin : unpack
            assign data[u] = data_flat[u*IN_W +: IN_W];
        end
    endgenerate

    genvar lvl, idx;
    generate
        wire signed [OUT_W-1:0] stage [0:LEVELS][0:PAD_N-1];

        for (idx = 0; idx < PAD_N; idx = idx + 1) begin : init_stage
            if (idx < N) begin
                assign stage[0][idx] = {{(OUT_W-IN_W){data[idx][IN_W-1]}}, data[idx]};
            end else begin
                assign stage[0][idx] = {OUT_W{1'b0}};  // dolgu: 0 (toplamaya etkisiz)
            end
        end

        for (lvl = 0; lvl < LEVELS; lvl = lvl + 1) begin : tree_level
            localparam CUR_N = PAD_N >> lvl;
            for (idx = 0; idx < CUR_N/2; idx = idx + 1) begin : pair_add
                assign stage[lvl+1][idx] = stage[lvl][2*idx] + stage[lvl][2*idx+1];
            end
        end

        assign sum = stage[LEVELS][0];
    endgenerate

endmodule
