// =============================================================================
//  tb_sistem_dizi.sv — 16x16 dizili tam sistem: bir eğitim adımı uçtan uca (Adım 5b-3e)
// -----------------------------------------------------------------------------
//  Vektörler (models/sistem/adim5_vektorleri/, ag2/, ag3/, ag4/; dizi_sistem_golden.py):
//    ag_yapilandirma.txt, bolgeler.txt, etiket.txt, veri_baslangic.txt, agirlik_baslangic.txt,
//    veri_beklenen.txt, agirlik_beklenen.txt
//  Her ağ: tamponlar sıfırlanır, başlangıç hâli yüklenir (yalnızca AKT0 ve ağırlıklar), sistem `basla` ile
//  bir eğitim adımını kendisi koşturur (komutları FSM üretir). Bitince:
//    - veri tamponunun golden'da yazılı bütün kelimeleri (aktivasyonlar, hatalar, CLU çıkışı, gradyanlar; 16 int8 + l)
//    - ağırlık tamponunun bütün kelimeleri (WU'dan sonraki ağırlıklar)
//    - bölge G register'ları
//  golden'ın son hâliyle karşılaştırılır. Dört ağ art arda, aralarında reset yok.
//  Sonuç: "SONUC tb_sistem_dizi: PASS n/n". Üst modülde sinyal yok (araç tuzağı 13).
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b-3e)
// =============================================================================
`timescale 1ns/1ps

module tb_sistem_dizi;
    tb_sistem_dizi_govde govde ();
endmodule

module tb_sistem_dizi_govde;

    localparam NB = 16, AW = 9, LMAX = 4, BMAX = 8;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                    rst = 1'b1, basla = 1'b0;
    reg  [3:0]             cfg_L = 0, cfg_m_u = 0;
    reg  [7:0]             cfg_batch = 0, cfg_s_a0 = 0;
    reg  [LMAX*8-1:0]      cfg_cin = 0, cfg_cout = 0, cfg_h = 0, cfg_w = 0, cfg_s = 0, cfg_p = 0, cfg_relu = 0, cfg_sw = 0;
    reg  [(LMAX+1)*AW-1:0] taban_akt = 0, taban_hata = 0, taban_grad = 0, taban_agr = 0;
    reg  [BMAX*4-1:0]      cfg_etiket = 0;
    wire [(LMAX+1)*6-1:0]  G_akt, G_hata, G_grad;
    wire                   bitti, mesgul, tasma, eksik;
    reg                    dis = 1'b1;
    reg  [NB*AW-1:0]       dv_oku = 0, dv_yaz_adr = 0, da_oku = 0, da_yaz_adr = 0;
    reg  [NB-1:0]          dv_yaz_en = 0, da_yaz_en = 0;
    reg  [NB*134-1:0]      dv_yaz_veri = 0;
    reg  [NB*72-1:0]       da_yaz_veri = 0;
    wire [NB*134-1:0]      dv_veri;
    wire [NB*72-1:0]       da_veri;

    sistem_dizi #(.NB(NB), .AW(AW), .LMAX(LMAX), .BMAX(BMAX)) dut (
        .clk(clk), .rst(rst), .basla(basla), .bitti(bitti), .mesgul(mesgul),
        .cfg_L(cfg_L), .cfg_batch(cfg_batch), .cfg_m_u(cfg_m_u), .cfg_s_a0(cfg_s_a0),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s), .cfg_p(cfg_p),
        .cfg_relu(cfg_relu), .cfg_sw(cfg_sw), .taban_akt(taban_akt), .taban_hata(taban_hata),
        .taban_grad(taban_grad), .taban_agr(taban_agr), .cfg_etiket(cfg_etiket),
        .G_akt(G_akt), .G_hata(G_hata), .G_grad(G_grad), .ps_tasma(tasma), .ps_eksik(eksik),
        .dis_aktif(dis), .dis_v_oku_adr(dv_oku), .dis_v_oku_veri(dv_veri), .dis_v_yaz_en(dv_yaz_en),
        .dis_v_yaz_adr(dv_yaz_adr), .dis_v_yaz_veri(dv_yaz_veri), .dis_a_oku_adr(da_oku), .dis_a_oku_veri(da_veri),
        .dis_a_yaz_en(da_yaz_en), .dis_a_yaz_adr(da_yaz_adr), .dis_a_yaz_veri(da_yaz_veri));

    integer kontrol = 0, hata = 0, n_ag = 0, n_kelime = 0, cevrim_top = 0;
    integer fd, n, i, q, x, v, tmp, bank, adr, ll, bekle, a, b_, c_, d_, e_, f_, g_, h_;
    integer G_bek_akt [0:8], G_bek_hata [0:8], G_bek_grad [0:8];
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

    task automatic hata_yaz(input string ne, input integer bk, input integer ad_);
        hata = hata + 1;
        if (hata <= 12) $display("HATA %s bank %0d adr %0d", ne, bk, ad_);
    endtask

    task automatic ag_kos(input string alt);
        dis = 1'b1;
        dosya_ac(alt, "ag_yapilandirma.txt");
        void'($fscanf(fd, "%d %d %d %d %d", a, b_, c_, d_, tmp));
        cfg_L = a; cfg_batch = b_; cfg_m_u = c_; cfg_s_a0 = d_;
        cfg_cin = 0; cfg_cout = 0; cfg_h = 0; cfg_w = 0; cfg_s = 0; cfg_p = 0; cfg_relu = 0; cfg_sw = 0;
        for (ll = 0; ll < a; ll = ll + 1) begin
            void'($fscanf(fd, "%d %d %d %d %d %d %d %d", b_, c_, d_, e_, f_, g_, h_, v));
            cfg_cin[8*ll +: 8] = b_; cfg_cout[8*ll +: 8] = c_; cfg_h[8*ll +: 8] = d_; cfg_w[8*ll +: 8] = e_;
            cfg_s[8*ll +: 8] = f_; cfg_p[8*ll +: 8] = g_; cfg_relu[8*ll +: 8] = h_; cfg_sw[8*ll +: 8] = v;
        end
        $fclose(fd);
        dosya_ac(alt, "etiket.txt");
        cfg_etiket = 0;
        for (i = 0; i < cfg_batch; i = i + 1) begin void'($fscanf(fd, "%d", v)); cfg_etiket[4*i +: 4] = v; end
        $fclose(fd);
        dosya_ac(alt, "bolgeler.txt");
        void'($fscanf(fd, "%d %d", n, tmp));
        for (i = 0; i < 9; i = i + 1) begin G_bek_akt[i] = 0; G_bek_hata[i] = 0; G_bek_grad[i] = 0; end
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d %d %d %d %d %d", ad, adr, tmp, tmp, tmp, tmp, tmp, v));
            ll = ad[7:0] - "0";
            if ((ad >> 8) == "AKT")  begin taban_akt[AW*ll +: AW] = adr;  G_bek_akt[ll] = v; end
            if ((ad >> 8) == "HATA") begin taban_hata[AW*ll +: AW] = adr; G_bek_hata[ll] = v; end
            if ((ad >> 8) == "GRAD") begin taban_grad[AW*ll +: AW] = adr; G_bek_grad[ll] = v; end
        end
        for (i = 0; i < cfg_L; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d", ad, ll, adr));
            taban_agr[AW*ll +: AW] = adr;
        end
        $fclose(fd);
        // tamponları sıfırla
        for (adr = 0; adr < (1 << AW); adr = adr + 1) begin
            @(negedge clk);
            dv_yaz_en = {NB{1'b1}}; da_yaz_en = {NB{1'b1}}; dv_yaz_veri = 0; da_yaz_veri = 0;
            for (bank = 0; bank < NB; bank = bank + 1) begin
                dv_yaz_adr[AW*bank +: AW] = adr; da_yaz_adr[AW*bank +: AW] = adr;
            end
        end
        @(negedge clk); dv_yaz_en = 0; da_yaz_en = 0;
        // başlangıç
        dosya_ac(alt, "veri_baslangic.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d %d", bank, adr, v));
            kel = 0; kel[133:128] = v;
            for (q = 0; q < 16; q = q + 1) begin void'($fscanf(fd, "%d", x)); kel[8*q +: 8] = x; end
            @(negedge clk);
            dv_yaz_en = 0; dv_yaz_en[bank] = 1'b1; dv_yaz_adr[AW*bank +: AW] = adr; dv_yaz_veri[134*bank +: 134] = kel;
        end
        $fclose(fd);
        dosya_ac(alt, "agirlik_baslangic.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d", bank, adr));
            wk = 0;
            for (q = 0; q < 9; q = q + 1) begin void'($fscanf(fd, "%d", x)); wk[8*q +: 8] = x; end
            @(negedge clk);
            dv_yaz_en = 0;
            da_yaz_en = 0; da_yaz_en[bank] = 1'b1; da_yaz_adr[AW*bank +: AW] = adr; da_yaz_veri[72*bank +: 72] = wk;
        end
        $fclose(fd);
        @(negedge clk); dv_yaz_en = 0; da_yaz_en = 0;
        // ---- bir eğitim adımı ----
        dis = 1'b0;
        @(negedge clk); basla = 1'b1; @(negedge clk); basla = 1'b0;
        bekle = 0;
        while (!bitti && bekle < 2000000) begin @(negedge clk); bekle = bekle + 1; end
        if (!bitti) begin
            $display("SONUC tb_sistem_dizi: FAIL %s bitmedi (zaman asimi)", alt);
            $finish;
        end
        cevrim_top = cevrim_top + bekle;
        $display("[%s] egitim adimi %0d cevrim", alt, bekle);
        n_ag = n_ag + 1;
        dis = 1'b1;
        // ---- sonuçlar ----
        dosya_ac(alt, "veri_beklenen.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d %d", bank, adr, v));
            kel = 0; kel[133:128] = v;
            for (q = 0; q < 16; q = q + 1) begin void'($fscanf(fd, "%d", x)); kel[8*q +: 8] = x; end
            @(negedge clk); dv_oku[AW*bank +: AW] = adr; @(negedge clk);
            kontrol = kontrol + 1; n_kelime = n_kelime + 1;
            if (dv_veri[134*bank +: 134] !== kel) hata_yaz("veri", bank, adr);
        end
        $fclose(fd);
        dosya_ac(alt, "agirlik_beklenen.txt");
        void'($fscanf(fd, "%d", n));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%d %d", bank, adr));
            wk = 0;
            for (q = 0; q < 9; q = q + 1) begin void'($fscanf(fd, "%d", x)); wk[8*q +: 8] = x; end
            @(negedge clk); da_oku[AW*bank +: AW] = adr; @(negedge clk);
            kontrol = kontrol + 1; n_kelime = n_kelime + 1;
            if (da_veri[72*bank +: 72] !== wk) hata_yaz("agirlik", bank, adr);
        end
        $fclose(fd);
        for (ll = 0; ll <= cfg_L; ll = ll + 1) begin
            kontrol = kontrol + 3;
            if (G_akt[6*ll +: 6]  !== G_bek_akt[ll][5:0])  hata_yaz("G_akt", ll, G_akt[6*ll +: 6]);
            if (G_hata[6*ll +: 6] !== G_bek_hata[ll][5:0]) hata_yaz("G_hata", ll, G_hata[6*ll +: 6]);
            if (G_grad[6*ll +: 6] !== G_bek_grad[ll][5:0]) hata_yaz("G_grad", ll, G_grad[6*ll +: 6]);
        end
        kontrol = kontrol + 1;
        if (tasma || eksik) hata_yaz("Psum FIFO bayragi", tasma, eksik);
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
        if (hata == 0) $display("SONUC tb_sistem_dizi: PASS %0d/%0d (%0d ag, %0d kelime, %0d cevrim)", kontrol, kontrol, n_ag, n_kelime, cevrim_top);
        else           $display("SONUC tb_sistem_dizi: FAIL %0d hata / %0d", hata, kontrol);
        sfd = $fopen({dizin, "sonuc_tb_sistem_dizi.txt"}, "w");
        if (sfd != 0) begin
            if (hata == 0) $fdisplay(sfd, "SONUC tb_sistem_dizi: PASS %0d/%0d", kontrol, kontrol);
            else           $fdisplay(sfd, "SONUC tb_sistem_dizi: FAIL %0d hata / %0d", hata, kontrol);
            $fclose(sfd);
        end
        $finish;
    end

endmodule
