# =============================================================================
#  run_sim.tcl — 16x16 dizili sistemin (Adim 5) testlerini Vivado XSIM'de calistirir
# -----------------------------------------------------------------------------
#  Testler:
#    tb_pe_dizi     : pe_dizi (256 pe_birlesik + PE ici Psum FIFO, D72-D75), 256 ayri
#                     pe_birlesik + testbench'te yazilmis FIFO referansina karsi, her cevrim
#    tb_grup_kurucu : grup_kurucu + sru_array (16 kanal), dizi golden'inin gruplarina karsi
#                     (D76; vektorler models/sistem/adim5_vektorleri/, ag1 ve ag2)
#    tb_on_getirme  : veri/agirlik tamponlari + on_getirme (GMS'li), dizili sistem golden'inin izine karsi (D90)
#    tb_dizi_motoru : dizi motoru (on-getirme + dizi + grup + LMS + yazma), golden'in komut listesiyle; son
#                     tampon golden'in son haliyle (D91; ag1, ag2, ag3, ag4)
#    tb_fsm_dizi    : master_controller_dizi, golden'in komut listesine karsi (D92)
#    tb_sistem_dizi : tam sistem (FSM + motor + CLU + WU + tamponlar), bir egitim adimi uctan uca (D93)
#  Bolucu IP'si (CLU, yalnizca tb_sistem_dizi): rtl/clu/ip/div_gen_0Z.xci gecici projeye kopyalanip uretilir;
#  bulunamaz ya da uretilemezse rtl/clu/sim_model/ altindaki davranissal model kullanilir ve OZET'te yazilir.
#  Kullanim:
#    1) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    2) Tcl Console'a yaz:   source C:/.../final/rtl/dizi/run_sim.tcl
#    Yalnizca bazi testler:   set sadece {tb_sistem_dizi} ; source .../run_sim.tcl
#  Beklenen (OZET basligi altinda):
#    BOLUCU: gercek IP (...)
#    SONUC tb_pe_dizi: PASS 2363392/2363392 (400 komut, 16x16)
#    SONUC tb_grup_kurucu: PASS 664/664 (2 ag, 648 grup)
#    SONUC tb_on_getirme: PASS 25054785/25054785 (6 ag, 7243 DIZI komutu)
#    SONUC tb_dizi_motoru: PASS 57957/57957 (6 ag, 7243 DIZI komutu, 57801 kelime)
#    SONUC tb_fsm_dizi: PASS 80832/80832 (6 ag, 8082 komut)
#    SONUC tb_sistem_dizi: PASS 65142/65142 (6 ag, 65037 kelime, 411757 cevrim)
#  (05.11, D103 sonrasi, ag6 dahil; davranissal bolucuyle XSIM CLI. Gercek IP'yle Vivado'da henuz kosulmadi.
#   tb_on_getirme ag6 yuzunden uzun: XSIM'de ~10-15 dk.)
#  Sure: tb_pe_dizi komut satirindaki XSIM'de ~4 dk (512 PE), digerleri birer-iki dakika.
#  tb_pe_dizi disindaki testbench'lerin ust modulunde sinyal yok (govde alt modulde): Vivado'nun dalga
#  gorunumu buyuk register'li testbench'lerde cokuyordu (arac tuzagi 13); boylece dalga penceresi acilmiyor.
#  Script bu klasorde gecici bir proje (vivado_sim/) kurar ve sonunda kapatir.
#  Yazan: Claude, 04.11.2026 (final/, Adim 5a-5b)
# =============================================================================

set kok  [file normalize [file dirname [info script]]]
set repo [file dirname [file dirname $kok]]
set pdir "$kok/vivado_sim"
set pad  "dizi_sim"
set vek  "$repo/models/sistem/adim5_vektorleri"

if {[regexp {[^A-Za-z0-9_./:\-]} $repo]} {
    puts "UYARI: Klasor yolunda bosluk ya da Turkce/ozel karakter var: $repo"
}
if {[llength [get_projects -quiet]] > 0} {
    puts "HATA: Acik bir proje var. File > Close Project ile kapatip script'i yeniden calistirin."
    return
}
if {[file exists $pdir]} {
    if {[catch {file delete -force $pdir}]} { set pdir "$kok/vivado_sim_[clock seconds]" }
}

