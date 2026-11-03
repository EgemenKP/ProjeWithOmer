// ============================================================================
// clu_top.v -- Cross-Entropy Loss Unit, Fig. 7'nin TAM yapisal gerceklemesi
//
// Alt bloklar: epu.v (N ornegi), teu.v (N ornegi), max_tree.v (x1),
// adder_tree.v (x2 -- sum1 ve sum2 icin), div_stage_ip.v (N ornegi --
// GERCEK Xilinx Divider Generator IP'sine (div_gen_0Z, 5.1) baglaniyor)
//
// ONEMLI: Bolucu IP'si saatli (clocked), 66 clock cycle sabit gecikmeli
// (latency). Bu yuzden bu modul artik saatsiz (combinational) degil --
// clk girisi eklendi, ve cikislarin (e0..e9) GECERLI oldugunu gosteren
// bir "valid" sinyali var (divider'larin tvalid'inden geliyor). EPU,
// TEU, Max Tree, Adder Tree#1, <<11 ve Adder Tree#2 + son kaydirma hala
// combinational -- sadece bolme asamasi pipeline'li.
//
// Genislik kararlari (D1-D8 + testte bulunan TEU-tasma dersi + IP'nin
// zorladigi genislikler):
//   GI_W   = 48  -- hem EPU hem TEU dalinin gi'sini tasiyabilecek ortak genislik
//   NUM_W  = 64  -- gi<<11 sonrasi (bolucunun payi) -- IP'nin Dividend Width'i ile BIREBIR AYNI olmali
//   SUM_W  = 56  -- sum1 (adder_tree #1 ciktisi) -- IP'nin Divisor Width'i ile BIREBIR AYNI olmali
//   QUOT_W = 64  -- IP'nin bolum ciktisi tam dividend genisliginde geliyor (gercek deger kucuk olsa da)
//   SUM2_W = 72  -- sum2 (adder_tree #2 ciktisi)
//
// ai_clip'in HER ZAMAN [0,10] araliginda oldugu ispatlanabilir (offset,
// maksimum elemanin tam 10'a esit olmasini garanti eder) -- bu yuzden
// EPU dalindaki gi degeri hep <=1023, tasma riski sadece TEU'da.
// ============================================================================
`timescale 1ns/1ps

module clu_top #(
    parameter N = 10
) (
    input  wire               clk,
    input  wire signed [7:0] a0, a1, a2, a3, a4, a5, a6, a7, a8, a9,
    input  wire signed [7:0] sa,
    input  wire [N-1:0]      y_onehot,
    output wire signed [7:0] e0, e1, e2, e3, e4, e5, e6, e7, e8, e9,
    output wire               valid
);

    localparam GI_W   = 48;
    localparam NUM_W  = 64;
    localparam SUM_W  = 56;
    localparam QUOT_W = 64;
    localparam SUM2_W = 72;

    // ---- girisleri diziye topla ----
    wire signed [7:0] a_arr [0:N-1];
    assign a_arr[0]=a0; assign a_arr[1]=a1; assign a_arr[2]=a2; assign a_arr[3]=a3;
    assign a_arr[4]=a4; assign a_arr[5]=a5; assign a_arr[6]=a6; assign a_arr[7]=a7;
    assign a_arr[8]=a8; assign a_arr[9]=a9;

    // ---- EPU ve TEU, her kanal icin N ornegi ----
    wire signed [GI_W-1:0] epu_scaled [0:N-1];
    wire signed [GI_W-1:0] teu_gi     [0:N-1];

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : epu_teu_inst
            epu #(.SCALED_W(GI_W)) u_epu (
                .ai(a_arr[g]), .sa(sa), .scaled(epu_scaled[g])
            );
            teu #(.GI_W(GI_W)) u_teu (
                .ai(a_arr[g]), .sa(sa), .gi(teu_gi[g])
            );
        end
    endgenerate

    // ---- epu_scaled dizisini duz veri yoluna (flat bus) paketle ----
    // (max_tree.v artik port olarak dizi degil, flat bus bekliyor --
    // Vivado XSIM dizi-port kabul etmedigi icin)
    wire signed [N*GI_W-1:0] epu_scaled_flat;
    generate
        for (g = 0; g < N; g = g + 1) begin : pack_epu
            assign epu_scaled_flat[g*GI_W +: GI_W] = epu_scaled[g];
        end
    endgenerate

    // ---- Max Tree: EPU ciktilarinin en buyugu ----
    wire signed [GI_W-1:0] a_max;
    max_tree #(.N(N), .W(GI_W)) u_max_tree (
        .data_flat(epu_scaled_flat), .max_val(a_max)
    );

    wire signed [GI_W-1:0] offset = a_max - 10;

    // ---- her kanal: offset cikar, 0'a kirp, 2^x-1, TEU ile mux ----
    wire use_epu = (sa > -7);
    wire signed [GI_W-1:0] ai_clip   [0:N-1];
    wire signed [GI_W-1:0] gi_epu    [0:N-1];
    wire signed [GI_W-1:0] gi        [0:N-1];

    generate
        for (g = 0; g < N; g = g + 1) begin : gi_sel
            wire signed [GI_W-1:0] diff = epu_scaled[g] - offset;
            assign ai_clip[g] = (diff < 0) ? $signed({GI_W{1'b0}}) : diff;
            assign gi_epu[g]  = ($signed({{(GI_W-1){1'b0}}, 1'b1}) <<< ai_clip[g]) - 1; // D1
            assign gi[g]      = use_epu ? gi_epu[g] : teu_gi[g];
        end
    endgenerate

    // ---- gi dizisini flat bus'a paketle ----
    wire signed [N*GI_W-1:0] gi_flat;
    generate
        for (g = 0; g < N; g = g + 1) begin : pack_gi
            assign gi_flat[g*GI_W +: GI_W] = gi[g];
        end
    endgenerate

    // ---- Adder Tree #1: sum1 = sum(gi) ----
    wire signed [SUM_W-1:0] sum1;
    adder_tree #(.N(N), .IN_W(GI_W), .OUT_W(SUM_W)) u_adder1 (
        .data_flat(gi_flat), .sum(sum1)
    );

    // ---- her kanal icin pay (<<11) -- bu kisim ucuz, N kopya sorun degil ----
    wire signed [NUM_W-1:0] numer [0:N-1];
    generate
        for (g = 0; g < N; g = g + 1) begin : numer_calc
            assign numer[g] = {{(NUM_W-GI_W){gi[g][GI_W-1]}}, gi[g]} <<< 11;
        end
    endgenerate

    // =========================================================================
    // BOLME ASAMASI -- TEK paylasimli Divider Generator IP, zaman-paylasimli
    // (round-robin) 10 kanali sirayla besliyor.
    //
    // NEDEN: Vivado BASIC/WebPACK lisansi simulasyonda en fazla 50.000
    // "instance" destekliyor. Gercek IP (64-bit/56-bit, 66 asamali pipeline)
    // tek basina cok buyuk bir yapisal agac -- 10 kopyasi (N paralel divider,
    // Shao'nun Fig.7'sinde cizildigi gibi) bu siniri asiyordu (80.053 > 50.000).
    // Tek paylasimli divider + zaman-paylasimi kullanarak hem lisans sinirinin
    // altinda kaliyoruz HEM DE daha once "mimari zayiflik" olarak not
    // ettigimiz (N paralel divider olceklenmiyor) noktayi cozmus oluyoruz.
    //
    // chan_cnt: 0..N-1 arasinda surekli donen sayac, her cevrim bir sonraki
    // kanalin (numer[chan_cnt]) payini bolucuye besliyor. tag_pipe, hangi
    // kanalin verisi oldugunu, bolucunun 66 cevrimlik gecikmesi kadar
    // kendi icinde tasiyan bir kaydirmali yazmac -- sonuc geldiginde hangi
    // gi2_reg[] elemanina yazilacagini belirliyor.
    // =========================================================================
    localparam DIV_LATENCY = 66;   // IP'nin bildirdigi sabit gecikme (Automatic)
    localparam TAG_W = 4;          // ceil(log2(N))

    reg [TAG_W-1:0] chan_cnt;
    initial chan_cnt = 0;
    always @(posedge clk) chan_cnt <= (chan_cnt == N-1) ? {TAG_W{1'b0}} : chan_cnt + 1'b1;

    reg [TAG_W-1:0] tag_pipe [0:DIV_LATENCY-1];
    integer ti;
    always @(posedge clk) begin
        tag_pipe[0] <= chan_cnt;
        for (ti = 1; ti < DIV_LATENCY; ti = ti + 1)
            tag_pipe[ti] <= tag_pipe[ti-1];
    end

    wire [NUM_W-1:0] div_in_dividend = numer[chan_cnt][NUM_W-1:0];
    wire [SUM_W-1:0] div_in_divisor  = sum1[SUM_W-1:0];
    wire [QUOT_W-1:0] div_out_q;
    wire              div_out_valid;

    div_stage_ip u_div (
        .clk(clk),
        .dividend(div_in_dividend),
        .divisor(div_in_divisor),
        .quotient(div_out_q),
        .valid(div_out_valid)
    );

    reg signed [QUOT_W-1:0] gi2_reg [0:N-1];
    reg [TAG_W:0] fill_cnt;   // kac kanalin doldugunu sayar (N'e doyar)
    initial fill_cnt = 0;

    always @(posedge clk) begin
        if (div_out_valid) begin
            gi2_reg[tag_pipe[DIV_LATENCY-1]] <= $signed(div_out_q);
            if (fill_cnt < N) fill_cnt <= fill_cnt + 1'b1;
        end
    end

    // NOT (acik nokta): "valid" burada basitlestirilmis -- N kanal bir
    // kere dolunca 1'de kalir, girisler degisse de otomatik 0'a donup
    // yeniden saymiyor. Su anki testbench akisi (sabit bekleme suresi)
    // bu basitlestirmeden etkilenmiyor, ama gercek bir ust-seviye
    // kontrolcuyle (master controller) entegre edilirken bu sinyalin
    // "giris degisti, yeniden say" mantigina genisletilmesi gerekecek.
    assign valid = (fill_cnt >= N);

    // ---- gi2_reg dizisini flat bus'a paketle ----
    wire signed [N*QUOT_W-1:0] gi2_flat;
    generate
        for (g = 0; g < N; g = g + 1) begin : pack_gi2
            assign gi2_flat[g*QUOT_W +: QUOT_W] = gi2_reg[g];
        end
    endgenerate

    // ---- Adder Tree #2: sum2 = sum(gi2) ----
    wire signed [SUM2_W-1:0] sum2;
    adder_tree #(.N(N), .IN_W(QUOT_W), .OUT_W(SUM2_W)) u_adder2 (
        .data_flat(gi2_flat), .sum(sum2)
    );

    // ---- son cikarma (y_onehot'a gore) + kaydirma + int8 kirpma ----
    wire signed [SUM2_W-1:0] e_raw [0:N-1];
    wire signed [7:0]        e_final [0:N-1];

    generate
        for (g = 0; g < N; g = g + 1) begin : final_stage
            wire signed [SUM2_W-1:0] gi2_ext = {{(SUM2_W-QUOT_W){gi2_reg[g][QUOT_W-1]}}, gi2_reg[g]};
            assign e_raw[g] = y_onehot[g] ? (gi2_ext - sum2) : gi2_ext;

            // D5: son >>4 (round-to-nearest) + D8 (stokastik degil) + int8 kirpma (-127..127)
            wire signed [SUM2_W-1:0] shifted = (e_raw[g] + (1 <<< 3)) >>> 4;
            assign e_final[g] = (shifted > 127)  ? 8'sd127  :
                                 (shifted < -127) ? -8'sd127 :
                                 shifted[7:0];
        end
    endgenerate

    assign e0=e_final[0]; assign e1=e_final[1]; assign e2=e_final[2]; assign e3=e_final[3];
    assign e4=e_final[4]; assign e5=e_final[5]; assign e6=e_final[6]; assign e7=e_final[7];
    assign e8=e_final[8]; assign e9=e_final[9];

endmodule
