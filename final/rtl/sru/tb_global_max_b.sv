// final/ (03.11.2026, D70): birlesik SRU'nun hedef girisi 7'ye baglandi (a/e yolu); baska degisiklik yok.
`timescale 1ns/1ps
module tb_global_max_b;

    localparam VFILE = "sru_katman.txt";

    reg clk = 0; always #5 clk = ~clk;
    reg rst, push;
    reg [5:0] B_yerel;
    wire [5:0] B_max, G;

    global_max_b dut (.clk(clk), .rst(rst), .push(push), .B_yerel(B_yerel), .hedef(3'd7),
                       .B_max(B_max), .G(G));

    integer fd, r, cfg[0:3];
    integer n_cases, case_no, n_groups, exp_G, exp_Bglobal;
    integer grp_no, n, exp_M, exp_B, exp_l, exp_delta;
    integer dummy1, dummy2, dummy3, dummy4;
    integer c, g, j;
    integer total_case, case_ok, case_fail;

    initial begin
        fd = $fopen(VFILE, "r");
        if (fd == 0) begin $display("HATA"); $finish; end
        r = $fscanf(fd, "%d %d %d %d", cfg[0],cfg[1],cfg[2],cfg[3]);
        r = $fscanf(fd, "%d", n_cases);
        total_case=0; case_ok=0; case_fail=0;
        push = 0; B_yerel = 0; rst = 0;

        for (c = 0; c < n_cases; c = c + 1) begin
            r = $fscanf(fd, "%d %d %d %d", case_no, n_groups, exp_G, exp_Bglobal);

            @(negedge clk); rst = 1;
            @(negedge clk); rst = 0;

            for (g = 0; g < n_groups; g = g + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d %d", grp_no, n, exp_M, exp_B, exp_l, exp_delta);
                for (j = 0; j < n; j = j + 1)
                    r = $fscanf(fd, "%d %d %d %d %d", dummy1,dummy2,dummy3,dummy4,dummy4);

                @(negedge clk);
                B_yerel = exp_B[5:0]; push = 1;
                @(posedge clk); #1;
                @(negedge clk);
                push = 0;
            end

            total_case = total_case + 1;
            if (B_max !== exp_Bglobal[5:0] || G !== exp_G[5:0]) begin
                case_fail = case_fail + 1;
                $display("FAIL case=%0d B_global: beklenen=%0d alinan=%0d | G: beklenen=%0d alinan=%0d",
                          case_no, exp_Bglobal, B_max, exp_G, G);
            end else case_ok = case_ok + 1;
        end
        $fclose(fd);
        $display("TOPLAM CASE=%0d DOGRU=%0d HATALI=%0d", total_case, case_ok, case_fail);
        if (case_fail==0) $display("SONUC: TUM TESTLER GECTI");
        $finish;
    end
endmodule
