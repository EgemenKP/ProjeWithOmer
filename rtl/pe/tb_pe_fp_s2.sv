`timescale 1ns/1ps
module tb_pe_fp_s2;

    localparam MAX_T = 32;
    localparam MAX_OFF = 8;
    localparam VFILE = "pe_vectors/pe_fp_s2.txt";

    reg clk = 0; always #5 clk = ~clk;

    reg signed [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
    reg signed [31:0] c0,t0,c1,t1,c2,t2,ps;
    wire signed [31:0] psum_out;

    pe_fp_s2 dut (.clk(clk), .w00(w00),.w01(w01),.w02(w02),
                  .w10(w10),.w11(w11),.w12(w12),.w20(w20),.w21(w21),.w22(w22),
                  .cift_r0(c0[7:0]), .tek_r0(t0[7:0]),
                  .cift_r1(c1[7:0]), .tek_r1(t1[7:0]),
                  .cift_r2(c2[7:0]), .tek_r2(t2[7:0]),
                  .ps_in(ps), .psum_out(psum_out));

    integer fd, r, mod_code, n_cases, case_no, n_pass, n_chan;
    integer pass_no, T, n_out, n_in, n_outc, pid;
    integer i, t, off, ok, found_off;
    integer row_c0[0:MAX_T-1], row_t0[0:MAX_T-1], row_c1[0:MAX_T-1], row_t1[0:MAX_T-1];
    integer row_c2[0:MAX_T-1], row_t2[0:MAX_T-1], row_ps[0:MAX_T-1];
    integer exp_t[0:MAX_T-1], exp_v[0:MAX_T-1];
    integer cap[0:MAX_T+MAX_OFF-1];
    integer total_pass, pass_ok, pass_fail;

    initial begin
        fd = $fopen(VFILE, "r");
        if (fd == 0) begin $display("HATA: %s acilamadi", VFILE); $finish; end

        r = $fscanf(fd, "%d %d", mod_code, n_cases);
        total_pass = 0; pass_ok = 0; pass_fail = 0;

        for (i = 0; i < n_cases; i = i + 1) begin
            r = $fscanf(fd, "%d %d %d", case_no, n_pass, n_chan);
            for (pass_no = 0; pass_no < n_pass; pass_no = pass_no + 1) begin
                r = $fscanf(fd, "%d %d %d %d %d", pid, T, n_out, n_in, n_outc);
                r = $fscanf(fd, "%d %d %d %d %d %d %d %d %d",
                            w00,w01,w02,w10,w11,w12,w20,w21,w22);
                for (t = 0; t < T; t = t + 1)
                    r = $fscanf(fd, "%d %d %d %d %d %d %d",
                                row_c0[t],row_t0[t],row_c1[t],row_t1[t],row_c2[t],row_t2[t],row_ps[t]);
                for (t = 0; t < n_out; t = t + 1)
                    r = $fscanf(fd, "%d %d", exp_t[t], exp_v[t]);

                for (t = 0; t < T + MAX_OFF; t = t + 1) begin
                    @(negedge clk);
                    if (t < T) begin
                        c0=row_c0[t]; t0=row_t0[t]; c1=row_c1[t]; t1=row_t1[t];
                        c2=row_c2[t]; t2=row_t2[t]; ps=row_ps[t];
                    end else begin
                        c0=0;t0=0;c1=0;t1=0;c2=0;t2=0;ps=0;
                    end
                    @(posedge clk); #1;
                    cap[t] = psum_out;
                end

                found_off = -1;
                for (off = 0; off < MAX_OFF && found_off == -1; off = off+1) begin
                    ok = 1;
                    for (t = 0; t < n_out; t = t+1)
                        if (cap[exp_t[t]-2+off] !== exp_v[t]) ok = 0;
                    if (ok) found_off = off;
                end

                total_pass = total_pass + 1;
                if (found_off != -1) pass_ok = pass_ok + 1;
                else begin
                    pass_fail = pass_fail + 1;
                    $display("FAIL case=%0d gecis=%0d", case_no, pass_no);
                end
            end
        end
        $fclose(fd);
        $display("[%s] TOPLAM GECIS=%0d, DOGRU=%0d, HATALI=%0d", VFILE, total_pass, pass_ok, pass_fail);
        $finish;
    end
endmodule
