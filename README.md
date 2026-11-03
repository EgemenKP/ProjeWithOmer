# ProjeWithOmer
KNK DEVIATIONS VE TASKS BURAYA

## Güncel durum (03.11.2026)
- **Hazır ve Vivado'da doğrulandı:** PE (6 mod), SRU, CLU, ReLU, Weight Update, fonksiyon motoru (ReLU + WU + CLU), Master Controller (FSM) ve tam sistem entegrasyonu.
- **Tam sistem:** FSM, komutları kendisi üreterek iki test ağının birer eğitim adımını (FP + CLU + BP + WG + ağırlık güncelleme) baştan sona çalıştırıyor. Sonuçlar golden modelle bit bit aynı.
- **Kapsam dışı:** Pooling (D39).
- **Sırada (Adım 5):** 16×16 PE dizisi, çok bankalı tamponlar, boru hattı.

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
