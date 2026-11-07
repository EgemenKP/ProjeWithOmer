# =============================================================================
#  run_sim.tcl — Adim 4 (tam sistem) testlerini Vivado XSIM'de calistirir (rtl/sistem/)
#    tb_fsm       : master controller (FSM) + Max Regs (02.11)
#    tb_sru_buyuk : SRU'nun 64 gruplu tamponu (D63, 03.11)
#    tb_pe_blok   : PE sarmalayicisi + Psum FIFO (03.11)
#    tb_pe_birlesik: tek PE (rtl/pe/pe_birlesik.v, 9 MAC, D69), eski sarmalayiciya karsi (final/)
#    tb_veriyolu  : Paket 2: komut yurutucusu + PE motoru + SRU + GMS FIFO + fonksiyon
#                   motoru (CLU dahil) + bellek; ag1 ve ag2'nin bir egitim adimi (03.11)
#    tb_sistem    : Paket 3: tam sistem (FSM + veri yolu); komutlari FSM uretir (03.11)
# -----------------------------------------------------------------------------
#  Kullanim:
#    1) Repo klasorunu bosluk ve Turkce karakter icermeyen bir yola koy,
#       or. C:/ProjeWithOmer-main
#    2) Vivado'yu ac. Acik bir proje varsa kapat (File > Close Project).
#    3) Alttaki Tcl Console'a yaz (ters bolu \ yerine duz bolu / kullan):
#           source C:/ProjeWithOmer-main/rtl/sistem/run_sim.tcl
#  Kullanilan dosyalar: rtl/sistem/ (bu klasor), rtl/sru/ (birlesik SRU, D70), rtl/fe/,
#  rtl/pe/ (pe_birlesik + Egemen'in referans devreleri) ve rtl/clu/; vektorler
#  models/sistem/adim4_vektorleri/
#  Script kendi klasorunde gecici bir proje (vivado_sim/) kurar, testleri sirayla
#  calistirir ve en sonda OZET basligi altinda SONUC satirlarini yazar. Beklenen:
#           BOLUCU: gercek IP (rtl/clu/ip/div_gen_0Z.xci, ...)
#           SONUC tb_fsm: PASS 6206/6206 (3 tur: ag1, ag2, ag1; 4633 komut, 1564 Max Regs olayi)
#           SONUC tb_sru_buyuk: PASS 8508/8508
#           SONUC tb_pe_blok: PASS 380490/380490
#           SONUC tb_pe_birlesik: PASS 80357/80357
#           SONUC tb_veriyolu: PASS 71048/71048
#           SONUC tb_sistem: PASS 21415/21415 (3 tur: ag1, ag2, ag1, aralarinda reset yok)
#  Bolucu IP'si (CLU icin): rtl/clu/ip/div_gen_0Z.xci gecici projeye kopyalanip uretilir. Bulunamaz
#  ya da uretilemezse rtl/clu/sim_model/ altindaki davranissal model kullanilir ve OZET'te yazilir.
#  Yazan: Claude, 02.11.2026 (tb_fsm), 03.11.2026 (diger testler, IP). tb_fsm, tb_sru_buyuk,
#  tb_pe_blok, tb_veriyolu Vivado'da gecti; tb_sistem sahte Vivado komutlariyla ve Icarus ile denendi.
#  (Ekrana yazilan mesajlar, Vivado konsolunda bozuk gorunmesin diye ASCII.)
# =============================================================================

set kok  [file normalize [file dirname [info script]]]
set repo [file dirname [file dirname $kok]]
set vek  "$repo/models/sistem/adim4_vektorleri"
set pdir "$kok/vivado_sim"
set pad  "adim4_sim"

if {[regexp {[^A-Za-z0-9_./:\-]} $repo]} {
    puts "UYARI: Klasor yolunda bosluk ya da Turkce/ozel karakter var: $repo"
    puts "       Vivado bu tur yollarda sorun cikarabilir. Repoyu or. C:/ProjeWithOmer-main altina tasiyin."
}

if {[llength [get_projects -quiet]] > 0} {
    puts "HATA: Acik bir proje var. File > Close Project ile kapatip script'i yeniden calistirin."
    return
}

