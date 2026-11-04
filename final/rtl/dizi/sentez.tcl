# =============================================================================
#  sentez.tcl — 16x16 dizili sistemin sentezi ve implementasyonu (Adim 5b-3f)
# -----------------------------------------------------------------------------
#  Shao Table I/II'nin karsiligi: kaynak kullanimi, 200 MHz zamanlama, guc tahmini.
#  Parca: xc7vx690tffg1761-2 (VC709, Shao IV). Saat: 5.000 ns (200 MHz, Shao IV).
#  Baglamsiz (out-of-context): ust modulun portlari pinlere atanmaz (I/O yollari kisitsiz).
#
#  Tam sistemin tek seferde sentezi 15 GB RAM'li bilgisayarda bellek sinirina dayandi (14,4 GB, 04.11).
#  Bu yuzden iki parca (asama):
#    dizi   : pe_dizi (256 PE + PE ici Psum FIFO'lar) tek basina
#    sistem : sistem_dizi, pe_dizi kara kutu (FSM, on-getirme, motor, tamponlar, CLU + bolucu IP, WU)
#  Tam sistemin kaynagi = iki parcanin toplami (pe_dizi'nin sinirindaki yollar her iki parcada da yarim).
#  Uygulama (place + route + guc): asama "dizi_uygulama" / "sistem_uygulama" (sentez checkpoint'inden).
#  Hizli sentez (hizli = 1, "sistem" asamasinda varsayilan): -directive RuntimeOptimized -no_timing_driven.
#    Neden (04.11): "sistem" parcasinin varsayilan sentezi Timing Optimization asamasinda 2 sa 13 dk ilerlemedi,
#    bellek tepe 13,2 GB (on_getirme'nin saatsiz akisi: yazmac olarak kurulan satir tamponlari + 256'ya 1 mux'lar).
#    Bu ayar kaynak sayisi icindir; gercek zamanlama place & route'tan alinir. Kapatmak icin: set hizli 0
#  Kullanim (Vivado Tcl Console ya da vivado -mode batch -source sentez.tcl):
#      set asama dizi ; source .../final/rtl/dizi/sentez.tcl
#  Ciktilar: final/rtl/dizi/sentez_cikti/ (raporlar ve checkpoint'ler; git disi)
#  Yazan: Claude, 04.11.2026 (final/, Adim 5b-3f)
# =============================================================================

set kok   [file normalize [file dirname [info script]]]
set repo  [file dirname [file dirname $kok]]
set cikti "$kok/sentez_cikti"
set parca xc7vx690tffg1761-2
if {![info exists asama]} { set asama dizi }
if {![info exists hizli]} { set hizli [expr {$asama eq "sistem"}] }
set sentez_ek [expr {$hizli ? {-directive RuntimeOptimized -no_timing_driven} : {}}]
# Hiyerarsi: "rebuilt" (varsayilan) ya da "none" (modul basina dogru kaynak dokumu; 05.11 olcumu)
if {![info exists duzlestir]} { set duzlestir rebuilt }
file mkdir $cikti
set_param general.maxThreads 4

proc saat_xdc {cikti} {
    set xdc "$cikti/saat.xdc"
    set kanal [open $xdc w]
    puts $kanal "create_clock -period 5.000 -name clk \[get_ports clk\]"
    close $kanal
    read_xdc -mode out_of_context $xdc
}

proc raporla {cikti ad} {
    report_utilization -file "$cikti/kaynak_$ad.txt"
    report_utilization -hierarchical -hierarchical_depth 3 -file "$cikti/kaynak_hiyerarsi_$ad.txt"
    report_timing_summary -max_paths 10 -file "$cikti/zamanlama_$ad.txt"
    report_power -file "$cikti/guc_$ad.txt"
}

