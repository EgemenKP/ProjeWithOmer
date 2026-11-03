# =============================================================================
#  run_sim.tcl — Fonksiyon motoru (Adim 3) testlerini Vivado XSIM'de calistirir
# -----------------------------------------------------------------------------
#  Testler:
#    tb_relu        : ReLU birimi (rtl/fe/relu_unit.v)
#    tb_wu          : agirlik guncelleme birimi (rtl/fe/wu_unit.v)
#    tb_sru_gradyan : gradyanin SRU'dan m_u hedefiyle gecisi + agirlik guncelleme
#                     (rtl/sru_hedefli/, DEVIATIONS D40, D61)
#    tb_fe_top      : fonksiyon motoru ust modulu: ReLU + WU + CLU (rtl/fe/fe_top.v, D62)
#  Vektorler: models/fe/fe_vektorleri/
#  Bolucu IP'si: rtl/clu/ip/div_gen_0Z.xci (gecici projeye kopyalanip uretilir).
#    Bulunamaz ya da uretilemezse rtl/clu/sim_model/ altindaki davranissal model
#    kullanilir ve bu OZET'te yazilir.
#  Kullanim:
#    1) Repo klasorunu bosluk ve Turkce karakter icermeyen bir yola koy,
#       or. C:/ProjeWithOmer-main
#    2) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    3) Tcl Console'a yaz:   source C:/ProjeWithOmer-main/rtl/fe/run_sim.tcl
#  Beklenen (OZET basligi altinda):
#    BOLUCU: gercek IP (...)
#    SONUC tb_relu: PASS 196608/196608
#    SONUC tb_wu: PASS 65536/65536
#    SONUC tb_sru_gradyan: PASS 1865/1865
#    SONUC tb_fe_top: PASS 456144/456144
#  Script bu klasorde gecici bir proje (vivado_sim/) kurar ve sonunda kapatir;
#  vivado_sim/ sonradan silinebilir.
#  Yazan: Claude, 03.11.2026 (fe_rtl ve adim3 script'lerinin repo duzenine
#  uyarlanmis birlesimi). Sahte Vivado komutlariyla ve Icarus ile denendi.
#  03.11 eki: IP'nin uretilen dosyalari gecici projenin icinde (gen_directory duzeltmesi);
#  hata olursa butun log'lardaki ERROR satirlari OZET'e yaziliyor.
#  (Ekrana yazilan mesajlar ASCII.)
# =============================================================================

set kok  [file normalize [file dirname [info script]]]
set repo [file dirname [file dirname $kok]]
set vek  "$repo/models/fe/fe_vektorleri"
set pdir "$kok/vivado_sim"
set pad  "fe_sim"

if {[regexp {[^A-Za-z0-9_./:\-]} $repo]} {
    puts "UYARI: Klasor yolunda bosluk ya da Turkce/ozel karakter var: $repo"
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
        puts "UYARI: Eski vivado_sim silinemedi ($hata)."
        puts "       Bu calistirma $pdir klasorunu kullaniyor. Sorun surerse Vivado'yu tamamen kapatip acin."
    }
}

# ---- Bolucu IP'si ve parca ----
set xci "$repo/rtl/clu/ip/div_gen_0Z.xci"
if {![file exists $xci]} { set xci "" }

