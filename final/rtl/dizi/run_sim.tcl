# =============================================================================
#  run_sim.tcl — 16x16 PE dizisinin (Adim 5) testlerini Vivado XSIM'de calistirir
# -----------------------------------------------------------------------------
#  Testler:
#    tb_pe_dizi     : pe_dizi (256 pe_birlesik + PE ici Psum FIFO, D72-D75), 256 ayri
#                     pe_birlesik + testbench'te yazilmis FIFO referansina karsi, her cevrim
#    tb_grup_kurucu : grup_kurucu + sru_array (16 kanal), dizi golden'inin gruplarina karsi
#                     (D76; vektorler models/sistem/adim5_vektorleri/, ag1 ve ag2)
#  Kullanim:
#    1) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    2) Tcl Console'a yaz:   source C:/.../final/rtl/dizi/run_sim.tcl
#  Beklenen (OZET basligi altinda):
#    SONUC tb_pe_dizi: PASS 2363392/2363392 (400 komut, 16x16)
#    SONUC tb_grup_kurucu: PASS 664/664 (2 ag, 648 grup)
#  Sure: tb_pe_dizi komut satirindaki XSIM'de ~4 dk (512 PE simule ediliyor), tb_grup_kurucu kisa.
#  Script bu klasorde gecici bir proje (vivado_sim/) kurar ve sonunda kapatir.
#  Yazan: Claude, 04.11.2026 (final/, Adim 5a; 5b'de tb_grup_kurucu eklendi)
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
create_project -force $pad $pdir

set rtl [list "$repo/rtl/pe/mac.v" "$repo/rtl/pe/pe_birlesik.v" "$repo/rtl/sistem/psum_fifo.v" \
              "$kok/pe_dizi.v" "$kok/grup_kurucu.v" "$repo/rtl/clu/max_tree.v"]
add_files -norecurse [concat $rtl [glob "$repo/rtl/sru/*.v"]]

set ozet {}
foreach tb {tb_pe_dizi tb_grup_kurucu} {
    set ss "sim_$tb"
    create_fileset -simset $ss
    add_files -fileset $ss -norecurse [list "$kok/$tb.sv"]
    set_property top $tb [get_filesets $ss]
    set_property top_lib xil_defaultlib [get_filesets $ss]
    update_compile_order -fileset $ss
    set calisma "$pdir/$pad.sim/$ss/behav/xsim"
    # vektorler calisma klasorune (ag2/ alt klasoruyle); testbench once oraya bakar
    file mkdir $calisma
    foreach f [glob -nocomplain "$vek/*"] { file copy -force $f $calisma }
    catch {set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets $ss]}
    # 512 PE'nin butun sinyalleri dalga penceresine eklenmesin (yavaslatir)
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
