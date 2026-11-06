# ProjeWithOmer
KNK DEVIATIONS VE TASKS BURAYA

## Güncel durum (06.11.2026)
- **Donanım (`final/rtl/dizi/`):** Shao'nun 16×16 dizili sistemi; 6 test ağında (ag1–ag6) golden'la bit bit aynı
  (`tb_sistem_dizi` 65.142/65.142, 419.000 çevrim). VGG ölçeği parametreler (512 kanal, batch 256, 15 katman, D103).
- **Donanımlaştırma (Adım 5c, D94–D107):** döngü sırası, register'lı komut sabitleri, sayaçlı adresler, satır başına
  line buffer, BP s2 çıkışları PE FIFO'sunda, tek GMS takımı, bank tarafında yazma, gereksiz sıfırlama kapıları yok,
  MAC seçicisi DSP48E1'de, pipeline aşaması.
- **Sentez (VC709, 200 MHz hedefi, 07.11):** toplam LUT 436.340 (%100,7; Shao 171.248), RAMB36 824 (Shao 896), DSP
  2.354 (Shao 2.324). WNS −11,85 ns (~59 MHz; en kötü yol CLU → bölücü). Güç ≈ 24,3 W (vektörsüz tahmin; Shao 16,27).
  Etkin 54,4 GOPS (D108; Shao 771). Ayrıntı: DEVIATIONS D107 "Faz 4 ölçümü", `final/SONUCLAR.md`.
- **CIFAR-10 (Fig. 9, `final/models/cifar/`):** çerçeve NITI'nin kendi ağında doğrulandı (vggsmall7, 30 epoch test
  %76,5). VGG16-like (D101, tamamen konvolüsyonel) 200 epoch: test %21,6 (Shao ~%88); VGG16 referansı koşulmadı.
- **Testler:** `final/rtl/dizi/run_sim.tcl` (6 test), `final/rtl/sistem/run_sim.tcl` (Adım 4, 6 test),
  `final/rtl/pe/run_sim.tcl`. Simülasyonda DSP için davranışsal model (`SIM_DAVRANISSAL`, D105).

## Önceki durum (03.11.2026)
- **Hazır ve Vivado'da doğrulandı:** PE (6 mod), SRU, CLU, ReLU, Weight Update, fonksiyon motoru (ReLU + WU + CLU), Master Controller (FSM) ve tam sistem entegrasyonu.
- **Tam sistem:** FSM, komutları kendisi üreterek iki test ağının birer eğitim adımını (FP + CLU + BP + WG + ağırlık güncelleme) baştan sona çalıştırıyor. Sonuçlar golden modelle bit bit aynı.
- **Kapsam dışı:** Pooling (D39).
- **Sırada (Adım 5):** 16×16 PE dizisi, çok bankalı tamponlar, boru hattı.

## `final/` (03.11.2026 akşamı, Adım 5'in tabanı)
Güncel tasarım `final/` altında. Eski `rtl/` ve `models/` karşılaştırma için değişmeden duruyor.
- **Tek PE (D69):** `final/rtl/pe/pe_birlesik.v`. Shao Fig. 2'deki gibi 9 MAC ile 6 mod; eski sarmalayıcı 5 devre ve 45 MAC'ti. Sentezde LUT 5127 → 1445.
- **Tek SRU (D70):** `final/rtl/sru/` (hedef girişi + 64 grup). `rtl/sru_hedefli/` ve `rtl/sru_64/` kopyaları `final/`'de yok.
- **Düzeltmeler:** D68 (`stochastic_round` latch), D71 (LMS'te |−2^31|).
- **Yeni `run_sim.tcl`'ler:** `final/rtl/pe/`, `final/rtl/sru/`, `final/rtl/clu/`.
- **Doğrulama:** `final/rtl/` altındaki beş `run_sim.tcl` (sistem, pe, sru, clu, fe) Vivado'da gerçek bölücü IP'siyle PASS (04.11).

## Adım 5a: 16×16 PE dizisi (04.11.2026)
- `final/rtl/dizi/pe_dizi.v`: 256 `pe_birlesik`; satır aynı girişi, sütun aynı ağırlığı paylaşıyor (Shao III-D, Fig. 8). Psum FIFO her PE'nin içinde (D74), MAC'ler DSP'de (D75).
- Açılım kararları: FP/BP'de satırlara çıkış satırı (D72), WG'de giriş kanalı (D73, Shao'ya sorulabilecek açık soru).
- Doğrulama: `tb_pe_dizi` 2.363.392/2.363.392 (XSIM CLI), 7 mutasyonun 7'si yakalandı. Sentez: DSP 2304, LUT 243.689.

## Adım 5b: 16×16 dizili tam sistem (04.11.2026)
- Fig. 8'in bütün blokları RTL'de: FSM (`master_controller_dizi`), dizi motoru (ön-getirme + dizi + 16 SRU'nun LMS'i), çok bankalı veri ve ağırlık tamponları, GMS ön-getirmede (Fig. 6), CLU ve WU. Tasarım: `final/rtl/dizi/TASARIM_DIZI.md`; kararlar D76–D93.
- Golden: `final/models/sistem/dizi_golden.py`, `dizi_sistem_golden.py` (4 test ağı, `adim5_vektorleri/`).
- Doğrulama (XSIM CLI): tam sistem bir eğitim adımını kendi FSM'iyle koşturuyor, sonuç golden'la bit bit aynı (`tb_sistem_dizi` 4829/4829). ag1'de eğitim adımı 2448 çevrim (Adım 4'te 25.434). Bütün testler: `final/rtl/dizi/run_sim.tcl`.
- Sırada: sentez/timing/güç (Table I/II karşılığı), CIFAR-10 deneyi (Fig. 9 karşılığı, `final/models/cifar/`).

Kararlar ve makaleden sapmalar: `DEVIATIONS.md`

## Klasörler
| Klasör | İçerik |
|---|---|
| `rtl/pe/`, `rtl/sru/`, `rtl/clu/` | PE, SRU, CLU (CLU'nun bölücü IP'si `rtl/clu/ip/`) |
| `rtl/fe/` | Fonksiyon motoru: ReLU, Weight Update, `fe_top` (Adım 3) |
| `rtl/sru_hedefli/`, `rtl/sru_64/` | SRU'nun hedef girişli (D61) ve 64 gruplu (D63) kopyaları |
| `rtl/clu_yuvarlama/` | CLU çıkışı için stokastik yuvarlama birimi (D57, şu an kullanılmıyor) |
| `rtl/sistem/` | Master Controller (FSM), komut yürütücüsü, PE motoru, bellek, üst modül ve tam sistem testleri (Adım 4) |
| `models/` | Python golden modelleri ve test vektörleri (`models/sistem/`: tam sistem) |

Her `rtl/` klasöründeki `run_sim.tcl` o klasörün testlerini Vivado'da çalıştırır, örneğin:
`source C:/ProjeWithOmer-main/rtl/sistem/run_sim.tcl`
