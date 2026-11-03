// =============================================================================
//  tb_lms_uc.sv — lms_group16'nın B ve l çıkışları, uç değerlerle (D71, araç tuzağı 9)
// -----------------------------------------------------------------------------
//  Referans: B = |grup|'un en büyüğünün bit_length'i (D28), l = max(0, B - hedef) (D27, D61).
//  Elle seçilmiş uç gruplar ([-2^31, 5], [2^31-1], hepsi 0, tek eleman ±1, -2^31 + 2^31-1) ve
//  20.000 rastgele grup (değerlerin bir kısmı -2^31, ±(2^k), ±(2^k - 1)); hedef 1..7.
//  Sonuç: "SONUC tb_lms_uc: PASS k/k" (konsol ve sonuc_tb_lms_uc.txt)
//  Yazan: Claude, 03.11.2026
// =============================================================================
`timescale 1ns/1ps

module tb_lms_uc;

    reg  signed [16*32-1:0] grup = 0;
    reg         [2:0]       hedef = 3'd7;
    wire signed [16*8-1:0]  cikis;
    wire        [15:0]      tasma;
    wire        [5:0]       l_out, B_out;

    lms_group16 dut (.group_in_flat(grup), .hedef(hedef), .group_out_flat(cikis),
                     .tasma_flat(tasma), .l_out(l_out), .B_out(B_out));

    integer hata = 0, kontrol = 0, n, i, k, sfd;
    reg [31:0] rs = 32'h1357_9BDF;
    function [31:0] rnd(input integer bos_arg);
        begin
            rs = rs ^ (rs << 13); rs = rs ^ (rs >> 17); rs = rs ^ (rs << 5);
            rnd = rs;
        end
    endfunction

    function integer bit_len(input longint m);
        integer b;
        begin
            b = 0;
            while (m > 0) begin b = b + 1; m = m >> 1; end
            bit_len = b;
        end
    endfunction

    reg [5:0] B_bek, l_bek;
    task denetle(input string ne);
        longint mx, a;
        begin
            #1;
            mx = 0;
            for (i = 0; i < 16; i = i + 1) begin
                a = $signed(grup[i*32 +: 32]);
                if (a < 0) a = -a;
                if (a > mx) mx = a;
            end
            B_bek = bit_len(mx);
            l_bek = (B_bek > hedef) ? (B_bek - hedef) : 0;
            kontrol = kontrol + 1;
            if (B_out !== B_bek || l_out !== l_bek) begin
                hata = hata + 1;
                if (hata <= 20) $display("FAIL %s: hedef %0d, maks|x| %0d: B %0d (bek %0d), l %0d (bek %0d)",
                                         ne, hedef, mx, B_out, B_bek, l_out, l_bek);
            end
        end
    endtask

    function [31:0] uc_deger(input integer bos_arg);
        reg [31:0] r;
        begin
            r = rnd(0);
            k = r[4:0];
            case (r[7:5])
                3'd0: uc_deger = 32'h8000_0000;                       // -2^31
                3'd1: uc_deger = 32'h7FFF_FFFF;
                3'd2: uc_deger = 32'd1 << k;                         // 2^k
                3'd3: uc_deger = (32'd1 << k) - 32'd1;               // 2^k - 1
                3'd4: uc_deger = -(32'd1 << k);
                default: uc_deger = rnd(0) >> (rnd(0) % 32);         // çeşitli genişlikler
            endcase
            if (r[8] && r[7:5] > 3'd4) uc_deger = -uc_deger;
        end
    endfunction

    initial begin
        // ---- elle seçilmiş uç gruplar ----
        grup = 0; grup[0 +: 32] = 32'h8000_0000; grup[32 +: 32] = 32'd5;  denetle("[-2^31, 5]");
        grup = 0; grup[0 +: 32] = 32'h7FFF_FFFF;                          denetle("[2^31-1]");
        grup = 0;                                                         denetle("hepsi 0");
        grup = 0; grup[15*32 +: 32] = 32'd1;                              denetle("[.., 1]");
        grup = 0; grup[3*32 +: 32] = 32'hFFFF_FFFF;                       denetle("[-1]");
        grup = 0; grup[0 +: 32] = 32'h8000_0000; grup[32 +: 32] = 32'h7FFF_FFFF; denetle("[-2^31, 2^31-1]");
        for (k = 1; k <= 7; k = k + 1) begin
            hedef = k;
            grup = 0; grup[7*32 +: 32] = 32'h8000_0000;                   denetle("[-2^31], hedef");
        end

        // ---- rastgele ----
        for (n = 0; n < 20000; n = n + 1) begin
            hedef = 1 + rnd(0) % 7;
            for (i = 0; i < 16; i = i + 1)
                grup[i*32 +: 32] = (rnd(0) % 3 == 0) ? 32'd0 : uc_deger(0);
            denetle("rastgele");
        end

        if (hata == 0) $display("SONUC tb_lms_uc: PASS %0d/%0d", kontrol, kontrol);
        else           $display("SONUC tb_lms_uc: FAIL %0d hata / %0d kontrol", hata, kontrol);
        sfd = $fopen("sonuc_tb_lms_uc.txt", "w");
        if (sfd != 0) begin
            if (hata == 0) $fdisplay(sfd, "SONUC tb_lms_uc: PASS %0d/%0d", kontrol, kontrol);
            else           $fdisplay(sfd, "SONUC tb_lms_uc: FAIL %0d hata / %0d kontrol", hata, kontrol);
            $fclose(sfd);
        end
        $finish;
    end

endmodule
