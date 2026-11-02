// ============================================================================
// gms_group16.v -- Global Maximum Scaling, en fazla 16 elemanlik grup.
// Delta = G - l (SRU-a8: "fark", resmi karar). stochastic_round.v'nin
// GUNCEL halini kullanir (SRU-a1=shao, SRU-a3=doyma yok).
// ============================================================================
`timescale 1ns/1ps

module gms_group16 (
    input  wire signed [16*8-1:0] lms_in_flat,
    input  wire [5:0]             l_in,
    input  wire [5:0]             G,
    output wire signed [16*8-1:0] group_out_flat,
    output wire        [15:0]     tasma_flat
);

    wire signed [7:0] lin [0:15];
    wire signed [31:0] lin_ext [0:15];
    wire [5:0] delta = G - l_in;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : unpack
            assign lin[i] = lms_in_flat[i*8 +: 8];
            assign lin_ext[i] = {{24{lin[i][7]}}, lin[i]};
        end
    endgenerate

    wire signed [7:0] gout [0:15];
    wire              gtasma[0:15];
    generate
        for (i = 0; i < 16; i = i + 1) begin : round_inst
            stochastic_round u_sr (.q32(lin_ext[i]), .bp(delta[4:0]),
                                    .q_out(gout[i]), .tasma(gtasma[i]));
            assign group_out_flat[i*8 +: 8] = gout[i];
            assign tasma_flat[i] = gtasma[i];
        end
    endgenerate

endmodule
