// ============================================================================
// bit_length32.v -- B(V): "bir sayiyi temsil etmek icin gereken en az bit"
// (Shao'nun kendi tanimi; D28/SRU-a5: ceil(log2) DEGIL, Python bit_length()
// ile ayni -- yalnizca 2'nin tam kuvvetlerinde farklari var, orada
// bit_length dogru olan).
// m=0 -> b=0. m=128 (0b10000000) -> b=8 (en yuksek '1' biti index 7, +1).
// ============================================================================
`timescale 1ns/1ps
module bit_length32 (
    input  wire [31:0] m,
    output reg  [5:0]  b
);
    integer i;
    always @(*) begin
        b = 0;
        for (i = 31; i >= 0; i = i - 1)
            if (m[i] && b == 0) b = i + 1;
    end
endmodule
