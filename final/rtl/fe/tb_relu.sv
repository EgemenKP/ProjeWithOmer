// =============================================================================
//  tb_relu.sv — relu_unit testbench
// -----------------------------------------------------------------------------
//  relu.hex'in 65536 satırının (tüm int8 (a, e) çiftleri) hepsini 16 şeritte dener.
//  Şerit i, dosyanın i. bölümünü okur: satır i*4096 + ((j + 17*i) mod 4096). Dosyada art arda
//  256 satırın ilk alanı aynı, ikinci alanı 256'lık döngüde; 17*i kaydırması sayesinde
//  aynı adımda her şerit hem farklı ilk alan hem farklı ikinci alan görür. Her satır yine
//  tam bir kez okunur.
//  Her satır üç kez kontrol edilir:
//    1) ileri (geri = 0)                       : y == relu(a)
//    2) geri, maske kaynağı ReLU girişi a      : y == e_geri
//    3) geri, maske kaynağı ReLU çıkışı relu(a): y == e_geri
//  Satır biçimi (32 bit): [31:24] a  [23:16] e  [15:8] relu(a)  [7:0] e_geri
//
//  Vektör klasörü: +VEKTOR_DIZINI=<klasör/> argümanıyla verilir (sonunda / olmalı).
//  Verilmezse ya da o klasörde dosya yoksa, dosya çalışma klasöründe aranır.
//  Sonuç satırı konsola ve <vektör klasörü>/sonuc_tb_relu.txt dosyasına yazılır:
//  "SONUC tb_relu: PASS ..." ya da "SONUC tb_relu: FAIL ..."
// =============================================================================
`timescale 1ns/1ps

module tb_relu;

    localparam N     = 16;          // şerit sayısı (DUT ile aynı)
    localparam SATIR = 65536;       // vektör satırı sayısı
    localparam ADIM  = SATIR / N;   // şerit başına satır sayısı (4096)

    reg  [31:0]    mem [0:SATIR-1];
    reg            geri;
    reg  [N*8-1:0] a_flat;
    reg  [N*8-1:0] e_flat;
    wire [N*8-1:0] y_flat;

    relu_unit #(.N(N)) dut (
        .geri   (geri),
        .a_flat (a_flat),
        .e_flat (e_flat),
        .y_flat (y_flat)
    );

    string     dizin;
    string     dosya;
    integer    fd;
    integer    k, i, j, s;
    integer    hata;
    integer    kontrol;
    reg [31:0] v;

    // Tek karşılaştırma; ilk 10 hatayı ayrıntılı yazar
    task kontrol_et(input string ad, input integer satir,
                    input [7:0] a, input [7:0] e, input [7:0] bek, input [7:0] gel);
        begin
            kontrol = kontrol + 1;
            if (gel !== bek) begin
                hata = hata + 1;
                if (hata <= 10)
                    $display("HATA %s satir=%0d a=%0d e=%0d beklenen=%0d gelen=%0d",
                             ad, satir, $signed(a), $signed(e), $signed(bek), $signed(gel));
            end
        end
    endtask

    // Sonuç satırını konsola ve vektör klasöründeki sonuc_<tb>.txt dosyasına yazar
    // (Vivado script'i özeti bu dosyadan okur).
    task sonuc_yaz(input string satir);
        begin
            $display("%s", satir);
            fd = $fopen({dizin, "sonuc_tb_relu.txt"}, "w");
            if (fd != 0) begin
                $fdisplay(fd, "%s", satir);
                $fclose(fd);
            end
        end
    endtask

    initial begin
        hata    = 0;
        kontrol = 0;
        geri    = 1'b0;
        a_flat  = '0;
        e_flat  = '0;

        if (!$value$plusargs("VEKTOR_DIZINI=%s", dizin))
            dizin = "";
        // Yedek: verilen klasörde dosya yoksa (ör. yolda boşluk varsa plusarg bozulur)
        // çalışma klasörüne bak; Vivado script'i dosyaları oraya da kopyalıyor.
        fd = $fopen({dizin, "relu.hex"}, "r");
        if (fd == 0)
            dizin = "";
        else
            $fclose(fd);
        dosya = {dizin, "relu.hex"};

        for (k = 0; k < SATIR; k = k + 1)
            mem[k] = 32'hxxxxxxxx;
        $readmemh(dosya, mem);
        if ((^mem[0] === 1'bx) || (^mem[SATIR-1] === 1'bx)) begin
            sonuc_yaz($sformatf("SONUC tb_relu: DOSYA OKUNAMADI (%s)", dosya));
            $finish;
        end

        for (j = 0; j < ADIM; j = j + 1) begin
            // Şeritleri doldur: şerit i <- satır i*ADIM + ((j + 17*i) % ADIM)
            for (i = 0; i < N; i = i + 1) begin
                v = mem[i*ADIM + ((j + 17*i) % ADIM)];
                a_flat[8*i +: 8] = v[31:24];
                e_flat[8*i +: 8] = v[23:16];
            end

            // 1) ileri
            geri = 1'b0;
            #1;
            for (i = 0; i < N; i = i + 1) begin
                s = i*ADIM + ((j + 17*i) % ADIM);
                v = mem[s];
                kontrol_et("ileri", s, v[31:24], v[23:16], v[15:8], y_flat[8*i +: 8]);
            end

            // 2) geri, maske kaynağı a
            geri = 1'b1;
            #1;
            for (i = 0; i < N; i = i + 1) begin
                s = i*ADIM + ((j + 17*i) % ADIM);
                v = mem[s];
                kontrol_et("geri(a)", s, v[31:24], v[23:16], v[7:0], y_flat[8*i +: 8]);
            end

            // 3) geri, maske kaynağı relu(a)
            for (i = 0; i < N; i = i + 1) begin
                v = mem[i*ADIM + ((j + 17*i) % ADIM)];
                a_flat[8*i +: 8] = v[15:8];
            end
            #1;
            for (i = 0; i < N; i = i + 1) begin
                s = i*ADIM + ((j + 17*i) % ADIM);
                v = mem[s];
                kontrol_et("geri(relu)", s, v[15:8], v[23:16], v[7:0], y_flat[8*i +: 8]);
            end
        end

        if (hata == 0)
            sonuc_yaz($sformatf("SONUC tb_relu: PASS %0d/%0d", kontrol, kontrol));
        else
            sonuc_yaz($sformatf("SONUC tb_relu: FAIL %0d hata / %0d kontrol", hata, kontrol));
        $finish;
    end

endmodule
