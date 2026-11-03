# Fonksiyon Motoru Golden Modeli — ReLU ve Ağırlık Güncelleme

> **Hazırlayan:** Claude (Ömer'in isteğiyle), 31.10.2026
>
> **Güncelleme (02.11.2026):** SRU-a3 değişti; SRU artık 128'e ulaşan sonucu ±127'ye doyuruyor. Bu klasördeki `sru_golden.py` 02.11 sürümü. `relu.hex` ve `wu_cikarma.hex` değişmedi (ReLU/WU RTL'inin Vivado testi geçerli). `wu_katman.txt`'de yalnızca 1. satırdaki SRU ayar kodu değişti.
>
> **Güncelleme (03.11.2026):** SRU-a3 yeniden "doyma yok" (D59). Bu klasördeki `sru_golden.py` 03.11 sürümü (`DOYMA = False`). Vektörler yeniden üretildi: `relu.hex` ve `wu_cikarma.hex` aynı; `wu_katman.txt`'de yalnızca 1. satır `1 1 0 1` oldu. Gradyan yolunda taşma olmadığı için (|g8| ≤ 2^m_u) değerler değişmedi. Doymasız SRU ReLU'ya −128 verebilir; ReLU birimi −128'i de doğru işliyor (65.536 çiftin hepsi test ediliyor). Aşağıda ±127 doymayı anlatan kısımlar 02.11 hâlidir.
>
> **Kaynak:** Shao vd., ISVLSI 2021 — Fig. 8 ve III-D (s. 258). Shao bu birimlerin yalnızca adını veriyor; davranış, "Shao sessizse NITI" kuralıyla NITI'den alındı: Alg. 1 satır 12–14 ve §3.3 (s. 3252–3253), kod `ti_torch.py` (TiReLU 268–290, UpdateWeight 16–21, grad_calc 135–147, int8_clip 71–72).
>
> **Durum:** Python'da doğrulandı (Bölüm 6). Verilog ile **henüz denenmedi**.

## 0. Kararlar

| Kod | Konu | Seçim | Kim, dayanak |
|---|---|---|---|
| K1 | Pooling birimi | Şimdilik yok | Ömer, 31.10. Shao'nun eğittiği ağda max-pooling yok (IV, s. 258) |
| K2a | Gradyanın SRU hedef genişliği | m_u bit | Ömer, 31.10. Shao sessiz → NITI Alg. 1 satır 13, §3.3 |
| K2b | w − g taşarsa | ±127'ye doyur | Ömer, 31.10. Shao sessiz → NITI `int8_clip` |
| K3 | GMS'in yeri | PE'nin yanı sıra ağırlık güncelleme ve CLU'dan önce de | Claude, Ömer'in "Shao'ya en uygun olanı seç" talimatıyla, 31.10 (gerekçe aşağıda) |

**SRU kararları aynen geçerli:** alt yarı Shao'daki gibi, tek bp makaledeki gibi, SRU'da doyma yok (SRU-a3, 03.11, D59), Δ = G − ℓ, B = `bit_length` (D28). `sru_golden.py` değiştirilmeden kullanıldı; `models/sru/` klasöründeki 03.11 sürümüyle aynı dosya.

**K3'ün gerekçesi:**
- Shao, CLU'nun son katman aktivasyonlarını **tek bir üs** s_a ile aldığını yazıyor (III-C, s. 258). Farklı ölçekte kalan gruplar tek bir s_a ile ifade edilemez.
- GMS'in gerekçesini "birlikte işlenen değerler aynı maksimumla ölçeklenmeli" diye veriyor (III-B, s. 257).
- İki aşamanın PE dizisinin tüm çıkışlarına (g dahil) uygulandığını yazıyor (III-D).
- Harfiyen okuma ("yalnızca PE'ye girerken") g'yi ve CLU'ya giden aktivasyonları GMS'siz bırakır; bu da III-C ile çelişir.

Dosya başlıklarındaki ayar kodları: `wu_katman.txt`'nin 1. satırı SRU kodu **`1 1 0 1`** (03.11; 02.11 sürümünde `1 1 1 1`), 2. satırı FE kodu **`1 1 1`** (hedef = m_u, doyma ±127, GMS ağırlık güncellemeden önce).

## 1. Modellerin yaptığı

**ReLU**
- İleri (FP): a ← max(0, a). Geri (BP): hata yalnızca a > 0 ise geçer; a = 0'da hata 0 olur (NITI: `act > 0`). Ölçek üssü değişmez.
- Maske için ReLU'nun girişi de çıkışı da kullanılabilir; a > 0 ile relu(a) > 0 her değerde aynı. Bu yüzden ek bellek gerekmez: WG için zaten saklanan aktivasyon maske olarak kullanılır.
- Fig. 8'e göre ReLU SRU'dan sonra geliyor. SRU 128'e ulaşan değeri ±127'ye doyurduğu için ReLU'ya −128 gelmez. Örnek: 2040 → LMS → 127 → ReLU → 127 (gerçek değer +127,5).
  - 31.10 sürümünde SRU'da doyma yoktu; aynı değer −128'e sarılıp ReLU'dan 0 çıkıyordu.
  - ReLU birimi −128..127 aralığının tamamında doğru çalıştığı için RTL'de değişiklik gerekmedi.

**Ağırlık güncelleme**
```
g32 (WG çıkışı) → LMS: grup başına ℓ = max(0, B_yerel − m_u)
               → tampon → GMS: Δ = G − ℓ,  G = max(0, B_global − m_u)
               → g8 (|g8| ≤ 2^m_u) → w_yeni = doyur(w − g8, ±127)
```
- Ayrı bir öğrenme oranı yok; adım büyüklüğünü m_u belirliyor. s_w hiç değişmiyor (NITI §3.1, §3.3).
- m_u, modele giriş olarak veriliyor. Hangi epoch'ta kaç olacağı (NITI: 5 → 4 → 3, epoch 100 ve 150) Adım 4'ün yapılandırma işi.
- Shao'daki alt yarı kararının etkisi burada da görülüyor: 18,75 → 18 ve 1,94 → 1. Büyüklük sıfıra doğru yuvarlanıyor.

## 2. Dosyalar

| Dosya | Ne için |
|---|---|
| `fe_golden.py` | Model ve vektör üreteci: `python3 fe_golden.py`. `sru_golden.py` aynı klasörde olmalı. |
| `sru_golden.py` | Teslim edilen SRU modeli (03.11 sürümü), değiştirilmemiş kopya |
| `fe_vektorleri/relu.hex` | ReLU birimi: 65.536 satır, tüm (a, e) çiftleri |
| `fe_vektorleri/wu_cikarma.hex` | Çıkarma + doyma aşaması: 65.536 satır, tüm (w, g8) çiftleri |
| `fe_vektorleri/wu_katman.txt` | Katman düzeyi: m_u hedefli LMS/GMS ve güncelleme, 16 case |
| `fe_vektorleri/OKUNUR.txt` | Örnekler, el kontrolü case'i, doyma örneği |
| `clu_vektor_uret.py` | Fonksiyon motoru üst modülü (`rtl/fe/fe_top.v`) testinin CLU vektörlerini üretir: bu klasörde `python3 clu_vektor_uret.py ../clu/vectors.txt` (D60: en yakına yuvarlama; Egemen'in `golden_model.py`'siyle 1940/1940 aynı) |
| `fe_vektorleri/clu_vektorleri.txt` | 1940 CLU vektörü, satır başına `a0..a9 s_a y e0..e9`; 400'ünde a'da −128 var (D59) |
| `fe_vektorleri/CASE_LISTESI.txt` | Case açıklamaları |

## 3. Önerilen arayüz (başlangıç)

| Birim | Giriş | Çıkış |
|---|---|---|
| ReLU | `a[7:0]`, `e[7:0]` (işaretli), mod (ileri/geri) | `a_out[7:0]` ya da `e_out[7:0]` |
| Çıkarma + doyma | `w[7:0]`, `g8[7:0]` (işaretli) | `w_yeni[7:0]` (−127…127) |
| SRU (gradyan için) | `g32[31:0]`, hedef = m_u | `g8[7:0]` |

RTL ipuçları [Çıkarım]:
- w − g, −255…255 aralığında; 9 bit işaretli fark yeter.
- Egemen'in SRU RTL'inde hedef genişlik 7 olarak sabit yazılmışsa gradyan için bir parametre gerekir. Bu Egemen'in modülü; değiştirmiyoruz, döndüğünde soracağız. **03.11:** Ömer'in kararıyla hedef girişi Egemen'in dosyalarının kopyasına eklendi (`rtl/sru_hedefli/`, D61).

## 4. Dosya biçimleri

`.hex` dosyaları `$readmemh` içindir. Dış döngü ilk alan (a ya da w, −128…127), iç döngü ikinci alan; satır no = (ilk + 128) · 256 + (ikinci + 128).

```
relu.hex       : 32 bit/satır  [31:24] a  [23:16] e  [15:8] relu(a)  [7:0] e_geri
wu_cikarma.hex : 24 bit/satır  [23:16] w  [15:8] g8  [7:0] w_yeni
wu_katman.txt  : 1. satır SRU ayar kodu (4 sayı), 2. satır FE ayar kodu (3 sayı), 3. satır CASE_SAYISI
                 her case : CASE_NO m_u GRUP_SAYISI G B_global
                 her grup : GRUP_NO N M_yerel B_yerel l Δ
                 N satır  : g32 w_eski g8_lms g8 w_yeni
```

`wu_katman.txt`, case 0, açıklamalı:

```
0 5 2 4 9          <- case 0: m_u = 5, 2 grup, G = 4, B_global = 9
0 3 300 9 4 0      <- grup 0: 3 değer, M = 300, B = 9, l = 4, Δ = 0
300 10 18 18 -8    <- g32 = 300 -> LMS 18 (18,75) -> GMS 18 -> w: 10 - 18 = -8
-200 -10 -13 -13 3
50 0 3 3 -3
1 3 31 5 0 4       <- grup 1: M = 31, B = 5, l = 0, Δ = 4
31 5 31 1 4        <- LMS'te aynen geçer, GMS'te 31/16 = 1,94 -> 1 -> w: 5 - 1 = 4
-20 100 -20 -1 101
17 -100 17 1 -101
```

## 5. Testbench önerisi

- **ReLU:** `relu.hex`'in 65.536 satırını oku ve ileri ile geri modu ayrı ayrı karşılaştır. RTL maskeyi saklanan (ReLU sonrası) aktivasyondan alıyorsa a yerine relu(a) ver; beklenen e_geri değişmez.
- **Çıkarma + doyma:** `wu_cikarma.hex`, 65.536 satır.
- **Katman:** g32 değerlerini SRU'ya hedef m_u ile ver ve `g8_lms`'i karşılaştır. Sonra Δ ile GMS'ten geçir ve `g8`'i karşılaştır. En son çıkarma yapıp `w_yeni`'yi karşılaştır.
- Donanımda büyük ihtimalle 16 paralel şerit olur (SRU başına bir). Şerit sayısı RTL'in seçimi; vektörler eleman başına.

## 6. Doğrulama durumu

- **ReLU:** 65.536 çiftin hepsi bağımsız bit düzeyi bir tanımla aynı. Maskenin girişten ya da çıkıştan alınması 256 değerin hepsinde aynı sonucu veriyor.
- **LMS/GMS:** Hedef 7'de, teslim edilen SRU modeliyle birebir aynı (500 rastgele katman).
- **NITI eşdeğerliği:** SRU kararları geçici olarak NITI koduna çevrildi. Bu durumda, tek grupta, NITI'nin ağırlık güncellemesinin saf Python yeniden yazımıyla (`grad_calc` + `PstoShift` + `int8_clip`) birebir aynı: 3000 vaka, m_u = 1…5.
  - Kapsam dışı 1: maksimumu 2'nin kuvveti olan vakalar. D28 gereği B orada 1 bit farklı.
  - Kapsam dışı 2: 2^24'ün üstündeki değerler. NITI kodu maksimumu float32'ye çevirdiği için orada 1 bit sapabiliyor [Çıkarım: ti_torch.py 373].
- **Katman:** 500 rastgele katmanda:
  - |g8| ≤ 2^m_u
  - işaret korunuyor
  - g8, g32 / 2^G'ye en fazla 2 LSB uzak (tüm gruplar tek ölçekte)
  - w, −127…127 aralığında
- **Geri okuma:** Dosyalar geri okunup yeniden hesaplandı; 65.536 + 65.536 + 558 değerin hepsi tuttu.
- **Mutasyon testi:** Bilerek sokulan 11 hatanın 11'i yakalandı. Örnekler: ReLU'da `>= 0`, hedefin hep 7 olması, GMS'in atlanması, doymanın kaldırılması, w + g, yanlış ℓ, B_global = min, işaretli maksimum, −128'e izin.
- **Verilog ile test edilmedi.**

## 7. DEVIATIONS.md için hazır kayıtlar

D numaralarını siz verin (Egemen D28'e kadar kullanmış görünüyor).

**D__ — Pooling birimi şimdilik yok**
- **Ne:** Fig. 8'deki Pooling birimi gerçeklenmiyor.
- **Neden:** Shao'nun donanımda eğittiği VGG16-benzeri ağda max-pooling, stride-2 conv ile değiştirilmiş.
- **Kanıt:** Shao IV, s. 258. Son havuzlamanın (ardından FC geldiği için) kalıp kalmadığı yazmıyor.
- **Durum:** Ertelendi. FSM'de pool fazına yer bırakılacak.

**D__ — Gradyanın SRU hedef genişliği m_u**
- **Ne:** g32, B − m_u bit kaydırılıp yuvarlanır. Sonuçta en fazla m_u bitlik bir güncelleme kalır.
- **Neden:** Shao yazmıyor; kural gereği NITI.
- **Kanıt:** NITI Alg. 1 satır 13, §3.3 (s. 3253); kodda grad_calc. Shao III-D: tüm PE çıkışları SRU'dan geçer.
- **Durum:** Kesin. m_u takvimi Adım 4'te.

**D__ — Ağırlık güncellemesinde ±127 doyma**
- **Ne:** w − g sonucu −127…127 aralığına kırpılır.
- **Neden:** Shao yazmıyor; kural gereği NITI. 8 bitte sarma, ağırlığın işaretini çevirirdi.
- **Kanıt:** NITI `ti_torch.py` 21 ve 71–72 (`int8_clip`).
- **Durum:** Kesin.

**D__ — GMS, PE dışındaki tüketicilerden (ağırlık güncelleme, CLU) önce de uygulanır**
- **Ne:** Katman çıktısı, kim kullanırsa kullansın, GMS'ten geçmiş olarak kullanılır.
- **Neden:** Shao GMS'i yalnızca PE girişi için anlatıyor; ağırlık güncelleme ve CLU için sessiz.
- **Kanıt:** Shao III-C (CLU tek s_a alır), III-B (GMS'in gerekçesi), III-D (tüm PE çıkışları SRU'dan geçer).
- **Durum:** Seçildi (Ömer'in talimatıyla Claude). CLU RTL'i değişmez; son katman çıkışını GMS'ten geçirmek FSM'in işi.

## 8. Adım 4'e kalanlar

- m_u takvimi (Shao sessiz → NITI: 5 → 4 → 3, epoch 100 ve 150): FSM'in yapılandırmasında olacak.
- Güncellenen ağırlığın ağırlık tamponuna yazma yolu Fig. 8'de çizilmemiş (K6).
- Egemen'in SRU RTL'inde hedef genişlik parametresi olup olmadığı.
- CLU'ya giden son katman aktivasyonlarının GMS'ten geçirilmesi (K3'ün sonucu).
