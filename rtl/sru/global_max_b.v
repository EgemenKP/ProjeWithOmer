// ============================================================================
// global_max_b.v -- Fig.6'daki Max Regs. + global-maksimum mantigi.
//
// Katmanin LMS gecisi sirasinda her grubun B_yerel'i bir cevrimde `push`
// ile buraya yazilir; B monoton oldugundan (D36/SRU-a13) sadece 6-bit B
// saklamak, 32-bit M_yerel saklamaktan daha ucuz ve yeterli.
// Katman bitince (tum gruplar islendikten sonra) B_max = B_global,
// G = max(0, B_global - 7) kombinasyonel olarak hazir olur.
// `rst`, yeni katmana baslarken B_max'i sifirlar.
// ============================================================================
`timescale 1ns/1ps

module global_max_b (
    input  wire       clk,
    input  wire       rst,      // yeni katman basinda 1 cevrim
    input  wire       push,     // bir grubun B_yerel'i gecerli, bu cevrimde yaz
    input  wire [5:0] B_yerel,
    output reg  [5:0] B_max,
    output wire [5:0] G
);

    always @(posedge clk) begin
        if (rst) B_max <= 6'd0;
        else if (push && B_yerel > B_max) B_max <= B_yerel;
    end

    assign G = (B_max > 6'd7) ? (B_max - 6'd7) : 6'd0;

endmodule