# ---- Bolucu IP'si ve parca (rtl/sistem/run_sim.tcl ile ayni) ----
set xci "$repo/rtl/clu/ip/div_gen_0Z.xci"
if {![file exists $xci]} { set xci "" }
set parca ""
if {$xci ne ""} {
    set kanal [open $xci r] ; set icerik [read $kanal] ; close $kanal
    foreach aday [regexp -all -inline {xc[0-9a-z]+-[0-9a-zL]+} $icerik] {
        if {[llength [get_parts -quiet $aday]] > 0} { set parca $aday ; break }
    }
    if {$parca eq ""} {
        set dev "" ; set pak "" ; set hiz ""
        regexp {"DEVICE":\s*\[\s*\{\s*"value":\s*"([^"]*)"} $icerik -> dev
        regexp {"PACKAGE":\s*\[\s*\{\s*"value":\s*"([^"]*)"} $icerik -> pak
        regexp {"SPEEDGRADE":\s*\[\s*\{\s*"value":\s*"([^"]*)"} $icerik -> hiz
        if {$dev ne "" && $pak ne ""} {
            set aday "$dev$pak$hiz"
            if {[llength [get_parts -quiet $aday]] > 0} { set parca $aday }
        }
    }
}
if {$parca eq ""} { set parca [lindex [get_parts -quiet xc7*] 0] }
if {$parca eq ""} { create_project -force $pad $pdir } else { create_project -force $pad $pdir -part $parca }

# ---- Tasarim kaynaklari ----
set rtl {}
foreach ad {pe_dizi grup_kurucu veri_tamponu agirlik_tamponu on_getirme dizi_motoru master_controller_dizi sistem_dizi} {
    lappend rtl "$kok/$ad.v"
}
foreach ad {pe/mac pe/pe_birlesik sistem/psum_fifo fe/relu_unit fe/wu_unit fe/fe_top \
            clu/max_tree clu/clu_top clu/epu clu/teu clu/adder_tree clu/div_stage_ip} {
    lappend rtl "$repo/rtl/$ad.v"
}
add_files -norecurse [concat $rtl [glob "$repo/rtl/sru/*.v"]]

set davranissal "$repo/rtl/clu/sim_model/div_gen_0Z_davranissal.v"
set bolucu "davranissal model (rtl/clu/sim_model/div_gen_0Z_davranissal.v) - gercek IP bulunamadi"
if {$xci ne ""} {
    set ipdir "$pdir/ip/div_gen_0Z"
    file mkdir $ipdir
    file copy -force $xci "$ipdir/div_gen_0Z.xci"
    set kanal [open "$ipdir/div_gen_0Z.xci" r] ; set icerik [read $kanal] ; close $kanal
    if {[regsub {"gen_directory":\s*"[^"]*"} $icerik {"gen_directory": "./gen"} icerik]} {
        set kanal [open "$ipdir/div_gen_0Z.xci" w] ; puts -nonewline $kanal $icerik ; close $kanal
    }
    if {[catch {
        read_ip "$ipdir/div_gen_0Z.xci"
        catch {upgrade_ip [get_ips div_gen_0Z]}
        generate_target simulation [get_files div_gen_0Z.xci]
    } hata]} {
        puts "UYARI: IP okunamadi ($hata). Davranissal modelle devam ediliyor."
        add_files -norecurse [list $davranissal]
        set bolucu "davranissal model - IP okunamadi: $hata"
    } else {
        set bolucu "gercek IP (rtl/clu/ip/div_gen_0Z.xci, parca $parca)"
    }
} else {
    add_files -norecurse [list $davranissal]
}

set testler {tb_pe_dizi tb_grup_kurucu tb_on_getirme tb_dizi_motoru tb_fsm_dizi tb_sistem_dizi}
if {[info exists ::sadece]} { set testler $::sadece }

set ozet [list "BOLUCU: $bolucu"]
foreach tb $testler {
    set ss "sim_$tb"
    create_fileset -simset $ss
    add_files -fileset $ss -norecurse [list "$kok/$tb.sv"]
    set_property top $tb [get_filesets $ss]
    set_property top_lib xil_defaultlib [get_filesets $ss]
    update_compile_order -fileset $ss
    set calisma "$pdir/$pad.sim/$ss/behav/xsim"
    # vektorler calisma klasorune (ag2/, ag3/, ag4/ alt klasorleriyle); testbench once oraya bakar
    file mkdir $calisma
    foreach f [glob -nocomplain "$vek/*"] { file copy -force $f $calisma }
    catch {set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets $ss]}
    catch {set_property -name {xsim.simulate.log_all_signals} -value {false} -objects [get_filesets $ss]}
    if {[catch {launch_simulation -simset $ss} hata]} {
        lappend ozet "SONUC $tb: CALISTIRILAMADI ([string range $hata 0 160])"
        catch {close_sim -force}
        continue
    }
    catch {run all}
    catch {close_sim -force}
    set satir "SONUC $tb: simulate.log'da SONUC satiri yok"
    if {[file exists "$calisma/simulate.log"]} {
        set kanal [open "$calisma/simulate.log" r] ; set icerik [read $kanal] ; close $kanal
        regexp "SONUC $tb: \[^\n\]*" $icerik satir
    }
    lappend ozet [string trim $satir]
}
close_project

puts ""
puts "==================== OZET ===================="
foreach s $ozet { puts $s }
puts "=============================================="
