// =============================================================================
//  tb_sru_gradyan.sv — Adım 3.3: gradyanın SRU'dan m_u hedefiyle geçişi + ağırlık güncelleme
// -----------------------------------------------------------------------------
//  Zincir (D40, D41, D42; fe_golden README Bölüm 3):
//    g32 (WG çıkışı) -> sru_top (hedef = m_u): LMS, tampon, GMS -> g8 -> wu_unit -> w_yeni
//  DUT'lar: rtl/sru_hedefli/sru_top.v (Egemen'in SRU'su + hedef girişi) ve
//           rtl/wu_unit.v (Ömer'in fe_rtl'i, değişmedi).
//  Vektör: wu_katman.txt (fe_golden.py, 03.11 sürümü; SRU ayar kodu 1 1 0 1).
//    1. satır SRU ayar kodu (4 sayı), 2. satır FE ayar kodu (3 sayı), 3. satır CASE_SAYISI
//    her case : CASE_NO m_u GRUP_SAYISI G B_global
//    her grup : GRUP_NO N M_yerel B_yerel l Δ
//    N satır  : g32 w_eski g8_lms g8 w_yeni
//  Her case için kontroller:
//    - push anında LMS çıkışı (g8_lms) ve l      (sru_top içindeki lms_out_flat / lms_l)
//    - G_out = G
//    - GMS çıkışı g8 (group_out_flat), grup sırası ve eleman sayısı (group_out_n)
//    - wu_unit çıkışı w_yeni
//  Grupların boş kalan şeritleri 0 ile doldurulur (en büyük mutlak değeri etkilemez).
//
//  Vektör klasörü: +VEKTOR_DIZINI=<klasör/> (sonunda /). Verilmezse ya da dosya yoksa
//  çalışma klasörüne bakılır. Sonuç satırı konsola ve <klasör>/sonuc_tb_sru_gradyan.txt'ye:
//  "SONUC tb_sru_gradyan: PASS k/k" ya da "... FAIL h hata / k kontrol"
// =============================================================================
`timescale 1ns/1ps

module tb_sru_gradyan;

    localparam MAXG = 16;   // sru_top MAX_GROUPS (Egemen: 16); wu_katman'da en çok 16 grup

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

    reg  [16*8-1:0] wu_w;
    reg  [16*8-1:0] wu_g;
    wire [16*8-1:0] wu_yeni;
    wu_unit #(.N(16)) u_wu (.w_flat(wu_w), .g_flat(wu_g), .w_yeni_flat(wu_yeni));

    // Bir case'in verisi
    integer n_eleman [0:MAXG-1];
    integer l_bek    [0:MAXG-1];
    integer g32_v    [0:MAXG-1][0:15];
    integer w_eski   [0:MAXG-1][0:15];
    integer lms_bek  [0:MAXG-1][0:15];
    integer g8_bek   [0:MAXG-1][0:15];
    integer w_bek    [0:MAXG-1][0:15];

    string  dizin, dosya;
    integer fd, r, sfd;
    integer a1, a2, a3, a4;
    integer n_case, c, cno, mu, ng, G_bek, Bg;
    integer g, gno, N, M, B, l, d, i;
    integer cikan, bekle;
    integer hata, kontrol;
    reg signed [7:0] deger;

    task kontrol_et(input integer olan, input integer beklenen, input string ne);
        begin
            kontrol = kontrol + 1;
            if (olan !== beklenen) begin
                hata = hata + 1;
                if (hata <= 20)
                    $display("FAIL case %0d: %s: olan %0d, beklenen %0d", cno, ne, olan, beklenen);
            end
        end
    endtask

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            sfd = $fopen({dizin, "sonuc_tb_sru_gradyan.txt"}, "w");
            if (sfd != 0) begin
                $fdisplay(sfd, "%s", satir);
                $fclose(sfd);
            end
        end
    endtask

    initial begin
        hata = 0; kontrol = 0;
        rst = 1'b1; hedef = 3'd7; push_group = 1'b0; last_group = 1'b0;
        group_in_flat = '0; group_n = 5'd0; wu_w = '0; wu_g = '0;

        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin)) dizin = "";
        dosya = {dizin, "wu_katman.txt"};
        fd = $fopen(dosya, "r");
        if (fd == 0) begin
            dizin = "";
            dosya = "wu_katman.txt";
            fd = $fopen(dosya, "r");
        end
        if (fd == 0) begin
            sonuc_yaz("SONUC tb_sru_gradyan: FAIL (wu_katman.txt bulunamadi)");
            $finish;
        end

        r = $fscanf(fd, "%d %d %d %d", a1, a2, a3, a4);   // SRU ayar kodu
        if (!(a1 == 1 && a2 == 1 && a3 == 0 && a4 == 1))
            $display("UYARI: SRU ayar kodu %0d %0d %0d %0d; bu RTL 1 1 0 1 (D59: doymasiz) bekliyor",
                     a1, a2, a3, a4);
        r = $fscanf(fd, "%d %d %d", a1, a2, a3);           // FE ayar kodu (1 1 1)
        r = $fscanf(fd, "%d", n_case);

        repeat (2) @(posedge clk);

        for (c = 0; c < n_case; c = c + 1) begin
            // ---- case'i oku ----
            r = $fscanf(fd, "%d %d %d %d %d", cno, mu, ng, G_bek, Bg);
            for (g = 0; g < ng; g = g + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d", gno, N, M, B, l, d);
                n_eleman[g] = N;
                l_bek[g] = l;
                for (i = 0; i < N; i = i + 1) begin
                    r = $fscanf(fd, "%d %d %d %d %d", a1, a2, a3, a4, M);
                    g32_v[g][i] = a1; w_eski[g][i] = a2; lms_bek[g][i] = a3;
                    g8_bek[g][i] = a4; w_bek[g][i] = M;
                end
            end

            // ---- yeni iş: rst + hedef (D56: İŞ_BAŞLA bunu sürer) ----
            @(negedge clk);
            rst = 1'b1; hedef = mu[2:0];
            @(negedge clk);
            rst = 1'b0;

            // ---- LMS: grupları sırayla it ----
            for (g = 0; g < ng; g = g + 1) begin
                group_in_flat = '0;
                for (i = 0; i < n_eleman[g]; i = i + 1)
                    group_in_flat[i*32 +: 32] = g32_v[g][i];
                group_n    = n_eleman[g];
                push_group = 1'b1;
                last_group = (g == ng - 1);
                #1;   // kombinasyonel LMS çıkışı otursun
                kontrol_et(dut.lms_l, l_bek[g], $sformatf("grup %0d l", g));
                for (i = 0; i < n_eleman[g]; i = i + 1) begin
                    deger = dut.lms_out_flat[i*8 +: 8];
                    kontrol_et(deger, lms_bek[g][i], $sformatf("grup %0d eleman %0d g8_lms", g, i));
                end
                @(negedge clk);
            end
            push_group = 1'b0; last_group = 1'b0;

            // ---- GMS: tampondaki gruplar sırayla çıkar ----
            cikan = 0; bekle = 0;
            while (cikan < ng && bekle < 4 * MAXG) begin
                @(posedge clk); #1;
                bekle = bekle + 1;
                if (group_out_valid) begin
                    kontrol_et(G_out, G_bek, "G");
                    kontrol_et(group_out_n, n_eleman[cikan], $sformatf("grup %0d n", cikan));
                    wu_w = '0; wu_g = '0;
                    for (i = 0; i < n_eleman[cikan]; i = i + 1) begin
                        deger = group_out_flat[i*8 +: 8];
                        kontrol_et(deger, g8_bek[cikan][i], $sformatf("grup %0d eleman %0d g8", cikan, i));
                        wu_w[i*8 +: 8] = w_eski[cikan][i];
                        wu_g[i*8 +: 8] = group_out_flat[i*8 +: 8];
                    end
                    #1;
                    for (i = 0; i < n_eleman[cikan]; i = i + 1) begin
                        deger = wu_yeni[i*8 +: 8];
                        kontrol_et(deger, w_bek[cikan][i], $sformatf("grup %0d eleman %0d w_yeni", cikan, i));
                    end
                    if (cikan == ng - 1)
                        kontrol_et(layer_done, 1, "layer_done");
                    cikan = cikan + 1;
                end
            end
            kontrol_et(cikan, ng, "cikan grup sayisi");
        end
        $fclose(fd);

        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_sru_gradyan: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_sru_gradyan: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
