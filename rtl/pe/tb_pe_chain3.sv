// ============================================================================
// tb_pe_chain3.sv -- pe_chain3.v'yi Omer Faruk'un uretttigi vektor
//   dosyalariyla (pe_fp_s1.txt / pe_bp_s1.txt -- ikisi de ayni format)
//   dogrular. Dosya adi VFILE parametresiyle veriliyor.
//
// Format (README_PE_GOLDEN.md Bolum 4):
//   MOD CASE_SAYISI
//   her case: CASE_NO GECIS_SAYISI KANAL_SAYISI
//   her gecis: GECIS_NO T N_CIKTI N_GIRIS N_CIKIS
//              9 agirlik
//              T satir, her biri N_GIRIS(=4) sayi: x_r0 x_r1 x_r2 psum
//              N_CIKTI satir, her biri: FIGUR_CEVRIMI + deger
// ============================================================================
`timescale 1ns/1ps

module tb_pe_chain3 #(parameter VFILE = "pe_vectors/pe_fp_s1.txt");

    localparam MAX_T = 32;
    localparam MAX_OFF = 8;

    reg clk = 0; always #5 clk = ~clk;

    reg signed [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
    reg signed [31:0] x0,x1,x2,ps;
    wire signed [31:0] psum_out;

    pe_chain3 dut (.clk(clk), .w00(w00),.w01(w01),.w02(w02),
                   .w10(w10),.w11(w11),.w12(w12),.w20(w20),.w21(w21),.w22(w22),
                   .x_row0(x0[7:0]), .x_row1(x1[7:0]), .x_row2(x2[7:0]),
                   .ps_in(ps), .psum_out(psum_out));

    integer fd, r, mod_code, n_cases, case_no, n_pass, n_chan;
    integer pass_no, T, n_out, n_in, n_outc;
    integer i, t, off, ok, found_off;
    integer row_x0[0:MAX_T-1], row_x1[0:MAX_T-1], row_x2[0:MAX_T-1], row_ps[0:MAX_T-1];
    integer exp_t[0:MAX_T-1], exp_v[0:MAX_T-1];
    integer cap[0:MAX_T+MAX_OFF-1];
    integer total_pass, pass_ok, pass_fail;
    integer pid;

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
                    r = $fscanf(fd, "%d %d %d %d", row_x0[t], row_x1[t], row_x2[t], row_ps[t]);
                for (t = 0; t < n_out; t = t + 1)
                    r = $fscanf(fd, "%d %d", exp_t[t], exp_v[t]);

                // bu gecisi sur, her cevrimden sonra psum_out'u yakala
                for (t = 0; t < T + MAX_OFF; t = t + 1) begin
                    @(negedge clk);
                    if (t < T) begin
                        x0 = row_x0[t]; x1 = row_x1[t]; x2 = row_x2[t]; ps = row_ps[t];
                    end else begin
                        x0 = 0; x1 = 0; x2 = 0; ps = 0;
                    end
                    @(posedge clk); #1;
                    cap[t] = psum_out;
                end

                // exp_t[k] figur cevrimi -- kaydedilen diziden ayni indeksten
                // (figur cevrimiyle birebir) once dene, olmazsa kayma ara
                found_off = -1;
                for (off = 0; off < MAX_OFF && found_off == -1; off = off + 1) begin
                    ok = 1;
                    for (t = 0; t < n_out; t = t + 1) begin
                        if (cap[exp_t[t] - 2 + off] !== exp_v[t]) ok = 0;
                    end
                    if (ok) found_off = off;
                end

                total_pass = total_pass + 1;
                if (found_off != -1) begin
                    pass_ok = pass_ok + 1;
                end else begin
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
