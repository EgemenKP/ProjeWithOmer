# =============================================================================
#  run_sim.tcl — CLU testini Vivado XSIM'de calistirir (rtl/clu/)
# -----------------------------------------------------------------------------
#  Test: tb_clu (Egemen'in clu_top.v'si, golden: models/clu/golden_model.py, vectors.txt)
#  Bolucu IP'si: rtl/clu/ip/div_gen_0Z.xci gecici projeye kopyalanip uretilir. Bulunamaz ya da
#    uretilemezse rtl/clu/sim_model/ altindaki davranissal model kullanilir ve OZET'te yazilir.
#  Kullanim:
#    1) Repo klasorunu bosluk ve Turkce karakter icermeyen bir yola koy.
#    2) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    3) Tcl Console'a yaz:   source C:/.../final/rtl/clu/run_sim.tcl
#  Beklenen (OZET basligi altinda):
#    BOLUCU: gercek IP (...)
#    SONUC tb_clu: PASS 40/40
#  tb_clu sonuc dosyasi yazmiyor; sonuc simulate.log'daki "TOPLAM: n test, k GECTI, h BASARISIZ"
#  satirindan okunur. Script bu klasorde gecici bir proje (vivado_sim/) kurar.
#  Yazan: Claude, 03.11.2026 (final/; IP kismi rtl/fe/run_sim.tcl'den)
# =============================================================================

set kok  [file normalize [file dirname [info script]]]
set repo [file dirname [file dirname $kok]]
set pdir "$kok/vivado_sim"
set pad  "clu_sim"

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

# ---- Bolucu IP'si ve parca (rtl/fe/run_sim.tcl ile ayni) ----
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
if {$parca eq ""} {
    create_project -force $pad $pdir
} else {
    create_project -force $pad $pdir -part $parca
}

set rtl {}
foreach ad {max_tree clu_top epu teu adder_tree div_stage_ip} { lappend rtl "$kok/$ad.v" }
add_files -norecurse $rtl

set davranissal "$kok/sim_model/div_gen_0Z_davranissal.v"
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

add_files -fileset sim_1 -norecurse [list "$kok/tb_clu.sv"]
set_property top tb_clu [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1
set calisma "$pdir/$pad.sim/sim_1/behav/xsim"
file mkdir $calisma
file copy -force "$repo/models/clu/vectors.txt" $calisma

set ozet [list "BOLUCU: $bolucu"]
catch {set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]}
if {[catch {launch_simulation} hata]} {
    lappend ozet "SONUC tb_clu: CALISTIRILAMADI ([string range $hata 0 160])"
} else {
    catch {run all}
    set satir "SONUC tb_clu: TOPLAM satiri yok (simulate.log'a bakin)"
    if {[file exists "$calisma/simulate.log"]} {
        set kanal [open "$calisma/simulate.log" r] ; set icerik [read $kanal] ; close $kanal
        if {[regexp {TOPLAM: (\d+) test, (\d+) GECTI, (\d+) BASARISIZ} $icerik -> n k h]} {
            if {$h == 0 && $n > 0} { set satir "SONUC tb_clu: PASS $k/$n" } else { set satir "SONUC tb_clu: FAIL $h hata / $n" }
        }
    }
    lappend ozet $satir
}
catch {close_sim -force}
close_project

puts ""
puts "==================== OZET ===================="
foreach s $ozet { puts $s }
puts "=============================================="
