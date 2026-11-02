// ============================================================================
// sru_top.v -- TEK bir SRU kanali, Fig.6'nin iki-fazli akisina birebir sadik.
//
// ONEMLI KAPSAM NOTU: Fig.8'e gore gercek donanimda PE dizisinin HER
// SATIRINDA ayri bir SRU var (16 paralel kanal). Bu modul bunlardan
// YALNIZCA BIRINI modelliyor -- 16 kanali paralel baglamak, henuz
// baslamadigimiz "16x16 PE dizisi" entegrasyonunun isi (TASKS.md).
// Makaleden sasmamak icin burada fazlasini eklemedim.
//
// Metin (s.257, III-B), birebir takip edildi:
//   "the PEs finish their computation and produce a group of int32
//    output data... The first stage (LMS) is carried out based on the
//    local maximum of this group... int8 outputs are transmitted to
//    the on-chip buffer, and the local maximum is reserved in a
//    register file. When all outputs of the layer are computed, the
//    global maximum... is obtained... the second stage (GMS) [uses]
//    the difference between the global maximum and corresponding
//    local maximum."
//
// Iki faz:
//   FAZ_LMS : gruplar sirayla gelir (push_group), her biri hemen LMS'ten
//             gecer, int8 sonuc + l tampona yazilir, B global_max_b'ye
//             itilir. last_group ile isaretlenen grup islenince FAZ_GMS'e
//             gecilir.
//   FAZ_GMS : tamponlanan gruplar sirayla (bir cevrimde bir grup) GMS'ten
//             gecirilip disariya verilir (group_out + group_out_valid).
//             Son grup ciktiktan sonra layer_done ve FAZ_LMS'e donus.
//
// MAX_GROUPS=16: makalede acik bir sayi yok (D30 hala acik); 16, Fig.8'deki
// 16 satirlik PE dizisiyle tutarli bir ust sinir olarak secildi -- bu bir
// VARSAYIM, kesinlesmedi.
// ============================================================================
`timescale 1ns/1ps

module sru_top #(
    parameter MAX_GROUPS = 16
) (
    input  wire               clk,
    input  wire                rst,          // yeni katman basinda 1 cevrim (FAZ_LMS'e donus, buf temiz)

    // --- FAZ_LMS girisi: PE'den gelen bir grup ---
    input  wire                push_group,    // bu cevrimde gecerli bir grup var
    input  wire signed [16*32-1:0] group_in_flat,
    input  wire        [4:0]  group_n,        // grubun eleman sayisi (1..16)
    input  wire                last_group,    // bu, katmanin SON grubu (push_group ile birlikte)

    // --- FAZ_GMS ciktisi: tamponlanan gruplar sirayla disari veriliyor ---
    output reg                 group_out_valid,
    output reg  signed [16*8-1:0] group_out_flat,
    output reg          [4:0]  group_out_n,
    output reg                 layer_done,    // katmanin TUM GMS ciktilari verildi

    output wire [5:0]          G_out,         // bilgi amacli: bu katmanin G'si
    output wire                busy           // FAZ_GMS surerken 1 (yeni push_group kabul edilmez)
);

    localparam FAZ_LMS = 1'b0;
    localparam FAZ_GMS = 1'b1;
    reg faz;

    // ---- LMS alt birimi (kombinasyonel) ----
    wire signed [16*8-1:0] lms_out_flat;
    wire [15:0] lms_tasma_flat;
    wire [5:0]  lms_l, lms_B;
    lms_group16 u_lms (.group_in_flat(group_in_flat), .group_out_flat(lms_out_flat),
                        .tasma_flat(lms_tasma_flat), .l_out(lms_l), .B_out(lms_B));

    // ---- global B birikimi ----
    wire [5:0] G;
    global_max_b u_gmb (.clk(clk), .rst(rst), .push(push_group && (faz==FAZ_LMS)),
                         .B_yerel(lms_B), .B_max(), .G(G));
    assign G_out = G;

    // ---- tampon: her grubun LMS int8 ciktisi + l + n ----
    reg signed [16*8-1:0] buf_data [0:MAX_GROUPS-1];
    reg        [5:0]      buf_l    [0:MAX_GROUPS-1];
    reg        [4:0]      buf_n    [0:MAX_GROUPS-1];
    reg        [4:0]      wr_ptr;        // FAZ_LMS: bir sonraki yazilacak grup indeksi
    reg        [4:0]      n_groups;      // bu katmandaki toplam grup sayisi (last_group ile sabitlenir)
    reg        [4:0]      rd_ptr;        // FAZ_GMS: bir sonraki okunacak grup indeksi

    // ---- GMS alt birimi (kombinasyonel) -- FAZ_GMS'de rd_ptr'deki grubu okur ----
    wire signed [16*8-1:0] gms_in  = buf_data[rd_ptr];
    wire        [5:0]      gms_l   = buf_l[rd_ptr];
    wire signed [16*8-1:0] gms_out_flat_c;
    wire        [15:0]     gms_tasma_c;
    gms_group16 u_gms (.lms_in_flat(gms_in), .l_in(gms_l), .G(G),
                        .group_out_flat(gms_out_flat_c), .tasma_flat(gms_tasma_c));

    assign busy = (faz == FAZ_GMS);

    always @(posedge clk) begin
        if (rst) begin
            faz <= FAZ_LMS;
            wr_ptr <= 5'd0;
            rd_ptr <= 5'd0;
            n_groups <= 5'd0;
            group_out_valid <= 1'b0;
            layer_done <= 1'b0;
        end else begin
            group_out_valid <= 1'b0;
            layer_done <= 1'b0;

            case (faz)
                FAZ_LMS: begin
                    if (push_group) begin
                        buf_data[wr_ptr] <= lms_out_flat;
                        buf_l[wr_ptr]    <= lms_l;
                        buf_n[wr_ptr]    <= group_n;
                        if (last_group) begin
                            n_groups <= wr_ptr + 5'd1;
                            rd_ptr   <= 5'd0;
                            faz      <= FAZ_GMS;
                        end else begin
                            wr_ptr <= wr_ptr + 5'd1;
                        end
                    end
                end

                FAZ_GMS: begin
                    group_out_flat  <= gms_out_flat_c;
                    group_out_n     <= buf_n[rd_ptr];
                    group_out_valid <= 1'b1;
                    if (rd_ptr + 5'd1 == n_groups) begin
                        layer_done <= 1'b1;
                        faz        <= FAZ_LMS;
                        wr_ptr     <= 5'd0;
                    end
                    rd_ptr <= rd_ptr + 5'd1;
                end
            endcase
        end
    end

endmodule
