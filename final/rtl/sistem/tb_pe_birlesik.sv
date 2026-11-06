// =============================================================================
//  tb_pe_birlesik.sv — pe_birlesik (tek PE, 9 MAC; D69) eski pe_sarmalayici'ya karşı (45 MAC)
// -----------------------------------------------------------------------------
//  İki devre aynı uyarıyla adım adım (lockstep) çalışır; her akış çevriminde cikis_flat ve
//  g_flat bit bit aynı olmalı. Uyarı, PE motorunun (pe_motoru.v) komut düzenini taklit eder:
//    - komutlar arası 1..3 çevrim boşta (mod 6/7, bütün girişler 0)       [D_BOSTA]
//    - komutun modunda 4 çevrim 0 akış (ağırlık + 3 satır okuması)          [D_AGIRLIK, D_SATIR]
//      Bu çevrimlerde karşılaştırma yok: ortak register'lar önceki modu temizliyor (D69).
//    - WG'de ilk komut 1 çevrim rst; aynı WG işinin sonraki komutları rst'siz (akümülatör
//      korunur). Bir WG işi yalnızca aynı WG moduyla sürer; araya başka mod girerse yeni iş
//      rst ile başlar (PE motorunun döngü sırası, D47).
//    - 3..40 çevrim rastgele akış (akis1/2/3) ve kısmi toplam, ardından 3 çevrim 0 akış
//      (zincir boşalması); hepsinde karşılaştırma.
//  3000 komut, her mod ve mod geçişi; değerler -128..127 (D23).
//  Sonuç: "SONUC tb_pe_birlesik: PASS k/k" (konsol ve <+VEKTOR_DIZINI>/sonuc_tb_pe_birlesik.txt)
//  Yazan: Claude, 03.11.2026
// =============================================================================
`timescale 1ns/1ps

module tb_pe_birlesik;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    integer hata = 0, kontrol = 0, sfd;
    reg [31:0] rs = 32'h0BAD_C0DE;
    function [31:0] rnd(input integer bos_arg);
        begin
            rs = rs ^ (rs << 13); rs = rs ^ (rs >> 17); rs = rs ^ (rs << 5);
            rnd = rs;
        end
    endfunction
    string dizin;

    reg          rst_pe = 1'b0;
    reg  [2:0]   mod    = 3'd7;
    reg  [71:0]  w      = 72'd0;
    reg  [23:0]  a1 = 24'd0, a2 = 24'd0, a3 = 24'd0;
    reg  [127:0] ps     = 128'd0;

    wire [127:0] c_yeni, c_eski;
    wire [287:0] g_yeni, g_eski;

    pe_birlesik    dut (.clk(clk), .rst(rst_pe), .mod(mod), .w_flat(w),
                        .akis1(a1), .akis2(a2), .akis3(a3), .ps_flat(ps),
                        .cikis_flat(c_yeni), .g_flat(g_yeni));
    pe_sarmalayici ref_pe (.clk(clk), .rst(rst_pe), .mod(mod), .w_flat(w),
                        .akis1(a1), .akis2(a2), .akis3(a3), .ps_flat(ps),
                        .cikis_flat(c_eski), .g_flat(g_eski));

    // Her mod için kaç komut karşılaştırıldı
    integer mod_say [0:5];
    integer gecis_say = 0;

    reg [127:0] c_y, c_e;
    reg [287:0] g_y, g_e;
    task karsilastir(input string ne);
        begin
            // Önce değişkene al (araç tuzağı 10: XSIM, task'a verilen ifadeyi bozabiliyor)
            c_y = c_yeni; c_e = c_eski; g_y = g_yeni; g_e = g_eski;
            // D104 (06.11): pe_birlesik seçili olmayan şeritleri / modda çıkışı artık 0'a çekmiyor (eski sarmalayıcı
            // çekiyor). Yalnızca o modun tüketicilerinin okuduğu kısım karşılaştırılır: zincir modlarında (FP s1/s2,
            // BP s1) şerit 0, BP s2'de 4 şerit, WG'de akümülatörler; diğer kısım iki tarafta da maskelenir.
            case (mod)
                3'd0, 3'd1, 3'd2: begin c_y[127:32] = 96'd0; c_e[127:32] = 96'd0; g_y = 288'd0; g_e = 288'd0; end
                3'd3:             begin g_y = 288'd0; g_e = 288'd0; end
                3'd4, 3'd5:       begin c_y = 128'd0; c_e = 128'd0; end
                default:          begin c_y = 128'd0; c_e = 128'd0; g_y = 288'd0; g_e = 288'd0; end
            endcase
            kontrol = kontrol + 1;
            if (c_y !== c_e || g_y !== g_e) begin
                hata = hata + 1;
                if (hata <= 20)
                    $display("FAIL %s mod %0d: cikis %h / %h, g %h / %h", ne, mod, c_y, c_e, g_y, g_e);
            end
        end
    endtask

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            sfd = $fopen({dizin, "sonuc_tb_pe_birlesik.txt"}, "w");
            if (sfd == 0) sfd = $fopen("sonuc_tb_pe_birlesik.txt", "w");
            if (sfd != 0) begin $fdisplay(sfd, "%s", satir); $fclose(sfd); end
        end
    endtask

    integer n, i, L, bos, onceki_mod, wg_is_modu, m_yeni;
    reg ilk;

    initial begin
        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin)) dizin = "";
        for (i = 0; i < 6; i = i + 1) mod_say[i] = 0;
        onceki_mod = 7;
        wg_is_modu = 7;                       // süren WG işinin modu (yoksa 7)
        repeat (3) @(posedge clk);

        for (n = 0; n < 3000; n = n + 1) begin
            // ---- boşta (D_BOSTA) ----
            bos = 1 + rnd(0) % 3;
            for (i = 0; i < bos; i = i + 1) begin
                @(negedge clk); mod = 3'd6 + (rnd(0) & 1); a1 = 0; a2 = 0; a3 = 0; ps = 0; rst_pe = 0;
                @(posedge clk); #1 karsilastir("bosta");
            end

            // ---- komutun modu ----
            m_yeni = rnd(0) % 6;
            // WG işi sürüyorsa çoğunlukla aynı modda devam et
            if (wg_is_modu != 7 && (rnd(0) % 4) != 0) m_yeni = wg_is_modu;
            if (m_yeni >= 4) begin
                ilk = (wg_is_modu != m_yeni) || ((rnd(0) % 3) == 0);
                wg_is_modu = m_yeni;
            end else begin
                ilk = 1'b1;
                wg_is_modu = 7;               // başka mod: WG işi biter
            end
            if (m_yeni != onceki_mod) gecis_say = gecis_say + 1;
            onceki_mod = m_yeni;
            mod_say[m_yeni] = mod_say[m_yeni] + 1;

            // ---- ağırlık + 3 satır okuması: 4 çevrim 0 akış, karşılaştırma yok ----
            @(negedge clk);
            mod = m_yeni[2:0];
            w   = (m_yeni >= 4) ? 72'd0 : {rnd(0), rnd(0), rnd(0)};
            repeat (4) @(negedge clk);

            // ---- WG rst ----
            if (m_yeni >= 4 && ilk) begin
                rst_pe = 1'b1;
                @(negedge clk);
                rst_pe = 1'b0;
            end

            // ---- akış ----
            L = 3 + rnd(0) % 38;
            for (i = 0; i < L; i = i + 1) begin
                a1 = rnd(0); a2 = rnd(0); a3 = rnd(0);
                ps = {rnd(0), rnd(0), rnd(0), rnd(0)};
                // ara sıra uç değerler (-128, 127, büyük kısmi toplamlar)
                if ((rnd(0) % 8) == 0) a1 = {3{8'h80}};
                if ((rnd(0) % 8) == 0) a2 = {3{8'h7F}};
                @(posedge clk); #1 karsilastir("akis");
                @(negedge clk);
            end
            // ---- zincir boşalması ----
            a1 = 0; a2 = 0; a3 = 0; ps = 0;
            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk); #1 karsilastir("bosalma");
                @(negedge clk);
            end
        end

        $display("Komut sayisi (FP s1, FP s2, BP s1, BP s2, WG s1, WG s2): %0d %0d %0d %0d %0d %0d; mod gecisi %0d",
                 mod_say[0], mod_say[1], mod_say[2], mod_say[3], mod_say[4], mod_say[5], gecis_say);
        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_pe_birlesik: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_pe_birlesik: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
