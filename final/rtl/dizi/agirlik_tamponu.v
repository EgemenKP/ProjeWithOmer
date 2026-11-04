// =============================================================================
//  agirlik_tamponu.v — Çok bankalı ağırlık tamponu (Fig. 8 Weight Buffer, D82)
// -----------------------------------------------------------------------------
//  NB bank, bank = o mod 16; kelime = w[o][c]'nin 9 int8'i (indis 3ki + kj -> [8(3ki+kj) +: 8]).
//  Adres = katman tabanı + (o div 16) * Cin + c. Bank başına 1 eşzamanlı okuma, 1 yazma portu (WU).
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b-3b)
// =============================================================================
`timescale 1ns/1ps

module agirlik_tamponu #(
    parameter NB = 16,
    parameter AW = 9
) (
    input  wire                 clk,
    input  wire [NB*AW-1:0]     oku_adr,
    output reg  [NB*72-1:0]     oku_veri,
    input  wire [NB-1:0]        yaz_en,
    input  wire [NB*AW-1:0]     yaz_adr,
    input  wire [NB*72-1:0]     yaz_veri
);

    genvar k;
    generate
        for (k = 0; k < NB; k = k + 1) begin : bank
            reg [71:0] mem [0:(1<<AW)-1];
            integer a;
            initial for (a = 0; a < (1<<AW); a = a + 1) mem[a] = 72'd0;
            always @(posedge clk) begin
                if (yaz_en[k]) mem[yaz_adr[AW*k +: AW]] <= yaz_veri[72*k +: 72];
                oku_veri[72*k +: 72] <= mem[oku_adr[AW*k +: AW]];
            end
        end
    endgenerate

endmodule
