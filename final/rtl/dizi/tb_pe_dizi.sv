// =============================================================================
//  tb_pe_dizi.sv — pe_dizi (16x16) için adım adım karşılaştırma
// -----------------------------------------------------------------------------
//  Referans: 256 ayrı pe_birlesik + testbench'te SystemVerilog kuyruklarıyla yazılmış Psum
//  FIFO ve B şeridi gecikmesi. Referansın girişleri dizilerden (satır başına akış, sütun başına
//  ağırlık) ayrı indislemeyle kuruluyor; dizinin satır/sütun bağlantısı, PE içi FIFO'ları ve
//  BP s2'nin B gecikmesi böylece bağımsız denetleniyor. PE'nin aritmetiği zaten doğrulandı
//  (D69: tb_pe_birlesik, Egemen'in PE testleri).
//
//  Uyaran: her komut rastgele mod (0..5), 0..3 boş çevrim, WG'de %50 rst, 3..40 akış çevrimi.
//  Her satıra ve sütuna her çevrim farklı rastgele değer. FIFO kontrolleri rastgele, ama
//  testbench boş FIFO'dan okumaz/seçmez, dolu FIFO'ya yazmaz (bayraklar 0 kalmalı). Arada
//  rastgele ps_temizle.
//  Her çevrim 256 PE'nin cikis_flat ve g_flat'ı karşılaştırılır.
//  Sonuç: "SONUC tb_pe_dizi: PASS n/n" (+ VEKTOR_DIZINI varsa sonuc_tb_pe_dizi.txt)
//  Yazan: Claude, 04.11.2026 (final/, Adım 5a)
// =============================================================================
`timescale 1ns/1ps

module tb_pe_dizi;

    localparam R = 16, C = 16, N = R*C;
    localparam DER = 64;
    localparam KOMUT = 400;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg              rst = 1'b0;
    reg  [2:0]       mod = 3'd6;
    reg  [R*24-1:0]  a1f = '0, a2f = '0, a3f = '0;
    reg  [C*72-1:0]  wf  = '0;
    reg              ps_temizle = 1'b1, ps_yaz = 1'b0, ps_oku = 1'b0, ps_sec = 1'b0;
    wire [N*128-1:0] cikis;
    wire [N*288-1:0] g;
    wire             tasma, eksik;

    pe_dizi #(.R(R), .C(C), .PS_DERINLIK(DER), .PS_AW(6)) dut (
        .clk(clk), .rst(rst), .mod(mod),
        .satir_akis1_flat(a1f), .satir_akis2_flat(a2f), .satir_akis3_flat(a3f),
        .sutun_w_flat(wf),
        .ps_temizle(ps_temizle), .ps_yaz(ps_yaz), .ps_oku(ps_oku), .ps_sec(ps_sec),
        .cikis_flat(cikis), .g_flat(g), .ps_tasma(tasma), .ps_eksik(eksik)
    );

    // ---- Referans: satır/sütun dizileri, 256 pe_birlesik ----
    reg  [23:0]  ra1 [0:R-1];
    reg  [23:0]  ra2 [0:R-1];
    reg  [23:0]  ra3 [0:R-1];
    reg  [71:0]  rw  [0:C-1];
    reg  [127:0] rps [0:R-1][0:C-1];
    wire [127:0] rcik [0:R-1][0:C-1];
    wire [287:0] rg   [0:R-1][0:C-1];

    genvar gr, gc;
    generate
        for (gr = 0; gr < R; gr = gr + 1) begin : rs
            for (gc = 0; gc < C; gc = gc + 1) begin : rc
                pe_birlesik u_ref (
                    .clk(clk), .rst(rst), .mod(mod), .w_flat(rw[gc]),
                    .akis1(ra1[gr]), .akis2(ra2[gr]), .akis3(ra3[gr]),
                    .ps_flat(rps[gr][gc]), .cikis_flat(rcik[gr][gc]), .g_flat(rg[gr][gc])
                );
            end
        end
    endgenerate

    // Referans FIFO'ları ve B gecikmesi
    reg [127:0] kuyruk [0:N-1][$];
    reg [127:0] rb [0:N-1];
    reg [127:0] rcik_kenar [0:N-1];   // ps_yaz'ın yazacağı değer: kenardan önceki referans çıkışı
    integer doluluk;             // bütün PE'lerde aynı (aynı kontrol)

    integer kontrol = 0, hata = 0;
    integer i, r, c, k, n, t, komut;
    reg [127:0] bas;

    task automatic rastgele_girisler;
        for (r = 0; r < R; r = r + 1) begin
            ra1[r] = {$random, $random}; ra2[r] = $random; ra3[r] = $random;
            a1f[24*r +: 24] = ra1[r]; a2f[24*r +: 24] = ra2[r]; a3f[24*r +: 24] = ra3[r];
        end
        for (c = 0; c < C; c = c + 1) begin
            rw[c] = {$random, $random, $random};
            wf[72*c +: 72] = rw[c];
        end
    endtask

    task automatic sifir_girisler;
        for (r = 0; r < R; r = r + 1) begin
            ra1[r] = 0; ra2[r] = 0; ra3[r] = 0;
        end
        for (c = 0; c < C; c = c + 1) rw[c] = 0;
        a1f = '0; a2f = '0; a3f = '0; wf = '0;
    endtask

    // Girişler negedge'de kuruldu; burada karşılaştır, referansın ps'ini kur, FIFO'yu ilerlet
    task automatic cevrim;
        #1;
        for (i = 0; i < N; i = i + 1) begin
            r = i / C; c = i % C;
            rcik_kenar[i] = rcik[r][c];          // girişler kenara kadar sabit: yazılacak değer
            kontrol = kontrol + 1;
            if (cikis[128*i +: 128] !== rcik[r][c] || g[288*i +: 288] !== rg[r][c]) begin
                hata = hata + 1;
                if (hata <= 10)
                    $display("HATA t=%0t mod=%0d PE(%0d,%0d): cikis %h / %h", $time, mod, r, c,
                             cikis[128*i +: 128], rcik[r][c]);
            end
            // referans ps (bu çevrim)
            bas = (doluluk > 0) ? kuyruk[i][0] : 128'd0;
            if (mod == 3'd3)
                rps[r][c] = {rb[i][96 +: 32], (ps_sec ? bas[64 +: 32] : 32'd0),
                             rb[i][32 +: 32], (ps_sec ? bas[0 +: 32] : 32'd0)};
            else
                rps[r][c] = {96'd0, (ps_sec ? bas[0 +: 32] : 32'd0)};
        end
        @(posedge clk);
        // kenarda olan FIFO işlemleri (yazılan değer kenardan önceki çıkış)
        for (i = 0; i < N; i = i + 1) begin
            r = i / C; c = i % C;
            bas = (doluluk > 0) ? kuyruk[i][0] : 128'd0;
            if (ps_temizle) begin
                kuyruk[i].delete();
            end else begin
                if (ps_oku) void'(kuyruk[i].pop_front());
                if (ps_yaz) kuyruk[i].push_back(rcik_kenar[i]);
            end
            rb[i] = (ps_oku && !ps_temizle && doluluk > 0) ? bas : 128'd0;
        end
        doluluk = kuyruk[0].size();
        @(negedge clk);
    endtask


    task automatic kontrolleri_sec(input integer akis);
        ps_temizle = ($urandom % 200 == 0);
        ps_oku = akis && (doluluk > 0) && ($urandom % 4 != 0);
        ps_sec = akis && (doluluk > 0) && ($urandom % 5 != 0);
        ps_yaz = akis && ($urandom % 3 != 0) && (doluluk - ps_oku < DER);
    endtask

    integer fd;
    reg [1023:0] dizin;
    initial begin
        for (i = 0; i < N; i = i + 1) rb[i] = 0;
        for (r = 0; r < R; r = r + 1) for (c = 0; c < C; c = c + 1) rps[r][c] = 0;
        sifir_girisler();
        doluluk = 0;
        repeat (2) @(negedge clk);
        ps_temizle = 1'b0;

        for (komut = 0; komut < KOMUT; komut = komut + 1) begin
            mod = $urandom % 6;
            n = $urandom % 4;
            for (t = 0; t < n; t = t + 1) begin
                sifir_girisler(); kontrolleri_sec(0); rst = 1'b0; cevrim();
            end
            if (mod >= 4 && ($urandom % 2)) begin
                sifir_girisler(); kontrolleri_sec(0); rst = 1'b1; cevrim(); rst = 1'b0;
            end
            n = 3 + $urandom % 38;
            for (t = 0; t < n; t = t + 1) begin
                rastgele_girisler(); kontrolleri_sec(1); cevrim();
            end
        end
        sifir_girisler(); kontrolleri_sec(0); cevrim();

        if (tasma || eksik) begin
            hata = hata + 1;
            $display("HATA: FIFO bayragi tasma=%0d eksik=%0d", tasma, eksik);
        end
        if (hata == 0) $display("SONUC tb_pe_dizi: PASS %0d/%0d (%0d komut, 16x16)", kontrol, kontrol, KOMUT);
        else           $display("SONUC tb_pe_dizi: FAIL %0d hata / %0d", hata, kontrol);
        if ($value$plusargs("VEKTOR_DIZINI=%s", dizin)) begin
            fd = $fopen({dizin, "sonuc_tb_pe_dizi.txt"}, "w");
            if (fd != 0) begin
                if (hata == 0) $fdisplay(fd, "SONUC tb_pe_dizi: PASS %0d/%0d", kontrol, kontrol);
                else           $fdisplay(fd, "SONUC tb_pe_dizi: FAIL %0d hata / %0d", hata, kontrol);
                $fclose(fd);
            end
        end
        $finish;
    end

endmodule
