// =============================================================================
//  tb_on_getirme.sv — on_getirme + veri/ağırlık tamponları, dizili sistem golden'ının izine karşı
// -----------------------------------------------------------------------------
//  Vektörler (models/sistem/adim5_vektorleri/ ve ag2/, dizi_sistem_golden.py):
//    ag_yapilandirma.txt, bolgeler.txt, komutlar_dizi.txt, veri_beklenen.txt, agirlik_baslangic.txt,
//    onget_izi.txt
//  Veri tamponu golden'ın son hâliyle yüklenir: her bölge bir kez yazılıyor, okunduğu andaki hâli son hâliyle
//  aynı. Ağırlık tamponu başlangıç hâliyle: FP ve BP güncellenmemiş ağırlıkları okuyor (D46). Bölgelerin G'si
//  bolgeler.txt'ten.
//  Her DİZİ komutunda ön-getirme başlatılır; akışın her çevriminde 16 PE satırının akis1/2/3'ü ve 16
//  sütunun hattı (ağırlık ya da WG hatası) golden'ın izine karşı karşılaştırılır; akış boyu ve mod da.
//  Sonuç: "SONUC tb_on_getirme: PASS n/n"
//  Üst modülde sinyal yok (araç tuzağı 13). Yazan: Claude, 04.11.2026 (final/, Adım 5b-3b)
// =============================================================================
`timescale 1ns/1ps

module tb_on_getirme;
    tb_on_getirme_govde govde ();
endmodule

module tb_on_getirme_govde;

    localparam NB = 16, AW = 9, LMAX = 8;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                    rst = 1'b1;
    reg                    basla = 1'b0;
    reg  [1:0]             faz = 0;
    reg  [3:0]             l = 1;
    reg  [7:0]             b = 0, k0 = 0, k1 = 0, z = 0;
    reg  [LMAX*8-1:0]      cfg_cin = 0, cfg_cout = 0, cfg_h = 0, cfg_w = 0, cfg_s = 0, cfg_p = 0;
    reg  [(LMAX+1)*AW-1:0] taban_akt = 0, taban_hata = 0, taban_agr = 0;
    reg  [(LMAX+1)*6-1:0]  G_akt = 0, G_hata = 0;

    wire [NB*AW-1:0]   v_adr, a_adr;
    wire [NB*134-1:0]  v_veri;
    wire [NB*72-1:0]   a_veri;
    reg  [NB-1:0]      v_yaz_en = 0, a_yaz_en = 0;
    reg  [NB*AW-1:0]   v_yaz_adr = 0, a_yaz_adr = 0;
    reg  [NB*134-1:0]  v_yaz_veri = 0;
    reg  [NB*72-1:0]   a_yaz_veri = 0;

    wire [2:0]         mod;
    wire [NB*24-1:0]   a1, a2, a3;
    wire [NB*72-1:0]   sw;
    wire               akis, bitti, mesgul;
    wire [7:0]         t, T;

    veri_tamponu #(.NB(NB), .AW(AW)) u_vt (.clk(clk), .oku_adr(v_adr), .oku_veri(v_veri),
        .yaz_en(v_yaz_en), .yaz_adr(v_yaz_adr), .yaz_veri(v_yaz_veri));
    agirlik_tamponu #(.NB(NB), .AW(AW)) u_at (.clk(clk), .oku_adr(a_adr), .oku_veri(a_veri),
        .yaz_en(a_yaz_en), .yaz_adr(a_yaz_adr), .yaz_veri(a_yaz_veri));

    on_getirme #(.NB(NB), .AW(AW), .LMAX(LMAX)) dut (
        .clk(clk), .rst(rst), .basla(basla), .faz(faz), .l(l), .b(b), .k0(k0), .k1(k1), .z(z),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s), .cfg_p(cfg_p),
        .taban_akt(taban_akt), .taban_hata(taban_hata), .taban_agr(taban_agr), .G_akt(G_akt), .G_hata(G_hata),
        .v_oku_adr(v_adr), .v_oku_veri(v_veri), .a_oku_adr(a_adr), .a_oku_veri(a_veri),
        .dis_G_sec(1'b0), .dis_G(6'd0), .gms_flat(),               // D100: tek birim

        .mod(mod), .satir_akis1_flat(a1), .satir_akis2_flat(a2), .satir_akis3_flat(a3), .sutun_w_flat(sw),
        .akis(akis), .t(t), .T(T), .bitti(bitti), .mesgul(mesgul));

    integer kontrol = 0, hata = 0, n_ag = 0, n_kayit_top = 0;
    integer bekle;
    integer fd, n, i, j, q, v, x, kn, md, TT, nr, nc, L, tmp, bank, adr, ll;
    integer kom [0:1023][0:9];
    integer ex_satir [0:15][0:63][0:8];
    integer ex_sutun [0:15][0:63];
    reg [8*16-1:0] ad;
    string dizin, yol;
    reg [133:0] kel;
    reg [71:0]  wk;

    task automatic dosya_ac(input string alt, input string isim);
        yol = {dizin, alt, isim};
        fd = $fopen(yol, "r");
        if (fd == 0) begin
            yol = {alt, isim};
            fd = $fopen(yol, "r");
        end
        if (fd == 0) begin hata = hata + 1; $display("HATA: %s acilamadi", yol); end
    endtask

    task automatic hata_say(input integer kom_no, input reg [8*24-1:0] ne, input integer satir, input integer tt,
                            input integer olan, input integer beklenen);
        hata = hata + 1;
        if (hata <= 12) $display("HATA komut %0d %0s [%0d] t=%0d: %0d, beklenen %0d", kom_no, ne, satir, tt, olan, beklenen);
    endtask

    task automatic ag_kos(input string alt);
        // ---- yapılandırma ----
        dosya_ac(alt, "ag_yapilandirma.txt");
        void'($fscanf(fd, "%d %d %d %d %d", L, tmp, tmp, tmp, tmp));
        for (ll = 0; ll < L; ll = ll + 1) begin
            void'($fscanf(fd, "%d %d %d %d %d %d %d %d", i, j, n, x, q, v, tmp, tmp));
            cfg_cin[8*ll +: 8] = i; cfg_cout[8*ll +: 8] = j; cfg_h[8*ll +: 8] = n; cfg_w[8*ll +: 8] = x;
            cfg_s[8*ll +: 8] = q; cfg_p[8*ll +: 8] = v;
        end
        $fclose(fd);
        dosya_ac(alt, "bolgeler.txt");
        void'($fscanf(fd, "%d %d", n, tmp));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d %d %d %d %d %d", ad, adr, tmp, tmp, tmp, tmp, tmp, v));
            // ad = AKTl / HATAl / GRADl; son karakter katman
            ll = ad[7:0] - "0";
            if ((ad >> 8) == "AKT")  begin taban_akt[AW*ll +: AW] = adr;  G_akt[6*ll +: 6] = v; end
            if ((ad >> 8) == "HATA") begin taban_hata[AW*ll +: AW] = adr; G_hata[6*ll +: 6] = v; end
        end
        for (i = 0; i < L; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d", ad, ll, adr));
            taban_agr[AW*ll +: AW] = adr;
        end
        $fclose(fd);
        // ---- tamponlar ----
        dosya_ac(alt, "veri_beklenen.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d %d", bank, adr, v));
            kel = 0; kel[133:128] = v;
            for (q = 0; q < 16; q = q + 1) begin void'($fscanf(fd, "%d", x)); kel[8*q +: 8] = x; end
            @(negedge clk);
            v_yaz_en = 0; v_yaz_en[bank] = 1'b1; v_yaz_adr[AW*bank +: AW] = adr; v_yaz_veri[134*bank +: 134] = kel;
        end
        $fclose(fd);
        dosya_ac(alt, "agirlik_baslangic.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d", bank, adr));
            wk = 0;
            for (q = 0; q < 9; q = q + 1) begin void'($fscanf(fd, "%d", x)); wk[8*q +: 8] = x; end
            @(negedge clk);
            v_yaz_en = 0;
            a_yaz_en = 0; a_yaz_en[bank] = 1'b1; a_yaz_adr[AW*bank +: AW] = adr; a_yaz_veri[72*bank +: 72] = wk;
        end
        $fclose(fd);
        @(negedge clk); v_yaz_en = 0; a_yaz_en = 0;
        // ---- komutlar ----
        dosya_ac(alt, "komutlar_dizi.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1)
            for (q = 0; q < 10; q = q + 1) void'($fscanf(fd, "%d", kom[i][q]));
        $fclose(fd);
        // ---- iz ----
        dosya_ac(alt, "onget_izi.txt");
        void'($fscanf(fd, "%d", n));
        n_ag = n_ag + 1;
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d %d %d %d", ad, kn, md, TT, nr, nc));
            for (j = 0; j < 16; j = j + 1)
                for (x = 0; x < TT; x = x + 1) for (q = 0; q < 9; q = q + 1) ex_satir[j][x][q] = 0;
            for (j = 0; j < nr; j = j + 1)
                for (x = 0; x < TT; x = x + 1) for (q = 0; q < 9; q = q + 1) void'($fscanf(fd, "%d", ex_satir[j][x][q]));
            for (j = 0; j < 16; j = j + 1) for (x = 0; x < 64; x = x + 1) ex_sutun[j][x] = 0;
            for (j = 0; j < nc; j = j + 1)
                for (x = 0; x < ((md < 4) ? 9 : TT); x = x + 1) void'($fscanf(fd, "%d", ex_sutun[j][x]));
            // komutu ver
            @(negedge clk);
            faz = kom[kn][1]; l = kom[kn][2]; b = kom[kn][3]; k0 = kom[kn][4]; k1 = kom[kn][5]; z = kom[kn][6];
            basla = 1'b1;
            @(negedge clk);
            basla = 1'b0;
            bekle = 0;
            while (!akis && bekle < 5000) begin @(negedge clk); bekle = bekle + 1; end
            if (!akis) begin
                hata_say(kn, "akis baslamadi", 0, 0, 0, 1);
                $display("SONUC tb_on_getirme: FAIL %0d hata / %0d (zaman asimi)", hata, kontrol);
                $finish;
            end
            kontrol = kontrol + 2;
            if (T != TT) hata_say(kn, "T", 0, 0, T, TT);
            if (mod != md) hata_say(kn, "mod", 0, 0, mod, md);
            for (x = 0; x < TT; x = x + 1) begin
                if (!akis || t != x) hata_say(kn, "akis/t", 0, x, t, x);
                for (j = 0; j < 16; j = j + 1) begin
                    for (q = 0; q < 3; q = q + 1) begin
                        kontrol = kontrol + 3;
                        if ($signed(a1[24*j + 8*q +: 8]) != ex_satir[j][x][q])     hata_say(kn, "akis1", j, x, $signed(a1[24*j + 8*q +: 8]), ex_satir[j][x][q]);
                        if ($signed(a2[24*j + 8*q +: 8]) != ex_satir[j][x][3 + q]) hata_say(kn, "akis2", j, x, $signed(a2[24*j + 8*q +: 8]), ex_satir[j][x][3 + q]);
                        if ($signed(a3[24*j + 8*q +: 8]) != ex_satir[j][x][6 + q]) hata_say(kn, "akis3", j, x, $signed(a3[24*j + 8*q +: 8]), ex_satir[j][x][6 + q]);
                    end
                    if (md < 4) begin
                        for (q = 0; q < 9; q = q + 1) begin
                            kontrol = kontrol + 1;
                            if ($signed(sw[72*j + 8*q +: 8]) != ex_sutun[j][q]) hata_say(kn, "agirlik", j, q, $signed(sw[72*j + 8*q +: 8]), ex_sutun[j][q]);
                        end
                    end else begin
                        kontrol = kontrol + 1;
                        if (sw[72*j +: 72] !== {48'd0, ex_sutun[j][x][7:0], ex_sutun[j][x][7:0], ex_sutun[j][x][7:0]})
                            hata_say(kn, "WG hata", j, x, $signed(sw[72*j +: 8]), ex_sutun[j][x]);
                    end
                end
                @(negedge clk);
            end
            kontrol = kontrol + 1;
            if (akis) hata_say(kn, "akis uzun", 0, TT, 1, 0);
            n_kayit_top = n_kayit_top + 1;
        end
        $fclose(fd);
    endtask

    integer sfd;
    initial begin
        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin)) dizin = "";
        repeat (2) @(negedge clk);
        rst = 1'b0;
        ag_kos("");
        ag_kos("ag2/");
        ag_kos("ag3/");
        ag_kos("ag4/");
        ag_kos("ag5/");
        if (hata == 0) $display("SONUC tb_on_getirme: PASS %0d/%0d (%0d ag, %0d DIZI komutu)", kontrol, kontrol, n_ag, n_kayit_top);
        else           $display("SONUC tb_on_getirme: FAIL %0d hata / %0d", hata, kontrol);
        sfd = $fopen({dizin, "sonuc_tb_on_getirme.txt"}, "w");
        if (sfd != 0) begin
            if (hata == 0) $fdisplay(sfd, "SONUC tb_on_getirme: PASS %0d/%0d", kontrol, kontrol);
            else           $fdisplay(sfd, "SONUC tb_on_getirme: FAIL %0d hata / %0d", hata, kontrol);
            $fclose(sfd);
        end
        $finish;
    end

endmodule
