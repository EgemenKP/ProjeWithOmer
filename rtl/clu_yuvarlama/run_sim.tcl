# =============================================================================
#  run_sim.tcl — CLU stokastik yuvarlama birimini (stok_yuvarla) Vivado XSIM'de dogrular
# -----------------------------------------------------------------------------
#  Rtl: rtl/clu_yuvarlama/  Vektorler: models/clu_yuvarlama/vektorler/
#  Kullanim:
#    1) Repo klasorunu bosluk ve Turkce karakter icermeyen bir yola koy,
#       or. C:/ProjeWithOmer-main
#    2) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    3) Alttaki Tcl Console'a yaz (ters bolu \ yerine duz bolu / kullan):
#           source C:/ProjeWithOmer-main/rtl/clu_yuvarlama/run_sim.tcl
#  Script kendi klasorunde gecici bir proje (vivado_sim/) kurar, tb_stok_yuvarla'yi calistirir
#  ve en sonda OZET basligi altinda SONUC satirini yazar. Beklenen:
#           SONUC tb_stok_yuvarla: PASS 40960/40960
#  Yazan: Claude, 02.11.2026 (Vivado'da gecti, 40960/40960). 03.11: repo duzenine
#  uyarlandi (yalnizca yollar), eski vivado_sim silinir, hata olursa script durmaz.
#  (Ekrana yazilan mesajlar, Vivado konsolunda bozuk gorunmesin diye ASCII.)
# =============================================================================

set kok  [file normalize [file dirname [info script]]]
set repo [file dirname [file dirname $kok]]
set vek  "$repo/models/clu_yuvarlama/vektorler"
set pdir "$kok/vivado_sim"
set pad  "clu_yuvarlama_sim"

if {[regexp {[^A-Za-z0-9_./:\-]} $repo]} {
    puts "UYARI: Klasor yolunda bosluk ya da Turkce/ozel karakter var: $kok"
    puts "       Vivado bu tur yollarda sorun cikarabilir. Repoyu or. C:/ProjeWithOmer-main altina tasiyin."
}

if {[llength [get_projects -quiet]] > 0} {
    puts "HATA: Acik bir proje var. File > Close Project ile kapatip script'i yeniden calistirin."
    return
}

# Onceki calistirmadan kalan gecici proje silinir; silinemezse yeni bir klasor adi kullanilir.
if {[file exists $pdir]} {
    if {[catch {file delete -force $pdir} hata]} {
        set pdir "$kok/vivado_sim_[clock seconds]"
        puts "UYARI: Eski vivado_sim silinemedi ($hata). Bu calistirma $pdir klasorunu kullaniyor."
    }
}

# Simulasyon icin parca onemli degil; kurulu herhangi bir 7-serisi parcayi kullan.
set parca [lindex [get_parts -quiet xc7*] 0]
if {$parca eq ""} {
    create_project -force $pad $pdir
} else {
    create_project -force $pad $pdir -part $parca
}

add_files -norecurse [list "$kok/stok_yuvarla.v"]
add_files -fileset sim_1 -norecurse [list "$kok/tb_stok_yuvarla.sv"]
update_compile_order -fileset sim_1

# XSIM'in calisma klasoru (vektor yolu yedegi icin)
set calisma "$pdir/$pad.sim/sim_1/behav/xsim"
set ozet {}

foreach tb {tb_stok_yuvarla} {
    # Eski sonuc dosyalari yaniltmasin
    file delete -force "$vek/sonuc_$tb.txt" "$calisma/sonuc_$tb.txt"

    set_property top $tb [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]

    # Vektor klasorunu testbench'e +VEKTOR_DIZINI ile ver
    if {[catch {set_property -name {xsim.simulate.xsim.more_options} \
                    -value "-testplusarg VEKTOR_DIZINI=$vek/" \
                    -objects [get_filesets sim_1]} hata]} {
        puts "BILGI: plusarg ayarlanamadi ($hata); vektorler calisma klasorunden okunacak."
    }
    # Yedek: vektor dosyalarini XSIM calisma klasorune de kopyala
    file mkdir $calisma
    foreach f [glob -nocomplain "$vek/*.txt"] {
        if {![string match "sonuc_*" [file tail $f]]} { file copy -force $f $calisma }
    }

    # Simulasyonu $finish'e kadar calistir
    catch {set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]}
    if {[catch {launch_simulation} hata]} {
        lappend ozet "SONUC $tb: CALISTIRILAMADI (launch_simulation hata verdi; ayrinti asagida)"
        set n 0
        foreach log {compile.log elaborate.log simulate.log} {
            set yol "$calisma/$log"
            if {![file exists $yol]} { continue }
            set kanal [open $yol r]
            foreach s [split [read $kanal] "\n"] {
                if {[string match "ERROR*" $s] && $n < 6} { lappend ozet "    $log: [string trim $s]" ; incr n }
            }
            close $kanal
        }
        if {$n == 0} { lappend ozet "    (log dosyalarinda ERROR satiri bulunamadi; Tcl Console'a bakin)" }
        catch {close_sim -force}
        continue
    }
    catch {run all}
    catch {close_sim -force}

    # Sonucu testbench'in yazdigi dosyadan oku
    set satir "SONUC $tb: sonuc dosyasi bulunamadi (konsoldaki SONUC satirina bakin)"
    foreach f [list "$vek/sonuc_$tb.txt" "$calisma/sonuc_$tb.txt"] {
        if {[file exists $f]} {
            set kanal [open $f r]
            set satir [string trim [gets $kanal]]
            close $kanal
            break
        }
    }
    file delete -force "$vek/sonuc_$tb.txt"
    lappend ozet $satir
}

close_project

puts ""
puts "==================== OZET ===================="
foreach s $ozet { puts $s }
puts "=============================================="
