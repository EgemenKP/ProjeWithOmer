// =============================================================================
//  tb_sistem.sv — Adım 4, Paket 3: tam sistem testi (sistem_ust = FSM + veri yolu)
// -----------------------------------------------------------------------------
//  Testbench yalnızca yapılandırmayı ve belleği hazırlar, basla verir ve bekler; komutları
//  FSM kendisi üretir, G'yi gerçek SRU'dan alır. Üç tur, aralarında reset yok:
//  ag1 (<VEKTOR_DIZINI>/), ag2 (<VEKTOR_DIZINI>/ag2/), yine ag1. Her turdan önce bellek
//  yeniden yüklenir (FSM SON durumundayken). Kontroller (golden: sistem_golden.py):
//    1) FSM'in her komutu komutlar.txt'teki sıradaki satırla 10 alanın hepsinde aynı. SA ve
//       CLU komutlarındaki s_a, FSM'in SRU'dan aldığı G'lerle hesaplandığı için bu, s_a'ların
//       da kontrolü. Komut, kom_gecerli 1 iken sabit kalıyor.
//    2) ÖLÇEK'te SRU'nun G'si (maksreg.txt'teki 2. tür olay) ve saydığı grup sayısı (a1).
//    3) BİTTİ'den sonra: kullanılan her bayt beklenen değerde (veriyolu_bellek.txt); AKT[1..L],
//       HATA[1..L] ve AGR'nin her baytı tam bir kez, diğerleri hiç yazılmamış.
//    4) Yürütücü her komutu tam bir kez alıyor ve aldığı, FSM'in o anki komutu (el sıkışma).
//    5) Yürütücünün hata bayrakları 0; FSM'in bitti'si 1, mesgul'ü 0; komut sayısı tam.
//  Sonuç: "SONUC tb_sistem: PASS k/k" (konsol ve <VEKTOR_DIZINI>/sonuc_tb_sistem.txt)
//  Yazan: Claude, 03.11.2026
// =============================================================================
`timescale 1ns/1ps

`define VY  dut.u_vy
`define SRU dut.u_vy.u_yur.u_sru

module tb_sistem;

    localparam AW = 13, BOYUT = 8192, LMAX = 8;
    localparam NKOM = 4096, NOLAY = 8192;
    localparam TUR = 3;
    localparam SINIR = 400000;           // tur başına en çok çevrim

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                    rst, basla;
    reg  [3:0]             cfg_L;
    reg  [7:0]             cfg_batch;
    reg  [3:0]             cfg_m_u;
    reg  [7:0]             cfg_s_a0;
    reg  [LMAX*8-1:0]      cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p, cfg_relu, cfg_sw;
    reg  [(LMAX+1)*AW-1:0] cfg_taban_akt, cfg_taban_hata, cfg_taban_agr;
    reg  [AW-1:0]          cfg_taban_etiket;
    wire                   mesgul, bitti;
    wire [5:0]             hata_b;

    sistem_ust #(.AW(AW), .BOYUT(BOYUT), .LMAX(LMAX)) dut (
        .clk(clk), .rst(rst), .basla(basla),
        .cfg_L(cfg_L), .cfg_batch(cfg_batch), .cfg_m_u(cfg_m_u), .cfg_s_a0(cfg_s_a0),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_s(cfg_s), .cfg_p(cfg_p), .cfg_relu(cfg_relu), .cfg_sw(cfg_sw),
        .cfg_taban_akt(cfg_taban_akt), .cfg_taban_hata(cfg_taban_hata), .cfg_taban_agr(cfg_taban_agr),
        .cfg_taban_etiket(cfg_taban_etiket),
        .mesgul(mesgul), .bitti(bitti), .hata(hata_b)
    );

    // ------------------------------------------------------------------
    // Sayaçlar ve kontrol
    // ------------------------------------------------------------------
    integer hata, kontrol, sfd, cevrim, tur;
    string  dizin, ag_adi;
    integer ki;                          // FSM'in verdiği komutun sırası
    reg     izleme;

    always @(posedge clk) cevrim <= cevrim + 1;

    // Değerler önce değişkene alınıp öyle verilir (XSIM araç tuzağı 10).
    task kontrol_et(input [511:0] olan, input [511:0] beklenen, input string ne);
        begin
            kontrol = kontrol + 1;
            if (olan !== beklenen) begin
                hata = hata + 1;
                if (hata <= 30) $display("FAIL [tur %0d %s] komut %0d: %s: olan %h, beklenen %h",
                                         tur, ag_adi, ki, ne, olan, beklenen);
            end
        end
    endtask

    task hata_bildir(input string ne);
        begin
            kontrol = kontrol + 1;
            hata = hata + 1;
            if (hata <= 30) $display("FAIL [tur %0d %s] komut %0d: %s", tur, ag_adi, ki, ne);
        end
    endtask

    // ------------------------------------------------------------------
    // Vektörler
    // ------------------------------------------------------------------
    integer n_kom, n_olay, N_bayt, L_ag, B_ag;
    integer kom_alan [0:NKOM-1][0:9];
    integer olay_tur [0:NOLAY-1], olay_d1 [0:NOLAY-1];
    integer bas_mem [0:BOYUT-1], bek_mem [0:BOYUT-1], bolge [0:BOYUT-1], yazma_sayisi [0:BOYUT-1];
    integer p2;                          // sıradaki G olayı (2. tür)

    function integer sonraki(input integer tur_, input integer p);
        integer q;
        begin
            q = p;
            while (q < n_olay && olay_tur[q] != tur_) q = q + 1;
            sonraki = q;
        end
    endfunction

    // Komutun i. alanı (16 bit, işaretli)
    function integer alan(input [159:0] k, input integer i);
        alan = $signed(k[16*i +: 16]);
    endfunction

    // ------------------------------------------------------------------
    // İzleyici (negedge): komut akışı, ÖLÇEK, yazma sayacı
    // ------------------------------------------------------------------
    reg [511:0] o_v, b_v;
    reg [159:0] kom_ilk;
    reg         gec_n;                   // kom_gecerli'nin önceki negedge'deki değeri
    integer     j2, f, olan_i, bek_i, op_su_an, esit;
    integer     kabul_ki, kabul_say;     // yürütücünün son aldığı komut ve aldığı komut sayısı
    always @(negedge clk) begin
        if (izleme) begin
            // 0) Yürütücü bu çevrimin sonunda komutu alıyor: FSM'in şu anki komutu olmalı ve
            //    aynı komut iki kez alınmamalı (el sıkışma)
            if (`VY.u_yur.durum == 4'd0 && `VY.kom_gecerli) begin
                kabul_say = kabul_say + 1;
                if (kabul_ki == ki) hata_bildir("yurutucu ayni komutu ikinci kez aldi");
                else if (ki >= n_kom) hata_bildir("yurutucu fazladan komut aldi");
                else begin
                    esit = 1;
                    for (f = 0; f < 10; f = f + 1)
                        if (alan(`VY.kom, f) != kom_alan[ki][f]) esit = 0;
                    if (!esit) hata_bildir("yurutucunun aldigi komut FSM'in siradaki komutu degil");
                    else kontrol = kontrol + 1;
                end
                kabul_ki = ki;
            end
            // 1) Yeni komut: komutlar.txt ile 10 alan
            if (`VY.kom_gecerli && !gec_n) begin
                kom_ilk = `VY.kom;
                if (ki >= n_kom) hata_bildir("beklenenden fazla komut");
                else begin
                    esit = 1;
                    for (f = 0; f < 10; f = f + 1)
                        if (alan(kom_ilk, f) != kom_alan[ki][f]) esit = 0;
                    if (!esit)
                        hata_bildir($sformatf("komut %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d, beklenen %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                            alan(kom_ilk,0), alan(kom_ilk,1), alan(kom_ilk,2), alan(kom_ilk,3), alan(kom_ilk,4),
                            alan(kom_ilk,5), alan(kom_ilk,6), alan(kom_ilk,7), alan(kom_ilk,8), alan(kom_ilk,9),
                            kom_alan[ki][0], kom_alan[ki][1], kom_alan[ki][2], kom_alan[ki][3], kom_alan[ki][4],
                            kom_alan[ki][5], kom_alan[ki][6], kom_alan[ki][7], kom_alan[ki][8], kom_alan[ki][9]));
                    else kontrol = kontrol + 1;
                end
            end
            // Komut, kom_gecerli 1 iken sabit
            if (`VY.kom_gecerli && gec_n && (`VY.kom !== kom_ilk))
                hata_bildir("komut, kom_gecerli 1 iken degisti");
            // 2) ÖLÇEK bitiyor: G ve grup sayısı (FSM G'yi bu çevrimin sonundaki kenarda örnekler)
            if (`VY.kom_bitti && `VY.kom_gecerli) begin
                op_su_an = alan(`VY.kom, 0);
                if (op_su_an == 2) begin
                    p2 = sonraki(2, p2);
                    if (p2 >= n_olay) hata_bildir("maksreg'de G olayi kalmadi");
                    else begin
                        olan_i = `VY.maks_G; bek_i = olay_d1[p2];
                        o_v = olan_i; b_v = bek_i;
                        kontrol_et(o_v, b_v, "OLCEK: SRU'nun G'si");
                        p2 = p2 + 1;
                    end
                    olan_i = `SRU.n_groups; bek_i = alan(`VY.kom, 7);
                    o_v = olan_i; b_v = bek_i;
                    kontrol_et(o_v, b_v, "OLCEK: SRU'nun grup sayisi = a1");
                end
                if (ki < n_kom) ki = ki + 1;      // bu komut bitti; sıradaki beklenen komut
            end
            gec_n = `VY.kom_gecerli;
            // 3) Yazma sayacı
            if (`VY.yaz)
                for (j2 = 0; j2 < 16; j2 = j2 + 1)
                    if (j2 < `VY.yaz_n && `VY.yaz_adr + j2 < BOYUT)
                        yazma_sayisi[`VY.yaz_adr + j2] = yazma_sayisi[`VY.yaz_adr + j2] + 1;
        end
    end

    // ------------------------------------------------------------------
    // Bir turun çalıştırılması
    // ------------------------------------------------------------------
    task dosya_ac(output integer fd, input string ad);
        begin
            fd = $fopen({dizin, ad}, "r");
            if (fd == 0) hata_bildir({"dosya acilamadi: ", dizin, ad});
        end
    endtask

    task tur_calistir(input string d, input string ad);
        integer fd, r, i, j, tmp, L_, B_, mu_, sa0_, ns_, cin_, cout_, h_, w_, s_, p_, relu_, sw_;
        integer bek_yaz, kacak, c0, hata0, kontrol0;
        begin
            dizin = d; ag_adi = ad;
            hata0 = hata; kontrol0 = kontrol;
            // ---- katman tablosu (FSM ve veri yolu) ----
            dosya_ac(fd, "ag_yapilandirma.txt");
            r = $fscanf(fd, "%d %d %d %d %d", L_, B_, mu_, sa0_, ns_);
            cfg_L = L_; cfg_batch = B_; cfg_m_u = mu_; cfg_s_a0 = sa0_;
            cfg_cin = 0; cfg_cout = 0; cfg_h = 0; cfg_w = 0; cfg_s = 0; cfg_p = 0; cfg_relu = 0; cfg_sw = 0;
            for (i = 0; i < L_; i = i + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d %d %d", cin_, cout_, h_, w_, s_, p_, relu_, sw_);
                cfg_cin [8*i +: 8] = cin_;  cfg_cout[8*i +: 8] = cout_;
                cfg_h   [8*i +: 8] = h_;    cfg_w   [8*i +: 8] = w_;
                cfg_s   [8*i +: 8] = s_;    cfg_p   [8*i +: 8] = p_;
                cfg_relu[8*i +: 8] = relu_; cfg_sw  [8*i +: 8] = sw_;
            end
            $fclose(fd);
            // ---- taban adresleri ----
            dosya_ac(fd, "veriyolu_duzen.txt");
            r = $fscanf(fd, "%d %d %d", L_ag, B_ag, N_bayt);
            for (i = 0; i < L_ag; i = i + 1)
                for (j = 0; j < 6; j = j + 1) r = $fscanf(fd, "%d", tmp);   // katman satırları (tablo yukarıda)
            cfg_taban_akt = 0; cfg_taban_hata = 0; cfg_taban_agr = 0;
            for (i = 0; i <= L_ag; i = i + 1) begin r = $fscanf(fd, "%d", tmp); cfg_taban_akt [AW*i +: AW] = tmp; end
            for (i = 0; i <= L_ag; i = i + 1) begin r = $fscanf(fd, "%d", tmp); cfg_taban_hata[AW*i +: AW] = tmp; end
            for (i = 0; i <= L_ag; i = i + 1) begin r = $fscanf(fd, "%d", tmp); cfg_taban_agr [AW*i +: AW] = tmp; end
            r = $fscanf(fd, "%d", tmp); cfg_taban_etiket = tmp;
            $fclose(fd);
            if (L_ag != L_ || B_ag != B_) hata_bildir("veriyolu_duzen.txt ile ag_yapilandirma.txt tutmuyor");
            // ---- bellek ----
            dosya_ac(fd, "veriyolu_bellek.txt");
            r = $fscanf(fd, "%d", tmp);
            if (tmp != N_bayt || N_bayt > BOYUT) hata_bildir("veriyolu_bellek.txt boyutu tutmuyor");
            for (i = 0; i < BOYUT; i = i + 1) begin bas_mem[i] = 0; bek_mem[i] = 0; bolge[i] = 0; end
            for (i = 0; i < N_bayt; i = i + 1) begin
                r = $fscanf(fd, "%d", tmp); bas_mem[i] = tmp;
                r = $fscanf(fd, "%d", tmp); bek_mem[i] = tmp;
                r = $fscanf(fd, "%d", tmp); bolge[i] = tmp;
            end
            $fclose(fd);
            // ---- beklenen komutlar ----
            dosya_ac(fd, "komutlar.txt");
            r = $fscanf(fd, "%d", n_kom);
            if (n_kom > NKOM) hata_bildir("komut sayisi NKOM'u asiyor");
            for (i = 0; i < n_kom; i = i + 1)
                for (j = 0; j < 10; j = j + 1) begin r = $fscanf(fd, "%d", tmp); kom_alan[i][j] = tmp; end
            $fclose(fd);
            // ---- Max Regs olayları (yalnızca G kullanılıyor) ----
            dosya_ac(fd, "maksreg.txt");
            r = $fscanf(fd, "%d", n_olay);
            if (n_olay > NOLAY) hata_bildir("olay sayisi NOLAY'i asiyor");
            for (i = 0; i < n_olay; i = i + 1) begin
                r = $fscanf(fd, "%d", tmp); olay_tur[i] = tmp;
                r = $fscanf(fd, "%d", tmp);
                r = $fscanf(fd, "%d", tmp); olay_d1[i] = tmp;
                r = $fscanf(fd, "%d", tmp);
            end
            $fclose(fd);
            p2 = 0;

            // ---- bellek yüklemesi (FSM durmuşken; tur 1'de reset sırasında) ----
            @(negedge clk);
            for (i = 0; i < BOYUT; i = i + 1) begin
                `VY.u_bellek.mem[i] = bas_mem[i];
                yazma_sayisi[i] = 0;
            end
            @(negedge clk);
            kacak = 0;
            for (i = 0; i < BOYUT; i = i + 1) begin
                o_v = `VY.u_bellek.mem[i]; b_v = 0; b_v[7:0] = bas_mem[i];
                if (o_v !== b_v) kacak = kacak + 1;
            end
            o_v = kacak; b_v = 0;
            kontrol_et(o_v, b_v, "bellek yuklemesi (hiyerarsik yazma) tutmayan bayt");
            rst = 1'b0;

            // ---- basla ----
            ki = 0; gec_n = 1'b0; kabul_ki = -1; kabul_say = 0; izleme = 1'b1;
            c0 = cevrim;
            @(posedge clk); basla <= 1'b1;
            @(posedge clk); basla <= 1'b0;
            @(posedge clk);                                   // önceki turun 'bitti'si artık 0
            i = 0;
            while (!bitti && i < SINIR) begin @(posedge clk); i = i + 1; end
            if (!bitti) hata_bildir($sformatf("ZAMAN ASIMI: %0d cevrimde bitmedi", SINIR));
            repeat (4) @(negedge clk);
            izleme = 1'b0;

            // ---- son kontroller ----
            o_v = ki; b_v = n_kom;
            kontrol_et(o_v, b_v, "tamamlanan komut sayisi");
            o_v = kabul_say; b_v = n_kom;
            kontrol_et(o_v, b_v, "yurutucunun aldigi komut sayisi");
            olan_i = sonraki(2, p2); o_v = olan_i; b_v = n_olay;
            kontrol_et(o_v, b_v, "G olaylari bitti (2. tur olay)");
            o_v = {bitti, mesgul}; b_v = 2'b10;
            kontrol_et(o_v, b_v, "FSM bitti = 1, mesgul = 0");
            o_v = hata_b; b_v = 0;
            kontrol_et(o_v, b_v, "yurutucu hata bayraklari {olcek, tuketici, gfifo eksik, gfifo tasma, psum eksik, psum tasma}");
            for (i = 0; i < N_bayt; i = i + 1) begin
                o_v = `VY.u_bellek.mem[i]; b_v = 0; b_v[7:0] = bek_mem[i];
                kontrol_et(o_v, b_v, $sformatf("bellek adr %0d (bolge %0d)", i, bolge[i]));
                bek_yaz = ((bolge[i] > 100 && bolge[i] < 200) || (bolge[i] > 200 && bolge[i] < 400)) ? 1 : 0;
                o_v = yazma_sayisi[i]; b_v = bek_yaz;
                kontrol_et(o_v, b_v, $sformatf("yazma sayisi adr %0d (bolge %0d)", i, bolge[i]));
            end
            kacak = 0;
            for (i = N_bayt; i < BOYUT; i = i + 1) if (yazma_sayisi[i] != 0) kacak = kacak + 1;
            o_v = kacak; b_v = 0;
            kontrol_et(o_v, b_v, "kullanilan alanin disina yazilan bayt");
            $display("[tur %0d %s] %0d komut, %0d cevrim (basla -> bitti); bu turda %0d kontrol, %0d hata",
                     tur, ad, ki, cevrim - c0, kontrol - kontrol0, hata - hata0);
        end
    endtask

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            sfd = $fopen({dizin, "sonuc_tb_sistem.txt"}, "w");
            if (sfd != 0) begin
                $fdisplay(sfd, "%s", satir);
                $fclose(sfd);
            end
        end
    endtask

    string kok;
    initial begin
        hata = 0; kontrol = 0; cevrim = 0; ki = 0; tur = 0;
        izleme = 1'b0; gec_n = 1'b0;
        rst = 1'b1; basla = 1'b0;
        cfg_L = 0; cfg_batch = 0; cfg_m_u = 0; cfg_s_a0 = 0;
        cfg_cin = 0; cfg_cout = 0; cfg_h = 0; cfg_w = 0; cfg_s = 0; cfg_p = 0; cfg_relu = 0; cfg_sw = 0;
        cfg_taban_akt = 0; cfg_taban_hata = 0; cfg_taban_agr = 0; cfg_taban_etiket = 0;
        if (!$value$plusargs("VEKTOR_DIZINI=%s", kok)) kok = "";
        // Klasör doğru mu? (yolda boşluk varsa plusarg bozulur) Bulunamazsa çalışma klasörü.
        sfd = $fopen({kok, "komutlar.txt"}, "r");
        if (sfd == 0) kok = ""; else $fclose(sfd);
        repeat (3) @(negedge clk);                            // reset (tur 1'in yüklemesine kadar sürer)

        for (tur = 1; tur <= TUR; tur = tur + 1) begin
            if (tur == 2) tur_calistir({kok, "ag2/"}, "ag2");
            else          tur_calistir(kok, "ag1");
        end

        dizin = kok;
        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_sistem: PASS %0d/%0d (3 tur: ag1, ag2, ag1, aralarinda reset yok)", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_sistem: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
