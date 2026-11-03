// ============================================================================
// sru_channel.v -- sru_top.v'nin 16-paralel entegrasyona uygun hali.
//
// sru_top.v'den (zaten dogrulanmis, DOKUNULMADI) TEK fark: global_max_b
// artik bu modulun İÇİNDE degil -- G disaridan geliyor (16 kanalin
// PAYLASTIGI tek bir global_max_reducer16'dan), ve bu kanal kendi B'sini
// disariya (B_out_valid/B_out) veriyor. Boylece 16 kanal AYNI G'yi
// kullanir (Fig.6: "global maximum value of ALL outputs" -- katmanin
// TUMU icin tek deger, kanal basina ayri degil).
//
// FSM mantigi (FAZ_LMS -> FAZ_GMS) sru_top.v ile birebir ayni.
// ============================================================================
// ----------------------------------------------------------------------------
// DEGISIKLIK (Claude, 03.11.2026; Omer'in istegiyle, D40/D61): Egemen'in dosyasinin
//   kopyasi. Sabit 7 yerine `hedef` girisi eklendi (a ve e icin 7, g icin m_u).
//   hedef: 3 bit, 1..7 olmali (0 verilirse l 32'ye cikabilir, bp 5 bite sigmaz).
//   hedef bir is (LMS + GMS) boyunca sabit tutulmali.
// DEGISIKLIK 2 (Claude, 03.11.2026; Adim 4, D63): MAX_GROUPS 16 -> 64, grup sayaclari
//   (wr_ptr, rd_ptr, n_groups) 5 -> 7 bit (PW). Tek PE ile bir iste 56-60 grup olusuyor (D43).
//   Baska satir degismedi.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

module sru_channel #(
    parameter MAX_GROUPS = 64,
    parameter PW         = 7     // grup sayaçlarının genişliği: MAX_GROUPS (64) sığmalı
) (
    input  wire               clk,
    input  wire                rst,
    input  wire        [2:0]   hedef,        // 7 (a, e) ya da m_u (g); is boyunca sabit

    input  wire                push_group,
    input  wire signed [16*32-1:0] group_in_flat,
    input  wire        [4:0]  group_n,
    input  wire                last_group,

    // --- bu kanalin B'si, paylasilan global_max_reducer16'ya ---
    output wire                 B_out_valid,   // = push_group (FAZ_LMS sirasinda)
    output wire        [5:0]   B_out,

    // --- paylasilan reducer'dan gelen, katmanin TEK G'si ---
    input  wire        [5:0]   G,

    output reg                 group_out_valid,
    output reg  signed [16*8-1:0] group_out_flat,
    output reg          [4:0]  group_out_n,
    output reg                 layer_done,

    output wire                busy
);

    localparam FAZ_LMS = 1'b0;
    localparam FAZ_GMS = 1'b1;
    reg faz;

    wire signed [16*8-1:0] lms_out_flat;
    wire [15:0] lms_tasma_flat;
    wire [5:0]  lms_l, lms_B;
    lms_group16 u_lms (.group_in_flat(group_in_flat), .hedef(hedef), .group_out_flat(lms_out_flat),
                        .tasma_flat(lms_tasma_flat), .l_out(lms_l), .B_out(lms_B));

    assign B_out_valid = push_group && (faz == FAZ_LMS);
    assign B_out = lms_B;

    reg signed [16*8-1:0] buf_data [0:MAX_GROUPS-1];
    reg        [5:0]      buf_l    [0:MAX_GROUPS-1];
    reg        [4:0]      buf_n    [0:MAX_GROUPS-1];
    reg        [PW-1:0]   wr_ptr;
    reg        [PW-1:0]   n_groups;
    reg        [PW-1:0]   rd_ptr;

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
            wr_ptr <= {PW{1'b0}};
            rd_ptr <= {PW{1'b0}};
            n_groups <= {PW{1'b0}};
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
                            n_groups <= wr_ptr + 1'b1;
                            rd_ptr   <= {PW{1'b0}};
                            faz      <= FAZ_GMS;
                        end else begin
                            wr_ptr <= wr_ptr + 1'b1;
                        end
                    end
                end

                FAZ_GMS: begin
                    group_out_flat  <= gms_out_flat_c;
                    group_out_n     <= buf_n[rd_ptr];
                    group_out_valid <= 1'b1;
                    if (rd_ptr + 1'b1 == n_groups) begin
                        layer_done <= 1'b1;
                        faz        <= FAZ_LMS;
                        wr_ptr     <= {PW{1'b0}};
                    end
                    rd_ptr <= rd_ptr + 1'b1;
                end
            endcase
        end
    end

endmodule
