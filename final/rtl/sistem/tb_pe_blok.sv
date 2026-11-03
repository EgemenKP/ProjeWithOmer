// =============================================================================
//  tb_pe_blok.sv — Adım 4: pe_sarmalayici ve psum_fifo testbench'i
// -----------------------------------------------------------------------------
//  A) pe_sarmalayici, Egemen'in beş PE modülüne karşı adım adım (lockstep):
//     Testbench aynı beş modülü kendi bağlantısıyla (port adlarıyla) ayrıca kurar ve aynı
//     uyarıyı yalnızca seçili moda verir. Her çevrimde sarmalayıcının çıkışı, seçili
//     referans modülün çıkışıyla aynı olmalı. 400 bölüm, her biri rastgele mod (0..7),
//     rastgele ağırlık, 5..40 çevrim rastgele akış ve kısmi toplam; WG modlarında ara sıra
//     rst. Mod değişince WG akümülatörlerinin korunduğu da böylece sınanır (referans da
//     yalnızca kendi modunda çalışıyor).
//     (Anlamsal doğruluk ayrıca Icarus'ta Egemen'in kendi PE testbench'leri sarmalayıcıdan
//     geçirilerek ölçüldü: 6 modun hepsi geçti, gecikme kaymaları değişmedi; README.)
//  B) psum_fifo (derinlik 256), bir kuyruk modeline karşı 60.000 çevrim rastgele yaz/oku,
//     taşma ve eksik denemeleri, ara sıra rst.
//  Sonuç: "SONUC tb_pe_blok: PASS k/k" (konsol ve <+VEKTOR_DIZINI>/sonuc_tb_pe_blok.txt)
// =============================================================================
`timescale 1ns/1ps

module tb_pe_blok;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    integer hata, kontrol, tohum, sfd;
    // xorshift32 rastgele sayı üreteci (sabit tohum: her çalıştırmada aynı dizi)
    reg [31:0] rs = 32'h1234_5678;
    function [31:0] rnd(input integer bos_arg);
        begin
            rs = rs ^ (rs << 13); rs = rs ^ (rs >> 17); rs = rs ^ (rs << 5);
            rnd = rs;
        end
    endfunction
    string  dizin;

    task kontrol_et(input [287:0] olan, input [287:0] beklenen, input string ne);
        begin
            kontrol = kontrol + 1;
            if (olan !== beklenen) begin
                hata = hata + 1;
                if (hata <= 20) $display("FAIL %s: olan %h, beklenen %h", ne, olan, beklenen);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // A) PE sarmalayıcısı
    // ------------------------------------------------------------------
    reg          rst_pe;
    reg  [2:0]   mod;
    reg  [71:0]  w;
    reg  [23:0]  a1, a2, a3;
    reg  [127:0] ps;
    wire [127:0] cikis;
    wire [287:0] g;

    pe_sarmalayici dut (.clk(clk), .rst(rst_pe), .mod(mod), .w_flat(w),
                        .akis1(a1), .akis2(a2), .akis3(a3), .ps_flat(ps),
                        .cikis_flat(cikis), .g_flat(g));

    // Referanslar: yalnızca kendi modunda uyarı alır
    wire s_c = (mod == 3'd0) || (mod == 3'd2);
    wire s_f = (mod == 3'd1);
    wire s_b = (mod == 3'd3);
    wire s_1 = (mod == 3'd4);
    wire s_2 = (mod == 3'd5);
    function signed [7:0] B8(input s, input [23:0] v, input integer r); B8 = s ? v[8*r +: 8] : 8'sd0; endfunction
    function signed [7:0] W8(input s, input [71:0] v, input integer k); W8 = s ? v[8*k +: 8] : 8'sd0; endfunction
    function signed [31:0] P32(input s, input [127:0] v, input integer k); P32 = s ? v[32*k +: 32] : 32'sd0; endfunction

    wire signed [31:0] rc, rf, rb0, rb1, rb2, rb3;
    wire signed [31:0] r1_00, r1_01, r1_02, r1_10, r1_11, r1_12, r1_20, r1_21, r1_22;
    wire signed [31:0] r2_00, r2_01, r2_02, r2_10, r2_11, r2_12, r2_20, r2_21, r2_22;

    pe_chain3 ref_c (.clk(clk),
        .w00(W8(s_c,w,0)), .w01(W8(s_c,w,1)), .w02(W8(s_c,w,2)),
        .w10(W8(s_c,w,3)), .w11(W8(s_c,w,4)), .w12(W8(s_c,w,5)),
        .w20(W8(s_c,w,6)), .w21(W8(s_c,w,7)), .w22(W8(s_c,w,8)),
        .x_row0(B8(s_c,a1,0)), .x_row1(B8(s_c,a1,1)), .x_row2(B8(s_c,a1,2)),
        .ps_in(P32(s_c,ps,0)), .psum_out(rc));
    pe_fp_s2 ref_f (.clk(clk),
        .w00(W8(s_f,w,0)), .w01(W8(s_f,w,1)), .w02(W8(s_f,w,2)),
        .w10(W8(s_f,w,3)), .w11(W8(s_f,w,4)), .w12(W8(s_f,w,5)),
        .w20(W8(s_f,w,6)), .w21(W8(s_f,w,7)), .w22(W8(s_f,w,8)),
        .cift_r0(B8(s_f,a1,0)), .tek_r0(B8(s_f,a2,0)),
        .cift_r1(B8(s_f,a1,1)), .tek_r1(B8(s_f,a2,1)),
        .cift_r2(B8(s_f,a1,2)), .tek_r2(B8(s_f,a2,2)),
        .ps_in(P32(s_f,ps,0)), .psum_out(rf));
    pe_bp_s2 ref_b (.clk(clk),
        .w00(W8(s_b,w,0)), .w01(W8(s_b,w,1)), .w02(W8(s_b,w,2)),
        .w10(W8(s_b,w,3)), .w11(W8(s_b,w,4)), .w12(W8(s_b,w,5)),
        .w20(W8(s_b,w,6)), .w21(W8(s_b,w,7)), .w22(W8(s_b,w,8)),
        .e_row0(B8(s_b,a1,0)), .e_row1(B8(s_b,a1,1)), .e_row2(B8(s_b,a1,2)),
        .psA0(P32(s_b,ps,0)), .psB0(P32(s_b,ps,1)), .psA1(P32(s_b,ps,2)), .psB1(P32(s_b,ps,3)),
        .out0(rb0), .out1(rb1), .out2(rb2), .out3(rb3));
    pe_wg_s1 ref_1 (.clk(clk), .rst(rst_pe & s_1),
        .a_row0(B8(s_1,a1,0)), .e_row0(B8(s_1,a2,0)),
        .a_row1(B8(s_1,a1,1)), .e_row1(B8(s_1,a2,1)),
        .a_row2(B8(s_1,a1,2)), .e_row2(B8(s_1,a2,2)),
        .g00(r1_00), .g01(r1_01), .g02(r1_02), .g10(r1_10), .g11(r1_11), .g12(r1_12),
        .g20(r1_20), .g21(r1_21), .g22(r1_22));
    pe_wg_s2 ref_2 (.clk(clk), .rst(rst_pe & s_2),
        .cift_r0(B8(s_2,a1,0)), .tek_r0(B8(s_2,a2,0)), .e_row0(B8(s_2,a3,0)),
        .cift_r1(B8(s_2,a1,1)), .tek_r1(B8(s_2,a2,1)), .e_row1(B8(s_2,a3,1)),
        .cift_r2(B8(s_2,a1,2)), .tek_r2(B8(s_2,a2,2)), .e_row2(B8(s_2,a3,2)),
        .g00(r2_00), .g01(r2_01), .g02(r2_02), .g10(r2_10), .g11(r2_11), .g12(r2_12),
        .g20(r2_20), .g21(r2_21), .g22(r2_22));

    wire [127:0] bek_cikis = s_c ? {96'd0, rc} : s_f ? {96'd0, rf} : s_b ? {rb3, rb2, rb1, rb0} : 128'd0;
    wire [287:0] bek_g = s_1 ? {r1_22, r1_21, r1_20, r1_12, r1_11, r1_10, r1_02, r1_01, r1_00} :
                         s_2 ? {r2_22, r2_21, r2_20, r2_12, r2_11, r2_10, r2_02, r2_01, r2_00} : 288'd0;

    // ------------------------------------------------------------------
    // B) Psum FIFO
    // ------------------------------------------------------------------
    reg         f_rst, f_yaz, f_oku;
    reg  [31:0] f_veri;
    wire [31:0] f_bas;
    wire        f_bos, f_dolu, f_tasma, f_eksik;
    wire [8:0]  f_doluluk;
    psum_fifo #(.DERINLIK(256), .AW(8)) u_fifo (
        .clk(clk), .rst(f_rst), .yaz(f_yaz), .yaz_veri(f_veri), .oku(f_oku),
        .bas_veri(f_bas), .bos(f_bos), .dolu(f_dolu), .doluluk(f_doluluk),
        .tasma(f_tasma), .eksik(f_eksik));

    reg [31:0] kuyruk [0:255];
    integer k_bas, k_say, k_tasma, k_eksik, bolum, uzunluk, cv, i, mod_r;
    integer say_dolu, say_bos, say_tasma_den, say_eksik_den, say_rst;   // kapsam sayaçları
    integer say_mod [0:7];
    // Beklenen değerler önce değişkene alınır: XSIM, geniş bir task girişine doğrudan verilen
    // karşılaştırma ifadesini (ör. (k_say == 0)) bozuk değerlendiriyor (03.11, Vivado'da görüldü).
    integer bek_bos, bek_dolu;
    reg [31:0] bek_bas;

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            sfd = $fopen({dizin, "sonuc_tb_pe_blok.txt"}, "w");
            if (sfd != 0) begin
                $fdisplay(sfd, "%s", satir);
                $fclose(sfd);
            end
        end
    endtask

    initial begin
        hata = 0; kontrol = 0; tohum = 404;
        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin)) dizin = "";
        // Klasör doğru mu? (yolda boşluk varsa plusarg bozulur) Vektör klasöründeki komutlar.txt
        // bulunamazsa sonuç dosyası çalışma klasörüne yazılır.
        sfd = $fopen({dizin, "komutlar.txt"}, "r");
        if (sfd == 0) dizin = ""; else $fclose(sfd);

        // ---------------- A ----------------
        rst_pe = 1'b0; mod = 3'd7; w = 0; a1 = 0; a2 = 0; a3 = 0; ps = 0;
        // Başlangıç: bütün WG akümülatörlerini sıfırla
        mod = 3'd4; rst_pe = 1'b1; @(negedge clk); mod = 3'd5; @(negedge clk); rst_pe = 1'b0;
        for (i = 0; i < 8; i = i + 1) say_mod[i] = 0;
        for (bolum = 0; bolum < 400; bolum = bolum + 1) begin
            mod_r = rnd(0) % 8; tohum = tohum + 1;
            mod = mod_r[2:0];
            say_mod[mod_r] = say_mod[mod_r] + 1;
            w = {rnd(0), rnd(0), rnd(0)}; tohum = tohum + 3;
            uzunluk = 5 + (rnd(0) % 36); tohum = tohum + 1;
            for (cv = 0; cv < uzunluk; cv = cv + 1) begin
                a1 = rnd(0); a2 = rnd(0); a3 = rnd(0);
                ps = {rnd(0), rnd(0), rnd(0), rnd(0)};
                rst_pe = ((rnd(0) % 23) == 0);
                tohum = tohum + 8;
                #1;
                kontrol_et(cikis, bek_cikis, $sformatf("bolum %0d mod %0d cevrim %0d cikis", bolum, mod, cv));
                kontrol_et(g, bek_g, $sformatf("bolum %0d mod %0d cevrim %0d g", bolum, mod, cv));
                @(negedge clk);
                kontrol_et(cikis, bek_cikis, $sformatf("bolum %0d mod %0d cevrim %0d cikis (kenar sonrasi)", bolum, mod, cv));
                kontrol_et(g, bek_g, $sformatf("bolum %0d mod %0d cevrim %0d g (kenar sonrasi)", bolum, mod, cv));
            end
        end
        rst_pe = 1'b0;

        // ---------------- B ----------------
        f_rst = 1'b1; f_yaz = 1'b0; f_oku = 1'b0; f_veri = 0;
        @(negedge clk); f_rst = 1'b0;
        k_bas = 0; k_say = 0; k_tasma = 0; k_eksik = 0;
        say_dolu = 0; say_bos = 0; say_tasma_den = 0; say_eksik_den = 0; say_rst = 0;
        for (cv = 0; cv < 60000; cv = cv + 1) begin
            // Kuyruk durumu kontrolü (kenardan sonra)
            kontrol_et(f_doluluk, k_say, $sformatf("fifo cevrim %0d doluluk", cv));
            bek_bos  = (k_say == 0)   ? 1 : 0;
            bek_dolu = (k_say == 256) ? 1 : 0;
            kontrol_et(f_bos, bek_bos, $sformatf("fifo cevrim %0d bos", cv));
            kontrol_et(f_dolu, bek_dolu, $sformatf("fifo cevrim %0d dolu", cv));
            kontrol_et(f_tasma, k_tasma, $sformatf("fifo cevrim %0d tasma", cv));
            kontrol_et(f_eksik, k_eksik, $sformatf("fifo cevrim %0d eksik", cv));
            if (k_say > 0) begin
                bek_bas = kuyruk[k_bas];
                kontrol_et(f_bas, bek_bas, $sformatf("fifo cevrim %0d bas", cv));
            end
            // Rastgele işlem: dolulukla dolaşan bir eğilim (dolma ve boşalma ikisi de görülsün)
            mod_r = rnd(0) % 100; tohum = tohum + 1;
            f_veri = rnd(0); tohum = tohum + 1;
            f_yaz = ((cv / 3000) % 2 == 0) ? (mod_r < 70) : (mod_r < 30);
            f_oku = ((cv / 3000) % 2 == 0) ? (mod_r >= 55) : (mod_r >= 20);
            f_rst = ((rnd(0) % 9000) == 0); tohum = tohum + 1;
            if (k_say == 256) say_dolu = say_dolu + 1;
            if (k_say == 0) say_bos = say_bos + 1;
            if (f_yaz && k_say == 256) say_tasma_den = say_tasma_den + 1;
            if (f_oku && k_say == 0) say_eksik_den = say_eksik_den + 1;
            if (f_rst) say_rst = say_rst + 1;
            @(negedge clk);
            // Model
            if (f_rst) begin
                k_bas = 0; k_say = 0; k_tasma = 0; k_eksik = 0;
            end else begin
                if (f_yaz && k_say == 256) k_tasma = 1;
                if (f_oku && k_say == 0)   k_eksik = 1;
                begin : model
                    integer yazildi, okundu;
                    yazildi = (f_yaz && k_say < 256);
                    okundu  = (f_oku && k_say > 0);
                    if (yazildi) kuyruk[(k_bas + k_say) % 256] = f_veri;
                    if (okundu) k_bas = (k_bas + 1) % 256;
                    k_say = k_say + yazildi - okundu;
                end
            end
        end

        $display("KAPSAM: mod bolumleri %0d %0d %0d %0d %0d %0d %0d %0d; fifo dolu %0d, bos %0d, dolu iken yazma %0d, bos iken okuma %0d, rst %0d",
                 say_mod[0], say_mod[1], say_mod[2], say_mod[3], say_mod[4], say_mod[5], say_mod[6], say_mod[7],
                 say_dolu, say_bos, say_tasma_den, say_eksik_den, say_rst);
        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_pe_blok: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_pe_blok: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
