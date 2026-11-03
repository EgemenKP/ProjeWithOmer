// ============================================================================
// global_max_reducer16.v -- Fig.6'nin "global maximum value of ALL outputs"
//   dedigi seyin 16-satirli karsiligi: KATMANIN TUMU icin TEK bir B_max/G,
//   16 SRU kanalinin hepsinden gelen B degerlerini birlikte degerlendirerek.
//
// global_max_b.v'den fark: orada tek kanal, cevrim basina 1 B degeri
// vardi. Burada 16 PE satiri AYNI ANDA (lockstep) calistigi icin, her
// cevrimde 16 kanaldan birden B gelebilir -- bu yuzden cevrim basina
// 16'li bir max-agaci + calisan maksimum register'i.
//
// push[i]=0 olan kanallar bu cevrim gecersiz sayilir (B=0 ile degil,
// max hesabina hic katilmaz).
// ============================================================================
// ----------------------------------------------------------------------------
// DEGISIKLIK (Claude, 03.11.2026; Omer'in istegiyle, D40/D61): Egemen'in dosyasinin
//   kopyasi. Sabit 7 yerine `hedef` girisi eklendi (a ve e icin 7, g icin m_u).
//   hedef: 3 bit, 1..7 olmali (0 verilirse l 32'ye cikabilir, bp 5 bite sigmaz).
//   hedef bir is (LMS + GMS) boyunca sabit tutulmali. Baska satir degismedi.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

module global_max_reducer16 (
    input  wire               clk,
    input  wire               rst,
    input  wire [15:0]        push,        // kanal basina: bu cevrim B_in[i] gecerli
    input  wire [16*6-1:0]    B_flat,      // kanal basina 6-bit B
    input  wire [2:0]         hedef,       // 7 (a, e) ya da m_u (g)
    output reg  [5:0]         B_max,
    output wire [5:0]         G
);

    wire signed [16*32-1:0] masked_flat;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : mask
            // max_tree 32-bit signed bekliyor -- B (6 bit, hep pozitif)
            // 32 bite genisletilip, push=0 ise 0'a maskeleniyor
            assign masked_flat[i*32 +: 32] = push[i] ? {26'd0, B_flat[i*6 +: 6]} : 32'sd0;
        end
    endgenerate

    wire signed [31:0] cur_max;
    max_tree #(.N(16), .W(32)) u_max (.data_flat(masked_flat), .max_val(cur_max));

    always @(posedge clk) begin
        if (rst) B_max <= 6'd0;
        else if (cur_max[5:0] > B_max && |push) B_max <= cur_max[5:0];
    end

    assign G = (B_max > {3'b000, hedef}) ? (B_max - {3'b000, hedef}) : 6'd0;

endmodule
