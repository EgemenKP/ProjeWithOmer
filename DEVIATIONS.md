# Tasarım Kararları ve Makaleden Sapmalar — Shao/NITI Verilog Gerçeklemesi

## Bu dosyayı nasıl kullanmalısın (Claude için talimat)

**Eğer bu projede Claude ile çalışıyorsan (Ömer Faruk dahil), yeni bir blok
veya açık nokta üzerinde çalışmaya başlamadan ÖNCE bu dosyanın tamamını oku.**
Burada kayıtlı her karar, iki kişinin (Egemen + Ömer Faruk) ayrı ayrı PDF'leri
(Shao ISVLSI 2021, NITI TPDS 2022), NITI'nin gerçek GitHub koduna
(github.com/wangmaolin/niti) ve birbirinin bağımsız RTL/golden-model
çıktılarına karşı **çapraz doğruladığı** sonuçlardır. Amaç: aynı soruyu
sıfırdan tekrar sormamak, zaten verilmiş bir kararı farkında olmadan tersine
çevirmemek, ve makaleye sadakat önceliğini (aşağıda) bozmamak.

**Öncelik sırası (çakışmada):** 1) Bu dosyadaki kesinleşmiş karar; 2) Shao'nun
kendi metni/şekli (makale numarası ve sayfa verilmiş); 3) NITI yalnızca
Shao'nun sessiz kaldığı ya da kendi içinde çeliştiği yerlerde **hakem**
olarak kullanılır, asla doğrudan tasarım kaynağı değil; 4) açık/karara
bağlanmamış noktalarda mühendislik tercihi, D-numarasıyla işaretlenip burada
kayda geçirilir.

**Yeni bir D maddesi eklerken:** Sıradaki boş numaradan devam et (şu an
**D38**), asla eskisini silme veya numarayı tekrar kullanma — eski bir D
kapandıysa bile tarihi referans olarak dursun. Her madde: **ne, neden/kanıt,
durum**. Kanıt seviyesini etiketle: `[PDF tam]` (makale metninden doğrudan),
`[PDF şekil]` (yalnızca şekilden, daha zayıf), `[NITI GitHub]` (kod
referansı, dosya adı + satır belirt), `[Ölçüldü]` (bir kontrol betiğiyle
sayısal olarak doğrulanmış), `[Çıkarım]` (hiçbir kaynağa dayanmayan mühendislik
tercihi), `[Varsayım]` (geçici, netleşmemiş).

---

## Güncel durum (özet tablo)

| Blok | RTL durumu | Test durumu | Dosyalar |
|---|---|---|---|
| **CLU** | Tamamlandı | 40/40, Vivado'da doğrulandı | `rtl/clu/` |
| **PE** (6 mod) | Tamamlandı | 138/138, Vivado'da doğrulandı, Ömer Faruk'un `pe_golden.py`'siyle bağımsız çapraz doğrulandı | `rtl/pe/` |
| **SRU** (tek kanal) | Tamamlandı | 154+2297+52+12, Vivado'da doğrulandı | `rtl/sru/` |
| **SRU** (16 paralel) | Tamamlandı | 12/12 (kendi test senaryomuz), Vivado'da doğrulandı | `rtl/sru/sru_array.v` |
| ReLU/Pooling/Weight Update | Başlanmadı | — | Ömer Faruk'ta |
| Master Controller | Başlanmadı | — | Ömer Faruk'ta |
| Tam sistem entegrasyonu | Başlanmadı | — | İkisi birlikte, en son |

---

## CLU (Cross-Entropy Loss Unit)

### D1 — gi = 2^ai - 1 (-1 dahil)
- **Ne:** Algoritma 2 satır 4'teki gi=2^ai-1 formülündeki "-1" terimi.
- **Neden karar gerekti:** Fig. 7'nin donanım şemasında (`1<<` bloğu) bu
  -1 hiç görünmüyor, sadece Algoritma 2'nin metninde var.
- **Kanıt:** Hem Shao'nun Algoritma 2'si HEM DE NITI'nin gerçek GitHub
  kodu (`ti_loss.py`: `out_grad = 2**s-1`) -1'i içeriyor. Yalnızca
  NITI'nin makale metnindeki (basitleştirilmiş) türetim -1'i atlıyor.
- **Durum:** Kesinleşti, -1 dahil edildi.

