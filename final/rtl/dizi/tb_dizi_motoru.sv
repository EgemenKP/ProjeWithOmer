// =============================================================================
//  tb_dizi_motoru.sv — dizi_motoru + tamponlar, golden'ın komut listesini yürütür (Adım 5b-3c)
// -----------------------------------------------------------------------------
//  Vektörler (models/sistem/adim5_vektorleri/, ag2/ ve ag3/, dizi_sistem_golden.py): ag_yapilandirma.txt,
//  bolgeler.txt, komutlar_dizi.txt, veri_baslangic.txt, veri_beklenen.txt, agirlik_baslangic.txt.
//  Başlangıç: veri tamponu = AKT0 (veri_baslangic) + HATA[L] (CLU'nun çıkışı, veri_beklenen'den; CLU 3e'de);
//  ağırlık tamponu = başlangıç (DİZİ komutları WU'dan önce okuyor, D46); bölgelerin G'si bolgeler.txt'ten
//  (her bölge yazıldıktan sonra okunuyor, okunduğu andaki G son hâliyle aynı).
//  Komutlar sırayla: İŞ_BAŞLA -> is_basla; DİZİ -> motor; ÖLÇEK -> motorun G'si golden'ınkiyle; SA, CLU, WU
//  ve BİTTİ atlanır (3d/3e). Sonunda veri tamponunun golden'da yazılı bütün kelimeleri (16 int8 + l)
//  veri_beklenen.txt ile karşılaştırılır.
//  Sonuç: "SONUC tb_dizi_motoru: PASS n/n". Üst modülde sinyal yok (araç tuzağı 13).
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b-3c)
// =============================================================================
`timescale 1ns/1ps

module tb_dizi_motoru;
    tb_dizi_motoru_govde govde ();
endmodule

module tb_dizi_motoru_govde;

    localparam NB = 16, AW = 9, LMAX = 8;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                    rst = 1'b1;
    reg                    is_basla = 1'b0, basla = 1'b0, ilk = 1'b0, son = 1'b0;
    reg  [2:0]             hedef = 3'd7;
    reg  [1:0]             faz = 0;
    reg  [3:0]             l = 1;
    reg  [7:0]             b = 0, k0 = 0, k1 = 0, z = 0;
    reg  [LMAX*8-1:0]      cfg_cin = 0, cfg_cout = 0, cfg_h = 0, cfg_w = 0, cfg_s = 0, cfg_p = 0, cfg_relu = 0;
    reg  [(LMAX+1)*AW-1:0] taban_akt = 0, taban_hata = 0, taban_grad = 0, taban_agr = 0;
    reg  [(LMAX+1)*6-1:0]  G_akt = 0, G_hata = 0;
    reg  [(LMAX+1)*6-1:0]  G_grad = 0;

    wire [NB*AW-1:0]   m_v_adr, a_adr, m_yaz_adr;
    wire [NB*134-1:0]  v_veri, m_yaz_veri;
    wire [NB-1:0]      m_yaz_en;
    wire [NB*72-1:0]   a_veri;
    reg                tb_surer = 1'b1;            // 1: tamponların portlarını testbench sürer
    reg  [NB-1:0]      t_yaz_en = 0, ta_yaz_en = 0;
    reg  [NB*AW-1:0]   t_yaz_adr = 0, ta_yaz_adr = 0, t_oku_adr = 0;
    reg  [NB*134-1:0]  t_yaz_veri = 0;
    reg  [NB*72-1:0]   ta_yaz_veri = 0;
    wire               bitti, mesgul, tasma, eksik, ps_bos;
    wire [5:0]         G;

    veri_tamponu #(.NB(NB), .AW(AW)) u_vt (.clk(clk),
        .oku_adr(tb_surer ? t_oku_adr : m_v_adr), .oku_veri(v_veri),
        .yaz_en(tb_surer ? t_yaz_en : m_yaz_en), .yaz_adr(tb_surer ? t_yaz_adr : m_yaz_adr),
        .yaz_veri(tb_surer ? t_yaz_veri : m_yaz_veri));
    agirlik_tamponu #(.NB(NB), .AW(AW)) u_at (.clk(clk), .oku_adr(a_adr), .oku_veri(a_veri),
        .yaz_en(ta_yaz_en), .yaz_adr(ta_yaz_adr), .yaz_veri(ta_yaz_veri));

    dizi_motoru #(.NB(NB), .AW(AW), .LMAX(LMAX)) dut (
        .clk(clk), .rst(rst), .is_basla(is_basla), .hedef_in(hedef), .basla(basla), .faz(faz), .l(l),
        .b(b), .k0(k0), .k1(k1), .z(z), .ilk(ilk), .son(son), .bitti(bitti), .mesgul(mesgul), .G_out(G),
        .ps_tasma(tasma), .ps_eksik(eksik), .ps_bos(ps_bos),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s), .cfg_p(cfg_p),
        .cfg_relu(cfg_relu), .taban_akt(taban_akt), .taban_hata(taban_hata), .taban_grad(taban_grad),
        .taban_agr(taban_agr), .G_akt(G_akt), .G_hata(G_hata),
        .v_oku_adr(m_v_adr), .v_oku_veri(v_veri), .v_yaz_en(m_yaz_en), .v_yaz_adr(m_yaz_adr), .v_yaz_veri(m_yaz_veri),
        .a_oku_adr(a_adr), .a_oku_veri(a_veri),
        .sis_G_sec(1'b0), .sis_G(6'd0), .gms_flat());              // D100: yürütücü yok

    integer kontrol = 0, hata = 0, n_ag = 0, n_dizi = 0, n_kelime = 0;
    integer fd, n, i, q, x, v, L, tmp, bank, adr, ll, bekle, hl_bas, hl_son;
    integer kom [0:1023][0:9];
    reg [8*16-1:0] ad;
    string dizin, yol;
    reg [133:0] kel;
    reg [71:0]  wk;

    task automatic dosya_ac(input string alt, input string isim);
        yol = {dizin, alt, isim};
        fd = $fopen(yol, "r");
        if (fd == 0) begin yol = {alt, isim}; fd = $fopen(yol, "r"); end
        if (fd == 0) begin hata = hata + 1; $display("HATA: %s acilamadi", yol); end
    endtask

    task automatic veri_yaz(input integer bk, input integer ad_, input reg [133:0] k);
        @(negedge clk);
        t_yaz_en = 0; t_yaz_en[bk] = 1'b1; t_yaz_adr[AW*bk +: AW] = ad_; t_yaz_veri[134*bk +: 134] = k;
        @(negedge clk);
        t_yaz_en = 0;
    endtask

    task automatic kelime_oku(input string satir_dosya_kaydi);
    endtask

    task automatic ag_kos(input string alt);
        tb_surer = 1'b1;
        dosya_ac(alt, "ag_yapilandirma.txt");
        void'($fscanf(fd, "%d %d %d %d %d", L, tmp, tmp, tmp, tmp));
        cfg_relu = 0;
        for (ll = 0; ll < L; ll = ll + 1) begin
            void'($fscanf(fd, "%d %d %d %d %d %d %d %d", i, q, n, x, tmp, v, adr, bank));
            cfg_cin[8*ll +: 8] = i; cfg_cout[8*ll +: 8] = q; cfg_h[8*ll +: 8] = n; cfg_w[8*ll +: 8] = x;
            cfg_s[8*ll +: 8] = tmp; cfg_p[8*ll +: 8] = v; cfg_relu[8*ll +: 8] = adr;
        end
        $fclose(fd);
        dosya_ac(alt, "bolgeler.txt");
        void'($fscanf(fd, "%d %d", n, tmp));
        hl_bas = -1; hl_son = 1 << AW;
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d %d %d %d %d %d", ad, adr, tmp, tmp, tmp, tmp, tmp, v));
            ll = ad[7:0] - "0";
            if ((ad >> 8) == "AKT")  begin taban_akt[AW*ll +: AW] = adr;  G_akt[6*ll +: 6] = v; end
            if ((ad >> 8) == "HATA") begin taban_hata[AW*ll +: AW] = adr; G_hata[6*ll +: 6] = v; if (ll == L) hl_bas = adr; end
            if ((ad >> 8) == "GRAD") begin taban_grad[AW*ll +: AW] = adr; G_grad[6*ll +: 6] = v; if (ll == 1) hl_son = adr; end
        end
        for (i = 0; i < L; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d", ad, ll, adr));
            taban_agr[AW*ll +: AW] = adr;
        end
        $fclose(fd);
        // tamponları temizle (bir önceki ağdan kalan kelimeler)
        for (adr = 0; adr < (1 << AW); adr = adr + 1) begin
            @(negedge clk);
            t_yaz_en = {NB{1'b1}}; ta_yaz_en = {NB{1'b1}};
            for (bank = 0; bank < NB; bank = bank + 1) begin
                t_yaz_adr[AW*bank +: AW] = adr; ta_yaz_adr[AW*bank +: AW] = adr;
            end
            t_yaz_veri = 0; ta_yaz_veri = 0;
        end
        @(negedge clk); t_yaz_en = 0; ta_yaz_en = 0;
        // başlangıç: AKT0 + HATA[L]
        dosya_ac(alt, "veri_baslangic.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d %d", bank, adr, v));
            kel = 0; kel[133:128] = v;
            for (q = 0; q < 16; q = q + 1) begin void'($fscanf(fd, "%d", x)); kel[8*q +: 8] = x; end
            veri_yaz(bank, adr, kel);
        end
        $fclose(fd);
        dosya_ac(alt, "veri_beklenen.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d %d", bank, adr, v));
            kel = 0; kel[133:128] = v;
            for (q = 0; q < 16; q = q + 1) begin void'($fscanf(fd, "%d", x)); kel[8*q +: 8] = x; end
            if (adr >= hl_bas && adr < hl_son) veri_yaz(bank, adr, kel);
        end
        $fclose(fd);
        dosya_ac(alt, "agirlik_baslangic.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d", bank, adr));
            wk = 0;
            for (q = 0; q < 9; q = q + 1) begin void'($fscanf(fd, "%d", x)); wk[8*q +: 8] = x; end
            @(negedge clk);
            ta_yaz_en = 0; ta_yaz_en[bank] = 1'b1; ta_yaz_adr[AW*bank +: AW] = adr; ta_yaz_veri[72*bank +: 72] = wk;
        end
        $fclose(fd);
        @(negedge clk); ta_yaz_en = 0;
        // ---- komutlar ----
        dosya_ac(alt, "komutlar_dizi.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1)
            for (q = 0; q < 10; q = q + 1) void'($fscanf(fd, "%d", kom[i][q]));
        $fclose(fd);
        n_ag = n_ag + 1;
        tb_surer = 1'b0;
        for (i = 0; i < n; i = i + 1) begin
            @(negedge clk);
            case (kom[i][0])
                8: begin hedef = kom[i][4]; is_basla = 1'b1; @(negedge clk); is_basla = 1'b0; end
                1: begin
                    faz = kom[i][1]; l = kom[i][2]; b = kom[i][3]; k0 = kom[i][4]; k1 = kom[i][5]; z = kom[i][6];
                    ilk = kom[i][7]; son = kom[i][8];
                    basla = 1'b1; @(negedge clk); basla = 1'b0;
                    bekle = 0;
                    while (!bitti && bekle < 5000) begin @(negedge clk); bekle = bekle + 1; end
                    if (!bitti) begin
                        hata = hata + 1;
                        $display("SONUC tb_dizi_motoru: FAIL komut %0d bitmedi (zaman asimi)", i);
                        $finish;
                    end
                    n_dizi = n_dizi + 1;
                end
                2: begin
                    kontrol = kontrol + 2;
                    if (!ps_bos) begin                     // golden: iş sonunda Psum FIFO boş
                        hata = hata + 1;
                        $display("HATA komut %0d (OLCEK): Psum FIFO bos degil", i);
                    end
                    ll = kom[i][2];
                    v = (kom[i][1] == 0) ? G_akt[6*ll +: 6] : (kom[i][1] == 1) ? G_hata[6*(ll-1) +: 6] : G_grad[6*ll +: 6];
                    if (G !== v[5:0]) begin
                        hata = hata + 1;
                        $display("HATA komut %0d (OLCEK faz %0d l %0d): G %0d, beklenen %0d", i, kom[i][1], ll, G, v);
                    end
                end
                default: ;
            endcase
        end
        kontrol = kontrol + 1;
        if (tasma || eksik) begin hata = hata + 1; $display("HATA: Psum FIFO tasma=%0d eksik=%0d", tasma, eksik); end
        // ---- son tampon ----
        tb_surer = 1'b1;
        dosya_ac(alt, "veri_beklenen.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d %d", bank, adr, v));
            kel = 0; kel[133:128] = v;
            for (q = 0; q < 16; q = q + 1) begin void'($fscanf(fd, "%d", x)); kel[8*q +: 8] = x; end
            @(negedge clk);
            t_oku_adr[AW*bank +: AW] = adr;
            @(negedge clk);
            kontrol = kontrol + 1; n_kelime = n_kelime + 1;
            if (v_veri[134*bank +: 134] !== kel) begin
                hata = hata + 1;
                if (hata <= 12) $display("HATA kelime bank %0d adr %0d: %h, beklenen %h", bank, adr, v_veri[134*bank +: 134], kel);
            end
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
        if (hata == 0) $display("SONUC tb_dizi_motoru: PASS %0d/%0d (%0d ag, %0d DIZI komutu, %0d kelime)", kontrol, kontrol, n_ag, n_dizi, n_kelime);
        else           $display("SONUC tb_dizi_motoru: FAIL %0d hata / %0d", hata, kontrol);
        sfd = $fopen({dizin, "sonuc_tb_dizi_motoru.txt"}, "w");
        if (sfd != 0) begin
            if (hata == 0) $fdisplay(sfd, "SONUC tb_dizi_motoru: PASS %0d/%0d", kontrol, kontrol);
            else           $fdisplay(sfd, "SONUC tb_dizi_motoru: FAIL %0d hata / %0d", hata, kontrol);
            $fclose(sfd);
        end
        $finish;
    end

endmodule
