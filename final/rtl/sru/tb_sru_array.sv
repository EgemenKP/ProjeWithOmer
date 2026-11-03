// final/ (03.11.2026, D70): birlesik SRU'nun hedef girisi 7'ye baglandi (a/e yolu); baska degisiklik yok.
`timescale 1ns/1ps
module tb_sru_array;

    localparam VFILE = "sru_array_test.txt";

    reg clk = 0; always #5 clk = ~clk;
    reg rst;
    reg [15:0] push_group_all, last_group_all;
    reg [16*16*32-1:0] group_in_flat_all;
    reg [16*5-1:0] group_n_all;
    wire [15:0] group_out_valid_all, layer_done_all, busy_all;
    wire [16*16*8-1:0] group_out_flat_all;
    wire [16*5-1:0] group_out_n_all;
    wire [5:0] G_shared;

    sru_array dut (.clk(clk), .rst(rst), .hedef(3'd7),
        .push_group_all(push_group_all), .group_in_flat_all(group_in_flat_all),
        .group_n_all(group_n_all), .last_group_all(last_group_all),
        .group_out_valid_all(group_out_valid_all), .group_out_flat_all(group_out_flat_all),
        .group_out_n_all(group_out_n_all), .layer_done_all(layer_done_all),
        .busy_all(busy_all), .G_shared(G_shared));

    integer fd, r, n_ch, exp_G, dummy_ch;
    integer n_groups[0:5];
    integer n_elem[0:5][0:1];
    integer x_store[0:5][0:1][0:15];
    integer exp_out[0:5][0:1][0:15];
    integer ch, g, j, n, l, dummy_lms, x_tmp, gms_tmp;
    integer total, ok, fail, bad;
    reg signed [7:0] got;
    integer got_g[0:5];

    initial begin
        // ---- dosyayi BIR KEZ oku, hem x hem beklenen gms'i sakla ----
        fd = $fopen(VFILE, "r");
        if (fd == 0) begin $display("HATA: %s acilamadi", VFILE); $finish; end
        r = $fscanf(fd, "%d %d", n_ch, exp_G);
        $display("kanal sayisi=%0d beklenen G_shared=%0d", n_ch, exp_G);

        for (ch = 0; ch < n_ch; ch = ch + 1) begin
            r = $fscanf(fd, "%d %d", dummy_ch, n_groups[ch]);
            for (g = 0; g < n_groups[ch]; g = g + 1) begin
                r = $fscanf(fd, "%d %d", n, l);
                n_elem[ch][g] = n;
                for (j = 0; j < n; j = j + 1) begin
                    r = $fscanf(fd, "%d %d %d", x_tmp, dummy_lms, gms_tmp);
                    x_store[ch][g][j] = x_tmp;
                    exp_out[ch][g][j] = gms_tmp;
                end
            end
        end
        $fclose(fd);

        // ---- simulasyon: 2 cevrimde (hepsi 2 gruplu) lockstep besle ----
        push_group_all = 0; last_group_all = 0; group_in_flat_all = 0; group_n_all = 0;
        @(negedge clk); rst = 1;
        @(negedge clk); rst = 0;

        for (g = 0; g < 2; g = g + 1) begin   // bu 6 case hepsi 2 gruplu
            @(negedge clk);
            for (ch = 0; ch < n_ch; ch = ch + 1) begin
                push_group_all[ch] = 1;
                last_group_all[ch] = (g == 1) ? 1 : 0;
                group_n_all[ch*5 +: 5] = n_elem[ch][g][4:0];
                for (j = 0; j < 16; j = j + 1) begin
                    if (j < n_elem[ch][g])
                        group_in_flat_all[ch*16*32 + j*32 +: 32] = x_store[ch][g][j][31:0];
                    else
                        group_in_flat_all[ch*16*32 + j*32 +: 32] = 0;
                end
            end
            @(posedge clk); #1;
            @(negedge clk);
            push_group_all = 0; last_group_all = 0;
        end

        // ---- FAZ_GMS ciktilarini topla ----
        total = 0; ok = 0; fail = 0;
        for (ch = 0; ch < n_ch; ch = ch + 1) got_g[ch] = 0;

        while (got_g[0] < n_groups[0]) begin
            @(posedge clk); #1;
            for (ch = 0; ch < n_ch; ch = ch + 1) begin
                if (group_out_valid_all[ch] && got_g[ch] < n_groups[ch]) begin
                    bad = 0;
                    for (j = 0; j < n_elem[ch][got_g[ch]]; j = j + 1) begin
                        got = group_out_flat_all[ch*16*8 + j*8 +: 8];
                        if (got !== exp_out[ch][got_g[ch]][j][7:0]) begin
                            $display("FAIL kanal=%0d grup=%0d eleman=%0d beklenen=%0d alinan=%0d",
                                      ch, got_g[ch], j, exp_out[ch][got_g[ch]][j], got);
                            bad = 1;
                        end
                    end
                    total = total + 1;
                    if (bad) fail = fail + 1; else ok = ok + 1;
                    got_g[ch] = got_g[ch] + 1;
                end
            end
        end

        if (G_shared !== exp_G[5:0])
            $display("UYARI: G_shared beklenen=%0d alinan=%0d", exp_G, G_shared);

        $display("TOPLAM GRUP=%0d DOGRU=%0d HATALI=%0d", total, ok, fail);
        if (fail==0) $display("SONUC: TUM TESTLER GECTI");
        $finish;
    end
endmodule
