// =============================================================================
//  tb_fsm_dizi.sv — master_controller_dizi, golden'ın komut listesine karşı (Adım 5b-3d)
// -----------------------------------------------------------------------------
//  Vektörler: ag_yapilandirma.txt, bolgeler.txt, komutlar_dizi.txt (ag1, ag2/, ag3/).
//  FSM'in her komutu (10 alan) golden'ın sırasıyla karşılaştırılır. kom_bitti 1–3 çevrim sonra verilir;
//  ÖLÇEK'te maks_G, işin yazdığı bölgenin golden G'si (FP l: AKT[l], BP l: HATA[l-1], WG l: GRAD[l]).
//  s_a (SA ve CLU komutlarında) bu G'lerle FSM'in kendisi tarafından hesaplanır (D32).
//  Üç ağ art arda, aralarında reset yok (basla ile yeniden).
//  Sonuç: "SONUC tb_fsm_dizi: PASS n/n". Yazan: Claude, 04.11.2026 (final/, Adım 5b-3d)
// =============================================================================
`timescale 1ns/1ps

module tb_fsm_dizi;
    tb_fsm_dizi_govde govde ();
endmodule

module tb_fsm_dizi_govde;

    localparam AW = 16, LMAX = 15;   // D103: sentezle aynı

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg              rst = 1'b1, basla = 1'b0, kom_bitti = 1'b0;
    reg  [3:0]       cfg_L = 0, cfg_m_u = 0;
    reg  [15:0]      cfg_batch = 0;
    reg  [7:0]       cfg_s_a0 = 0;
    reg  [LMAX*16-1:0] cfg_cin = 0, cfg_cout = 0;
    reg  [LMAX*8-1:0] cfg_h = 0, cfg_w = 0, cfg_s = 0, cfg_p = 0, cfg_relu = 0, cfg_sw = 0;
    reg  [5:0]       maks_G = 0;
    wire             kom_gecerli, mesgul, bitti;
    wire [10*AW-1:0] kom;

    master_controller_dizi #(.AW(AW), .LMAX(LMAX)) dut (
        .clk(clk), .rst(rst), .basla(basla), .cfg_L(cfg_L), .cfg_batch(cfg_batch), .cfg_m_u(cfg_m_u),
        .cfg_s_a0(cfg_s_a0), .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w), .cfg_s(cfg_s),
        .cfg_p(cfg_p), .cfg_relu(cfg_relu), .cfg_sw(cfg_sw), .maks_G(maks_G), .kom_bitti(kom_bitti),
        .kom_gecerli(kom_gecerli), .kom(kom), .mesgul(mesgul), .bitti(bitti));

    integer kontrol = 0, hata = 0, n_ag = 0, n_kom = 0;
    integer fd, n, i, q, v, ll, tmp, adr, bekle, a, b_, c_, d_, e_, f_, g_, h_;
    localparam KMAX = 32768;
    integer kmt [0:KMAX-1][0:9];       // D103: önceden 0:1023 (AG6 aşar)
    integer G_akt [0:15], G_hata [0:15], G_grad [0:15];   // D103: LMAX 15
    reg [8*16-1:0] ad;
    string dizin, yol;

    task automatic dosya_ac(input string alt, input string isim);
        yol = {dizin, alt, isim};
        fd = $fopen(yol, "r");
        if (fd == 0) begin yol = {alt, isim}; fd = $fopen(yol, "r"); end
        if (fd == 0) begin hata = hata + 1; $display("HATA: %s acilamadi", yol); end
    endtask

    task automatic ag_kos(input string alt);
        dosya_ac(alt, "ag_yapilandirma.txt");
        void'($fscanf(fd, "%d %d %d %d %d", a, b_, c_, d_, tmp));
        cfg_L = a; cfg_batch = b_; cfg_m_u = c_; cfg_s_a0 = d_;
        cfg_cin = 0; cfg_cout = 0; cfg_h = 0; cfg_w = 0; cfg_s = 0; cfg_p = 0; cfg_relu = 0; cfg_sw = 0;
        for (ll = 0; ll < a; ll = ll + 1) begin
            void'($fscanf(fd, "%d %d %d %d %d %d %d %d", b_, c_, d_, e_, f_, g_, h_, v));
            cfg_cin[16*ll +: 16] = b_; cfg_cout[16*ll +: 16] = c_; cfg_h[8*ll +: 8] = d_; cfg_w[8*ll +: 8] = e_;
            cfg_s[8*ll +: 8] = f_; cfg_p[8*ll +: 8] = g_; cfg_relu[8*ll +: 8] = h_; cfg_sw[8*ll +: 8] = v;
        end
        $fclose(fd);
        dosya_ac(alt, "bolgeler.txt");
        void'($fscanf(fd, "%d %d", n, tmp));
        for (i = 0; i < n; i = i + 1) begin
            void'($fscanf(fd, "%s %d %d %d %d %d %d %d", ad, adr, tmp, tmp, tmp, tmp, tmp, v));
            ll = ad[7:0] - "0";
            if ((ad >> 8) == "AKT")  G_akt[ll] = v;
            if ((ad >> 8) == "HATA") G_hata[ll] = v;
            if ((ad >> 8) == "GRAD") G_grad[ll] = v;
        end
        $fclose(fd);
        dosya_ac(alt, "komutlar_dizi.txt");
        void'($fscanf(fd, "%d", n));
        if (n > KMAX) $fatal(1, "komut sayısı %0d > KMAX %0d", n, KMAX);
        for (i = 0; i < n; i = i + 1)
            for (q = 0; q < 10; q = q + 1) void'($fscanf(fd, "%d", kmt[i][q]));
        $fclose(fd);
        n_ag = n_ag + 1;
        @(negedge clk); basla = 1'b1; @(negedge clk); basla = 1'b0;
        for (i = 0; i < n; i = i + 1) begin
            bekle = 0;
            while (!kom_gecerli && bekle < 100) begin @(negedge clk); bekle = bekle + 1; end
            if (!kom_gecerli) begin
                hata = hata + 1; $display("HATA: komut %0d gelmedi", i); return;
            end
            for (q = 0; q < 10; q = q + 1) begin
                kontrol = kontrol + 1;
                if ($signed(kom[AW*q +: AW]) != kmt[i][q]) begin
                    hata = hata + 1;
                    if (hata <= 12) $display("HATA %0s komut %0d alan %0d: %0d, beklenen %0d", alt, i, q,
                                             $signed(kom[AW*q +: AW]), kmt[i][q]);
                end
            end
            n_kom = n_kom + 1;
            if (kmt[i][0] == 2) begin
                ll = kmt[i][2];
                maks_G = (kmt[i][1] == 0) ? G_akt[ll] : (kmt[i][1] == 1) ? G_hata[ll - 1] : G_grad[ll];
            end
            repeat ((i % 3) + 1) @(negedge clk);
            kom_bitti = 1'b1; @(negedge clk); kom_bitti = 1'b0;
        end
        repeat (3) @(negedge clk);
        kontrol = kontrol + 2;
        if (!bitti) begin hata = hata + 1; $display("HATA %0s: bitti 1 degil", alt); end
        if (kom_gecerli) begin hata = hata + 1; $display("HATA %0s: BITTI'den sonra komut", alt); end
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
        ag_kos("ag6/");
        if (hata == 0) $display("SONUC tb_fsm_dizi: PASS %0d/%0d (%0d ag, %0d komut)", kontrol, kontrol, n_ag, n_kom);
        else           $display("SONUC tb_fsm_dizi: FAIL %0d hata / %0d", hata, kontrol);
        sfd = $fopen({dizin, "sonuc_tb_fsm_dizi.txt"}, "w");
        if (sfd != 0) begin
            if (hata == 0) $fdisplay(sfd, "SONUC tb_fsm_dizi: PASS %0d/%0d", kontrol, kontrol);
            else           $fdisplay(sfd, "SONUC tb_fsm_dizi: FAIL %0d hata / %0d", hata, kontrol);
            $fclose(sfd);
        end
        $finish;
    end

endmodule
