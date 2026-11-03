# SRU Golden Model — Testbench Kullanım Notu

> **Hazırlayan:** Claude (Ömer'in isteğiyle), 28.10.2026
>
> **Güncelleme (02.11.2026):** SRU-a3 değişti: 128'e ulaşan sonuç artık ±127'ye doyuruluyor (D9, NITI `int8_clip`). Ayar kodu `1 1 0 1` → `1 1 1 1`. Değişen vektörler yalnızca taşma satırları (Bölüm 1).
>
> **Güncelleme (03.11.2026):** SRU-a3 yeniden "doyma yok" (Ömer, makaleye sadakat; D59). `sru_golden.py`'de `DOYMA = False`; ayar kodu yine `1 1 0 1`. Üretilen `sru_bm.txt`, `sru_yuvarla.txt` ve `sru_katman.txt`, 28.10 sürümüyle ve Egemen'in repodaki dosyalarıyla birebir aynı (03.11'de `cmp` ile kontrol edildi). Bu notta ±127 doymayı anlatan kısımlar 02.11 hâlidir; `DOYMA = True` yapılırsa o davranış geri gelir.
>
> **Kaynak:** Shao vd., ISVLSI 2021 — II-B-1 (s. 255), Algoritma 1 (s. 256), III-B ve Fig. 6 (s. 257), Fig. 8 (s. 258). Hakem: NITI, IEEE TPDS 2022 — 3.2, 3.4, Alg. 1–3 (s. 3252–3254).
>
> **Durum:** Python'da doğrulandı (Bölüm 6). Verilog/XSIM ile **henüz denenmedi**.

## 0. Kararlar (vektörler bunlarla üretildi)

| Kod | Konu | Seçim | Karar |
|---|---|---|---|
| SRU-a1 | Alg. 1 satır 6, alt yarı aralığı | Shao'daki gibi: f[bp/2, 0] | Ömer, 28.10 |
| SRU-a2 | bp tek olunca | Makaledeki gibi: f'nin en alt biti atılır, bp − 1 ile devam edilir | Ömer, 28.10 |
| SRU-a3 | 127 + 1 = 128 olursa | ±127'ye doyurulur: +128 → 127, −128 → −127. Dayanak: D9 (int8 simetrik, −127..127); Shao bu durumu tanımlamıyor; NITI kodu üç yuvarlama fonksiyonunda da `int8_clip` ile ±127'ye kırpıyor | **03.11: doyurulmaz** (8 bitte sarılır, +128 → −128; Shao Alg. 1'de kırpma adımı yok, makaleye sadakat; D59). Soldaki ±127 hâli 02.11 kararıydı (D38), `DOYMA = True` ile geri gelir |
| SRU-a5 | Bit genişliği B(m) | `bit_length()`: m'yi temsil eden en az bit (m = 0 → 0) | Egemen tarafı, D28 |
| SRU-a8 | GMS kaydırma miktarı | Δ = G − ℓ (kaydırma miktarlarının farkı) | Ömer, 28.10 |

`sru_yuvarla.txt` ve `sru_katman.txt`'nin ilk satırı bu kararların kodudur: **`1 1 0 1`** (alt_yari = shao, tek_bp = makale, doyma = yok, gms = fark; 03.11). Testbench bunu okuyup yazdırırsa yanlış sürüm dosyayla test yapılmaz. 02.11 sürümünün kodu `1 1 1 1` idi.

**D28 için bir düzeltme:** `bit_length` tanımı Shao'dan değil, NITI makalesinden geliyor (Bölüm 3.2, s. 3253: "maksimum değeri tam temsil için gereken en az bit"). Shao formül vermiyor, yalnızca "en büyük etkin bit genişliği" diyor. D28'in kanıt alanına bunu yazın.

**Kaynaktan gelen ya da açık bırakılan noktalar:**

| Kod | Modeldeki hâli | Dayanak |
|---|---|---|
| SRU-a4 | bp = max(0, B − 7) | NITI Alg. 1 satır 4 (s. 3252) |
| SRU-a6 | Maksimum = mutlak değerlerin en büyüğü | NITI kodu `torch.max(torch.abs(...))`; işaretli maksimum negatif ağırlıklı veride yanlış ölçek verir |
| SRU-a7 | "Grup" tanımı **açık** | Model kendisine verilen listeyi grup sayar; vektörlerde gruplar açıkça yazılı (boy 1–16) |
| SRU-a9 | Ölçek üssü: s_çıkış = s_giriş + G | NITI Alg. 2 satır 1; vektörlerde G var |
| SRU-a10 | a ve e için yuvarlama Alg. 1 | Shao II-B-1 (s. 255) |
| SRU-a12 | Hedef genişlik 7 (a ve e) | g (WG çıkışı) SRU'dan geçecekse m_u ile ayrı vektör gerekir; **açık** |

## 1. Bu kararların sonuçları

Bilerek seçildi. Ancak RTL'i ve sonraki eğitim sonuçlarını etkiler; bilinmesi gerekiyor.

- **±127 doyma:** Rastgele değerlerin %0,30'unda yuvarlama 128'e ulaşıyor (200.000 rastgele pozitif int32 değer, bp kendi B'sinden hesaplandı). Bu değerler 127'ye doyuruluyor; hata en fazla 1 LSB.
  - Örnek (katman case 5): 2040 → LMS'te 128 → 127 → GMS'ten sonra 63. Doğrusu ≈ 63,75.
  - Doyma olmayan 28.10 sürümünde aynı değer 8 bitte −128'e sarılıyor, GMS'ten sonra −64 çıkıyordu. Sistem düzeyinde bu, grubun en büyük değerinin işaret değiştirmesi demek. 200'er rastgele eğitim adımında aktivasyon sapması %10'u aşan adımların oranı:
    - doyma yokken: ag1'de %7, ag2'de %18,5
    - doymayla: hiç yok

    Ayrıntı: Adım 4, `TASARIM_FSM.md` Bölüm 10.
- **Shao'daki alt yarı aralığı:** Yuvarlama aşağı yönde sapıyor. Rastgele değerlerde yukarı yuvarlama oranı %18,9, ortalama hata −0,27 LSB. NITI aralığında bu hata bp = 8 için yaklaşık −0,03 LSB. bp = 2'de hiç yukarı yuvarlamıyor (0…4095 aralığının tamamı denendi).
- **İki aşama ≠ tek aşama:** Gruplar farklı ölçekteyse değerlerin %7,1'i tek aşamalı (global) ölçeklemeden 1 LSB farklı çıkıyor (en fazla 1). Ölçüm 3000 rastgele katmanla yapıldı, her katmanda 2–8 grup × 16 değer vardı. Tüm gruplar aynı B'deyse sonuç birebir aynı.
- **Bir kararı değiştirmek** için `sru_golden.py`'nin başındaki dört satırı düzenleyip betiği yeniden çalıştırmak yeter; vektörler yeniden üretilir.

## 2. Dosyalar

| Dosya | Hangi RTL birimi için |
|---|---|
| `sru_golden.py` | Model ve vektör üreteci. `python3 sru_golden.py`; ek kütüphane gerekmez. |
| `sru_vektorleri/sru_bm.txt`, `sru_bm.hex` | B(m) birimi (öncelik kodlayıcı); Egemen'in "A seçeneği" |
| `sru_vektorleri/sru_yuvarla.txt`, `sru_yuvarla.hex` | Alg. 1 yuvarlama birimi (`stochastic_round.v`) |
| `sru_vektorleri/sru_katman.txt` | LMS + GMS (`lms.v`, `gms.v`, `sru_top.v`) |
| `sru_vektorleri/OKUNUR.txt` | Alg. 1'in adım adım dökümü ve katman case 0 tablosu |
| `sru_vektorleri/CASE_LISTESI.txt` | Katman case'lerinin açıklaması |

**Uyarı:** "Vivado kurulumu" sohbetinde üretilen `psto_vektorleri.hex` başka kurallarla üretildi: NITI kodunun tek-bp yöntemi ve NITI alt yarı aralığı (±127 kırpma artık ortak). Bu dosyalarla aynı 48 bitlik biçimde olduğu için karıştırılabilir; **onu kullanmayın**.

## 3. Önerilen arayüz (başlangıç; Egemen'le birlikte netleştirin)

| Birim | Giriş | Çıkış |
|---|---|---|
| B(m) | `m[31:0]` işaretsiz (en fazla 2^31) | `B[5:0]` (0…32) |
| Yuvarlama | `q32[31:0]` işaretli, `bp[4:0]` (0…25) | `q8[7:0]` işaretli; isteğe bağlı `tasma` |
| LMS | grubun int32 değerleri | int8 değerler; ayrıca M_yerel, B_yerel ve ℓ |
| GMS | tampondaki int8 değer, Δ | int8 |

İki RTL ipucu [Çıkarım]:
- |−2^31| = 2^31 işaretsiz 32 bite sığıyor, fakat bp = 25'te `[bp+7 : bp]` dilimi 32. bite uzanıyor. Büyüklüğü 33 bit (`{1'b0, mutlak}`) tutarsanız dilim taşmaz.
- B monoton olduğu için B(global maksimum) = yerel B'lerin en büyüğü. Max Regs'te 32 bitlik maksimum yerine 6 bitlik B saklamak aynı sonucu verir (SRU-a13). Adım 4'te Shao'ya uymak için 32 bitlik yerel maksimum seçildi (T4, Ömer 02.11).
- ±127 doyma, Alg. 1'deki gibi işaret-büyüklükle çalışılırken işaret uygulanmadan önce tek satır: `q_doy[6:0] = q[6:0] | {7{q[7]}}`. q en fazla 128 olabildiği için bu, min(q, 127) ile aynı (q = 0…128 için tek tek denendi).

## 4. Dosya biçimleri

Ondalık dosyalarda yalnızca tamsayılar var. Boşluk ve satır sonu fark etmez; `$fscanf(fd, "%d", x)` ile sırayla okunur. Hex dosyaları `$readmemh` içindir; satır başına bir kelime, yorum yok.

```
sru_bm.txt      : N, sonra N satır: m B
sru_bm.hex      : satır başına 40 bit: [39:8] m, [7:0] B
sru_yuvarla.txt : 1. satır ayar kodu (4 sayı), 2. satır N,
                  sonra N satır: q32 bp beklenen_q8 tasma
sru_yuvarla.hex : satır başına 48 bit: [47:16] q32 (ikiye tümleyen), [15:8] bp, [7:0] beklenen q8
sru_katman.txt  : 1. satır ayar kodu, 2. satır CASE_SAYISI
                  her case : CASE_NO GRUP_SAYISI G B_global
                  her grup : GRUP_NO N M_yerel B_yerel l Δ
                  N satır  : x32 lms8 lms_tasma gms8 gms_tasma
```

`sru_katman.txt`'nin başı (case 0), açıklamalı:

```
1 1 0 1        <- ayar kodu
12             <- 12 case
0 2 2 9        <- case 0: 2 grup, G = 2, B_global = 9
0 3 300 9 2 0  <- grup 0: 3 değer, M = 300, B = 9, l = 2, Δ = 0
300 75 0 75 0  <- x = 300 -> LMS 75 -> GMS 75 (taşma yok)
-200 -50 0 -50 0
50 12 0 12 0
1 3 31 5 0 2   <- grup 1: 3 değer, M = 31, B = 5, l = 0, Δ = 2
31 31 0 7 0    <- LMS'te aynen geçer, GMS'te 31/4 = 7,75 -> 7
-20 -20 0 -5 0
17 17 0 4 0
```

## 5. Testbench önerisi

- **Yuvarlama birimi:** `sru_yuvarla.hex`'i `$readmemh` ile oku, her satırda q32 ve bp'yi sür, q8'i karşılaştır. RTL'de taşma çıkışı yoksa `.txt`'deki 4. sütunu yok say.
- **B(m):** `sru_bm.hex` ile aynı şekilde.
- **LMS:** Grubun değerlerini ver, `lms8` sütunuyla karşılaştır. RTL ℓ'yi kendisi hesaplıyorsa M_yerel, B_yerel ve ℓ'yi de karşılaştır.
- **GMS:** `lms8` sütununu ve Δ'yı ver, `gms8` ile karşılaştır.
- **sru_top:** Tüm grupları sırayla ver; G'yi ve `gms8`'i karşılaştır.
- Taşma vakaları (`tasma = 1`) bilerek var: `sru_yuvarla`'da 48 satır (25'i +127, 23'ü −127), `sru_katman`'da 1 değer. Bu satırlarda beklenen değer 8 bitte sarılmış sonuçtur (+128 → −128; 03.11, D59); `tasma` sütunu taşmanın olduğunu gösterir.

## 6. Doğrulama durumu

- **B(m):** 0…2^20 aralığının tamamında ve 2^20…2^31 arasındaki 2'nin kuvvetlerinin çevresinde, metin tabanlı ayrı bir hesapla aynı.
- **Alg. 1:** bp = 0…25 için, her bp'de 4000 rastgele değerle, makaleyi satır satır bit aralıklarıyla izleyen ayrı bir uygulamayla aynı.
- **Parametre yolu:** Kararlar NITI koduna çevrilince sonuç NITI `PstoShift` ile birebir aynı (bp = 1…25, her birinde 2000 değer).
- **Katman:** 400 rastgele katman ve 12 vektör case'i denendi.
  - Her aşama, bağımsız hesaplanan ℓ, G ve Δ ile satır satır Alg. 1'den yeniden üretildi.
  - Taşma olmayan her çıkış gerçek değere (x / 2^G) 2 LSB'den yakın.
  - Tüm gruplar aynı B'deyse iki aşama tek aşamayla aynı.
- **Dosya geri okuma:** Dosyalar geri okunup yeniden hesaplandı; 154 B(m), 2297 yuvarlama ve 538 katman değerinin hepsi tuttu.
- **Mutasyon testi:** Modele bilerek sokulan 11 anlamlı hatanın 11'i de yakalandı. Bir mutasyon davranışı hiç değiştirmediği için sayılmadı.
  - 02.11'de doyma mantığı için ayrıca 6 hata denendi (asimetrik aralık, tek taraflı doyma, sınır 126, doymanın uygulanmaması, taşma bayrağının yanlış yerde hesaplanması); 6'sı da yakalandı.
- **Verilog ile test edilmedi.**

## 7. Açık kalanlar (D adayı)

- **SRU-a7 — "grup" tanımı:** Bir PE satırının mı, tüm dizinin mi bir geçişteki çıktıları? Fig. 8'de SRU satır başına çizilmiş.
- **SRU-a12 — gradyanlar (g):** 31.10'da K2a ile kapandı: hedef m_u (NITI). Bu yolda taşma olamıyor (m_u ≤ 6).
- **SRU-a13 — Max Regs içeriği:** 32 bitlik maksimum mu, 6 bitlik B mi? İkisi aynı sonucu verir. 02.11'de T4 ile kapandı: 32 bitlik yerel maksimum (Shao Fig. 6).
- **SRU-a14 — küçük Δ:** Δ = 1 ve 2'de Alg. 1 neredeyse kesme gibi davranıyor. Shao'daki alt yarı aralığıyla Δ = 2'de hiç yukarı yuvarlamıyor.
