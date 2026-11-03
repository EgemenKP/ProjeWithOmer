# =============================================================================
#  run_sim.tcl — SRU testlerini Vivado XSIM'de calistirir (rtl/sru/, birlesik SRU, D70)
# -----------------------------------------------------------------------------
#  Testler:
#    tb_bm_official     : bit_length32, resmi sru_bm.txt (D28)
#    tb_global_max_b    : Max Regs / G (hedef = 7)
#    tb_sround_official : stochastic_round, resmi sru_yuvarla.txt (Alg. 1, ayar kodu 1 1 0 1)
#    tb_sru_array       : 16 kanal + paylasilan G (hedef = 7)
#    tb_sru_katman      : LMS + GMS, sru_katman.txt (hedef = 7)
#    tb_sru_top         : tek kanal SRU, sru_katman.txt (hedef = 7)
#    tb_lms_uc          : LMS'in B ve l'si, uc degerler (|-2^31|, D71)
#    tb_sru_gradyan     : g'nin m_u hedefiyle gecisi + agirlik guncelleme (D40, D61)
#  Vektorler: models/sru/*.txt, models/fe/fe_vektorleri/wu_katman.txt
#  Kullanim:
#    1) Repo klasorunu bosluk ve Turkce karakter icermeyen bir yola koy.
#    2) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    3) Tcl Console'a yaz:   source C:/.../final/rtl/sru/run_sim.tcl
#  Beklenen (OZET basligi altinda):
#    SONUC tb_bm_official: PASS 154/154
#    SONUC tb_global_max_b: PASS 12/12
#    SONUC tb_sround_official: PASS 2297/2297
#    SONUC tb_sru_array: PASS 12/12
#    SONUC tb_sru_katman: PASS 52/52
#    SONUC tb_sru_top: PASS 52/52
#    SONUC tb_lms_uc: PASS 20013/20013
#    SONUC tb_sru_gradyan: PASS 1865/1865
#  Egemen'in testbench'leri sonuc dosyasi yazmiyor; sonuc simulate.log'daki TOPLAM ya da SONUC
#  satirindan okunur. Script bu klasorde gecici bir proje (vivado_sim/) kurar.
#  Yazan: Claude, 03.11.2026 (final/)
# =============================================================================

set kok  [file normalize [file dirname [info script]]]
set repo [file dirname [file dirname $kok]]
set pdir "$kok/vivado_sim"
set pad  "sru_sim"

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

set rtl [glob "$kok/*.v"]
lappend rtl "$repo/rtl/clu/max_tree.v" "$repo/rtl/fe/wu_unit.v"
add_files -norecurse $rtl

set vektorler [concat [glob "$repo/models/sru/*.txt"] [list "$repo/models/fe/fe_vektorleri/wu_katman.txt"]]

# simulate.log'dan sonuc: "SONUC tb: ..." satiri varsa o; yoksa "TOPLAM[ X]=n[,] DOGRU=k[,] HATALI=h"
proc log_sonucu {tb log} {
    if {![file exists $log]} { return "SONUC $tb: simulate.log yok" }
    set kanal [open $log r] ; set icerik [read $kanal] ; close $kanal
    if {[regexp "SONUC $tb: \[^\n\]*" $icerik satir]} { return [string trim $satir] }
    if {[regexp {TOPLAM(?: \w+)?=(\d+),? DOGRU=(\d+),? HATALI=(\d+)} $icerik -> n k h]} {
        if {$h == 0 && $n > 0} { return "SONUC $tb: PASS $k/$n" }
        return "SONUC $tb: FAIL $h hata / $n"
    }
    return "SONUC $tb: TOPLAM satiri yok (simulate.log'a bakin)"
}

set testler {tb_bm_official tb_global_max_b tb_sround_official tb_sru_array tb_sru_katman tb_sru_top \
             tb_lms_uc tb_sru_gradyan}
set ozet {}
foreach tb $testler {
    set ss "sim_$tb"
    create_fileset -simset $ss
    add_files -fileset $ss -norecurse [list "$kok/$tb.sv"]
    set_property top $tb [get_filesets $ss]
    set_property top_lib xil_defaultlib [get_filesets $ss]
    update_compile_order -fileset $ss
    set calisma "$pdir/$pad.sim/$ss/behav/xsim"
    file mkdir $calisma
    foreach f $vektorler { file copy -force $f $calisma }
    catch {set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets $ss]}
    if {[catch {launch_simulation -simset $ss} hata]} {
        lappend ozet "SONUC $tb: CALISTIRILAMADI ([string range $hata 0 160])"
        catch {close_sim -force}
        continue
    }
    catch {run all}
    catch {close_sim -force}
    lappend ozet [log_sonucu $tb "$calisma/simulate.log"]
}
close_project

puts ""
puts "==================== OZET ===================="
foreach s $ozet { puts $s }
puts "=============================================="
