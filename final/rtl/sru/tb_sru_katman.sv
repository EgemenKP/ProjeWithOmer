// final/ (03.11.2026, D70): birlesik SRU'nun hedef girisi 7'ye baglandi (a/e yolu); baska degisiklik yok.
`timescale 1ns/1ps
module tb_sru_katman;

    localparam VFILE = "sru_katman.txt";

    reg signed [16*32-1:0] group_in_flat;
    wire signed [16*8-1:0] lms_out_flat;
    wire [15:0] lms_tasma_flat;
    wire [5:0] l_out, B_out;
    reg [5:0] G;
    wire signed [16*8-1:0] gms_out_flat;
    wire [15:0] gms_tasma_flat;

    lms_group16 u_lms (.group_in_flat(group_in_flat), .hedef(3'd7), .group_out_flat(lms_out_flat),
                        .tasma_flat(lms_tasma_flat), .l_out(l_out), .B_out(B_out));
    gms_group16 u_gms (.lms_in_flat(lms_out_flat), .l_in(l_out), .G(G),
                        .group_out_flat(gms_out_flat), .tasma_flat(gms_tasma_flat));

    integer fd, r, cfg[0:3];
    integer n_cases, case_no, n_groups, exp_G, exp_Bglobal;
    integer grp_no, n, exp_M, exp_B, exp_l, exp_delta;
    integer x[0:15], exp_lms[0:15], exp_lmst[0:15], exp_gms[0:15], exp_gmst[0:15];
    integer c, g, j;
    integer total_grp, grp_ok, grp_fail;
    reg signed [7:0] got_lms, got_gms;
    reg got_lmst, got_gmst;
    integer bad;

    initial begin
        fd = $fopen(VFILE, "r");
        if (fd == 0) begin $display("HATA: %s acilamadi", VFILE); $finish; end

        r = $fscanf(fd, "%d %d %d %d", cfg[0],cfg[1],cfg[2],cfg[3]);
        $display("ayar kodu: %0d %0d %0d %0d (beklenen 1 1 0 1)", cfg[0],cfg[1],cfg[2],cfg[3]);
        r = $fscanf(fd, "%d", n_cases);
        total_grp = 0; grp_ok = 0; grp_fail = 0;

        for (c = 0; c < n_cases; c = c + 1) begin
            r = $fscanf(fd, "%d %d %d %d", case_no, n_groups, exp_G, exp_Bglobal);
            G = exp_G[5:0];

            for (g = 0; g < n_groups; g = g + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d", grp_no, n, exp_M, exp_B, exp_l, exp_delta);
                for (j = 0; j < n; j = j + 1)
                    r = $fscanf(fd, "%d %d %d %d %d", x[j], exp_lms[j], exp_lmst[j], exp_gms[j], exp_gmst[j]);
                for (j = n; j < 16; j = j + 1) x[j] = 0;

                group_in_flat = 0;
                for (j = 0; j < 16; j = j + 1)
                    group_in_flat[j*32 +: 32] = x[j][31:0];
                #1;

                total_grp = total_grp + 1;
                bad = 0;
                if (l_out !== exp_l[5:0] || B_out !== exp_B[5:0]) begin
                    $display("FAIL(l/B) case=%0d grup=%0d l:beklenen=%0d alinan=%0d B:beklenen=%0d alinan=%0d",
                              case_no, grp_no, exp_l, l_out, exp_B, B_out);
                    bad = 1;
                end
                for (j = 0; j < n; j = j + 1) begin
                    got_lms  = lms_out_flat[j*8 +: 8];
                    got_lmst = lms_tasma_flat[j];
                    got_gms  = gms_out_flat[j*8 +: 8];
                    got_gmst = gms_tasma_flat[j];
                    if (got_lms !== exp_lms[j][7:0] || got_lmst !== exp_lmst[j][0] ||
                        got_gms !== exp_gms[j][7:0] || got_gmst !== exp_gmst[j][0]) begin
                        $display("FAIL(val) case=%0d grup=%0d eleman=%0d x=%0d beklenen=(lms=%0d,t=%0d,gms=%0d,t=%0d) alinan=(lms=%0d,t=%0d,gms=%0d,t=%0d)",
                                  case_no, grp_no, j, x[j], exp_lms[j],exp_lmst[j],exp_gms[j],exp_gmst[j],
                                  got_lms,got_lmst,got_gms,got_gmst);
                        bad = 1;
                    end
                end
                if (bad) grp_fail = grp_fail + 1;
                else grp_ok = grp_ok + 1;
            end
        end
        $fclose(fd);
        $display("TOPLAM GRUP=%0d DOGRU=%0d HATALI=%0d", total_grp, grp_ok, grp_fail);
        if (grp_fail==0) $display("SONUC: TUM TESTLER GECTI");
        $finish;
    end
endmodule
