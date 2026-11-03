# ProjeWithOmer
KNK DEVIATIONS VE TASKS BURAYA

## Güncel durum (03.11.2026)
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
- Sırada (5b): grup kurulumu + 16 SRU bağlantısı, çok bankalı tamponlar, ön-getirme, dizi kontrolü, yeni golden.

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
