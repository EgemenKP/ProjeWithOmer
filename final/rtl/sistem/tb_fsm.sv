// =============================================================================
//  tb_fsm.sv — master_controller + maks_reg testbench (sahte bloklarla)
// -----------------------------------------------------------------------------
//  Sahte (stub) blok, FSM'in her komutuna rastgele 1-5 çevrim sonra kom_bitti verir
//  (16 bitlik LFSR). Böylece el sıkışma da test edilir. Kontroller:
//    1) FSM'in her komutu komutlar.txt'teki sıradaki satırla 10 alanın hepsinde aynı mı
//    2) Komut, kom_gecerli 1 iken sabit kalıyor mu
//    3) maks_reg (maksreg.txt ile):
//       - 'son' PE geçişinde sahte PE grubun yerel maksimumunu verir; lms_kaydirma == l mi
//       - ÖLÇEK'te G doğru mu
//       - KOPYA/WU'da gms_kaydirma == Δ mı
//    4) Komut ve olay sayıları tam mı; BİTTİ'den sonra 'bitti' 1, 'mesgul' 0 mı
//  Üç tur çalıştırılır: ana test ağı (ag1), ikinci yapılandırma (ag2/), yine ag1.
//  Böylece yeniden başlatma ve yapılandırma değişikliği de test edilir.
//  SA ve CLU komutlarındaki s_a, FSM'in maks_reg'den aldığı G'lerle hesaplanır;
//  komut karşılaştırması bunu da kontrol eder.
//
//  Vektör klasörü: +VEKTOR_DIZINI=<klasör/> argümanıyla verilir (sonunda / olmalı).
//  Verilmezse ya da o klasörde dosya yoksa, dosyalar çalışma klasöründe aranır.
//  Okunan dosyalar (klasörde ve ag2/ alt klasöründe):
//    ag_yapilandirma.txt, komutlar.txt, maksreg.txt
//  Sonuç satırı konsola ve <vektör klasörü>/sonuc_tb_fsm.txt dosyasına yazılır:
//  "SONUC tb_fsm: PASS ..." ya da "SONUC tb_fsm: FAIL ..."
//  Hazırlayan: Claude (Ömer'in isteğiyle), 02.11.2026
// =============================================================================
`timescale 1ns/1ps

module tb_fsm;

    localparam AW    = 16;
    localparam LMAX  = 8;
    localparam CW    = 8;
    localparam AD    = 6;
    localparam NK    = 8192;         // en çok komut
    localparam NO    = 4096;         // en çok olay
    localparam TUR   = 3;            // tur sayısı: ag1, ag2, ag1
    localparam SINIR = 400000;       // tur başına en çok çevrim (zaman aşımı)

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg              rst;
    reg              basla;
    reg [3:0]        cfg_L;
    reg [7:0]        cfg_batch;
    reg [3:0]        cfg_m_u;
    reg [7:0]        cfg_s_a0;
    reg [LMAX*8-1:0] cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p, cfg_relu, cfg_sw;

    wire             kom_gecerli;
    wire [10*AW-1:0] kom;
    reg              kom_bitti;
    wire             mesgul;
    wire             bitti;
    reg              yerel_gecerli;
    reg  [AW-1:0]    yerel_grup;
    reg  [31:0]      yerel_maks;
    wire [5:0]       lms_kaydirma;
    wire [5:0]       maks_G;
    wire [5:0]       gms_kaydirma;

    master_controller #(.AW(AW), .LMAX(LMAX), .CW(CW)) fsm (
        .clk(clk), .rst(rst), .basla(basla),
        .cfg_L(cfg_L), .cfg_batch(cfg_batch), .cfg_m_u(cfg_m_u), .cfg_s_a0(cfg_s_a0),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_s(cfg_s), .cfg_p(cfg_p), .cfg_relu(cfg_relu), .cfg_sw(cfg_sw),
        .maks_G(maks_G), .kom_bitti(kom_bitti),
        .kom_gecerli(kom_gecerli), .kom(kom), .mesgul(mesgul), .bitti(bitti));

    maks_reg #(.AW(AW), .AD(AD)) mr (
        .clk(clk), .rst(rst), .kom_gecerli(kom_gecerli), .kom(kom),
        .yerel_gecerli(yerel_gecerli), .yerel_grup(yerel_grup), .yerel_maks(yerel_maks),
        .lms_kaydirma(lms_kaydirma), .G(maks_G), .gms_kaydirma(gms_kaydirma));

    // ---- Beklenen değerler ----
    integer bek  [0:NK*10-1];        // komutlar: satır i, alan f -> bek[i*10 + f]
    longint olay [0:NO*4-1];         // olaylar: satır i -> tür, grup, değer1, değer2
    integer n_kom, n_olay;

    // ---- Sayaçlar ----
    integer hata, kontrol;
    integer idx, oi;                 // sıradaki beklenen komut ve olay

    string  dizin;
    string  alt;                     // turun alt klasörü: "" (ag1) ya da "ag2/"
    integer fd, r, i, f, tur, cevrim, toplam_kom, toplam_olay;
    reg     dosya_tamam;

    // Komutun i. alanı (işaretli)
    function integer alan(input [10*AW-1:0] k, input integer i);
        alan = $signed(k[AW*i +: AW]);
    endfunction

    task hata_yaz(input string mesaj);
        begin
            hata = hata + 1;
            if (hata <= 12)
                $display("HATA (tur %0d, komut %0d): %s", tur, idx, mesaj);
        end
    endtask

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            fd = $fopen({dizin, "sonuc_tb_fsm.txt"}, "w");
            if (fd != 0) begin
                $fdisplay(fd, "%s", satir);
                $fclose(fd);
            end
        end
    endtask

    // ---------------------------------------------------------------------
    // Sahte blok: komutu karşılaştırır, olayı işler, rastgele gecikmeyle bitti verir
    // ---------------------------------------------------------------------
    reg              gec_q;          // kom_gecerli'nin bir önceki çevrimdeki değeri
    reg              calisiyor;
    integer          kalan;
    reg [15:0]       lfsr;
    reg [10*AW-1:0]  kom_ilk;
    reg              yerel_bek;      // sonraki kenarda lms_kaydirma kontrol edilecek
    integer          bek_l;
    integer          op, ok, gi;

    always @(posedge clk) begin
        if (rst) begin
            gec_q         <= 1'b0;
            kom_bitti     <= 1'b0;
            yerel_gecerli <= 1'b0;
            yerel_grup    <= 0;
            yerel_maks    <= 0;
            calisiyor     =  0;
            yerel_bek     =  0;
            lfsr          <= 16'hACE1;
        end else begin
            gec_q         <= kom_gecerli;
            kom_bitti     <= 1'b0;
            yerel_gecerli <= 1'b0;
            lfsr          <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

            // Bir önceki çevrimde verilen yerel maksimumun LMS kaydırması
            if (yerel_bek) begin
                kontrol = kontrol + 1;
                if (lms_kaydirma !== bek_l[5:0])
                    hata_yaz($sformatf("lms_kaydirma=%0d, beklenen l=%0d", lms_kaydirma, bek_l));
                yerel_bek = 0;
            end

            // Komut geçerliyken değişmemeli
            if (kom_gecerli && gec_q && (kom !== kom_ilk))
                hata_yaz("komut, kom_gecerli 1 iken degisti");

            if (kom_gecerli && !gec_q) begin
                // ---- Yeni komut ----
                kom_ilk = kom;
                if (calisiyor)
                    hata_yaz("onceki komut bitmeden yeni komut geldi");
                kontrol = kontrol + 1;
                ok = (idx < n_kom);
                if (ok)
                    for (f = 0; f < 10; f = f + 1)
                        if (alan(kom, f) != bek[idx*10 + f]) ok = 0;
                if (!ok) begin
                    if (idx < n_kom)
                        hata_yaz($sformatf("gelen %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d | beklenen %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                            alan(kom,0), alan(kom,1), alan(kom,2), alan(kom,3), alan(kom,4),
                            alan(kom,5), alan(kom,6), alan(kom,7), alan(kom,8), alan(kom,9),
                            bek[idx*10+0], bek[idx*10+1], bek[idx*10+2], bek[idx*10+3], bek[idx*10+4],
                            bek[idx*10+5], bek[idx*10+6], bek[idx*10+7], bek[idx*10+8], bek[idx*10+9]));
                    else
                        hata_yaz("beklenenden fazla komut");
                end

                // ---- Max Regs olayları ----
                op = alan(kom, 0);
                if ((op == 1 && alan(kom, 8) == 1) || op == 2 || op == 3 || op == 6) begin
                    kontrol = kontrol + (op == 1 ? 0 : 1);     // tür 1'in kontrolü bir sonraki kenarda
                    if (oi >= n_olay)
                        hata_yaz("maksreg.txt'te olay kalmadi");
                    else if (op == 1) begin                     // 'son' PE: 1 grup M l
                        gi = alan(kom, 9);
                        if (olay[oi*4] != 1 || olay[oi*4+1] != gi)
                            hata_yaz($sformatf("olay %0d: tur 1, grup %0d bekleniyordu", oi, gi));
                        else begin
                            yerel_gecerli <= 1'b1;
                            yerel_grup    <= gi;
                            yerel_maks    <= olay[oi*4+2];
                            bek_l         =  olay[oi*4+3];
                            yerel_bek     =  1;
                        end
                        oi = oi + 1;
                    end else if (op == 2) begin                 // ÖLÇEK: 2 0 G 0
                        if (olay[oi*4] != 2 || maks_G != olay[oi*4+2])
                            hata_yaz($sformatf("OLCEK: G=%0d, beklenen %0d (olay %0d)", maks_G, olay[oi*4+2], oi));
                        oi = oi + 1;
                    end else begin                              // KOPYA/WU: 3 grup Δ 0
                        gi = alan(kom, 7);
                        if (olay[oi*4] != 3 || olay[oi*4+1] != gi || gms_kaydirma != olay[oi*4+2])
                            hata_yaz($sformatf("grup %0d: gms_kaydirma=%0d, beklenen %0d (olay %0d)",
                                               gi, gms_kaydirma, olay[oi*4+2], oi));
                        oi = oi + 1;
                    end
                end
                idx = idx + 1;

                // ---- Rastgele gecikme: 1-5 çevrim ----
                kalan     = 1 + (lfsr % 5);
                calisiyor = 1;
            end else if (calisiyor) begin
                kalan = kalan - 1;
                if (kalan == 0) begin
                    kom_bitti <= 1'b1;
                    calisiyor =  0;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // Dosyaları oku, üç tur çalıştır, sonucu yaz
    // ---------------------------------------------------------------------
    integer L_, B_, mu_, sa0_, ns_;
    integer cin_, cout_, h_, w_, s_, p_, relu_, sw_;

    // Bir turun dosyalarını {dizin, alt} klasöründen okur; katman tablosunu FSM'e verir.
    task dosyalari_oku(input string alt_klasor);
        begin
            dosya_tamam = 1'b0;
            // Katman tablosu
            fd = $fopen({dizin, alt_klasor, "ag_yapilandirma.txt"}, "r");
            if (fd == 0) begin
                sonuc_yaz({"SONUC tb_fsm: DOSYA OKUNAMADI (", dizin, alt_klasor, "ag_yapilandirma.txt)"});
                $finish;
            end
            r = $fscanf(fd, "%d %d %d %d %d", L_, B_, mu_, sa0_, ns_);
            cfg_L = L_; cfg_batch = B_; cfg_m_u = mu_; cfg_s_a0 = sa0_;
            cfg_cin = 0; cfg_cout = 0; cfg_h = 0; cfg_w = 0;
            cfg_s = 0; cfg_p = 0; cfg_relu = 0; cfg_sw = 0;
            for (i = 0; i < L_; i = i + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d %d %d", cin_, cout_, h_, w_, s_, p_, relu_, sw_);
                cfg_cin [8*i +: 8] = cin_;
                cfg_cout[8*i +: 8] = cout_;
                cfg_h   [8*i +: 8] = h_;
                cfg_w   [8*i +: 8] = w_;
                cfg_s   [8*i +: 8] = s_;
                cfg_p   [8*i +: 8] = p_;
                cfg_relu[8*i +: 8] = relu_;
                cfg_sw  [8*i +: 8] = sw_;
            end
            $fclose(fd);

            // Beklenen komutlar
            fd = $fopen({dizin, alt_klasor, "komutlar.txt"}, "r");
            if (fd == 0) begin
                sonuc_yaz({"SONUC tb_fsm: DOSYA OKUNAMADI (", dizin, alt_klasor, "komutlar.txt)"});
                $finish;
            end
            r = $fscanf(fd, "%d", n_kom);
            if (r == 1 && n_kom >= 1 && n_kom <= NK)
                for (i = 0; i < n_kom * 10; i = i + 1)
                    r = $fscanf(fd, "%d", bek[i]);
            $fclose(fd);
            if (r != 1 || n_kom < 1 || n_kom > NK) begin
                sonuc_yaz({"SONUC tb_fsm: DOSYA OKUNAMADI (", dizin, alt_klasor, "komutlar.txt eksik)"});
                $finish;
            end

            // Max Regs olayları
            fd = $fopen({dizin, alt_klasor, "maksreg.txt"}, "r");
            if (fd == 0) begin
                sonuc_yaz({"SONUC tb_fsm: DOSYA OKUNAMADI (", dizin, alt_klasor, "maksreg.txt)"});
                $finish;
            end
            r = $fscanf(fd, "%d", n_olay);
            if (r == 1 && n_olay >= 1 && n_olay <= NO)
                for (i = 0; i < n_olay * 4; i = i + 1)
                    r = $fscanf(fd, "%d", olay[i]);
            $fclose(fd);
            if (r != 1 || n_olay < 1 || n_olay > NO) begin
                sonuc_yaz({"SONUC tb_fsm: DOSYA OKUNAMADI (", dizin, alt_klasor, "maksreg.txt eksik)"});
                $finish;
            end
            dosya_tamam = 1'b1;
        end
    endtask

    initial begin
        hata = 0; kontrol = 0; idx = 0; oi = 0; tur = 0;
        toplam_kom = 0; toplam_olay = 0;
        rst = 1'b1; basla = 1'b0;

        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin))
            dizin = "";
        // Yedek: verilen klasörde dosya yoksa (ör. yolda boşluk varsa plusarg bozulur)
        // çalışma klasörüne bak; Vivado script'i dosyaları oraya da kopyalıyor.
        fd = $fopen({dizin, "komutlar.txt"}, "r");
        if (fd == 0)
            dizin = "";
        else
            $fclose(fd);

        dosyalari_oku("");
        repeat (3) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        for (tur = 1; tur <= TUR; tur = tur + 1) begin
            // FSM durmuşken (BOSTA ya da SON) turun dosyalarını yükle
            if (tur == 2) alt = "ag2/";
            else          alt = "";
            dosyalari_oku(alt);
            idx = 0;
            oi  = 0;
            @(posedge clk);
            basla <= 1'b1;
            @(posedge clk);                 // FSM basla'yı bu kenarda görür
            basla <= 1'b0;
            @(posedge clk);                 // önceki turun 'bitti'si artık 0
            cevrim = 1;
            while (!bitti && cevrim < SINIR) begin
                @(posedge clk);
                cevrim = cevrim + 1;
            end
            kontrol = kontrol + 1;
            if (!bitti)
                hata_yaz($sformatf("ZAMAN ASIMI: %0d cevrimde bitmedi", SINIR));
            repeat (4) @(posedge clk);
            kontrol = kontrol + 1;
            if (idx != n_kom || oi != n_olay)
                hata_yaz($sformatf("sayi eksik: %0d/%0d komut, %0d/%0d olay", idx, n_kom, oi, n_olay));
            kontrol = kontrol + 1;
            if (kom_gecerli || mesgul || !bitti)
                hata_yaz("BITTI'den sonra FSM durmadi");
            toplam_kom  = toplam_kom + idx;
            toplam_olay = toplam_olay + oi;
            if (tur == 2)
                $display("tur %0d (ag2): %0d komut, %0d olay, %0d cevrim", tur, idx, oi, cevrim);
            else
                $display("tur %0d (ag1): %0d komut, %0d olay, %0d cevrim", tur, idx, oi, cevrim);
        end

        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_fsm: PASS %0d/%0d (3 tur: ag1, ag2, ag1; %0d komut, %0d Max Regs olayi)",
                                kontrol, kontrol, toplam_kom, toplam_olay));
        else
            sonuc_yaz($sformatf("SONUC tb_fsm: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
