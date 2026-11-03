// =============================================================================
//  tb_sru_buyuk.sv — Adım 4 (D63): sru_top'un 64 gruplu tamponu
// -----------------------------------------------------------------------------
//  DUT: rtl/sru/sru_top.v (Egemen'in SRU'su + hedef girişi (D61) + MAX_GROUPS 64 (D63)).
//  Vektör: sru_buyuk.txt (sru_buyuk_uret.py; sru_katman.txt biçimi). Case'lerde 64, 60, 56,
//  17, 1 ve boyu karışık 64 grup var.
//  Her case: rst, hedef = 7, grupları sırayla it (son grupta last_group); push anında LMS
//  çıkışını (sru_top içindeki lms_out_flat) kontrol et; sonra GMS akışında her grubun
//  değerlerini, eleman sayısını ve sırasını, G'yi, layer_done'ı ve fazla çıkış olmadığını.
//  Vektör klasörü: +VEKTOR_DIZINI=<klasör/>; yoksa çalışma klasörü.
//  Sonuç: "SONUC tb_sru_buyuk: PASS k/k" (konsol ve <klasör>/sonuc_tb_sru_buyuk.txt)
// =============================================================================
`timescale 1ns/1ps

module tb_sru_buyuk;

    localparam MAXG = 64;

    reg                     clk = 1'b0;
    reg                     rst;
    reg  [2:0]              hedef;
    reg                     push_group;
    reg  signed [16*32-1:0] group_in_flat;
    reg  [4:0]              group_n;
    reg                     last_group;
    wire                    group_out_valid;
    wire signed [16*8-1:0]  group_out_flat;
    wire [4:0]              group_out_n;
    wire                    layer_done;
    wire [5:0]              G_out;
    wire                    busy;

    always #5 clk = ~clk;

    sru_top dut (
        .clk(clk), .rst(rst), .hedef(hedef),
        .push_group(push_group), .group_in_flat(group_in_flat),
        .group_n(group_n), .last_group(last_group),
        .group_out_valid(group_out_valid), .group_out_flat(group_out_flat),
        .group_out_n(group_out_n), .layer_done(layer_done),
        .G_out(G_out), .busy(busy)
    );

    integer n_el  [0:MAXG-1];
    integer q     [0:MAXG-1][0:15];
    integer lmsb  [0:MAXG-1][0:15];
    integer gmsb  [0:MAXG-1][0:15];

    string  dizin;
    integer fd, sfd, r, a1, a2, a3, a4, a5, a6;
    integer n_case, c, cno, ng, G_bek, Bg, g, i, cikan, bekle, done_say;
    integer hata, kontrol;
    reg signed [7:0] deger;

    task kontrol_et(input integer olan, input integer beklenen, input string ne);
        begin
            kontrol = kontrol + 1;
            if (olan !== beklenen) begin
                hata = hata + 1;
                if (hata <= 20) $display("FAIL case %0d: %s: olan %0d, beklenen %0d", cno, ne, olan, beklenen);
            end
        end
    endtask

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            sfd = $fopen({dizin, "sonuc_tb_sru_buyuk.txt"}, "w");
            if (sfd != 0) begin
                $fdisplay(sfd, "%s", satir);
                $fclose(sfd);
            end
        end
    endtask

    initial begin
        hata = 0; kontrol = 0;
        rst = 1'b1; hedef = 3'd7; push_group = 1'b0; last_group = 1'b0;
        group_in_flat = '0; group_n = 5'd0;

        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin)) dizin = "";
        fd = $fopen({dizin, "sru_buyuk.txt"}, "r");
        if (fd == 0) begin
            dizin = "";
            fd = $fopen("sru_buyuk.txt", "r");
        end
        if (fd == 0) begin
            sonuc_yaz("SONUC tb_sru_buyuk: FAIL (sru_buyuk.txt bulunamadi)");
            $finish;
        end
        r = $fscanf(fd, "%d %d %d %d", a1, a2, a3, a4);
        r = $fscanf(fd, "%d", n_case);
        repeat (2) @(negedge clk);

        for (c = 0; c < n_case; c = c + 1) begin
            r = $fscanf(fd, "%d %d %d %d", cno, ng, G_bek, Bg);
            for (g = 0; g < ng; g = g + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d", a1, a2, a3, a4, a5, a6);
                n_el[g] = a2;
                for (i = 0; i < a2; i = i + 1) begin
                    r = $fscanf(fd, "%d %d %d %d %d", a1, a3, a4, a5, a6);
                    q[g][i] = a1; lmsb[g][i] = a3; gmsb[g][i] = a5;
                end
            end

            @(negedge clk);                     // rst bir pozitif kenarı kapsasın
            rst = 1'b1; hedef = 3'd7;
            @(negedge clk);
            rst = 1'b0;

            done_say = 0;
            for (g = 0; g < ng; g = g + 1) begin
                group_in_flat = '0;
                for (i = 0; i < n_el[g]; i = i + 1) group_in_flat[i*32 +: 32] = q[g][i];
                group_n = n_el[g];
                push_group = 1'b1;
                last_group = (g == ng - 1);
                #1;
                for (i = 0; i < n_el[g]; i = i + 1) begin
                    deger = dut.lms_out_flat[i*8 +: 8];
                    kontrol_et(deger, lmsb[g][i], $sformatf("grup %0d eleman %0d lms", g, i));
                end
                @(negedge clk);
                kontrol_et(group_out_valid, 0, $sformatf("grup %0d itilirken cikis yok", g));
            end
            push_group = 1'b0; last_group = 1'b0;

            cikan = 0; bekle = 0;
            while (bekle < MAXG + 8) begin
                @(posedge clk); #1;
                bekle = bekle + 1;
                if (layer_done) done_say = done_say + 1;
                if (group_out_valid) begin
                    if (cikan < ng) begin
                        kontrol_et(G_out, G_bek, "G");
                        kontrol_et(group_out_n, n_el[cikan], $sformatf("grup %0d n", cikan));
                        for (i = 0; i < n_el[cikan]; i = i + 1) begin
                            deger = group_out_flat[i*8 +: 8];
                            kontrol_et(deger, gmsb[cikan][i], $sformatf("grup %0d eleman %0d gms", cikan, i));
                        end
                        kontrol_et(layer_done, (cikan == ng - 1), $sformatf("grup %0d layer_done", cikan));
                    end
                    cikan = cikan + 1;
                end
            end
            kontrol_et(cikan, ng, "cikan grup sayisi");
            kontrol_et(done_say, 1, "layer_done sayisi");
        end
        $fclose(fd);

        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_sru_buyuk: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_sru_buyuk: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
