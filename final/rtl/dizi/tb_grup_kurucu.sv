// =============================================================================
//  tb_grup_kurucu.sv — grup_kurucu + sru_array (16 kanal), dizi golden'ının gruplarına karşı
// -----------------------------------------------------------------------------
//  Vektör: models/sistem/adim5_vektorleri/dizi_grup.txt ve ag2/dizi_grup.txt (dizi_golden.py).
//  Her iş: SRU ve kurucu sıfırlanır, hedef verilir; her kayıtta PE çıkışları (cikis_flat ya da g_flat)
//  kurulur, kayıttaki her seçim için 1 çevrim `kur`; sonra `son_it`. Ardından 16 SRU kanalının GMS
//  çıkışları, golden'ın grup başına int8 değerleriyle sırayla karşılaştırılır; G de kontrol edilir.
//  Kayıtta olmayan PE'ler, dolu sütunların dışı ve kullanılmayan şeritler her kayıtta rastgele: grup
//  kurucunun seçimi ve sütun maskesi böylece denetleniyor.
//  Sonuç: "SONUC tb_grup_kurucu: PASS n/n" (+ VEKTOR_DIZINI varsa sonuc_tb_grup_kurucu.txt)
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b)
// =============================================================================
`timescale 1ns/1ps

// Üst modülde hiç sinyal yok: Vivado GUI'nin başlatma script'i üst seviyede sinyal bulamayınca dalga
// penceresi açmıyor. Bu testbench'in büyük register'ları ve SV kuyrukları dalga görünümünü çökertiyordu
// (04.11, araç tuzağı 13). Testbench'in kendisi aşağıdaki tb_grup_kurucu_govde modülünde.
module tb_grup_kurucu;
    tb_grup_kurucu_govde govde ();
endmodule

module tb_grup_kurucu_govde;

    localparam R = 16, C = 16, N = R*C;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg              rst = 1'b1;
    reg  [2:0]       hedef = 3'd7;
    reg  [N*128-1:0] cikis = '0;
    reg  [N*288-1:0] g = '0;
    reg              kur = 1'b0, akum_mi = 1'b0, son_it = 1'b0;
    reg  [3:0]       sec = 4'd0;
    reg  [R-1:0]     maske = '0;
    reg  [4:0]       n_sutun = 5'd0;

    wire [R-1:0]       push, last;
    wire [R*512-1:0]   grup;
    wire [R*5-1:0]     grup_n;
    wire [R-1:0]       o_gecerli, katman_bitti, mesgul;
    wire [R*128-1:0]   o_grup;
    wire [R*5-1:0]     o_n;
    wire [5:0]         G;

    grup_kurucu #(.R(R), .C(C)) dut (
        .clk(clk), .rst(rst), .cikis_flat(cikis), .g_flat(g),
        .kur(kur), .akum_mi(akum_mi), .sec(sec), .satir_maske(maske), .n_sutun(n_sutun), .son_it(son_it),
        .push_group_all(push), .group_in_flat_all(grup), .group_n_all(grup_n), .last_group_all(last)
    );

    sru_array u_sru (
        .clk(clk), .rst(rst), .hedef(hedef),
        .push_group_all(push), .group_in_flat_all(grup), .group_n_all(grup_n), .last_group_all(last),
        .group_out_valid_all(o_gecerli), .group_out_flat_all(o_grup), .group_out_n_all(o_n),
        .layer_done_all(katman_bitti), .busy_all(mesgul), .G_shared(G)
    );

    // ---- Beklenen GMS çıkışları: kanal başına kuyruk (grup boyu + değerler) ----
    int beklenen_n [R][$];
    int beklenen_v [R][$];
    integer kontrol = 0, hata = 0;
    reg izle = 1'b0;

    always @(posedge clk) begin : gozle
        integer i, k, n, v;
        if (izle) begin
            for (i = 0; i < R; i = i + 1) begin
                if (o_gecerli[i]) begin
                    kontrol = kontrol + 1;
                    if (beklenen_n[i].size() == 0) begin
                        hata = hata + 1;
                        if (hata <= 10) $display("HATA kanal %0d: beklenmeyen grup", i);
                    end else begin
                        n = beklenen_n[i].pop_front();
                        if (o_n[5*i +: 5] !== n[4:0]) begin
                            hata = hata + 1;
                            if (hata <= 10) $display("HATA kanal %0d: grup boyu %0d, beklenen %0d", i, o_n[5*i +: 5], n);
                        end
                        for (k = 0; k < n; k = k + 1) begin
                            v = beklenen_v[i].pop_front();
                            if (o_grup[128*i + 8*k +: 8] !== v[7:0]) begin
                                hata = hata + 1;
                                if (hata <= 10) $display("HATA kanal %0d eleman %0d: %0d, beklenen %0d", i, k,
                                                         $signed(o_grup[128*i + 8*k +: 8]), v);
                            end
                        end
                    end
                end
            end
        end
    end

    task automatic rastgele_cikislar;
        integer q;
        for (q = 0; q < N*4; q = q + 1)  cikis[32*q +: 32] = $random;
        for (q = 0; q < N*9; q = q + 1)  g[32*q +: 32]     = $random;
    endtask

    integer fd, n_is, is_, n_kayit, kk, mod_, am, nr, no, n_alt, a, i, j, q, v, s_, m_, G_bek, h_, sayi, gg, e;
    integer n_ag = 0, n_grup = 0;
    reg [8*16-1:0] etiket;
    reg [1023:0] dizin, yol;
    int n_sira [R][$];                 // kanal başına, kurulan grupların boyu (kurulma sırasıyla)

    task automatic ag_kos(input reg [1023:0] dosya);
        fd = $fopen(dosya, "r");
        if (fd == 0) begin
            hata = hata + 1;
            $display("HATA: %0s acilamadi", dosya);
            return;
        end
        n_ag = n_ag + 1;
        void'($fscanf(fd, "%d", n_is));
        for (is_ = 0; is_ < n_is; is_ = is_ + 1) begin
            void'($fscanf(fd, "%s %d %d %d", etiket, h_, G_bek, n_kayit));
            @(negedge clk);
            rst = 1'b1; hedef = h_[2:0]; izle = 1'b1;
            @(negedge clk);
            rst = 1'b0;
            for (kk = 0; kk < n_kayit; kk = kk + 1) begin
                void'($fscanf(fd, "%s %d %d %d %d %d", etiket, mod_, am, nr, no, n_alt));
                rastgele_cikislar();
                for (i = 0; i < nr; i = i + 1)
                    for (j = 0; j < no; j = j + 1)
                        for (q = 0; q < (am ? 9 : 4); q = q + 1) begin
                            void'($fscanf(fd, "%d", v));
                            if (am) g[288*(i*C + j) + 32*q +: 32] = v;
                            else    cikis[128*(i*C + j) + 32*q +: 32] = v;
                        end
                for (a = 0; a < n_alt; a = a + 1) begin
                    void'($fscanf(fd, "%d %d", s_, m_));
                    kur = 1'b1; akum_mi = am[0]; sec = s_[3:0]; maske = m_[R-1:0]; n_sutun = no[4:0];
                    for (i = 0; i < R; i = i + 1) if (m_[i]) n_sira[i].push_back(no);
                    @(negedge clk);
                    kur = 1'b0;
                end
            end
            // beklenen GMS çıkışları
            for (i = 0; i < R; i = i + 1) begin
                void'($fscanf(fd, "%d", sayi));
                for (gg = 0; gg < sayi; gg = gg + 1) begin
                    no = n_sira[i].pop_front();
                    beklenen_n[i].push_back(no);
                    for (e = 0; e < no; e = e + 1) begin
                        void'($fscanf(fd, "%d", v));
                        beklenen_v[i].push_back(v);
                    end
                    n_grup = n_grup + 1;
                end
            end
            son_it = 1'b1;
            @(negedge clk);
            son_it = 1'b0;
            @(negedge clk);
            kontrol = kontrol + 1;
            if (G !== G_bek[5:0]) begin
                hata = hata + 1;
                $display("HATA is %0d: G %0d, beklenen %0d", is_, G, G_bek);
            end
            // GMS çıkışlarının bitmesini bekle (her kanal en çok 64 grup)
            repeat (80) @(negedge clk);
            for (i = 0; i < R; i = i + 1)
                if (beklenen_n[i].size() != 0) begin
                    hata = hata + 1;
                    if (hata <= 10) $display("HATA is %0d kanal %0d: %0d grup gelmedi", is_, i, beklenen_n[i].size());
                    beklenen_n[i].delete(); beklenen_v[i].delete();
                end
            izle = 1'b0;
        end
        $fclose(fd);
    endtask

    integer sfd;
    initial begin
        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin)) dizin = "";
        repeat (2) @(negedge clk);
        yol = {dizin, "dizi_grup.txt"};
        fd = $fopen(yol, "r");
        if (fd == 0) yol = "dizi_grup.txt"; else $fclose(fd);
        ag_kos(yol);
        yol = {dizin, "ag2/dizi_grup.txt"};
        fd = $fopen(yol, "r");
        if (fd == 0) yol = "ag2/dizi_grup.txt"; else $fclose(fd);
        ag_kos(yol);

        if (hata == 0) $display("SONUC tb_grup_kurucu: PASS %0d/%0d (%0d ag, %0d grup)", kontrol, kontrol, n_ag, n_grup);
        else           $display("SONUC tb_grup_kurucu: FAIL %0d hata / %0d", hata, kontrol);
        sfd = $fopen({dizin, "sonuc_tb_grup_kurucu.txt"}, "w");
        if (sfd != 0) begin
            if (hata == 0) $fdisplay(sfd, "SONUC tb_grup_kurucu: PASS %0d/%0d", kontrol, kontrol);
            else           $fdisplay(sfd, "SONUC tb_grup_kurucu: FAIL %0d hata / %0d", hata, kontrol);
            $fclose(sfd);
        end
        $finish;
    end

endmodule