### D2 — EPU'nun Shift Unit'i iki yönlü
- **Ne:** EPU içindeki kaydırma biriminin s_a'nın işaretine göre hem
  sola hem sağa kayabilmesi.
- **Kanıt:** `[NITI GitHub]` `ti_loss.py` (satır ~15-18, `TiLoss.forward`
  içinde): `if out_exp>=0: s=s*2**out_exp else: s=s/(2**-out_exp)`.
- **Durum:** Kesinleşti.

### D3 — TEU kanal başına ayrı örnek (paylaşımlı değil)
- **Ne:** Fig. 7'de TEU'nun N kere mi çizildiği, yoksa zaman-paylaşımlı
  tek bir TEU mu olduğu.
- **Kanıt:** `[PDF şekil]` Fig. 7'de TEU, EPU ile AYNI çizim kuralıyla
  (N kez stacklenmiş) gösterilmiş.
- **Durum:** Kesinleşti, N ayrı örnek.

### D4 — EPU'da log2(e) yaklasik 184/2^7 (Algoritma 2'nin 47274/2^15'i DEĞİL)
- **Ne:** log2(e) sabiti için iki farklı değer: Algoritma 2 metninde
  47274/2^15, Fig. 7'nin donanım bloğunda 184/2^7.
- **Neden:** Makalenin KENDİ İÇİNDE bir tutarsızlığı — iki değer
  farklı hassasiyette (184/128=1.4375 vs 47274/32768≈1.4426,
  gerçek değer ≈1.4427).
- **Durum:** Donanım şemasına (Fig.7) sadık kalındı, 184/2^7 kullanıldı
  `[PDF tam + PDF şekil]`.

### D5 — Son >>4 kaydırma + int8 kırpma (Shao'da çizilmemiş) — AÇIK, Shao'ya mail atıldı
- **Ne:** CLU çıkışının (e_i) son mux'tan sonra hâlâ ~12-bit (±2048
  civarı) olması, int8'e (-127..127) hiç indirgenmemesi.
- **Kanıt:** `[NITI GitHub]` son adım `StoShift(out_grad, 4)` + int8 clip
  var, ama Fig. 7'nin son mux'ından direkt e_i çıkıyor, ara blok yok.
  `[PDF tam]` Shao'nun metninde "CLU yazılımla aynı sonucu veriyor" cümlesi
  de bu adımın bir yerde olması gerektiğini destekliyor.
- **Durum:** EKLENDİ ama **HENÜZ KESİNLEŞMEDİ** — Shao'ya mail atıldı
  (hkshao@smail.nju.edu.cn), cevap bekleniyor. SRU'dan geçmediği `[PDF tam]`
  Fig.8 + metninden kesin (SRU yalnızca PE çıktıları için, bkz. D30).

### D6 — N (sınıf sayısı) = 10, sabit
- **Ne:** CIFAR-10 için N=10, henüz parametrik değil. `[Varsayım]`

### D7 — Bölmede yuvarlama yok (truncate)
- **Ne:** `(gi<<11)/sum1` bölme işleminin yuvarlama davranışı.
- **Neden:** Makalede bu bölme için ayrı bir yuvarlama şeması belirtilmiyor.
- **Durum:** `[Varsayım]`, düz bölme (aşağı yuvarlama) kullanıldı.

### D8 — Son kaydırmada stokastik değil, düz yuvarlama — AÇIK
- **Ne:** D5'teki son >>4 kaydırmanın yuvarlama tipi.
- **Kanıt:** `[NITI GitHub]` `ti_loss.py` satır 35: `StoShift(out_grad.type(torch.int32), 4)`,
  ve `StoShift` (`ti_torch.py`) içinde `torch.randint(...)` ile **gerçek
  rastgele sayı** üretiliyor — Algoritma 1/3'teki deterministik, bit-tabanlı
  `PstoShift` DEĞİL. İkisi tamamen farklı mekanizma, karıştırılmamalı.
- **Kapatma seçenekleri (karar bekliyor):**
  - (a) En-yakına yuvarlama kalsın (şimdiki basitleştirme, uygulanan)
  - (b) Algoritma 1 (deterministik, `stochastic_round.v` ile aynı) kullanılsın
    — donanım dostu ama NITI'nin gerçek loss kodundan (StoShift) ayrı bir
    sapma olur
  - (c) Gerçek stokastik (LFSR tabanlı) yuvarlama — NITI'ye en sadık ama
    Python/RTL'in aynı LFSR'yi aynı tohumla kullanması gerekir (zor)
