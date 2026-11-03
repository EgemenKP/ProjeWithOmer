// ============================================================================
// tb_clu.sv — Shao CLU (Cross-Entropy Loss Unit) testbench
//
// vectors.txt'i okur (golden_model.py tarafindan uretildi), her satiri DUT'a
// uygular, DUT ciktisini golden model'in beklediği değerle karsilastirir.
//
// DUT arayuzu (kararlastirilan, bkz. proje hafizasi):
//   N = 10 (CIFAR-10, sabit)
//   a0..a9 : signed int8 aktivasyonlar
//   sa     : signed int8 ortak olcek ussu
//   y_onehot[9:0] : dogru sinif (one-hot)
//   e0..e9 : signed int8 cikis (hata/gradyan)
// ============================================================================
`timescale 1ns/1ps

module tb_clu;

    localparam N = 10;
    localparam VFILE = "vectors.txt";

    // Divider Generator IP'nin (div_gen_0Z, 5.1) sabit latency'si: 66
    // clock. ARTIK TEK PAYLASIMLI divider N=10 kanali sirayla (round-robin)
    // besliyor (lisans sinirina takilan N-paralel-divider tasarimi yerine --
    // bkz. clu_top.v) -- bu yuzden bekleme suresi: kanallari beslemek icin
    // N cevrim + divider'in 66 cevrimlik gecikmesi + guvenlik payi.
    localparam DIV_LATENCY = 66;
    localparam N_CHAN      = 10;
    localparam WAIT_CYCLES = N_CHAN + DIV_LATENCY + 10;   // guvenlik payi

    // Saat uretimi (10ns periyot -- fonksiyonel dogrulama icin, gercek
    // 200MHz hedefiyle birebir ayni olmasi gerekmiyor)
    reg clk = 1'b0;
    always #5 clk = ~clk;

    // DUT portlariyla birebir eslesen sinyaller
    reg  signed [7:0] a0, a1, a2, a3, a4, a5, a6, a7, a8, a9;
    reg  signed [7:0] sa;
    reg  [N-1:0]      y_onehot;
    wire signed [7:0] e0, e1, e2, e3, e4, e5, e6, e7, e8, e9;
    wire               dut_valid;

    // Karsilastirma icin beklenen degerler
    integer exp_e [0:N-1];
    integer a_arr [0:N-1];
    integer y_idx;
    integer sa_int;

    integer fd, r, i;
    integer test_no;
    integer pass_count, fail_count;
    reg signed [7:0] dut_e [0:N-1];

    // -------------------------------------------------------------------
    // DUT ornegi -- clu_top.v, GERCEK Divider Generator IP'sine (66 clock
    // latency) baglanmis yapisal tasarim. clk eklendi, valid cikisi
    // gozlemleniyor (bilgi amacli, karsilastirma hala sabit bekleme ile).
    // -------------------------------------------------------------------
    clu_top #(.N(N)) dut (
        .clk(clk),
        .a0(a0), .a1(a1), .a2(a2), .a3(a3), .a4(a4),
        .a5(a5), .a6(a6), .a7(a7), .a8(a8), .a9(a9),
        .sa(sa),
        .y_onehot(y_onehot),
        .e0(e0), .e1(e1), .e2(e2), .e3(e3), .e4(e4),
        .e5(e5), .e6(e6), .e7(e7), .e8(e8), .e9(e9),
        .valid(dut_valid)
    );

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_no = 0;

        fd = $fopen(VFILE, "r");
        if (fd == 0) begin
            $display("HATA: %s acilamadi", VFILE);
            $finish;
        end

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                        a_arr[0], a_arr[1], a_arr[2], a_arr[3], a_arr[4],
                        a_arr[5], a_arr[6], a_arr[7], a_arr[8], a_arr[9],
                        sa_int, y_idx,
                        exp_e[0], exp_e[1], exp_e[2], exp_e[3], exp_e[4],
                        exp_e[5], exp_e[6], exp_e[7], exp_e[8], exp_e[9]);

            if (r == 22) begin
                test_no = test_no + 1;

                // girisleri bir saat kenarinda uygula (yaris/race onlemek icin negedge'de)
                @(negedge clk);
                a0 = a_arr[0]; a1 = a_arr[1]; a2 = a_arr[2]; a3 = a_arr[3]; a4 = a_arr[4];
                a5 = a_arr[5]; a6 = a_arr[6]; a7 = a_arr[7]; a8 = a_arr[8]; a9 = a_arr[9];
                sa = sa_int;
                y_onehot = (1 << y_idx);

                // Divider IP'sinin sabit gecikmesi kadar (+ pay) saat
                // darbesi bekle -- girisler bu sure boyunca sabit
                // kaldigi icin pipeline'in ucundaki sonuc artik dogru
                repeat (WAIT_CYCLES) @(posedge clk);

                dut_e[0]=e0; dut_e[1]=e1; dut_e[2]=e2; dut_e[3]=e3; dut_e[4]=e4;
                dut_e[5]=e5; dut_e[6]=e6; dut_e[7]=e7; dut_e[8]=e8; dut_e[9]=e9;

                begin : check
                    integer ok;
                    ok = 1;
                    for (i = 0; i < N; i = i + 1) begin
                        if (dut_e[i] !== exp_e[i]) ok = 0;
                    end

                    if (ok) begin
                        pass_count = pass_count + 1;
                    end else begin
                        fail_count = fail_count + 1;
                        $display("FAIL test #%0d  (sa=%0d, y_idx=%0d)", test_no, sa_int, y_idx);
                        $write("  beklenen: ");
                        for (i = 0; i < N; i = i + 1) $write("%0d ", exp_e[i]);
                        $write("\n  dut     : ");
                        for (i = 0; i < N; i = i + 1) $write("%0d ", dut_e[i]);
                        $write("\n");
                    end
                end
            end
        end

        $fclose(fd);
        $display("----------------------------------------");
        $display("TOPLAM: %0d test, %0d GECTI, %0d BASARISIZ", test_no, pass_count, fail_count);
        if (fail_count == 0)
            $display("SONUC: TUM TESTLER GECTI");
        else
            $display("SONUC: BASARISIZ TESTLER VAR");
        $finish;
    end

endmodule
