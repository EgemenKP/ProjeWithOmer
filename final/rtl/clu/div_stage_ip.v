// ============================================================================
// div_stage_ip.v -- Fig.7'deki divider blogunu GERCEK Xilinx Divider
//   Generator IP'sine (div_gen_0Z, 5.1) baglayan saatli sarmalayici.
//
// IP ayarlari (Ego'nun Vivado'da urettigi): Radix2, Unsigned,
//   Dividend Width=64, Divisor Width=56, Remainder Type=Remainder,
//   Flow Control=Non Blocking, Latency=66 clock (Automatic)
//
// Cikis formati (Remainder modu): m_axis_dout_tdata = {quotient, remainder}
//   ust 64 bit = bolum (bizim istedigimiz), alt 56 bit = kalan (kullanilmiyor)
//
// Non-Blocking modda TREADY yok, tvalid girisleri surekli 1'e baglandi
// (her çevrimde yeni bolme baslatiliyor, tam pipeline).
// ============================================================================
`timescale 1ns/1ps

module div_stage_ip (
    input  wire        clk,
    input  wire [63:0] dividend,   // daima >=0 (ispatlandi), unsigned IP'ye ham bit olarak veriliyor
    input  wire [55:0] divisor,    // daima >0 (ispatlandi)
    output wire [63:0] quotient,
    output wire        valid
);

    wire [119:0] dout_tdata;
    wire         dout_tvalid;

    div_gen_0Z u_div (
        .aclk(clk),
        .s_axis_divisor_tvalid(1'b1),
        .s_axis_divisor_tdata(divisor),
        .s_axis_dividend_tvalid(1'b1),
        .s_axis_dividend_tdata(dividend),
        .m_axis_dout_tvalid(dout_tvalid),
        .m_axis_dout_tdata(dout_tdata)
    );

    assign quotient = dout_tdata[119:56];  // ust 64 bit = bolum
    assign valid    = dout_tvalid;

endmodule