- **Durum:** (a) ile devam ediliyor. SRU'da Algoritma 1 ayrı bir yerde zaten
  var ama CLU'nun D8'ini otomatik çözmüyor (CLU çıkışı SRU'dan geçmiyor, D30).

### D9 — int8 aralığı simetrik: -127..127 (-128 değil)
- **Kanıt:** `[NITI GitHub]` NITI metni açıkça "±127" doyma ve "a_i<=127" diyor.
- **Durum:** Kesinleşti.

---

## PE (Processing Element) — 6 mod, tamamlandı

### Doğrulanan (varsayım değil): PE'nin temel yapısı
- **Kanıt:** `[PDF tam]` s.256: "nine multiply-accumulate units (MACs),
  several multiplexers, and a partial sum (Psum) FIFO queue". 9 MAC, 3x3
  dizilim. **Not:** Projenin erken bir aşamasında bu yanlışlıkla "3 MAC, 4
  mux, Psum regfile" olarak yazılmıştı — bu, SiPS 2020 öncül makalesinin
  (farklı makale, "A Reconfigurable DNN Training Accelerator on FPGA") PE
  tanımıyla karıştırılmasından kaynaklanıyordu. Düzeltildi.
- **Kanıt:** `[PDF tam]` s.255: "The computation results of the int8
  parameters are accumulated in int32 precision" — MAC'ın iç toplama/mux
  yolu 32-bit, varsayım değil.
- **Kanıt:** `[PDF tam]` 6 çalışma modu var (FP/BP/WG x stride1/2), "1x1 conv"
  modu Shao'da YOK (yine SiPS makalesiyle karışmıştı, düzeltildi).

### D10/D14 (PE-a1) — MAC mux'larının her modda ne seçtiği — ÇÖZÜLDÜ
- **Ne:** Fig.2'deki mux/toplayıcıların FP/BP/WG x s1/s2'ye göre tam davranışı.
- **Kanıt:** Ömer Faruk'un `pe_golden.py` + `README_PE_GOLDEN.md`'si (6 modun
  tam mux/zincir davranışını) adjoint-özdeşlik testi (300 rastgele), dosya
  geri-okuma testi (1071 değer), mutasyon testi (8/8) ile çıkardı.
  **Çapraz doğrulama:** Egemen bu belgeyi hiç görmeden, yalnızca ham vektör
  dosyalarından (`pe_fp_s1.txt` vb.) RTL'i (`pe_chain3.v`, `pe_fp_s2.v`,
  `pe_bp_s2.v`, `pe_wg_s1.v`, `pe_wg_s2.v`) bağımsız yazdı — iki yöntem
  (yazılı spesifikasyon vs. ham veriden tersine mühendislik) **7 ayrı
  mimari iddiada birebir örtüştü** (psum giriş noktası, satır toplayıcının
  kombinasyonel olması, FP_S2'nin gecikme register'ı, BP_S2'nin A/B
  zincirleri ve çıkış formülü, WG'nin gecikme zinciri — tam liste için bkz.
  `README_PE_GOLDEN.md` Bölüm 3). RTL ayrıca Vivado'da 138/138 geçti.
- **Durum:** Kesinleşti. Kesinleşen davranış: psum yalnızca satır 0'ın zincir
  başına girer (D15); FP_S1=BP_S1 aynı donanım (yalnızca 180°-döndürülmüş
  ağırlık farklı, döndürme donanım dışında/ön-getirmede yapılıyor); FP_S2'de
  MAC2 çift akışın 1-çevrim-gecikmeli halini alıyor; BP_S2'de her satırda
  A(2 MAC)+B(1 MAC) ayrı zincir var; WG'de her MAC kendi akümülatöründe
  birikiyor, hata sinyali sütun başına 0/1/2 çevrim gecikmeli.

### D15 (PE-a2) — Satır başı mux'un girişleri — ÇÖZÜLDÜ
- **Ne:** Her satırın başındaki küçük mux'a ne bağlı.
- **Kanıt:** `pe_golden.py`: psum yalnızca satır 0'ın zincir başına girer;
  satır 1-2'de her zaman 0.
