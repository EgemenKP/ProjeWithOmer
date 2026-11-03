// =============================================================================
//  tb_wu.sv — wu_unit testbench
// -----------------------------------------------------------------------------
//  wu_cikarma.hex'in 65536 satırının (tüm int8 (w, g8) çiftleri) hepsini 16 şeritte dener.
//  Şerit i, dosyanın i. bölümünü okur: satır i*4096 + ((j + 17*i) mod 4096). Dosyada art arda
//  256 satırın ilk alanı aynı, ikinci alanı 256'lık döngüde; 17*i kaydırması sayesinde
//  aynı adımda her şerit hem farklı ilk alan hem farklı ikinci alan görür. Her satır yine
//  tam bir kez okunur.
//  Satır biçimi (24 bit): [23:16] w  [15:8] g8  [7:0] doyur(w - g8, ±127)
//
//  Vektör klasörü: +VEKTOR_DIZINI=<klasör/> argümanıyla verilir (sonunda / olmalı).
//  Verilmezse ya da o klasörde dosya yoksa, dosya çalışma klasöründe aranır.
//  Sonuç satırı konsola ve <vektör klasörü>/sonuc_tb_wu.txt dosyasına yazılır:
//  "SONUC tb_wu: PASS ..." ya da "SONUC tb_wu: FAIL ..."
// =============================================================================
`timescale 1ns/1ps

module tb_wu;

    localparam N     = 16;
    localparam SATIR = 65536;
    localparam ADIM  = SATIR / N;   // şerit başına satır sayısı (4096)

    reg  [23:0]    mem [0:SATIR-1];
    reg  [N*8-1:0] w_flat;
    reg  [N*8-1:0] g_flat;
    wire [N*8-1:0] w_yeni_flat;

    wu_unit #(.N(N)) dut (
        .w_flat      (w_flat),
        .g_flat      (g_flat),
        .w_yeni_flat (w_yeni_flat)
    );

    string     dizin;
    string     dosya;
    integer    fd;
    integer    k, i, j, s;
    integer    hata;
    integer    kontrol;
    reg [23:0] v;
    reg [7:0]  gelen;

    // Sonuç satırını konsola ve vektör klasöründeki sonuc_<tb>.txt dosyasına yazar
    // (Vivado script'i özeti bu dosyadan okur).
    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            fd = $fopen({dizin, "sonuc_tb_wu.txt"}, "w");
            if (fd != 0) begin
                $fdisplay(fd, "%s", satir);
                $fclose(fd);
            end
        end
    endtask

    initial begin
        hata    = 0;
        kontrol = 0;
        w_flat  = '0;
        g_flat  = '0;

        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin))
            dizin = "";
        // Yedek: verilen klasörde dosya yoksa (ör. yolda boşluk varsa plusarg bozulur)
        // çalışma klasörüne bak; Vivado script'i dosyaları oraya da kopyalıyor.
        fd = $fopen({dizin, "wu_cikarma.hex"}, "r");
        if (fd == 0)
            dizin = "";
        else
            $fclose(fd);
        dosya = {dizin, "wu_cikarma.hex"};

        for (k = 0; k < SATIR; k = k + 1)
            mem[k] = 24'hxxxxxx;
        $readmemh(dosya, mem);
        if ((^mem[0] === 1'bx) || (^mem[SATIR-1] === 1'bx)) begin
            sonuc_yaz($sformatf("SONUC tb_wu: DOSYA OKUNAMADI (%s)", dosya));
            $finish;
        end

        for (j = 0; j < ADIM; j = j + 1) begin
            // Şeritleri doldur: şerit i <- satır i*ADIM + ((j + 17*i) % ADIM)
            for (i = 0; i < N; i = i + 1) begin
                v = mem[i*ADIM + ((j + 17*i) % ADIM)];
                w_flat[8*i +: 8] = v[23:16];
                g_flat[8*i +: 8] = v[15:8];
            end
            #1;
            for (i = 0; i < N; i = i + 1) begin
                s = i*ADIM + ((j + 17*i) % ADIM);
                v = mem[s];
                gelen = w_yeni_flat[8*i +: 8];
                kontrol = kontrol + 1;
                if (gelen !== v[7:0]) begin
                    hata = hata + 1;
                    if (hata <= 10)
                        $display("HATA satir=%0d w=%0d g=%0d beklenen=%0d gelen=%0d",
                                 s, $signed(v[23:16]), $signed(v[15:8]),
                                 $signed(v[7:0]), $signed(gelen));
                end
            end
        end

        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_wu: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_wu: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
