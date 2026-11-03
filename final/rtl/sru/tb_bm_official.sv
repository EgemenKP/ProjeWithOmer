`timescale 1ns/1ps
module tb_bm_official;
    localparam VFILE = "sru_bm.txt";
    reg [31:0] m; wire [5:0] b;
    bit_length32 dut(.m(m), .b(b));
    integer fd, r, N, i, exp_b;
    integer total, ok, fail;
    initial begin
        fd = $fopen(VFILE,"r");
        if (fd==0) begin $display("HATA"); $finish; end
        r = $fscanf(fd, "%d", N);
        total=0; ok=0; fail=0;
        for (i=0;i<N;i=i+1) begin
            r = $fscanf(fd, "%d %d", m, exp_b);
            #1;
            total=total+1;
            if (b !== exp_b[5:0]) begin
                fail=fail+1;
                if (fail<=20) $display("FAIL m=%0d beklenen=%0d alinan=%0d", m, exp_b, b);
            end else ok=ok+1;
        end
        $fclose(fd);
        $display("TOPLAM=%0d DOGRU=%0d HATALI=%0d", total, ok, fail);
        $finish;
    end
endmodule