- **Durum:** Kesinleşti, RTL'e işlendi (`pe_chain3.v`, `pe_fp_s2.v`).

### D16 (PE-a3) — Mux kontrol zamanlaması, boşaltma (flush) çevrimleri
- **Ne:** Kontrol sinyallerinin ne zaman değiştiği, stride=2'de kaç ek
  çevrim gerektiği.
- **Kanıt:** `[Ölçüldü]` (`kontrol_pe.py`): stride=2 modellerinde (FP ve WG)
  1 ek boşaltma çevrimi gerekti, referans fonksiyonla eşleşmesi için.
- **Durum:** Davranış modeli doğrulandı ve RTL'e işlendi.

### D12/D17 (PE-a4) — Psum FIFO queue derinliği/genişliği — AÇIK
- **Ne:** Makalede hiç sayı verilmemiş.
- **Durum:** Açık. Şimdilik RTL'de gerçek bir FIFO yok, doğrudan port.

### D13 — mac.v'nin `sel` kodlaması
- **Ne:** `mac.v`'deki 2-bit `sel` (00=partial_sum, 01=passed_value,
  10=accumulated_value) kodlaması.
- **Durum:** Kesinleşti, D10/D14 çözümüyle tutarlı.

### D18 (PE-a5) — BP stride=2'de çıktı grubu - çekirdek alt kümesi eşlemesi
- **Ne:** Çift/tek satır-sütun grubu (4 grup) ile kullanılan çekirdek
  satır/sütun alt kümesi arasındaki ilişki, ileri geçişteki dolguya bağlı.
