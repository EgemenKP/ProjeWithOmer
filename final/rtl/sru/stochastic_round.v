// ============================================================================
// stochastic_round.v -- Shao Algoritma 1 (sayfa 256), isaret-buyukluk
//   sozde-stokastik yuvarlama. SRU'nun (LMS/GMS) her ikisinde de kullanilan
//   cekirdek fonksiyon.
//
// GUNCELLENDI (28.10.2026): Omer Faruk'un resmi sru_golden.py'si (D adaylari
// SRU-a1/a2/a3 icin kesin karar verdi) ile birebir eslestirildi -- iki nokta
// BENIM onceki (gecici) secimimden FARKLI cikti, duzeltildi:
//
//   SRU-a1 (ALT_YARI): "shao" -- f[h,0] (h+1 bit, Shao'nun KENDI yazimi,
//     NITI'nin "duzeltmesi" DEGIL). Onceki surumde yanlislikla NITI'nin
//     f[h-1,0] araligini kullanmistim -- D24 artik "shao" olarak kesinlesti.
//   SRU-a3 (DOYMA): YOK. +-127'ye kirpma YOK, sonuc 8 bitte dogal olarak
//     SARIYOR (128 -> -128, iki tumleyen tasmasi). Onceki surumde ben
//     +-127 doyma eklemistim -- bu artik KALDIRILDI.
//   SRU-a2 (TEK_BP): "makale" (f>>=1, bp-=1) -- bu zaten boyle yazilmisti,
//     degisiklik yok.
//
// Ek olarak bir "tasma" (overflow) ciktisi eklendi -- yuvarlama sonrasi
// buyukluk 128'e ulastiysa 1 (resmi vektor dosyalarindaki 4. sutun).
//
// Saf kombinasyonel (saat gerektirmiyor).
// ============================================================================
`timescale 1ns/1ps

module stochastic_round (
    input  wire signed [31:0] q32,
    input  wire        [4:0]  bp,      // 0..25 yeterli
    output wire signed [7:0]  q_out,
    output wire                tasma
);

    reg        sign;
    reg [31:0] mag;
    reg [7:0]  q;
    reg [31:0] f_full;
    reg [4:0]  eff_bp;
    reg [31:0] h;
    reg [31:0] top, bot;
    reg [31:0] qext;
    reg signed [8:0] q_signed;   // -256..255 araligini rahat tasir

    always @(*) begin
        sign = q32[31];
        mag  = sign ? (~q32 + 32'd1) : q32;

        q      = (mag >> bp) & 8'hFF;              // |q32|[bp+7:bp]
        f_full = mag & ((32'd1 << bp) - 32'd1);     // |q32|[bp-1:0]
        eff_bp = bp;

        if (bp[0]) begin                            // bp tek (SRU-a2: makale)
            f_full = f_full >> 1;
            eff_bp = bp - 5'd1;
        end

        h = eff_bp >> 1;

        // D68 (final/, 03.11.2026): top ve bot her yolda atanir; eff_bp = 0 dalinda
        // kullanilmiyorlar ama atanmadiklari icin sentez latch cikariyordu.
        top = 32'd0;
        bot = 32'd0;
        if (eff_bp != 0) begin
            top = f_full >> h;                       // ust yari, h bit
            bot = f_full & ((32'd1 << (h+1)) - 32'd1); // SRU-a1=shao: alt yari h+1 bit
            qext = (top > bot) ? (q + 1) : q;
        end else begin
            qext = q;
        end

        q_signed = sign ? -$signed({1'b0,qext[8:0]}) : $signed({1'b0,qext[8:0]});
    end

    assign tasma = (qext >= 9'd128);
    assign q_out = q_signed[7:0];   // SRU-a3: doyma yok, dogal 8-bit sarma

endmodule
