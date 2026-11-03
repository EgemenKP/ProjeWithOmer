// =============================================================================
//  tb_fe_top.sv — Adım 3.4: fonksiyon motoru üst modülü (fe_top) testbench'i
// -----------------------------------------------------------------------------
//  A) Akış yolu, 16 şerit, her vektör satırı bir kez:
//     relu.hex (65.536 satır, tüm (a, e) çiftleri): mod 0 (geçir), 1 (ReLU ileri), 2 (ReLU geri)
//     wu_cikarma.hex (65.536 satır, tüm (w, g8) çiftleri): mod 3 (w - g8, ±127)
//  B) CLU yolu: clu_vektorleri.txt (1940 vektör; 400'ünde a'da -128 var)
//     - Her vektörden önce 0..12 çevrim rastgele boşluk (bölücü sayacının fazı değişsin)
//     - clu_basla -> clu_bitti tam BEKLEME çevrim mi; arada clu_mesgul = 1 mi
//     - e0..e9 beklenenle aynı mı; 3 çevrim sonra hâlâ aynı mı
//     - Her 7. vektörde, meşgulken farklı girişlerle ikinci bir clu_basla verilir;
//       yok sayılmalı
//  Satır biçimleri:
//     relu.hex       : [31:24] a  [23:16] e  [15:8] relu(a)  [7:0] e_geri
//     wu_cikarma.hex : [23:16] w  [15:8] g8  [7:0] w_yeni
//     clu_vektorleri : a0..a9 s_a y e0..e9 (onluk)
//  Vektör klasörü: +VEKTOR_DIZINI=<klasör/> (sonunda /). Verilmezse ya da dosya yoksa
//  çalışma klasörüne bakılır. Sonuç: "SONUC tb_fe_top: PASS k/k" (konsol ve
//  <klasör>/sonuc_tb_fe_top.txt)
//  BEKLEME parametresi DUT'a geçer (varsayılan 77). 76 ile çalıştırılırsa test FAIL vermeli.
// =============================================================================
`timescale 1ns/1ps

module tb_fe_top;

    parameter BEKLEME = 77;
    localparam N = 16;
    localparam SATIR = 65536;
    localparam NV_EN_COK = 4000;

    reg              clk = 1'b0;
    reg              rst;
    reg  [1:0]       mod;
    reg  [N*8-1:0]   veri_flat, maske_flat, w_flat;
    wire [N*8-1:0]   cikis_flat;
    reg              clu_basla;
    reg  [10*8-1:0]  clu_a_flat;
    reg  [7:0]       clu_sa;
    reg  [9:0]       clu_y_onehot;
    wire [10*8-1:0]  clu_e_flat;
    wire             clu_bitti, clu_mesgul;

    always #5 clk = ~clk;

    fe_top #(.N(N), .CLU_BEKLEME(BEKLEME)) dut (
        .clk(clk), .rst(rst),
        .mod(mod), .veri_flat(veri_flat), .maske_flat(maske_flat), .w_flat(w_flat),
        .cikis_flat(cikis_flat),
        .clu_basla(clu_basla), .clu_a_flat(clu_a_flat), .clu_sa(clu_sa),
        .clu_y_onehot(clu_y_onehot), .clu_e_flat(clu_e_flat),
        .clu_bitti(clu_bitti), .clu_mesgul(clu_mesgul)
    );

    reg [31:0] relu_mem [0:SATIR-1];
    reg [23:0] wu_mem   [0:SATIR-1];
    integer    cv [0:NV_EN_COK-1][0:21];

    string  dizin;
    integer fd, sfd, r, k, j, i, nv, bosluk, cevrim, tohum;
    integer t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11;
    integer t12, t13, t14, t15, t16, t17, t18, t19, t20, t21;
    integer hata, kontrol;
    reg [31:0] rv;
    reg [23:0] wv;
    reg [10*8-1:0] e_bek;

    task kontrol_et(input integer olan, input integer beklenen, input string ne);
        begin
            kontrol = kontrol + 1;
            if (olan !== beklenen) begin
                hata = hata + 1;
                if (hata <= 20) $display("FAIL %s: olan %0d, beklenen %0d", ne, olan, beklenen);
            end
        end
    endtask

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            sfd = $fopen({dizin, "sonuc_tb_fe_top.txt"}, "w");
            if (sfd != 0) begin
                $fdisplay(sfd, "%s", satir);
                $fclose(sfd);
            end
        end
    endtask

    // Vektör klasörünü bul: önce +VEKTOR_DIZINI, yoksa çalışma klasörü
    task dizin_bul;
        begin
            if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin)) dizin = "";
            fd = $fopen({dizin, "clu_vektorleri.txt"}, "r");
            if (fd == 0) begin
                dizin = "";
                fd = $fopen("clu_vektorleri.txt", "r");
            end
        end
    endtask

    integer s;
    initial begin
        hata = 0; kontrol = 0; tohum = 2026;
        rst = 1'b1; mod = 2'd0; veri_flat = '0; maske_flat = '0; w_flat = '0;
        clu_basla = 1'b0; clu_a_flat = '0; clu_sa = 8'd0; clu_y_onehot = 10'd0;

        dizin_bul;
        if (fd == 0) begin
            sonuc_yaz("SONUC tb_fe_top: FAIL (clu_vektorleri.txt bulunamadi)");
            $finish;
        end
        // CLU vektörlerini oku
        nv = 0;
        while (!$feof(fd) && nv < NV_EN_COK) begin
            r = $fscanf(fd, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                        t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11,
                        t12, t13, t14, t15, t16, t17, t18, t19, t20, t21);
            if (r == 22) begin
                cv[nv][0] = t0;  cv[nv][1] = t1;  cv[nv][2] = t2;  cv[nv][3] = t3;
                cv[nv][4] = t4;  cv[nv][5] = t5;  cv[nv][6] = t6;  cv[nv][7] = t7;
                cv[nv][8] = t8;  cv[nv][9] = t9;  cv[nv][10] = t10; cv[nv][11] = t11;
                cv[nv][12] = t12; cv[nv][13] = t13; cv[nv][14] = t14; cv[nv][15] = t15;
                cv[nv][16] = t16; cv[nv][17] = t17; cv[nv][18] = t18; cv[nv][19] = t19;
                cv[nv][20] = t20; cv[nv][21] = t21;
                nv = nv + 1;
            end
        end
        $fclose(fd);
        $readmemh({dizin, "relu.hex"}, relu_mem);
        $readmemh({dizin, "wu_cikarma.hex"}, wu_mem);
        if (relu_mem[SATIR-1] === 32'bx || wu_mem[SATIR-1] === 24'bx) begin
            sonuc_yaz("SONUC tb_fe_top: FAIL (relu.hex ya da wu_cikarma.hex okunamadi)");
            $finish;
        end

        repeat (2) @(negedge clk);
        rst = 1'b0;

        // ---------------- A) akış yolu ----------------
        for (k = 0; k < SATIR / N; k = k + 1) begin
            for (i = 0; i < N; i = i + 1) begin
                rv = relu_mem[k * N + i];
                veri_flat[i*8 +: 8]  = rv[31:24];      // a
                maske_flat[i*8 +: 8] = 8'hAA;          // mod 0/1'de kullanılmamalı
            end
            mod = 2'd0; #1;
            for (i = 0; i < N; i = i + 1) begin
                rv = relu_mem[k * N + i];
                kontrol_et(cikis_flat[i*8 +: 8], rv[31:24], "mod 0 gecir");
            end
            mod = 2'd1; #1;
            for (i = 0; i < N; i = i + 1) begin
                rv = relu_mem[k * N + i];
                kontrol_et(cikis_flat[i*8 +: 8], rv[15:8], "mod 1 ReLU ileri");
            end
            for (i = 0; i < N; i = i + 1) begin
                rv = relu_mem[k * N + i];
                veri_flat[i*8 +: 8]  = rv[23:16];      // e
                maske_flat[i*8 +: 8] = rv[31:24];      // saklı a
            end
            mod = 2'd2; #1;
            for (i = 0; i < N; i = i + 1) begin
                rv = relu_mem[k * N + i];
                kontrol_et(cikis_flat[i*8 +: 8], rv[7:0], "mod 2 ReLU geri");
            end
            for (i = 0; i < N; i = i + 1) begin
                wv = wu_mem[k * N + i];
                w_flat[i*8 +: 8]    = wv[23:16];
                veri_flat[i*8 +: 8] = wv[15:8];
            end
            mod = 2'd3; #1;
            for (i = 0; i < N; i = i + 1) begin
                wv = wu_mem[k * N + i];
                kontrol_et(cikis_flat[i*8 +: 8], wv[7:0], "mod 3 agirlik guncelleme");
            end
        end

        // ---------------- B) CLU yolu ----------------
        for (j = 0; j < nv; j = j + 1) begin
            bosluk = $urandom(tohum) % 13;
            tohum = tohum + 1;
            repeat (bosluk) @(negedge clk);
            for (i = 0; i < 10; i = i + 1) begin
                clu_a_flat[i*8 +: 8] = cv[j][i];
                e_bek[i*8 +: 8]      = cv[j][12 + i];
            end
            clu_sa       = cv[j][10];
            clu_y_onehot = 10'd1 << cv[j][11];
            clu_basla = 1'b1;
            @(negedge clk);
            clu_basla = 1'b0;
            kontrol_et(clu_mesgul, 1, $sformatf("vektor %0d mesgul", j));
            // girişleri boz: modül kenarda tutmuş olmalı
            clu_a_flat = ~clu_a_flat; clu_sa = ~clu_sa; clu_y_onehot = 10'd0;
            cevrim = 0;   // clu_basla kenarından sonraki kenar sayısı
            while (!clu_bitti && cevrim < 400) begin
                if (j % 7 == 3 && cevrim == 20) begin
                    clu_basla = 1'b1;                   // meşgulken ikinci istek: yok sayılmalı
                    @(negedge clk);
                    clu_basla = 1'b0;
                end else
                    @(negedge clk);
                cevrim = cevrim + 1;
                if (!clu_bitti) kontrol_et(clu_mesgul, 1, $sformatf("vektor %0d mesgul surer", j));
            end
            kontrol_et(cevrim, BEKLEME, $sformatf("vektor %0d gecikme", j));
            for (i = 0; i < 10; i = i + 1)
                kontrol_et($signed(clu_e_flat[i*8 +: 8]), $signed(e_bek[i*8 +: 8]),
                           $sformatf("vektor %0d e%0d", j, i));
            @(negedge clk);
            kontrol_et(clu_bitti, 0, $sformatf("vektor %0d bitti tek cevrim", j));
            kontrol_et(clu_mesgul, 0, $sformatf("vektor %0d mesgul bitti", j));
            repeat (2) @(negedge clk);
            for (i = 0; i < 10; i = i + 1)
                kontrol_et(clu_e_flat[i*8 +: 8], e_bek[i*8 +: 8], $sformatf("vektor %0d e%0d sabit kaldi", j, i));
        end

        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_fe_top: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_fe_top: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