- **Kanıt:** `[Ölçüldü]` (`kontrol_pe.py`, adjoint testiyle): dolgu=0'da çift
  grup çekirdek satır/sütun {0,2}'yi, dolgu=1'de {1}'i kullanıyor. Shao
  dolguyu hiç yazmıyor; NITI'nin varsayılan conv dolgusu 1 `[NITI GitHub:
  ti_torch.py, TiConv2d]`.
- **Durum:** Matematiksel olarak doğrulandı, dolgu varsayımı (1) açık.

### D19 (PE-a6) — BP s2'de hata satırı - PE satırı eşlemesi
- **Ne:** Fig.4(b)'deki satır-indis eşlemesi. `[PDF şekil]`, metinde yok.
- **Durum:** Açık, ön-getirme modülünün işi.

### D20 (PE-a7) — WG'de a/e satırlarının MAC'lere veriliş sırası
- **Ne:** Fig.5'teki indis ataması. `[PDF şekil]`.
- **Durum:** Açık ama matematiksel sonuç `[Ölçüldü]` ile doğrulandı.

### D21 (PE-a8) — WG birikiminin int32'ye sığması, batch üst sınırı
- **Kanıt:** `[Çıkarım+Ölçüldü]`: 512 kanallı FP'de en kötü durum
  74.322.432 < 2^31-1, güvenli. WG'de 32x32 haritada batch <= 130
  (127^2*32*32*B < 2^31-1 için B<=130).
- **Durum:** Üst sınır hesaplandı, kesin batch boyutu açık.

### D22 (PE-a9) — FC katmanlarının PE'ye eşlenmesi — AÇIK, düşük öncelik
- **Ne:** Metinde yalnızca "diğer desenler çıktı-durağan" deniyor `[PDF tam]`.

### D23 (PE-a10) — İlk katmanda -128 girişi
- **Ne:** D9 ile bağlantılı: NITI'nin `TiFloatToInt8` fonksiyonu girişi
  -128..127'ye (asimetrik) kırpıyor `[NITI GitHub]`, CLU/PE içindeki
  değerler -127..127 simetrik (D9). İlk katman girişinde -128 görülebilir.
- **Öneri:** PE test vektörlerine -128 dahil edildi (CASE_LISTESI.txt).

---

## SRU (Scaling and Rounding Unit) — tamamlandı (tek kanal + 16-paralel)

**Kaynaklar:** Shao II-B-1 (s.255, algoritma) + Algoritma 1 (s.256) + III-B
ve Fig.6 (s.257, donanım) + Fig.8 (s.258, sistem). NITI hakem: bp formülü ve
B(V) tanımı (s.3252-3253), Alg. 1-3 (s.3252-3254).

**Doğrulanan (varsayım değil):**
- SRU, int32/int8 veri + shifting-bit alıp int8 üretiyor; LMS ve GMS AYNI
  donanım birimiyle yapılıyor `[PDF tam: III-B]`.
- Fig.6 bit alanı: 32-bit = [üst bitler | 8 | shift-bit]; shift-bit alanı
  üst yarı (a) ve alt yarı (b)'ye ayrılıyor; a>b ise +1 `[PDF şekil,
  doğrudan tekrar incelendi]`.
- Shao'nun SRU'sunda **hiç bölücü yok**, yalnızca kaydırma+yuvarlama
  `[PDF tam: III-B, III-C]` — CLU'daki tek bölücüyle (divider IP)
  karıştırılmamalı.

### SRU-a1/a2/a3/a8 — RESMİ KARARLAR (Ömer Faruk'un sru_golden.py'si, 28.10.2026)

Bu dört karar, `sru_yuvarla.txt`/`sru_katman.txt` dosyalarının ilk satırındaki
**ayar kodu `1 1 0 1`** ile kayıtlı:

- **SRU-a1 (alt yarı aralığı): "shao"** — Algoritma 1 satır 6'nın KENDİ
  yazımı f[h,0] (h+1 bit). **Egemen'in PDF'ten tekrar doğrudan okuduğu
  transkripsiyon ile teyit edildi:** satır 6 harfiyen "if f[bp-1,bp/2] >
  f[bp/2,0]" — yani bu, NITI'nin "düzeltmesi" değil, **Shao'nun yazdığının
  birebir kendisi**. (NITI'nin kendi Algoritma 3'ü f[bp/2-1,0] yazıyor —
  Shao bunu NITI'den uyarlarken "-1"i düşürmüş olabilir, ama elimizdeki tek
  somut kanıt Shao'nun kendi metni, o yüzden literal okuma doğru öncelik.)
- **SRU-a3 (doyma): YOK** — ±127'ye kırpma yok, sonuç 8 bitte doğal olarak
  sarıyor (128 -> -128, iki tümleyen taşması). Algoritma 1 satır 9'da bitiyor,
  hiçbir kırpma adımı yok — bu da literal okuma. **Risk (makalenin kendi
  eksiği, bizim sapmamız değil):** NITI'nin gerçek kodu (`int8_clip`) kırpma
  yapıyor; Shao'nun algoritması muhtemelen bunu "örtük" sayıp atlamış. Sonuç:
  pozitif büyük bir değer yuvarlamayla işaret değiştirip NEGATİF çıkabiliyor
  (örn. 2040 -> LMS'te 128 -> 8 bitte -128). **Makaleye sadakat önceliği
  gereği düzeltilmedi, olduğu gibi gerçeklendi** — tez tartışmasında
  mutlaka gündeme gelmeli, muhtemelen Shao'ya ikinci bir soru.
- **SRU-a2 (tek bp):** "makale" (f'nin en alt biti atılır, bp-1 ile devam).
- **SRU-a8 (GMS kaydırma):** Delta = G - l (kaydırma miktarlarının farkı).

`stochastic_round.v` bu kararlara göre yazıldı, resmi 2297 satırlık
`sru_yuvarla.txt` ile **2297/2297** doğrulandı.

### D24 (SRU-a1 kanıt detayı)
- **Kanıt:** `[Ölçüldü]` (`kontrol_sru.py`): Shao'nun yazımı bp=2'de hiç
  yukarı yuvarlamıyor (oran 0.000); NITI aralığıyla oran 0.249. bp=8'de
  ort. hata Shao-yazımı -0.28 LSB, NITI aralığı -0.03 LSB.

### D25 (SRU-a2 kanıt detayı)
- **Kanıt:** `[Ölçüldü]`: örneklerin %26-50'si NITI koduyla farklı sonuç
  veriyor (bp=1'de en kötü).

### D26 (SRU-a3 kanıt detayı)
- **Kanıt:** `[Ölçüldü]`: rastgele 200.000 değerin ~%0.3-0.8'inde klipsiz
  sonuç 128 çıkıyor.

### D27 (SRU-a4) — bp = max(0, B-7)
- **Kanıt:** `[NITI GitHub + makale]` "If b=B(V)>7, shifted right by b-7".

### D28 (SRU-a5) — B(V) tanımı: bit_length(), ceil(log2) DEĞİL
- **Ne:** Makale "en büyük değeri temsil etmek için gereken en az bit"
  diyor; bu `bit_length()` demek, NITI kodunun `ceil(log2(max))`'ı değil.
  **Düzeltme:** Bu tanım Shao'dan değil **NITI makalesinden** geliyor
  (Bölüm 3.2, s.3253) — Shao kendi formül vermiyor, yalnızca "en büyük
  etkin bit genişliği" diyor.
- **Kanıt:** `[Ölçüldü]`: yalnızca 2'nin tam kuvvetlerinde ayrışıyor.
- **Durum:** Kesinleşti, `bit_length32.v` ile RTL'e işlendi, resmi 154
  değerlik `sru_bm.txt` ile **154/154** doğrulandı.

### D29 (SRU-a6) — Maksimum = mutlak değerlerin maksimumu
- **Kanıt:** `[NITI GitHub]` `torch.max(torch.abs(input))`.

### D30 (SRU-a7) — "Grup" tanımı — KISMEN ÇÖZÜLDÜ (mimari kararla)
- **Ne:** LMS'in üzerinde çalıştığı "grup"un tanımı.
- **Kanıt:** `[PDF tam: III-B]` "PEs finish their computation and produce a
  group of int32 output data, which is part of the full-layer outputs".
  Fig.8'de SRU her PE satırının sonunda bir tane (16 satır = 16 SRU).
- **Mimari karar (`sru_array.v`):** Bir "grup" = bir PE satırının bir
  geçişte ürettikleri; 16 satır = 16 paralel SRU kanalı (`sru_channel.v`),
  hepsi **TEK bir paylaşılan G**'yi kullanıyor (`global_max_reducer16.v`,
  Fig.6'nın "global maximum value of ALL outputs" ifadesiyle tutarlı — her
  satırın kendi G'si DEĞİL). `[Çıkarım]` — 16 satırın "lockstep" (aynı
  cevrimde aynı grup indeksi) çalıştığı varsayıldı, makale bunu açıkça
  yazmıyor, sistolik dizinin doğal çalışma şeklinden çıkarım.
- **Hâlâ açık:** MAX_GROUPS=16 sınırı (bir katmandaki maksimum geçiş
  sayısı) `[Varsayım]`, doğrudan metinden gelmiyor.

### D31 (SRU-a8 kanıt detayı) — Delta=(G-l), B(M)-B(Mg) DEĞİL
- **Kanıt:** `[Ölçüldü]`: B(M)-B(Mg) okuması küçük gruplarda (B<7) yanlış
  sonuç veriyor.

### D32 (SRU-a9) — Ölçek üssü güncellemesi: s_çıkış = s_giriş + G
- **Kanıt:** `[NITI GitHub + makale]` Alg.2 satır 1: "sq <- sq32 + bp".

### D33 (SRU-a10) — a ve e için yuvarlama tipi Algoritma 1
- **Kanıt:** `[NITI GitHub]` NITI'nin varsayılanı aktivasyon/hata için
  `RoundShift`, yalnızca ağırlık gradyanı için `PstoShift` — ama Shao'ya
  sadık kalınarak a ve e için de Algoritma 1 kullanıldı.

### D34 (SRU-a11) — İki aşamalı != tek aşamalı (beklenen fark, hata değil)
- **Kanıt:** `[Ölçüldü, sentetik]`: farklı ölçekli gruplarda değerlerin
  %7-26'sı 1 LSB farklı (daha fazla değil).

### D35 (SRU-a12) — WG çıktıları (g) SRU'dan geçiyor mu? — AÇIK
- **Ne:** NITI, g'yi b-m_u ile kaydırıyor (m_u=1-5 bit, deneysel); Shao
  m_u'dan hiç bahsetmiyor, PE dizisinin TÜM çıktıları SRU'dan geçiyor gibi
  anlatılıyor `[PDF tam: III-D]`.
- **Öneri:** Hedef genişlik parametrize edilsin; Shao'ya sadık kalmak
  isteniyorsa muhtemelen hep 7.

### D36 (SRU-a13) — Max Regs. yalnızca B saklıyor (32-bit değil)
- **Kanıt:** `[Çıkarım]` B monoton olduğundan B(max)=max(B); `global_max_b.v`
  ve `global_max_reducer16.v` bu şekilde (6-bit) yazıldı, RTL'e işlendi.

### D37 (SRU-a14) — Küçük Delta'da Algoritma 1 neredeyse kesme gibi davranıyor
- **Not:** Kodlama hatası değil, yöntemin doğal özelliği.

---

## Mimari zayıflıklar (makalenin kendi sorunları, tez tartışması için)

- CLU'nun N paralel divider'ı sınıf sayısıyla ölçeklenmiyor (**doğrulandı**:
  Vivado BASIC lisansının 50.000 instance sınırına çarptık, 10x64-bit
  divider 80.053 instance'a çıktı — tek paylaşımlı + zaman-paylaşımlı
  tasarıma geçildi, CLU'da çözüldü)
- GMS (SRU'nun 2. aşaması) katmanın tamamı bitene kadar pipeline'ı durduruyor
- EPU ve TEU her zaman ikisi de hesaplanıyor, güç israfı
- 16x16 sabit PE dizisi, 16'nın katı olmayan kanal sayılarında yetersiz
  kullanılıyor
- Yalnızca düz SGD destekleniyor, momentum/Adam yok
- Batch-level paralellik hiç ele alınmamış
- TEU dalının ürettiği gi değerleri EPU'dan milyonlarca kat büyük olabiliyor
  (ölçüldü: sa=-10'da ~2.2M vs EPU'nun max 1023) — ortak boru hattı TEU'nun
  en kötü durumuna göre boyutlanmak zorunda
- SRU'nun doyma yapmaması (SRU-a3), pozitif değerlerin sessizce negatife
  dönmesine yol açabiliyor — makalenin kendi eksiği, bkz. yukarı

---

## Araç/dil tuzakları (yeni blok yazarken karşına çıkabilir)

1. **Verilog `{concatenation}` her zaman unsigned.** `ai * ({...} <<< x)`
   gibi bir ifadede negatif `ai` yanlış yorumlanır. Çözüm: `$signed(...)`
   ile sarmalayın. (CLU'nun TEU'sunda gerçek bir hataya yol açmıştı,
   testbench yakaladı.)
2. **Vivado XSIM, port olarak tanımlı diziyi kabul etmiyor**
   (`input [W-1:0] x[0:N-1]` port olarak yasak, Icarus'ta sorun yoktu).
   Çözüm: flat bus (`input [N*W-1:0] x_flat`) + modül içinde unpack.
   Projedeki her modül bu kuralı izliyor (`max_tree.v`, `sru_array.v` vb.).
3. **Xilinx IP core'ları (Divider Generator vb.) tek başına binlerce
   simülasyon "instance"ı.** N paralel kopya hızla BASIC/WebPACK
   lisansının 50.000 sınırını aşar. Çözüm: tek paylaşımlı IP + zaman
   paylaşımlı (round-robin) besleme, sonucu etiketli (tag) bir gecikme
   hattıyla doğru kanala geri yazma (CLU'daki `div_stage_ip.v`).
4. **`.v` uzantılı ama SystemVerilog sözdizimi (`longint`, dizi port vb.)
   kullanan dosyalar Vivado'da "File Type: SystemVerilog" olarak
   işaretlenmeli**, yoksa `xvlog` eski Verilog-2001 kurallarıyla derlemeye
   çalışıp hata verir. **Not:** Bu projedeki GÜNCEL dosyaların çoğu (PE,
   SRU) saf Verilog-2001, bu işarete gerek duymuyor — yalnızca eski/ilk
   CLU denemelerinde gerekmişti.
5. **Divider Generator IP saatli (clocked), sabit latency'li.** IP kullanan
   her blok saatsiz (combinational) kalamaz — clk portu ve testbench'te
   sabit bekleme süresi (latency + pay) gerekir.
6. **Testbench'teki başlangıç register'ları (ilklendirilmemiş `reg`)
   X (tanımsız) olarak başlar.** Reset ile gerçek veri arasındaki bir
   "boşluk" çevriminde bu X sızıp akümülatörlere karışabilir (SRU'nun WG
   benzeri akümülatör tabanlı testlerinde gerçek bir hataya yol açmıştı).
   Çözüm: tüm giriş register'larını deklarasyonda `=0` ile ilklendirin.
