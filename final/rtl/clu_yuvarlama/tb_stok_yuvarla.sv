// =============================================================================
//  tb_stok_yuvarla.sv — stok_yuvarla testbench: 10 kanal, her kanal kendi tohumuyla
// -----------------------------------------------------------------------------
//  stok_yuvarla.txt'teki her satır bir CLU işlemi: 10 kanalın hepsine x verilir, y'ler
//  beklenenle karşılaştırılır, sonra 'ilerle' ile LFSR'ler bir kez ilerletilir.
//  Satırlar arasına 0-2 boş çevrim (ilerle = 0) konur: LFSR'in yalnızca 'ilerle' ile
//  ilerlediği de böylece test edilir.
//  Dosyanın 2. satırındaki tohumlar, aşağıdaki TOHUMLAR ile aynı olmalı (kontrol ediliyor).
//
//  Vektör klasörü: +VEKTOR_DIZINI=<klasör/> argümanıyla verilir (sonunda / olmalı).
//  Verilmezse ya da o klasörde dosya yoksa, dosya çalışma klasöründe aranır.
//  Sonuç satırı konsola ve <vektör klasörü>/sonuc_tb_stok_yuvarla.txt dosyasına yazılır:
//  "SONUC tb_stok_yuvarla: PASS ..." ya da "SONUC tb_stok_yuvarla: FAIL ..."
//  Hazırlayan: Claude (Ömer'in isteğiyle), 02.11.2026
// =============================================================================
`timescale 1ns/1ps

module tb_stok_yuvarla;

    localparam N  = 10;            // sınıf kanalı sayısı
    localparam W  = 16;            // giriş genişliği
    localparam TM = 8192;          // en çok satır
    // clu_yuvarlama.py kanal_tohumlari(): kanal i, [16*i +: 16] bitlerinde
    localparam [16*N-1:0] TOHUMLAR = {16'hDD68, 16'hA0EA, 16'h5B00, 16'hE338, 16'h3F3B,
                                      16'h0A65, 16'hF205, 16'h490B, 16'h166E, 16'hACE1};

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg            rst;
    reg            ilerle;
    reg  [N*W-1:0] x_flat;
    wire [N*8-1:0] y_flat;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : kanal
            stok_yuvarla #(.W(W), .TOHUM(TOHUMLAR[16*g +: 16])) dut (
                .clk(clk), .rst(rst), .ilerle(ilerle),
                .x(x_flat[W*g +: W]), .y(y_flat[8*g +: 8]));
        end
    endgenerate

    integer vx  [0:TM*N-1];
    integer vy  [0:TM*N-1];
    integer n_dosya, T, k_dosya, tohum;
    integer fd, r, t, i, hata, kontrol, gelen;
    string  dizin;

    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            fd = $fopen({dizin, "sonuc_tb_stok_yuvarla.txt"}, "w");
            if (fd != 0) begin
                $fdisplay(fd, "%s", satir);
                $fclose(fd);
            end
        end
    endtask

    initial begin
        hata = 0; kontrol = 0;
        rst = 1'b1; ilerle = 1'b0; x_flat = '0;

        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin))
            dizin = "";
        fd = $fopen({dizin, "stok_yuvarla.txt"}, "r");
        if (fd == 0) begin
            dizin = "";                 // yedek: çalışma klasörü
            fd = $fopen("stok_yuvarla.txt", "r");
        end
        if (fd == 0) begin
            sonuc_yaz({"SONUC tb_stok_yuvarla: DOSYA OKUNAMADI (", dizin, "stok_yuvarla.txt)"});
            $finish;
        end
        r = $fscanf(fd, "%d %d %d", n_dosya, T, k_dosya);
        if (r != 3 || n_dosya != N || k_dosya != 4 || T < 1 || T > TM) begin
            sonuc_yaz("SONUC tb_stok_yuvarla: DOSYA BICIMI BEKLENENDEN FARKLI");
            $finish;
        end
        for (i = 0; i < N; i = i + 1) begin
            r = $fscanf(fd, "%d", tohum);
            if (tohum != TOHUMLAR[16*i +: 16]) begin
                sonuc_yaz($sformatf("SONUC tb_stok_yuvarla: FAIL tohum uyusmuyor (kanal %0d: dosya %0d, tb %0d)",
                                    i, tohum, TOHUMLAR[16*i +: 16]));
                $finish;
            end
        end
        for (i = 0; i < T * N; i = i + 1)
            r = $fscanf(fd, "%d %d", vx[i], vy[i]);
        $fclose(fd);
        if (r != 2) begin
            sonuc_yaz("SONUC tb_stok_yuvarla: DOSYA EKSIK");
            $finish;
        end

        repeat (3) @(posedge clk);
        #1 rst = 1'b0;

        for (t = 0; t < T; t = t + 1) begin
            for (i = 0; i < N; i = i + 1)
                x_flat[W*i +: W] = vx[t*N + i];
            #1;
            for (i = 0; i < N; i = i + 1) begin
                kontrol = kontrol + 1;
                gelen = $signed(y_flat[8*i +: 8]);
                if (gelen != vy[t*N + i]) begin
                    hata = hata + 1;
                    if (hata <= 10)
                        $display("HATA satir=%0d kanal=%0d x=%0d beklenen=%0d gelen=%0d",
                                 t, i, vx[t*N + i], vy[t*N + i], gelen);
                end
            end
            ilerle = 1'b1;
            @(posedge clk);
            #1 ilerle = 1'b0;
            repeat (t % 3) @(posedge clk);       // boş çevrimler: LFSR ilerlememeli
            #1;
        end

        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_stok_yuvarla: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_stok_yuvarla: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