# IP varsa IP'nin uretildigi parca kullanilir (parca degisirse IP kilitlenebilir),
# yoksa kurulu herhangi bir 7-serisi parca. Simulasyon icin parca onemli degil.
set parca ""
if {$xci ne ""} {
    set kanal [open $xci r]
    set icerik [read $kanal]
    close $kanal
    # Eski .xci bicimi: parca adi tek parca halinde (or. xc7vx690tffg1761-2)
    foreach aday [regexp -all -inline {xc[0-9a-z]+-[0-9a-zL]+} $icerik] {
        if {[llength [get_parts -quiet $aday]] > 0} { set parca $aday ; break }
    }
    # Yeni (JSON) bicim: DEVICE + PACKAGE + SPEEDGRADE ayri alanlarda
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

# ---- Tasarim kaynaklari ----
set rtl [list "$repo/rtl/fe/relu_unit.v" "$repo/rtl/fe/wu_unit.v" "$repo/rtl/fe/fe_top.v"]
set rtl [concat $rtl [glob "$repo/rtl/sru_hedefli/*.v"]]
# Egemen'in degismemis dosyalari (SRU'nun hedef girisi olmayan alt bloklari ve CLU)
foreach ad {sru/gms_group16 sru/stochastic_round sru/bit_length32 \
            clu/max_tree clu/clu_top clu/epu clu/teu clu/adder_tree clu/div_stage_ip} {
    lappend rtl "$repo/rtl/$ad.v"
}
add_files -norecurse $rtl

set davranissal "$repo/rtl/clu/sim_model/div_gen_0Z_davranissal.v"
set bolucu "davranissal model (rtl/clu/sim_model/div_gen_0Z_davranissal.v) - gercek IP bulunamadi"
if {$xci ne ""} {
    # IP gecici projeye kopyalanir; uretilen dosyalar repoya yazilmaz
    set ipdir "$pdir/ip/div_gen_0Z"
    file mkdir $ipdir
    file copy -force $xci "$ipdir/div_gen_0Z.xci"
    # .xci'deki gen_directory goreli ("../../../../project_2.gen/..."): IP'nin uretildigi projeye
    # gore yazilmis; kopyada degistirilmezse uretilen dosyalar gecici projenin disina (or.
    # C:/project_2.gen) yazilir. Kopyada IP'nin yanindaki gen/ klasorune cevrilir.
    set kanal [open "$ipdir/div_gen_0Z.xci" r]
    set icerik [read $kanal]
    close $kanal
    if {[regsub {"gen_directory":\s*"[^"]*"} $icerik {"gen_directory": "./gen"} icerik]} {
        set kanal [open "$ipdir/div_gen_0Z.xci" w]
        puts -nonewline $kanal $icerik
        close $kanal
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

add_files -fileset sim_1 -norecurse [list "$kok/tb_relu.sv" "$kok/tb_wu.sv" \
    "$repo/rtl/sru_hedefli/tb_sru_gradyan.sv" "$kok/tb_fe_top.sv"]
update_compile_order -fileset sim_1

set calisma "$pdir/$pad.sim/sim_1/behav/xsim"
set ozet [list "BOLUCU: $bolucu"]

foreach tb {tb_relu tb_wu tb_sru_gradyan tb_fe_top} {
    file delete -force "$vek/sonuc_$tb.txt" "$calisma/sonuc_$tb.txt"

    set_property top $tb [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]

    if {[catch {set_property -name {xsim.simulate.xsim.more_options} \
                    -value "-testplusarg VEKTOR_DIZINI=$vek/" \
                    -objects [get_filesets sim_1]} hata]} {
        puts "BILGI: plusarg ayarlanamadi ($hata); vektorler calisma klasorunden okunacak."
    }
    # Yedek: vektorleri XSIM calisma klasorune de kopyala (yolda bosluk varsa plusarg bozulur)
    file mkdir $calisma
    foreach f [concat [glob -nocomplain "$vek/*.txt"] [glob -nocomplain "$vek/*.hex"]] {
        if {![string match "sonuc_*" [file tail $f]]} { file copy -force $f $calisma }
    }

    catch {set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]}
    if {[catch {launch_simulation} hata]} {
        # Derleme/elaborate/simulasyon hatasi: script durmasin, hatayi ozete yaz, siradaki teste gec
        lappend ozet "SONUC $tb: CALISTIRILAMADI (launch_simulation hata verdi; ayrinti asagida)"
        # Calisma klasorundeki butun log'lar (xvlog.log, xvhdl.log, compile.log, xelab.log,
        # elaborate.log, simulate.log ...): ERROR gecen satirlar, tekrarsiz, en cok 10 tane
        set n 0
        set gorulen {}
        foreach yol [lsort [glob -nocomplain "$calisma/*.log"]] {
            set kanal [open $yol r]
            foreach s [split [read $kanal] "\n"] {
                set s [string trim $s]
                if {[string first "ERROR" $s] >= 0 && [lsearch -exact $gorulen $s] < 0 && $n < 10} {
                    lappend gorulen $s
                    lappend ozet "    [file tail $yol]: $s"
                    incr n
                }
            }
            close $kanal
        }
        if {$n == 0} {
            lappend ozet "    (log dosyalarinda ERROR satiri yok; Tcl Console'daki hata: [string range $hata 0 200])"
        }
        catch {close_sim -force}
        continue
    }
    catch {run all}
    catch {close_sim -force}

    # Sonucu testbench'in yazdigi dosyadan oku, sonra sil (repo klasoru temiz kalsin)
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
