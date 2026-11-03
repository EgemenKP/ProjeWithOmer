// final/ (03.11.2026, D70): birlesik SRU'nun hedef girisi 7'ye baglandi (a/e yolu); baska degisiklik yok.
`timescale 1ns/1ps
module tb_sru_top;

    localparam VFILE = "sru_katman.txt";

    reg clk = 0; always #5 clk = ~clk;
    reg rst, push_group, last_group;
    reg signed [16*32-1:0] group_in_flat;
    reg [4:0] group_n;
    wire group_out_valid;
    wire signed [16*8-1:0] group_out_flat;
    wire [4:0] group_out_n;
    wire layer_done;
    wire [5:0] G_out;
    wire busy;

    sru_top dut (.clk(clk), .rst(rst), .hedef(3'd7), .push_group(push_group),
                 .group_in_flat(group_in_flat), .group_n(group_n), .last_group(last_group),
                 .group_out_valid(group_out_valid), .group_out_flat(group_out_flat),
                 .group_out_n(group_out_n), .layer_done(layer_done),
                 .G_out(G_out), .busy(busy));

    integer fd, r, cfg[0:3];
    integer n_cases, case_no, n_groups, exp_G, exp_Bglobal;
    integer grp_no, n, exp_M, exp_B, exp_l, exp_delta;
    integer x[0:15], exp_lms[0:15], exp_lmst[0:15], exp_gms[0:15], exp_gmst[0:15];
    integer cap_out[0:15][0:15];   // [grup][eleman] -- FAZ_GMS'den gelen sirayla yakalanan
    integer cap_n[0:15];
    integer c, g, j, got_groups;
    integer total_grp, grp_ok, grp_fail;
    reg signed [7:0] got;
    integer bad;

    initial begin
        fd = $fopen(VFILE, "r");
        if (fd == 0) begin $display("HATA: %s acilamadi", VFILE); $finish; end

        r = $fscanf(fd, "%d %d %d %d", cfg[0],cfg[1],cfg[2],cfg[3]);
        r = $fscanf(fd, "%d", n_cases);
        total_grp = 0; grp_ok = 0; grp_fail = 0;
        push_group = 0; last_group = 0; group_in_flat = 0; group_n = 0;

        @(negedge clk); rst = 1;
        @(negedge clk); rst = 0;

        for (c = 0; c < n_cases; c = c + 1) begin
            r = $fscanf(fd, "%d %d %d %d", case_no, n_groups, exp_G, exp_Bglobal);

            // --- FAZ_LMS: gruplari sirayla besle ---
            for (g = 0; g < n_groups; g = g + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d", grp_no, n, exp_M, exp_B, exp_l, exp_delta);
                for (j = 0; j < n; j = j + 1)
                    r = $fscanf(fd, "%d %d %d %d %d", x[j], exp_lms[j], exp_lmst[j], exp_gms[j], exp_gmst[j]);
                for (j = n; j < 16; j = j + 1) x[j] = 0;

                cap_n[g] = n;
                for (j = 0; j < n; j = j + 1) cap_out[g][j] = exp_gms[j];  // beklenenleri sakla

                group_in_flat = 0;
                for (j = 0; j < 16; j = j + 1) group_in_flat[j*32 +: 32] = x[j][31:0];
                group_n = n[4:0];

                @(negedge clk);
                push_group = 1;
                last_group = (g == n_groups-1) ? 1 : 0;
                @(posedge clk); #1;
                @(negedge clk);
                push_group = 0; last_group = 0;
            end

            // --- FAZ_GMS: cikislari topla ---
            got_groups = 0;
            while (got_groups < n_groups) begin
                @(posedge clk); #1;
                if (group_out_valid) begin
                    bad = 0;
                    for (j = 0; j < cap_n[got_groups]; j = j + 1) begin
                        got = group_out_flat[j*8 +: 8];
                        if (got !== cap_out[got_groups][j][7:0]) begin
                            $display("FAIL case=%0d grup=%0d eleman=%0d beklenen=%0d alinan=%0d",
                                      case_no, got_groups, j, cap_out[got_groups][j], got);
                            bad = 1;
                        end
                    end
                    total_grp = total_grp + 1;
                    if (bad) grp_fail = grp_fail + 1; else grp_ok = grp_ok + 1;
                    got_groups = got_groups + 1;
                end
            end

            if (G_out !== exp_G[5:0])
                $display("UYARI case=%0d: G beklenen=%0d alinan=%0d", case_no, exp_G, G_out);

            // bir sonraki katman icin sifirla
            @(negedge clk); rst = 1;
            @(negedge clk); rst = 0;
        end
        $fclose(fd);
        $display("TOPLAM GRUP=%0d DOGRU=%0d HATALI=%0d", total_grp, grp_ok, grp_fail);
        if (grp_fail==0) $display("SONUC: TUM TESTLER GECTI");
        $finish;
    end
endmodule
