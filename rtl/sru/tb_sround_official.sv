`timescale 1ns/1ps
module tb_sround_official;
    localparam VFILE = "sru_yuvarla.txt";
    reg signed [31:0] q32;
    reg [4:0] bp;
    wire signed [7:0] q_out;
    wire tasma;
    stochastic_round dut(.q32(q32), .bp(bp), .q_out(q_out), .tasma(tasma));

    integer fd, r, cfg[0:3], N, i;
    integer exp_q, exp_t;
    integer total, ok, fail;

    initial begin
        fd = $fopen(VFILE,"r");
        if (fd==0) begin $display("HATA: %s acilamadi", VFILE); $finish; end
        r = $fscanf(fd, "%d %d %d %d", cfg[0],cfg[1],cfg[2],cfg[3]);
        $display("ayar kodu: %0d %0d %0d %0d (beklenen: 1 1 0 1)", cfg[0],cfg[1],cfg[2],cfg[3]);
        r = $fscanf(fd, "%d", N);
        total=0; ok=0; fail=0;
        for (i=0;i<N;i=i+1) begin
            r = $fscanf(fd, "%d %d %d %d", q32, bp, exp_q, exp_t);
            #1;
            total = total+1;
            if (q_out !== exp_q[7:0] || tasma !== exp_t[0]) begin
                fail = fail+1;
                if (fail <= 20)
                    $display("FAIL q32=%0d bp=%0d beklenen=(%0d,%0d) alinan=(%0d,%0d)",
                              q32,bp,exp_q,exp_t,q_out,tasma);
            end else ok = ok+1;
        end
        $fclose(fd);
        $display("TOPLAM=%0d DOGRU=%0d HATALI=%0d", total, ok, fail);
        $finish;
    end
endmodule
