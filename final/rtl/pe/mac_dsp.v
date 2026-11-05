// mac_dsp.v — Fig. 2'nin MAC'i, 3'e 1 seçici DSP48E1'in Z seçicisinde (D105, Faz 3 adım 3)
// mac.v (Egemen) ile aynı davranış: result <= {port3 | port4 | port5} + weight*activation, 32 bit. Seçici LUT yerine
// DSP'nin kendi Z mux'unda; port 4 (soldaki MAC'in sonucu) DSP zinciriyle (PCOUT -> PCIN). mac.v Egemen'in 5 PE
// devresi (ASIL testler) için değişmeden duruyor. Tek PE sentezi: 622 -> 273 LUT (05.11).
// P = Z + A*B;  Z: 000 = 0, 001 = PCIN (soldaki MAC), 010 = P (kendi akümülatörü), 011 = C (Psum FIFO)
// Çıkış P[31:0]; 48 bitlik toplamın alt 32 biti, 32 bitte sarmalı toplamla aynı.
`timescale 1ns/1ps
module mac_dsp (
    input  wire               clk,
    input  wire               rst,          // RSTP (WG akümülatör temizliği)
    input  wire signed [7:0]  weight,
    input  wire signed [7:0]  activation,
    input  wire signed [31:0] c_in,         // port 3: kısmi toplam
    input  wire        [47:0] pcin,         // port 4: soldaki MAC'in PCOUT'u
    input  wire        [2:0]  zsel,
    output wire signed [31:0] result,
    output wire        [47:0] pcout
);
    wire [47:0] p;
    assign result = p[31:0];
`ifdef SIM_DAVRANISSAL
    // Simülasyon için davranışsal eşdeğer (Vivado projesinde glbl'nin 100 ns'lik GSR darbesi DSP'nin P register'ını
    // ilk hesapta tutar; bu yalnızca simülasyona ait). Aynı veri yolu: P = Z + A*B, 48 bit, PCOUT = P.
    reg  [47:0] p_r = 48'd0;
    wire signed [47:0] carpim = $signed(weight) * $signed(activation);   // 48 bite işaretle genişletilmiş çarpım
    reg  [47:0] z;
    always @* begin
        case (zsel)
            3'b001:  z = pcin;
            3'b010:  z = p_r;
            3'b011:  z = {{16{c_in[31]}}, c_in};
            default: z = 48'd0;
        endcase
    end
    always @(posedge clk) p_r <= rst ? 48'd0 : z + carpim;
    assign p = p_r;
    assign pcout = p_r;
`else
    DSP48E1 #(
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT"), .USE_DPORT("FALSE"), .USE_MULT("MULTIPLY"),
        .USE_SIMD("ONE48"), .AUTORESET_PATDET("NO_RESET"), .USE_PATTERN_DETECT("NO_PATDET"),
        .ACASCREG(0), .ADREG(0), .ALUMODEREG(0), .AREG(0), .BCASCREG(0), .BREG(0), .CARRYINREG(0),
        .CARRYINSELREG(0), .CREG(0), .DREG(0), .INMODEREG(0), .MREG(0), .OPMODEREG(0), .PREG(1)
    ) u_dsp (
        .CLK(clk),
        .A({{22{activation[7]}}, activation}), .B({{10{weight[7]}}, weight}),
        .C({{16{c_in[31]}}, c_in}), .D(25'd0),
        .PCIN(pcin), .ACIN(30'd0), .BCIN(18'd0), .CARRYCASCIN(1'b0), .MULTSIGNIN(1'b0),
        .OPMODE({zsel, 2'b01, 2'b01}), .ALUMODE(4'b0000), .INMODE(5'b00000),
        .CARRYIN(1'b0), .CARRYINSEL(3'b000),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0), .CEALUMODE(1'b0), .CEB1(1'b0), .CEB2(1'b0), .CEC(1'b0),
        .CECARRYIN(1'b0), .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0), .CEP(1'b1),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTCTRL(1'b0),
        .RSTD(1'b0), .RSTINMODE(1'b0), .RSTM(1'b0), .RSTP(rst),
        .P(p), .PCOUT(pcout),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .MULTSIGNOUT(), .OVERFLOW(), .PATTERNBDETECT(),
        .PATTERNDETECT(), .UNDERFLOW(), .CARRYOUT()
    );
`endif
endmodule