if {$asama eq "dizi"} {
    create_project -in_memory -part $parca
    read_verilog [list "$kok/pe_dizi.v" "$repo/rtl/pe/mac.v" "$repo/rtl/pe/pe_birlesik.v" "$repo/rtl/sistem/psum_fifo.v"]
    saat_xdc $cikti
    synth_design -top pe_dizi -part $parca -mode out_of_context -flatten_hierarchy $duzlestir {*}$sentez_ek
    write_checkpoint -force "$cikti/dizi_sentez.dcp"
    raporla $cikti dizi_sentez
    puts "SENTEZ BITTI (dizi): $cikti"
} elseif {$asama eq "sistem"} {
    create_project -in_memory -part $parca
    set rtl {}
    foreach ad {veri_tamponu agirlik_tamponu on_getirme dizi_motoru master_controller_dizi sistem_dizi} {
        lappend rtl "$kok/$ad.v"
    }
    foreach ad {fe/relu_unit fe/wu_unit fe/fe_top clu/max_tree clu/clu_top clu/epu clu/teu clu/adder_tree clu/div_stage_ip} {
        lappend rtl "$repo/rtl/$ad.v"
    }
    # pe_dizi kara kutu: yalnizca portlari (pe_dizi.v ile ayni)
    set kutu "$cikti/pe_dizi_kara_kutu.v"
    set kanal [open $kutu w]
    puts $kanal {(* black_box *)
module pe_dizi #(parameter R = 16, parameter C = 16, parameter PS_DERINLIK = 64, parameter PS_AW = 6) (
    input  wire clk, input wire rst, input wire [2:0] mod,
    input  wire [R*24-1:0] satir_akis1_flat, input wire [R*24-1:0] satir_akis2_flat,
    input  wire [R*24-1:0] satir_akis3_flat, input wire [C*72-1:0] sutun_w_flat,
    input  wire ps_temizle, input wire ps_yaz, input wire ps_oku, input wire ps_sec,
    output wire [R*C*128-1:0] cikis_flat, output wire [R*C*288-1:0] g_flat,
    output wire ps_tasma, output wire ps_eksik, output wire ps_bos, output wire [R*C*128-1:0] ps_bas_flat);
endmodule}
    close $kanal
    lappend rtl $kutu
    read_verilog [concat $rtl [glob "$repo/rtl/sru/*.v"]]
    # Bolucu IP'si: kopya, gen_directory duzeltmesi, ust modulle birlikte sentez
    set ipdir "$cikti/ip/div_gen_0Z"
    file mkdir $ipdir
    file copy -force "$repo/rtl/clu/ip/div_gen_0Z.xci" "$ipdir/div_gen_0Z.xci"
    set kanal [open "$ipdir/div_gen_0Z.xci" r] ; set icerik [read $kanal] ; close $kanal
    if {[regsub {"gen_directory":\s*"[^"]*"} $icerik {"gen_directory": "./gen"} icerik]} {
        set kanal [open "$ipdir/div_gen_0Z.xci" w] ; puts -nonewline $kanal $icerik ; close $kanal
    }
    read_ip "$ipdir/div_gen_0Z.xci"
    catch {upgrade_ip [get_ips div_gen_0Z]}
    set_property generate_synth_checkpoint false [get_files div_gen_0Z.xci]
    generate_target all [get_files div_gen_0Z.xci]
    saat_xdc $cikti
    synth_design -top sistem_dizi -part $parca -mode out_of_context -flatten_hierarchy $duzlestir {*}$sentez_ek
    write_checkpoint -force "$cikti/sistem_sentez.dcp"
    raporla $cikti sistem_sentez
    puts "SENTEZ BITTI (sistem): $cikti"
} else {
    # dizi_uygulama / sistem_uygulama
    set ad [lindex [split $asama _] 0]
    open_checkpoint "$cikti/${ad}_sentez.dcp"
    opt_design
    place_design
    phys_opt_design
    route_design
    write_checkpoint -force "$cikti/${ad}_uygulama.dcp"
    raporla $cikti ${ad}_uygulama
    puts "UYGULAMA BITTI ($ad): $cikti"
}
