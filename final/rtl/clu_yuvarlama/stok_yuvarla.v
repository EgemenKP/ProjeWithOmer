`timescale 1ns/1ps
// =============================================================================
//  stok_yuvarla.v — CLU çıkışı için >>4 stokastik yuvarlama (D8 = c), bir kanal
// -----------------------------------------------------------------------------
//  NITI StoShift(x, 4) + int8_clip'in donanım karşılığı (ti_loss.py 35, ti_torch.py 33-46):
//    q = |x| >> 4,  f = |x| mod 16,  r = LFSR'in alt 4 biti
//    f > r ise q = q + 1;  q = min(q, 127) (D9);  y = işaret(x) * q
//  LFSR (alternatif; Shao ve NITI'de tanımlı değil): 16 bit Fibonacci,
//    x^16 + x^14 + x^13 + x^11 + 1, periyot 65535. Her kullanımdan sonra 4 adım ilerler,
//    böylece ardışık r'ler örtüşmez. Her sınıf kanalı kendi örneğini kullanır; tohumlar
//    clu_yuvarlama.py'deki kanal_tohumlari() ile aynı olmalı.
//
//  Portlar:
//    clk            saat
//    rst            eşzamanlı, aktif-yüksek reset: LFSR <- TOHUM
//    ilerle         1 ise bu çevrimin sonucu kullanıldı; saat kenarında LFSR 4 adım ilerler
//    x    [W-1:0]   işaretli giriş (CLU'nun e_i'si, >>4'ten önce); ikiye tümleyen
//    y    [7:0]     işaretli int8 sonuç, -127..127. Saatsiz: x'e ve LFSR'in o anki durumuna bağlı
//  Parametreler: W giriş genişliği (en az 5), TOHUM LFSR'in başlangıç değeri (sıfır olamaz).
//  Verilog-2001. Hazırlayan: Claude (Ömer'in isteğiyle), 02.11.2026
// =============================================================================
module stok_yuvarla #(
    parameter        W     = 16,
    parameter [15:0] TOHUM = 16'hACE1
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         ilerle,
    input  wire [W-1:0] x,
    output wire [7:0]   y
);

    // LFSR'in tek adımı: yeni bit = s[15] ^ s[13] ^ s[12] ^ s[10], durum sola kayar
    function [15:0] adim;
        input [15:0] s;
        begin
            adim = {s[14:0], s[15] ^ s[13] ^ s[12] ^ s[10]};
        end
    endfunction

    reg  [15:0] lfsr;
    wire [15:0] lfsr_4 = adim(adim(adim(adim(lfsr))));     // 4 adım sonraki durum

    always @(posedge clk) begin
        if (rst)
            lfsr <= TOHUM;
        else if (ilerle)
            lfsr <= lfsr_4;
    end

    // İşaret-büyüklük yuvarlama
    wire         negatif = x[W-1];
    wire [W-1:0] mutlak  = negatif ? (~x + 1'b1) : x;      // |x|; x = -2^(W-1) için de doğru (işaretsiz)
    wire [W-5:0] q       = mutlak[W-1:4];                    // tam kısım
    wire [3:0]   f       = mutlak[3:0];                      // kesir
    wire [3:0]   r       = lfsr[3:0];                        // rastgele sayı
    wire [W-4:0] q_yuv   = q + (f > r);                      // olasılık f/16 ile yukarı
    wire [6:0]   q_doy   = (q_yuv > 127) ? 7'd127 : q_yuv[6:0];   // D9: ±127
    assign y = negatif ? (~{1'b0, q_doy} + 1'b1) : {1'b0, q_doy};

endmodule