# Onceki calistirmadan kalan gecici proje silinir (eski simulasyon dosyalari karismasin).
# Silinemezse (or. dosya hala kullanimda) yeni bir klasor adi kullanilir.
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
set rtl {}
foreach ad {master_controller maks_reg pe_sarmalayici psum_fifo pe_motoru grup_fifo bellek \
            komut_yurutucu sistem_veriyolu sistem_ust} {
    lappend rtl "$kok/$ad.v"
}
foreach ad {relu_unit wu_unit fe_top} { lappend rtl "$repo/rtl/fe/$ad.v" }
set rtl [concat $rtl [glob "$repo/rtl/sru/*.v"]]
# PE: pe_birlesik (sistemde, D69) + Egemen'in bes devresi (tb_pe_blok / tb_pe_birlesik referansi); CLU
foreach ad {pe/mac pe/mac_dsp pe/pe_birlesik pe/pe_chain3 pe/pe_fp_s2 \
            pe/pe_bp_s2 pe/pe_wg_s1 pe/pe_wg_s2 clu/max_tree clu/clu_top clu/epu clu/teu \
            clu/adder_tree clu/div_stage_ip} {
    lappend rtl "$repo/rtl/$ad.v"
}
add_files -norecurse $rtl

set davranissal "$repo/rtl/clu/sim_model/div_gen_0Z_davranissal.v"
set bolucu "davranissal model (rtl/clu/sim_model/div_gen_0Z_davranissal.v) - gercek IP bulunamadi"
if {$xci ne ""} {
    # IP gecici projeye kopyalanir; uretilen dosyalar rtl/clu/ip/ klasorune yazilmaz
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

# Calistirilacak testler. Yalnizca bazilarini calistirmak icin script'ten once, or.:
#     set sadece {tb_sistem} ; source C:/ProjeWithOmer-main/rtl/sistem/run_sim.tcl
set testler {tb_fsm tb_sru_buyuk tb_pe_blok tb_pe_birlesik tb_veriyolu tb_sistem}
if {[info exists ::sadece]} { set testler $::sadece }
set ozet [list "BOLUCU: $bolucu"]

# Her test kendi simulasyon kumesinde (sim_<test>) ve kendi klasorunde calisir: bir testin
# derleme/simulasyon dosyalari sonrakine karismaz (03.11: dorduncu testin derleme adimi,
# log'larda hata olmadan USF-XSim-62 verdi; eski klasorde kilitli kalan dosya tahmini).
foreach tb $testler {
    set ss "sim_$tb"
    if {[catch {
        create_fileset -simset $ss
        add_files -fileset $ss -norecurse [list "$kok/$tb.sv"]
        set_property top $tb [get_filesets $ss]
        set_property top_lib xil_defaultlib [get_filesets $ss]
        update_compile_order -fileset $ss
    } hata]} {
        lappend ozet "SONUC $tb: CALISTIRILAMADI (simulasyon kumesi kurulamadi: $hata)"
        continue
    }
    set calisma "$pdir/$pad.sim/$ss/behav/xsim"

    # Eski sonuc dosyalari yaniltmasin
    file delete -force "$vek/sonuc_$tb.txt" "$calisma/sonuc_$tb.txt"

    # 07.11: xsim.*.more_options yalnizca ETKIN simset'te script'lere geciyor (Vivado 2026.1); once etkin yap
    current_fileset -simset [get_filesets $ss]
    # Vektor klasorunu testbench'e +VEKTOR_DIZINI ile ver
    if {[catch {set_property -name {xsim.simulate.xsim.more_options} \
                    -value "-testplusarg VEKTOR_DIZINI=$vek/" \
                    -objects [get_filesets $ss]} hata]} {
        puts "BILGI: plusarg ayarlanamadi ($hata); vektorler calisma klasorunden okunacak."
    }
    # Yedek: vektor dosyalarini (ag2 alt klasoru dahil) XSIM calisma klasorune de kopyala
    file mkdir $calisma
    foreach f [glob -nocomplain "$vek/*.txt"] {
        if {![string match "sonuc_*" [file tail $f]]} { file copy -force $f $calisma }
    }
    file delete -force "$calisma/ag2"
    file copy -force "$vek/ag2" "$calisma/ag2"

    # Simulasyonu $finish'e kadar calistir
    catch {set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets $ss]}
    # D105: mac_dsp'nin davranissal hali (glbl'nin 100 ns GSR'si DSP48E1'in P register'ini ilk hesapta tutar)
    set_property -name {xsim.compile.xvlog.more_options} -value {-d SIM_DAVRANISSAL} -objects [get_filesets $ss]
    if {[catch {launch_simulation -simset $ss} hata]} {
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
    set dsp_ok 0
    foreach g [glob -nocomplain "$calisma/compile.bat" "$calisma/*.prj"] {
        set kanal [open $g r] ; if {[string first SIM_DAVRANISSAL [read $kanal]] >= 0} { set dsp_ok 1 } ; close $kanal
    }
    if {!$dsp_ok} { lappend ozet "UYARI $tb: SIM_DAVRANISSAL derlemeye gecmedi (DSP48E1 primitifi simule edildi)" }
    catch {run all}
    catch {close_sim -force}

    # Sonucu testbench'in yazdigi dosyadan oku, sonra sil
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
