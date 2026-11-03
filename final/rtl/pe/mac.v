// ============================================================================
// mac.v -- Multiply-Accumulate birimi (Fig. 2, sol-ust kutu)
//
// Metinden (sayfa 255): "The basic computing unit of the PE is MAC, which
// is composed of a multiplier, an adder, a multiplexer, and a register.
// The external ports of MAC receive data from SRAM, including activations,
// errors, and weights, while the internal ports are responsible for
// intermediate values."
//
// Ic akis: (weight x activation) + mux(partial_sum, passed_value, accumulated_value) -> register
//
// Genislik karari: "The computation results of the int8 parameters are
// accumulated in int32 precision" (sayfa 255, Bolum II-A metni) -- bu
// YAZIYOR, varsayim degil. Bu yuzden ic toplama/mux yolu 32-bit.
//
// ACIK NOKTA (D13): `sel` kodlamasi (partial_sum/passed_value/accumulated_value
// arasinda hangi 2-bit degerin hangisini sectigi) ve bu secimin FP/BP/WG
// fazlarina gore NE ZAMAN degistigi makalede yazmiyor -- Omer Faruk'un
// golden model'i (Fig.3-5'teki 6 bağlanti semasini kodlayinca) netlesecek.
// Simdilik duz bir 2-bit secim sinyaliyle disariya acik birakildi.
// ============================================================================
`timescale 1ns/1ps

module mac (
    input  wire               clk,
    input  wire                rst,          // senkron, aktif-yuksek -- yalniz WG (akumulator) moduna gerekli, digerlerinde 0'a baglanir
    input  wire signed [7:0]  weight,       // dis port 1
    input  wire signed [7:0]  activation,   // dis port 2
    input  wire signed [31:0] partial_sum,       // ic port 3
    input  wire signed [31:0] passed_value,      // ic port 4 (ya da 0)
    input  wire signed [31:0] accumulated_value, // ic port 5
    input  wire [1:0]         sel,          // D13: kodlama acik -- 00=partial_sum, 01=passed_value, 10=accumulated_value
    output reg  signed [31:0] result
);

    wire signed [31:0] mux_out = (sel == 2'b00) ? partial_sum :
                                  (sel == 2'b01) ? passed_value :
                                                    accumulated_value;

    wire signed [15:0] product = weight * activation;   // int8*int8 -> 16-bit
    wire signed [31:0] product_ext = {{16{product[15]}}, product};  // isaretli genisletme

    // WG modunda (output-stationary) result kendi akumulatoru olarak
    // geri besleniyor (accumulated_value = result) -- baslangic degeri
    // 0 olmali (case basinda sifirlanmis akumulator varsayimi).
    initial result = 32'sd0;

    always @(posedge clk) begin
        if (rst) result <= 32'sd0;
        else     result <= mux_out + product_ext;
    end

endmodule
