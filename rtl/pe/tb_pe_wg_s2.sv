`timescale 1ns/1ps
module tb_pe_wg_s2;

    localparam MAX_T = 32;
    localparam VFILE = "pe_vectors/pe_wg_s2.txt";

    reg clk = 0; always #5 clk = ~clk;
    reg rst;

    reg signed [31:0] c0=0,t0=0,e0v=0,c1=0,t1=0,e1v=0,c2=0,t2=0,e2v=0;
    wire signed [31:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;

    pe_wg_s2 dut (.clk(clk), .rst(rst),
                  .cift_r0(c0[7:0]), .tek_r0(t0[7:0]), .e_row0(e0v[7:0]),
                  .cift_r1(c1[7:0]), .tek_r1(t1[7:0]), .e_row1(e1v[7:0]),
                  .cift_r2(c2[7:0]), .tek_r2(t2[7:0]), .e_row2(e2v[7:0]),
                  .g00(g00),.g01(g01),.g02(g02),
                  .g10(g10),.g11(g11),.g12(g12),
                  .g20(g20),.g21(g21),.g22(g22));

    integer fd, r, mod_code, n_cases, case_no, n_pass, n_chan;
    integer pass_no, T, n_out, n_in, n_outc, pid;
    integer i, t;
    integer junk[0:8];
    integer row_c0[0:MAX_T-1], row_t0[0:MAX_T-1], row_e0[0:MAX_T-1];
    integer row_c1[0:MAX_T-1], row_t1[0:MAX_T-1], row_e1[0:MAX_T-1];
    integer row_c2[0:MAX_T-1], row_t2[0:MAX_T-1], row_e2[0:MAX_T-1];
    integer exp_g[0:8];
    integer total_case, case_ok, case_fail, ok;

    initial begin
        fd = $fopen(VFILE, "r");
        if (fd == 0) begin $display("HATA: %s acilamadi", VFILE); $finish; end

        r = $fscanf(fd, "%d %d", mod_code, n_cases);
        total_case = 0; case_ok = 0; case_fail = 0;
        rst = 0;

        for (i = 0; i < n_cases; i = i + 1) begin
            r = $fscanf(fd, "%d %d %d", case_no, n_pass, n_chan);

            @(negedge clk); rst = 1;
            @(negedge clk); rst = 0;

            for (pass_no = 0; pass_no < n_pass; pass_no = pass_no + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d", pid, T, n_out, n_in, n_outc);
                r = $fscanf(fd, "%d %d %d %d %d %d %d %d %d",
                            junk[0],junk[1],junk[2],junk[3],junk[4],junk[5],junk[6],junk[7],junk[8]);
                for (t = 0; t < T; t = t + 1)
                    r = $fscanf(fd, "%d %d %d %d %d %d %d %d %d",
                                row_c0[t],row_t0[t],row_e0[t],
                                row_c1[t],row_t1[t],row_e1[t],
                                row_c2[t],row_t2[t],row_e2[t]);

                for (t = 0; t < T; t = t + 1) begin
                    @(negedge clk);
                    c0=row_c0[t]; t0=row_t0[t]; e0v=row_e0[t];
                    c1=row_c1[t]; t1=row_t1[t]; e1v=row_e1[t];
                    c2=row_c2[t]; t2=row_t2[t]; e2v=row_e2[t];
                    @(posedge clk); #1;
                end
            end

            for (t = 0; t < 9; t = t + 1) r = $fscanf(fd, "%d", exp_g[t]);

            ok = 1;
            if (g00 !== exp_g[0]) ok=0; if (g01 !== exp_g[1]) ok=0; if (g02 !== exp_g[2]) ok=0;
            if (g10 !== exp_g[3]) ok=0; if (g11 !== exp_g[4]) ok=0; if (g12 !== exp_g[5]) ok=0;
            if (g20 !== exp_g[6]) ok=0; if (g21 !== exp_g[7]) ok=0; if (g22 !== exp_g[8]) ok=0;

            total_case = total_case + 1;
            if (ok) case_ok = case_ok + 1;
            else begin
                case_fail = case_fail + 1;
                $display("FAIL case=%0d  beklenen: %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                         case_no, exp_g[0],exp_g[1],exp_g[2],exp_g[3],exp_g[4],exp_g[5],exp_g[6],exp_g[7],exp_g[8]);
                $display("         dut     : %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                         g00,g01,g02,g10,g11,g12,g20,g21,g22);
            end
        end
        $fclose(fd);
        $display("[%s] TOPLAM CASE=%0d, DOGRU=%0d, HATALI=%0d", VFILE, total_case, case_ok, case_fail);
        $finish;
    end
endmodule
