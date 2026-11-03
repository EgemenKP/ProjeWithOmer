# =============================================================================
#  run_sim.tcl — PE testlerini Vivado XSIM'de calistirir (rtl/pe/)
# -----------------------------------------------------------------------------
#  Iki kosu, ayni testbench'ler (Egemen'in tb_pe_*.sv'leri, DEGISMEDEN):
#    ASIL     : Egemen'in bes devresi (pe_chain3, pe_fp_s2, pe_bp_s2, pe_wg_s1, pe_wg_s2)
#    BIRLESIK : pe_birlesik.v (Shao Fig. 2, tek PE, 9 MAC; D69), pe_birlesik_kabuklar.sv
#               uzerinden (kabuklar Egemen'in modul adlarini tasir, o yuzden ayri proje)
#  Vektorler: models/pe/pe_vectors/ (Omer'in pe_golden.py'si)
#  Kullanim:
#    1) Repo klasorunu bosluk ve Turkce karakter icermeyen bir yola koy.
#    2) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    3) Tcl Console'a yaz:   source C:/.../final/rtl/pe/run_sim.tcl
#  Beklenen (OZET basligi altinda), her iki kosu icin:
#    SONUC tb_pe_chain3: PASS 38/38       (FP s1)
#    SONUC tb_pe_fp_s1_run: PASS 38/38
#    SONUC tb_pe_bp_s1_run: PASS 34/34
#    SONUC tb_pe_fp_s2: PASS 24/24
#    SONUC tb_pe_bp_s2: PASS 32/32
#    SONUC tb_pe_wg_s1: PASS 5/5
#    SONUC tb_pe_wg_s2: PASS 5/5
#  Egemen'in testbench'leri sonuc dosyasi yazmiyor; sonuc simulate.log'daki TOPLAM satirindan
#  okunur (HATALI=0 ise PASS). Script bu klasorde gecici projeler (vivado_sim_*/) kurar.
#  Yazan: Claude, 03.11.2026 (final/)
# =============================================================================

set kok  [file normalize [file dirname [info script]]]
set repo [file dirname [file dirname $kok]]
set vek  "$repo/models/pe/pe_vectors"

if {[regexp {[^A-Za-z0-9_./:\-]} $repo]} {
    puts "UYARI: Klasor yolunda bosluk ya da Turkce/ozel karakter var: $repo"
}
if {[llength [get_projects -quiet]] > 0} {
    puts "HATA: Acik bir proje var. File > Close Project ile kapatip script'i yeniden calistirin."
    return
}

set testler {tb_pe_chain3 tb_pe_fp_s1_run tb_pe_bp_s1_run tb_pe_fp_s2 tb_pe_bp_s2 tb_pe_wg_s1 tb_pe_wg_s2}
set ozet {}

# simulate.log'dan "[...] TOPLAM GECIS=n, DOGRU=k, HATALI=h" ya da "TOPLAM CASE=..." satirini oku
proc log_sonucu {tb log} {
    if {![file exists $log]} { return "SONUC $tb: simulate.log yok" }
    set kanal [open $log r] ; set icerik [read $kanal] ; close $kanal
    if {[regexp {TOPLAM \w+=(\d+), DOGRU=(\d+), HATALI=(\d+)} $icerik -> n k h]} {
        if {$h == 0 && $n > 0} { return "SONUC $tb: PASS $k/$n" }
        return "SONUC $tb: FAIL $h hata / $n"
    }
    if {[string first "acilamadi" $icerik] >= 0} { return "SONUC $tb: FAIL (vektor dosyasi acilamadi)" }
    return "SONUC $tb: TOPLAM satiri yok (simulate.log'a bakin)"
}

foreach {kosu kaynaklar} [list \
        ASIL     [list "$kok/mac.v" "$kok/pe_chain3.v" "$kok/pe_fp_s2.v" "$kok/pe_bp_s2.v" "$kok/pe_wg_s1.v" "$kok/pe_wg_s2.v"] \
        BIRLESIK [list "$kok/mac.v" "$kok/pe_birlesik.v" "$kok/pe_birlesik_kabuklar.sv"]] {
    set pdir "$kok/vivado_sim_[string tolower $kosu]"
    set pad  "pe_[string tolower $kosu]"
    if {[file exists $pdir]} { catch {file delete -force $pdir} }
    create_project -force $pad $pdir
    add_files -norecurse $kaynaklar
    lappend ozet "---- $kosu ----"
    foreach tb $testler {
        set ss "sim_$tb"
        create_fileset -simset $ss
        # tb_pe_fp_s1_run ve tb_pe_bp_s1_run, tb_pe_chain3'u parametreyle kurar
        add_files -fileset $ss -norecurse [lsort -unique [list "$kok/$tb.sv" "$kok/tb_pe_chain3.sv"]]
        set_property top $tb [get_filesets $ss]
        set_property top_lib xil_defaultlib [get_filesets $ss]
        update_compile_order -fileset $ss
        set calisma "$pdir/$pad.sim/$ss/behav/xsim"
        # Testbench'ler "pe_vectors/..." goreli yolunu okuyor: vektorleri calisma klasorune kopyala
        file mkdir $calisma
        file delete -force "$calisma/pe_vectors"
        file copy -force $vek "$calisma/pe_vectors"
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
}

puts ""
puts "==================== OZET ===================="
foreach s $ozet { puts $s }
puts "=============================================="
