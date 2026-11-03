`timescale 1ns/1ps
module tb_pe_bp_s2;

    localparam MAX_T = 32;
    localparam MAX_OFF = 8;
    localparam VFILE = "pe_vectors/pe_bp_s2.txt";

    reg clk = 0; always #5 clk = ~clk;

    reg signed [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
    reg signed [31:0] e0,e1,e2,psA0,psB0,psA1,psB1;
    wire signed [31:0] out0,out1,out2,out3;

    pe_bp_s2 dut (.clk(clk), .w00(w00),.w01(w01),.w02(w02),
                  .w10(w10),.w11(w11),.w12(w12),.w20(w20),.w21(w21),.w22(w22),
                  .e_row0(e0[7:0]), .e_row1(e1[7:0]), .e_row2(e2[7:0]),
                  .psA0(psA0), .psB0(psB0), .psA1(psA1), .psB1(psB1),
                  .out0(out0), .out1(out1), .out2(out2), .out3(out3));

    integer fd, r, mod_code, n_cases, case_no, n_pass, n_chan;
    integer pass_no, T, n_out, n_in, n_outc, pid;
    integer i, t, off, ok, found_off;
    integer row_e0[0:MAX_T-1], row_e1[0:MAX_T-1], row_e2[0:MAX_T-1];
    integer row_pA0[0:MAX_T-1], row_pB0[0:MAX_T-1], row_pA1[0:MAX_T-1], row_pB1[0:MAX_T-1];
    integer exp_t[0:MAX_T-1];
    integer exp_v0[0:MAX_T-1], exp_v1[0:MAX_T-1], exp_v2[0:MAX_T-1], exp_v3[0:MAX_T-1];
    integer cap0[0:MAX_T+MAX_OFF-1], cap1[0:MAX_T+MAX_OFF-1], cap2[0:MAX_T+MAX_OFF-1], cap3[0:MAX_T+MAX_OFF-1];
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
                                row_e0[t],row_e1[t],row_e2[t],row_pA0[t],row_pB0[t],row_pA1[t],row_pB1[t]);
                for (t = 0; t < n_out; t = t + 1)
                    r = $fscanf(fd, "%d %d %d %d %d", exp_t[t], exp_v0[t], exp_v1[t], exp_v2[t], exp_v3[t]);

                for (t = 0; t < T + MAX_OFF; t = t + 1) begin
                    @(negedge clk);
                    if (t < T) begin
                        e0=row_e0[t]; e1=row_e1[t]; e2=row_e2[t];
                        psA0=row_pA0[t]; psB0=row_pB0[t]; psA1=row_pA1[t]; psB1=row_pB1[t];
                    end else begin
                        e0=0;e1=0;e2=0;psA0=0;psB0=0;psA1=0;psB1=0;
                    end
                    @(posedge clk); #1;
                    cap0[t]=out0; cap1[t]=out1; cap2[t]=out2; cap3[t]=out3;
                end

                found_off = -1;
                for (off = 0; off < MAX_OFF && found_off == -1; off = off+1) begin
                    ok = 1;
                    for (t = 0; t < n_out; t = t+1) begin
                        if (cap0[exp_t[t]-1+off] !== exp_v0[t]) ok = 0;
                        if (cap1[exp_t[t]-1+off] !== exp_v1[t]) ok = 0;
                        if (cap2[exp_t[t]-1+off] !== exp_v2[t]) ok = 0;
                        if (cap3[exp_t[t]-1+off] !== exp_v3[t]) ok = 0;
                    end
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
