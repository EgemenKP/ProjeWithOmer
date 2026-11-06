// =============================================================================
//  tb_veriyolu.sv — Adım 4, Paket 2: komut yürütücüsü + bellek (sistem_veriyolu) testi
// -----------------------------------------------------------------------------
//  Testbench FSM'in yerine geçer: komutlar.txt'teki komutları FSM'in el sıkışmasıyla verir
//  (kom_gecerli seviye; kom_bitti'yi gördüğü kenarda indirir, 1 çevrim sonra sonraki komut).
//  İki ağ sırayla: ag1 (<VEKTOR_DIZINI>/) ve ag2 (<VEKTOR_DIZINI>/ag2/).
//  Kontroller (golden: sistem_golden.py, yorumla()):
//    1) PE izi (pe_izi.txt): her PE komutunda PE'ye giden mod, T ve 9 ağırlık; her akış
//       çevriminde 13 giriş (3 satır akışı × 3 + 4 kısmi toplam); her geçerli çıkış;
//       son = 1 ise SRU'ya gidecek int32 grup.
//    2) SRU (maksreg.txt): itilen her grubun LMS kaydırması l ve B'si (1. tür olay), ÖLÇEK'te
//       G (2. tür) ve SRU'nun saydığı grup sayısı (ÖLÇEK'in a1'i, A4), GMS'teki her grubun
//       kaydırması Δ = G - l (3. tür).
//    3) Bellek (veriyolu_bellek.txt): BİTTİ'den sonra kullanılan her bayt beklenen değerde;
//       AKT[1..L], HATA[1..L] ve AGR'nin her baytı tam bir kez, diğer baytlar hiç yazılmamış.
//    4) Yürütücünün hata bayrakları (FIFO taşma/eksik, ÖLÇEK'te grup yok) 0.
//  Sonuç: "SONUC tb_veriyolu: PASS k/k" (konsol ve <VEKTOR_DIZINI>/sonuc_tb_veriyolu.txt)
//  Yazan: Claude, 03.11.2026
// =============================================================================
`timescale 1ns/1ps

`define MOT dut.u_yur.u_motor
`define SRU dut.u_yur.u_sru

module tb_veriyolu;

    localparam AW = 13, BOYUT = 8192, LMAX = 8;
    localparam NKOM = 4096, NOLAY = 8192;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                    rst;
    reg  [159:0]           kom;
    reg                    kom_gecerli;
    wire                   kom_bitti;
    wire [5:0]             maks_G, hata_b;
    reg  [LMAX*8-1:0]      cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p;
    reg  [(LMAX+1)*AW-1:0] cfg_taban_akt, cfg_taban_hata, cfg_taban_agr;
    reg  [AW-1:0]          cfg_taban_etiket;

    sistem_veriyolu #(.AW(AW), .BOYUT(BOYUT), .LMAX(LMAX)) dut (
        .clk(clk), .rst(rst), .kom(kom), .kom_gecerli(kom_gecerli), .kom_bitti(kom_bitti),
        .maks_G(maks_G),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s), .cfg_p(cfg_p),
        .cfg_taban_akt(cfg_taban_akt), .cfg_taban_hata(cfg_taban_hata), .cfg_taban_agr(cfg_taban_agr),
        .cfg_taban_etiket(cfg_taban_etiket), .hata(hata_b)
    );

    // ------------------------------------------------------------------
    // Sayaçlar ve kontrol
    // ------------------------------------------------------------------
    integer hata, kontrol, sfd, cevrim;
    string  dizin, ag_adi;
    integer ki;                       // yürütülen komutun sırası
    reg     izleme;                   // izleyici açık mı

    always @(posedge clk) cevrim <= cevrim + 1;

    // Değerler önce değişkene alınıp öyle verilir (XSIM araç tuzağı 10: geniş task girişine
    // doğrudan verilen karşılaştırma ifadesi bozuk değerlendirilebiliyor).
    task kontrol_et(input [511:0] olan, input [511:0] beklenen, input string ne);
        begin
            kontrol = kontrol + 1;
            if (olan !== beklenen) begin
                hata = hata + 1;
                if (hata <= 30) $display("FAIL [%s] komut %0d: %s: olan %h, beklenen %h", ag_adi, ki, ne, olan, beklenen);
            end
        end
    endtask

    task hata_bildir(input string ne);
        begin
            kontrol = kontrol + 1;
            hata = hata + 1;
            if (hata <= 30) $display("FAIL [%s] komut %0d: %s", ag_adi, ki, ne);
        end
    endtask

    function integer bit_uzunlugu(input integer m);      // m >= 0 için bit_length
        integer b;
        reg [31:0] x;
        begin
            x = m;
            b = 0;
            while (x != 0) begin x = x >> 1; b = b + 1; end
            bit_uzunlugu = b;
        end
    endfunction

    // ------------------------------------------------------------------
    // Vektörler
    // ------------------------------------------------------------------
    integer n_kom, n_olay, N_bayt, L_ag, B_ag;
    integer kom_alan [0:NKOM-1][0:9];
    integer olay_tur [0:NOLAY-1], olay_grup [0:NOLAY-1], olay_d1 [0:NOLAY-1], olay_d2 [0:NOLAY-1];
    integer bas_mem [0:BOYUT-1], bek_mem [0:BOYUT-1], bolge [0:BOYUT-1], yazma_sayisi [0:BOYUT-1];
    integer p1, p2, p3;               // olay türü başına sıradaki olay

    function integer sonraki(input integer tur, input integer p);
        integer q;
        begin
            q = p;
            while (q < n_olay && olay_tur[q] != tur) q = q + 1;
            sonraki = q;
        end
    endfunction

    // PE izi: sıradaki PE komutunun kaydı
    integer fd_iz, n_iz, iz_sayisi;
    integer iz_kom_no, iz_mod, iz_T, iz_son, iz_ng, iz_ncik;
    integer iz_w [0:8];
    integer iz_akis [0:63][0:12];
    integer iz_cik_t [0:63];
    integer iz_cik_v [0:63][0:3];
    integer iz_grup [0:15];
    reg     iz_yuklu;
    integer akis_say, cik_ptr;

    task iz_oku(input integer beklenen_kom);
        integer r, tmp, j, k;
        begin
            r = $fscanf(fd_iz, "%d %d %d %d %d", iz_kom_no, iz_mod, iz_T, iz_son, iz_ng);
            if (r != 5) hata_bildir("pe_izi.txt okunamadi (kayit basligi)");
            if (iz_kom_no != beklenen_kom) hata_bildir($sformatf("pe_izi kaydi komut %0d icin, beklenen %0d", iz_kom_no, beklenen_kom));
            if (iz_T > 64 || iz_ng > 16) hata_bildir("pe_izi kaydi sinir disi");
            for (j = 0; j < 9; j = j + 1) begin r = $fscanf(fd_iz, "%d", tmp); iz_w[j] = tmp; end
            for (k = 0; k < iz_T; k = k + 1)
                for (j = 0; j < 13; j = j + 1) begin r = $fscanf(fd_iz, "%d", tmp); iz_akis[k][j] = tmp; end
            r = $fscanf(fd_iz, "%d", iz_ncik);
            for (k = 0; k < iz_ncik; k = k + 1) begin
                r = $fscanf(fd_iz, "%d", tmp); iz_cik_t[k] = tmp;
                for (j = 0; j < 4; j = j + 1) begin r = $fscanf(fd_iz, "%d", tmp); iz_cik_v[k][j] = tmp; end
            end
            if (iz_son)
                for (k = 0; k < iz_ng; k = k + 1) begin r = $fscanf(fd_iz, "%d", tmp); iz_grup[k] = tmp; end
            iz_yuklu  = 1'b1;
            akis_say  = 0;
            cik_ptr   = 0;
            iz_sayisi = iz_sayisi + 1;
        end
    endtask

    // ------------------------------------------------------------------
    // İzleyici (negedge: saatsiz sinyaller oturmuş)
    // ------------------------------------------------------------------
    reg [511:0] o_v, b_v;
    integer     tt, j2, olan_i, bek_i;
    always @(negedge clk) begin
        if (izleme) begin
            // 1) PE akışı
            if (`MOT.akis_gecerli) begin
                if (!iz_yuklu) hata_bildir("PE akisi var ama iz kaydi yok");
                else begin
                    tt = `MOT.t;
                    if (akis_say == 0) begin
                        o_v = `MOT.pe_mod; b_v = iz_mod;
                        kontrol_et(o_v, b_v, "PE modu");
                        o_v = `MOT.T; b_v = iz_T;
                        kontrol_et(o_v, b_v, "akis uzunlugu T");
                        o_v = `MOT.w_r; b_v = 0;
                        for (j2 = 0; j2 < 9; j2 = j2 + 1) b_v[8*j2 +: 8] = iz_w[j2];
                        kontrol_et(o_v, b_v, "PE agirliklari");
                    end
                    o_v = tt; b_v = akis_say;
                    kontrol_et(o_v, b_v, "akis cevrim sirasi");
                    if (tt < iz_T) begin
                        o_v = {`MOT.pe_ps, `MOT.pe_a3, `MOT.pe_a2, `MOT.pe_a1};
                        b_v = 0;
                        for (j2 = 0; j2 < 3; j2 = j2 + 1) begin
                            b_v[8*j2      +: 8] = iz_akis[tt][j2];        // akis1
                            b_v[24 + 8*j2 +: 8] = iz_akis[tt][3 + j2];    // akis2
                            b_v[48 + 8*j2 +: 8] = iz_akis[tt][6 + j2];    // akis3
                        end
                        for (j2 = 0; j2 < 4; j2 = j2 + 1) b_v[72 + 32*j2 +: 32] = iz_akis[tt][9 + j2];
                        kontrol_et(o_v, b_v, $sformatf("PE girisleri, cevrim %0d", tt));
                    end
                    akis_say = akis_say + 1;
                end
            end
            // 2) Çıkış yakalama
            if (`MOT.cikis_yakala) begin
                if (!iz_yuklu || cik_ptr >= iz_ncik) hata_bildir("beklenmeyen PE cikisi");
                else begin
                    o_v = `MOT.fig; b_v = iz_cik_t[cik_ptr];
                    kontrol_et(o_v, b_v, "cikis cevrimi");
                    o_v = `MOT.pe_cikis; b_v = 0;
                    for (j2 = 0; j2 < 4; j2 = j2 + 1) b_v[32*j2 +: 32] = iz_cik_v[cik_ptr][j2];
                    // D104 (06.11): pe_birlesik BP s2 dışında üst şeritleri (1-3) 0'a çekmiyor; tüketici (pe_motoru)
                    // o modlarda yalnızca şerit 0'ı okuyor. Yalnızca okunan şeritler karşılaştırılır.
                    if (iz_mod != 3) begin o_v[127:32] = 96'd0; b_v[127:32] = 96'd0; end
                    kontrol_et(o_v, b_v, $sformatf("PE cikisi, cevrim %0d", iz_cik_t[cik_ptr]));
                    cik_ptr = cik_ptr + 1;
                end
            end
            // 3) Geçişin sonu
            if (`MOT.bitti) begin
                if (!iz_yuklu) hata_bildir("motor bitti ama iz kaydi yok");
                else begin
                    o_v = akis_say; b_v = iz_T;
                    kontrol_et(o_v, b_v, "akis cevrim sayisi");
                    o_v = cik_ptr; b_v = iz_ncik;
                    kontrol_et(o_v, b_v, "cikis sayisi");
                    o_v = `MOT.grup_gecerli; b_v = iz_son;
                    kontrol_et(o_v, b_v, "grup_gecerli");
                    if (iz_son) begin
                        o_v = `MOT.grup_n; b_v = iz_ng;
                        kontrol_et(o_v, b_v, "grup eleman sayisi");
                        o_v = `MOT.grup_flat; b_v = 0;
                        for (j2 = 0; j2 < iz_ng; j2 = j2 + 1) b_v[32*j2 +: 32] = iz_grup[j2];
                        kontrol_et(o_v, b_v, "grup (int32)");
                    end
                    iz_yuklu = 1'b0;
                end
            end
            // 4) SRU: itilen grup (1. tür olay)
            if (`SRU.push_group) begin
                p1 = sonraki(1, p1);
                if (`SRU.faz != 1'b0) hata_bildir("SRU GMS'teyken grup itildi");
                if (p1 >= n_olay) hata_bildir("fazla grup itildi (maksreg'de 1. tur olay kalmadi)");
                else begin
                    olan_i = `SRU.lms_l; bek_i = olay_d2[p1];
                    o_v = olan_i; b_v = bek_i;
                    kontrol_et(o_v, b_v, $sformatf("SRU LMS kaydirmasi l, grup %0d", olay_grup[p1]));
                    olan_i = `SRU.lms_B; bek_i = bit_uzunlugu(olay_d1[p1]);
                    o_v = olan_i; b_v = bek_i;
                    kontrol_et(o_v, b_v, $sformatf("SRU yerel B, grup %0d", olay_grup[p1]));
                    p1 = p1 + 1;
                end
            end
            // 5) SRU: GMS (3. tür olay), her çevrimde bir grup
            if (`SRU.faz == 1'b1) begin
                p3 = sonraki(3, p3);
                if (p3 >= n_olay) hata_bildir("fazla GMS grubu (maksreg'de 3. tur olay kalmadi)");
                else begin
                    olan_i = `SRU.G; olan_i = olan_i - `SRU.gms_l; bek_i = olay_d1[p3];
                    o_v = olan_i; b_v = bek_i;
                    kontrol_et(o_v, b_v, $sformatf("SRU GMS kaydirmasi G - l, grup %0d", olay_grup[p3]));
                    p3 = p3 + 1;
                end
            end
            // 6) Yazma sayacı
            if (dut.yaz)
                for (j2 = 0; j2 < 16; j2 = j2 + 1)
                    if (j2 < dut.yaz_n && dut.yaz_adr + j2 < BOYUT)
                        yazma_sayisi[dut.yaz_adr + j2] = yazma_sayisi[dut.yaz_adr + j2] + 1;
        end
    end

    // ------------------------------------------------------------------
    // Bir ağın çalıştırılması
    // ------------------------------------------------------------------
    task dosya_ac(output integer fd, input string ad);
        begin
            fd = $fopen({dizin, ad}, "r");
            if (fd == 0) hata_bildir({"dosya acilamadi: ", dizin, ad});
        end
    endtask

    task ag_calistir(input string d, input string ad);
        integer fd, r, i, j, tmp, a, cin_, cout_, h_, w_, s_, p_, zaman, c0, bek_yaz, kacak;
        integer hata0, kontrol0;
        reg [15:0] alan [0:9];
        begin
            dizin = d; ag_adi = ad;
            hata0 = hata; kontrol0 = kontrol;
            izleme = 1'b0;
            // ---- düzen ve yapılandırma ----
            dosya_ac(fd, "veriyolu_duzen.txt");
            r = $fscanf(fd, "%d %d %d", L_ag, B_ag, N_bayt);
            cfg_cin = 0; cfg_cout = 0; cfg_h = 0; cfg_w = 0; cfg_s = 0; cfg_p = 0;
            for (i = 0; i < L_ag; i = i + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d", cin_, cout_, h_, w_, s_, p_);
                cfg_cin[8*i +: 8] = cin_; cfg_cout[8*i +: 8] = cout_;
                cfg_h[8*i +: 8] = h_; cfg_w[8*i +: 8] = w_;
                cfg_s[8*i +: 8] = s_; cfg_p[8*i +: 8] = p_;
            end
            cfg_taban_akt = 0; cfg_taban_hata = 0; cfg_taban_agr = 0;
            for (i = 0; i <= L_ag; i = i + 1) begin r = $fscanf(fd, "%d", tmp); cfg_taban_akt [AW*i +: AW] = tmp; end
            for (i = 0; i <= L_ag; i = i + 1) begin r = $fscanf(fd, "%d", tmp); cfg_taban_hata[AW*i +: AW] = tmp; end
            for (i = 0; i <= L_ag; i = i + 1) begin r = $fscanf(fd, "%d", tmp); cfg_taban_agr [AW*i +: AW] = tmp; end
            r = $fscanf(fd, "%d", tmp); cfg_taban_etiket = tmp;
            $fclose(fd);
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
            // ---- komutlar ----
            dosya_ac(fd, "komutlar.txt");
            r = $fscanf(fd, "%d", n_kom);
            if (n_kom > NKOM) hata_bildir("komut sayisi NKOM'u asiyor");
            for (i = 0; i < n_kom; i = i + 1)
                for (j = 0; j < 10; j = j + 1) begin r = $fscanf(fd, "%d", tmp); kom_alan[i][j] = tmp; end
            $fclose(fd);
            // ---- Max Regs olayları ----
            dosya_ac(fd, "maksreg.txt");
            r = $fscanf(fd, "%d", n_olay);
            if (n_olay > NOLAY) hata_bildir("olay sayisi NOLAY'i asiyor");
            for (i = 0; i < n_olay; i = i + 1) begin
                r = $fscanf(fd, "%d", tmp); olay_tur[i] = tmp;
                r = $fscanf(fd, "%d", tmp); olay_grup[i] = tmp;
                r = $fscanf(fd, "%d", tmp); olay_d1[i] = tmp;
                r = $fscanf(fd, "%d", tmp); olay_d2[i] = tmp;
            end
            $fclose(fd);
            p1 = 0; p2 = 0; p3 = 0;
            // ---- PE izi ----
            dosya_ac(fd_iz, "pe_izi.txt");
            r = $fscanf(fd_iz, "%d", n_iz);
            iz_sayisi = 0; iz_yuklu = 1'b0; akis_say = 0; cik_ptr = 0;

            // ---- reset, belleğin yüklenmesi ----
            @(negedge clk);
            rst = 1'b1; kom_gecerli = 1'b0; kom = 160'd0;
            for (i = 0; i < BOYUT; i = i + 1) begin
                dut.u_bellek.mem[i] = bas_mem[i];
                yazma_sayisi[i] = 0;
            end
            repeat (3) @(negedge clk);
            // Yükleme tuttu mu? (testbench belleğe hiyerarşik olarak yazıyor)
            kacak = 0;
            for (i = 0; i < BOYUT; i = i + 1) begin
                o_v = dut.u_bellek.mem[i]; b_v = 0; b_v[7:0] = bas_mem[i];
                if (o_v !== b_v) kacak = kacak + 1;
            end
            o_v = kacak; b_v = 0;
            kontrol_et(o_v, b_v, "bellek yuklemesi (hiyerarsik yazma) tutmayan bayt");
            rst = 1'b0;
            izleme = 1'b1;
            c0 = cevrim;

            // ---- komutlar FSM'in el sıkışmasıyla ----
            for (ki = 0; ki < n_kom; ki = ki + 1) begin
                if (kom_alan[ki][0] == 1) iz_oku(ki);
                for (j = 0; j < 10; j = j + 1) alan[j] = kom_alan[ki][j];
                @(posedge clk);
                kom         <= {alan[9], alan[8], alan[7], alan[6], alan[5], alan[4], alan[3], alan[2], alan[1], alan[0]};
                kom_gecerli <= 1'b1;
                zaman = 0;
                @(posedge clk);
                while (!kom_bitti && zaman < 20000) begin @(posedge clk); zaman = zaman + 1; end
                if (!kom_bitti) begin
                    hata_bildir($sformatf("kom_bitti gelmedi (op %0d)", kom_alan[ki][0]));
                    ki = n_kom;                               // çık
                end else begin
                    kom_gecerli <= 1'b0;
                    if (kom_alan[ki][0] == 2) begin           // ÖLÇEK: G (2. tür olay) ve grup sayısı
                        p2 = sonraki(2, p2);
                        if (p2 >= n_olay) hata_bildir("maksreg'de G olayi kalmadi");
                        else begin
                            olan_i = maks_G; bek_i = olay_d1[p2];
                            o_v = olan_i; b_v = bek_i;
                            kontrol_et(o_v, b_v, "OLCEK: G");
                            p2 = p2 + 1;
                        end
                        olan_i = `SRU.n_groups; bek_i = kom_alan[ki][7];
                        o_v = olan_i; b_v = bek_i;
                        kontrol_et(o_v, b_v, "OLCEK: SRU'nun grup sayisi = a1");
                    end
                end
            end
            @(posedge clk);
            repeat (4) @(negedge clk);
            izleme = 1'b0;
            $fclose(fd_iz);

            // ---- son kontroller ----
            o_v = iz_sayisi; b_v = n_iz;
            kontrol_et(o_v, b_v, "kullanilan PE izi kaydi");
            olan_i = sonraki(1, p1); o_v = olan_i; b_v = n_olay; kontrol_et(o_v, b_v, "itilmeyen grup kalmadi (1. tur)");
            olan_i = sonraki(2, p2); o_v = olan_i; b_v = n_olay; kontrol_et(o_v, b_v, "G olaylari bitti (2. tur)");
            olan_i = sonraki(3, p3); o_v = olan_i; b_v = n_olay; kontrol_et(o_v, b_v, "GMS olaylari bitti (3. tur)");
            o_v = hata_b; b_v = 0;
            kontrol_et(o_v, b_v, "yurutucu hata bayraklari {olcek, tuketici, gfifo eksik, gfifo tasma, psum eksik, psum tasma}");
            for (i = 0; i < N_bayt; i = i + 1) begin
                o_v = dut.u_bellek.mem[i]; b_v = 0; b_v[7:0] = bek_mem[i];
                kontrol_et(o_v, b_v, $sformatf("bellek adr %0d (bolge %0d)", i, bolge[i]));
                bek_yaz = ((bolge[i] > 100 && bolge[i] < 200) || (bolge[i] > 200 && bolge[i] < 400)) ? 1 : 0;
                o_v = yazma_sayisi[i]; b_v = bek_yaz;
                kontrol_et(o_v, b_v, $sformatf("yazma sayisi adr %0d (bolge %0d)", i, bolge[i]));
            end
            kacak = 0;
            for (i = N_bayt; i < BOYUT; i = i + 1) if (yazma_sayisi[i] != 0) kacak = kacak + 1;
            o_v = kacak; b_v = 0;
            kontrol_et(o_v, b_v, "kullanilan alanin disina yazilan bayt");
            $display("[%s] %0d komut, %0d PE gecisi, %0d cevrim; bu agda %0d kontrol, %0d hata",
                     ad, n_kom, iz_sayisi, cevrim - c0, kontrol - kontrol0, hata - hata0);
        end
    endtask

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            sfd = $fopen({dizin, "sonuc_tb_veriyolu.txt"}, "w");
            if (sfd != 0) begin
                $fdisplay(sfd, "%s", satir);
                $fclose(sfd);
            end
        end
    endtask

    string kok;
    initial begin
        hata = 0; kontrol = 0; cevrim = 0; ki = 0;
        izleme = 1'b0; iz_yuklu = 1'b0;
        rst = 1'b1; kom = 160'd0; kom_gecerli = 1'b0;
        if (!$value$plusargs("VEKTOR_DIZINI=%s", kok)) kok = "";
        // Klasör doğru mu? (yolda boşluk varsa plusarg bozulur) Bulunamazsa çalışma klasörü.
        sfd = $fopen({kok, "komutlar.txt"}, "r");
        if (sfd == 0) kok = ""; else $fclose(sfd);

        ag_calistir(kok, "ag1");
        ag_calistir({kok, "ag2/"}, "ag2");

        dizin = kok;
        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_veriyolu: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_veriyolu: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
