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
**D69**), asla eskisini silme veya numarayı tekrar kullanma — eski bir D
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
| **SRU** (tek kanal) | Tamamlandı; doymasız (D59). Hedef girişli kopya hazır (D61) | 154+2297+52+12, Vivado'da doğrulandı; kopya Icarus'ta aynı testlerle; gradyan yolu 1865/1865, Vivado'da doğrulandı (03.11) | `rtl/sru/`, `rtl/sru_hedefli/` |
| **SRU** (16 paralel) | Tamamlandı | 12/12 (kendi test senaryomuz), Vivado'da doğrulandı | `rtl/sru/sru_array.v` |
| ReLU ve Weight Update | Tamamlandı | ReLU 196.608, WU 65.536; Vivado'da doğrulandı | `rtl/fe/`, `models/fe/` (Ömer) |
| Pooling | Kapsam dışı (D39) | — | — |
| Master Controller (FSM) | Tamamlandı; entegrasyonda RTL'i değişmedi (D64: G SRU'dan geliyor; `maks_reg` yalnızca `tb_fsm`'de) | 6206/6206, Vivado'da doğrulandı (02.11 ve 03.11 vektörleriyle) | `rtl/sistem/` |
| PE sarmalayıcısı + Psum FIFO | Tamamlandı (D64) | 380.490/380.490, Vivado'da doğrulandı (03.11) | `rtl/sistem/` |
| SRU, 64 gruplu kopya (D63) | Tamamlandı | 8508/8508, Vivado'da doğrulandı (03.11) | `rtl/sru_64/` |
| CLU stokastik yuvarlama birimi (D57) | Hazır, kullanılmıyor (D60) | 40.960/40.960, Vivado'da doğrulandı | `rtl/clu_yuvarlama/`, `models/clu_yuvarlama/` (Ömer) |
| Fonksiyon motoru üst modülü (`fe_top`: ReLU + WU + CLU) | Tamamlandı (D62) | 456.144/456.144, Vivado'da gerçek bölücü IP'siyle doğrulandı (03.11) | `rtl/fe/fe_top.v`; bölücü IP'si `rtl/clu/ip/div_gen_0Z.xci` (Ömer) |
| Komut yürütücüsü + PE motoru (ön-getirme, grup toplayıcı) + GMS FIFO + test belleği (Adım 4, Paket 2) | Tamamlandı (D66, D67) | 71.048/71.048 (ag1 ve ag2'nin bir eğitim adımı, FSM'in komut dosyasıyla), Vivado'da gerçek bölücü IP'siyle doğrulandı (03.11) | `rtl/sistem/`, `models/sistem/` |
| Tam sistem entegrasyonu (Adım 4, Paket 3: `sistem_ust` = FSM + veri yolu; `maks_reg` çıktı, A1) | Tamamlandı | 21.415/21.415 (3 tur: ag1, ag2, ag1, arada reset yok; komutları FSM üretiyor), Vivado'da gerçek bölücü IP'siyle doğrulandı (03.11) | `rtl/sistem/` (`sistem_ust.v`, `tb_sistem.sv`, `run_sim.tcl`) |

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
- **Güncelleme (02.11):** Ömer (c)'yi seçti; ayrıntı ve hazır birim D57'de.
- **Güncelleme (03.11):** Ömer şimdilik (a)'ya döndü; bkz. D60.

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
- **Not (03.11):** PE testbench'leri çıkışı 0–7 çevrimlik herhangi bir kaymada
  aradığı için gecikme testte sabitlenmiyordu. `[Ölçüldü]` Her modda sabit:
  FP s1, BP s1 ve FP s2'de kayma 2, BP s2'de 1 (bütün geçişlerde aynı).

### D12/D17 (PE-a4) — Psum FIFO queue derinliği/genişliği — AÇIK
- **Ne:** Makalede hiç sayı verilmemiş.
- **Durum:** Açık. Şimdilik RTL'de gerçek bir FIFO yok, doğrudan port.
- **Not (03.11):** Tek PE (D43) ve D47'deki döngü sırasıyla test ağında en çok
  128 int32 gerekiyor.

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
- **Not (03.11):** Dolgu 0 ve dolgu 1 sistem golden'da doğrulandı; bkz. D58.

### D19 (PE-a6) — BP s2'de hata satırı - PE satırı eşlemesi
- **Ne:** Fig.4(b)'deki satır-indis eşlemesi. `[PDF şekil]`, metinde yok.
- **Durum:** Açık, ön-getirme modülünün işi.
- **Not (03.11):** Eşleme sistem golden'ın komut yorumlayıcısında var ve
  doğrulandı; bkz. D58.

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
  **Güncelleme (02.11):** Ömer ±127 doymaya çevirdi; bkz. D38 (ayar kodu artık
  `1 1 1 1`). **Güncelleme (03.11):** Yeniden doymasız, makaleye sadakat; bkz. D59.
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
- **Not (02.11):** Karar ±127 doymaya çevrildi; bkz. D38.
- **Not (03.11):** Geri alındı, doyma yok; bkz. D59.

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
- **03.11:** Entegrasyon kopyasında 64; bkz. D63.
- **Not (03.11):** Tek PE ile (D43) bir işte 56–60 grup oluşuyor; MAX_GROUPS ≥ 64
  ve 7 bitlik sayaçlar gerekiyor.

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
- **Güncelleme (31.10):** Kapandı; bkz. D40 (hedef m_u).

### D36 (SRU-a13) — Max Regs. yalnızca B saklıyor (32-bit değil)
- **Kanıt:** `[Çıkarım]` B monoton olduğundan B(max)=max(B); `global_max_b.v`
  ve `global_max_reducer16.v` bu şekilde (6-bit) yazıldı, RTL'e işlendi.
- **Not (03.11):** Ömer bu yapıyı onayladı ("Egemen'inkine uygun gidelim");
  FSM tarafı için bkz. D49.

### D37 (SRU-a14) — Küçük Delta'da Algoritma 1 neredeyse kesme gibi davranıyor
- **Not:** Kodlama hatası değil, yöntemin doğal özelliği.

---

## Ömer tarafı ve sistem kararları (02–03.11.2026)

Bu bölüm, Ömer'in ayrı tuttuğu karar dosyasındaki maddelerin bu dosyaya
birleştirilmiş hâlidir. O dosyada geçici olarak D29–D54 numaraları
kullanılmıştı; buradaki numaralarla çakıştığı için yeniden numaralandı.
Yukarıda zaten bulunan SRU kararları tekrar yazılmadı.

| Ömer'in dosyasındaki geçici no | Bu dosyada |
|---|---|
| D28 | D28 (aynı madde) |
| D29 (SRU-a1) | Zaten var: SRU-a1 resmi kararı + D24 |
| D30 (SRU-a2) | Zaten var: SRU-a2 resmi kararı + D25 |
| D32 (SRU-a4) | Zaten var: D27 (hedef m_u için bkz. D40) |
| D33 (SRU-a6) | Zaten var: D29 |
| D34 (SRU-a7) | Zaten var: D30 |
| D35 (SRU-a8) | Zaten var: SRU-a8 resmi kararı + D31 |
| D36 (SRU-a9) | Zaten var: D32 (s_giriş = s_a + s_w) |
| D31 (SRU-a3, ±127 doyma) | D38 |
| D37–D44 (K1, K2a, K2b, K3, K4+K5, K6a, K6b, K7) | D39–D46 |
| D45–D54 (T1, T2, T4, T5, T6, T7, T8, T10, T11, T12) | D47–D56 |
| D8'in 02.11 güncellemesi | D57 |
| — | D58 (yeni) |

Ayrıntılı tasarım: Adım 4 tasarım belgesi `rtl/sistem/TASARIM_FSM.md` (T maddeleri, Bölüm 9).

### D38 — SRU-a3 değişti: 128'e ulaşan sonuç ±127'ye doyurulur
- **03.11: GERİ ALINDI**, bkz. D59. Aşağıdaki kanıt ve ölçümler kayıt için duruyor.
- **Ne:** Alg. 1'in yukarı yuvarlamasından sonra |q| = 128 olursa sonuç ±127'ye
  kırpılır: +128 → 127, −128 → −127.
- **Neden:** Doyma yokken pozitif bir değer −128'e sarılıp işaret değiştiriyor;
  taşan değerlerin %98–100'ü grubun en büyük değeri `[Ölçüldü]`.
- **Kanıt:**
  - `[PDF tam]` Shao Alg. 1 (s. 256) taşma adımı içermiyor ama çıkışı
    "rounded 8-bit integer" olarak tanımlıyor; +128 8 bite sığmadığı için bu
    durum metinde tanımsız.
  - `[NITI GitHub]` `ti_torch.py` 23–72: RoundShift, StoShift ve PstoShift
    sonucu `int8_clip` ile ±127'ye kırpıyor.
  - D9: int8 aralığı −127..127.
  - `[Ölçüldü]` Sistem golden, ağ başına 200 rastgele eğitim adımı: aktivasyon
    sapması %10'u aşan adımlar doyma yokken %7 (ag1) ve %18,5 (ag2), doymayla
    hiç yok. En kötü sapma %147 ve %183'ten %6,9 ve %7,0'a iniyor.
- **Donanım:** İşaret uygulanmadan önce `q[6:0] | {7{q[7]}}`; q en fazla 128
  olabildiği için min(q, 127) ile aynı.
- **Durum:** Ömer, 02.11: "şuanlık öyle yapalım ileride değiştiririz". Vektör
  ayar kodu `1 1 1 1`. `stochastic_round.v` için 4 satırlık düzeltme önerisi hazır;
  yeni vektörlerle bütün SRU testleri geçiyor. Egemen'in onayı bekleniyor.
  - **Not:** Yukarıdaki "SRU-a3: YOK" kaydı, Claude'un 28.10'da Ömer'in
    "Doyurma" cevabını "doyurma yapma" diye okumasından çıktı. Bu karar,
    Egemen'in "makaleye sadakat" gerekçesiyle çelişiyor; ekip olarak
    netleştirilmeli.

### D39 — Pooling birimi şimdilik yok (K1)
- **Kanıt:** `[PDF tam]` Shao IV (s. 258): eğittikleri VGG16 benzeri ağda
  max-pooling yerine stride 2 conv kullanılıyor.
- **Durum:** Ömer, 31.10. Gerekirse sonra eklenir.

### D40 — Gradyan (g) SRU'dan m_u hedefiyle geçer (K2a) — D35'i kapatır
- **Kanıt:** Shao m_u'dan bahsetmiyor. `[NITI GitHub + makale]` NITI Alg. 1
  satır 13 ve §3.3: g, b − m_u kadar kaydırılır; m_u takvimi 5 → 4 → 3.
- **Durum:** Ömer, 31.10. Bu yolda taşma olamaz (m_u ≤ 6).
- **Gerektirdiği RTL değişikliği:** SRU'da sabit 7 yerine hedef girişi
  (`lms_group16.v`, `global_max_b.v`, `global_max_reducer16.v`).
- **03.11:** Ömer "aynen koruyalım" dedi; RTL'i D61.

### D41 — w − g taşarsa ±127'ye doyurulur (K2b)
- **Kanıt:** `[NITI GitHub]` `ti_torch.py` 21 (`weight_update`) ve 71–72
  (`int8_clip`); D9.
- **Durum:** Ömer, 31.10. `wu_unit.v` ile RTL'e işlendi, Vivado'da 65.536/65.536.

### D42 — GMS bütün tüketicilerden önce uygulanır (K3)
- **Ne:** GMS, PE'ye giden yolun yanı sıra ağırlık güncellemeden ve CLU'dan önce
  de uygulanır.
- **Kanıt:** `[PDF tam: III-B, III-C, III-D]` III-C: CLU son katman
  aktivasyonlarını tek bir s_a ile alıyor; farklı ölçekte kalan gruplar tek üsle
  ifade edilemez. III-B: birlikte işlenen değerler aynı maksimumla
  ölçeklenmeli. III-D (s. 258): "The outputs of PE array are scaled and rounded
  by SRU before transmitted to the output buffer." GMS'in ağırlık güncelleme ve
  CLU yolundaki yeri metinde açıkça yazmıyor; sonuç bu cümlelerden çıkarım.
- **Durum:** Claude, Ömer'in "Shao'ya en uygun olanı seç" talimatıyla, 31.10.

### D43 — Test ağı: 1 PE; son katman 3×3 conv = FC eşdeğeri (K4 + K5)
- **Ne:** 16×16 dizi yerine tek PE; dizinin satırları zamanla taklit edilir. Son
  katman 3×3 girişte dolgusuz 3×3 conv (36 girişli FC eşdeğeri); çıkışı CLU'ya
  (N = 10) gider.
- **Sonuçları:**
  - Bir işte 56–60 grup oluşur; D30'daki MAX_GROUPS = 16 yetmez, ≥ 64 gerekir.
  - Psum FIFO B kat büyür (D47).
- **Durum:** Ömer, Adım 4.

### D44 — GMS + ReLU bir kopyalama geçişinde, sonuç aktivasyon deposuna yazılır (K6a)
- **Not:** Shao Fig. 6'da GMS, tampondan PE'ye giden yolda anında yapılıyor; bu
  karar ondan sapıyor. Egemen'in SRU'sunda GMS çıkışı akış hâlinde geldiği için
  bu geçiş, akışın ReLU'dan geçip depoya yazılmasına dönüşüyor.
- **Durum:** Ömer, Adım 4.

### D45 — Ağırlık güncelleme tampona doğrudan yazar; GMS + w − g + yazma tek geçişte (K6b, T9)
- **Durum:** Ömer, Adım 4.

### D46 — Faz sırası: BP eski ağırlıkla, sonra WG, sonra WU; 1. katmanda BP yok (K7, T3)
- **Kanıt:** Shao iş sırasını yazmıyor; `[NITI GitHub]` NITI'nin kod sırası.
- **Durum:** Kesinleşti.

### D47 — Döngü sırası: örnek döngüsü kanal çiftinin içinde (T1)
- **Ne:** FP o→c→b→r, BP c→o→b→p, WG o→c→b→r.
- **Kanıt:** `[PDF tam]` III-D (s. 258): girişler batch ya da satır boyunca PE
  satırlarına, ağırlıklar çıkış kanalı boyunca sütunlara açılır. III-A-1:
  ağırlıklar kanal bitene kadar sabit.
- **Bedel:** Tek PE ile (D43) Psum FIFO test ağında 64'ten 128 int32'ye çıkıyor
  (bkz. D12/D17).
- **Durum:** Ömer, 02.11.

### D48 — Bir katman, sonrakine geçmeden batch'in bütün örnekleri için bitirilir (T2)
- **Kanıt:** `[PDF tam]` III-D + `[NITI GitHub]` katman başına tek ölçek üssü.
- **Durum:** Kesinleşti.

### D49 — Max Regs SRU'nun içinde; FSM G'yi SRU'dan alır (T4)
- **Ne:** D36'daki yapı (6 bitlik B'nin yürüyen maksimumu, grup başına ℓ SRU
  tamponunda) aynen kullanılır. FSM'deki ayrı `maks_reg` bloğu entegrasyonda
  çıkarılır.
- **Durum:** Ömer, 03.11 ("Egemen'inkine uygun gidelim"). 02.11'de onaylanan ayrı
  blok ve 32 bitlik maksimum önerisi bununla geri alındı.

### D50 — Tek komut, tek "bitti"; boru hattı yok; komutlar arası en az 1 çevrim boşluk (T5)
- **Durum:** `[Çıkarım]` İki kaynak da kontrol arayüzünü tanımlamıyor. Hangi
  bloğun "bitti" vereceği 4.0 arayüz sözleşmesinde belirlenecek.

### D51 — BP stride 2'de tamamen kırpılacak geçişler atlanır: ⌈(H + p)/2⌉ geçiş (T6)
- **Kanıt:** `[PDF tam]` Shao'nun amacı stride 2'de boşa giden (dummy)
  işlemleri ayıklamak (I, III-A, V). Geçişin kendisi metinde yok.
- **Durum:** Kesinleşti.

### D52 — Dolguya düşen BP stride 2 çıktıları SRU grubuna girmez, yazılmaz (T7)
- **Kanıt:** `[PDF tam]` III-B: grup, PE çıktılarının bir parçası; var olmayan
  değerler yerel maksimumu belirlememeli.
- **Durum:** Kesinleşti.

### D53 — ReLU ile GMS'in sırası sonucu değiştirmez (T8)
- **Kanıt:** `[Ölçüldü]` Bütün int8 değerleri × 0..31 kaydırma × maskenin işaret
  sınıfları (49.152 durum) ve sistem düzeyinde bit bit aynı.
- **Durum:** Egemen'in SRU'suyla (D49) sıra fiilen "önce GMS, sonra ReLU".

### D54 — Katman tablosu FSM'e giriş portlarından gelir (T10)
- **Durum:** `[Çıkarım]` Testbench dosyadan sürüyor; entegrasyonda bir
  yapılandırma register'ı sürecek.

### D55 — Sistem golden modelinde CLU bir yer tutucu fonksiyonla hesaplanır (T11)
- **Kanıt:** `[Ölçüldü]` D8 = (a) iken yer tutucu, Egemen'in `golden_model.py`'si
  ve `clu_top.v`'siyle 1500 rastgele vektörde (EPU ve TEU dalları) bit bit aynı.
- **Durum:** D57 (c) yer tutucuda uygulandı; D5 hâlâ açık.

### D56 — İŞ_BAŞLA komutu (T12)
- **Ne:** Her PE işinden önce gelir; tamponları sıfırlar, SRU'nun `rst`'ünü ve
  hedef genişliğini (7 ya da m_u, D40) sürer.
- **Durum:** `[Çıkarım]` Ömer, 02.11.

### D57 — D8 kararı: CLU'nun son >>4'ü LFSR'li stokastik yuvarlanır (seçenek c)
- **03.11: ASKIDA**, şimdilik (a); bkz. D60. Birim hazır duruyor.
- **Kanıt:** `[NITI GitHub]` `ti_loss.py` 35 `StoShift(out_grad, 4)`;
  `ti_torch.py` 33–46. NITI'nin ortamı PyTorch 1.7 (Dockerfile); bu sürümde `//`
  sıfıra doğru kestiği için yuvarlama işaret-büyüklükle yapılıyor: q = |x| >> 4,
  f = |x| mod 16, f > r ise q + 1, ardından ±127.
- **LFSR (alternatif, iki kaynakta da yok):**
  - 16 bit Fibonacci, x^16 + x^14 + x^13 + x^11 + 1 (periyot 65535)
  - r = alt 4 bit; kullanım başına 4 adım ilerler
  - kanal başına ayrı LFSR (D3); tohumlar i · 6553 adım aralıklı
- **D8'deki "zor" notu çözüldü:** `[Ölçüldü]` Python modeli ile `stok_yuvarla.v`
  40.960/40.960 bit bit aynı (Icarus ve Vivado). Aynı r verildiğinde NITI
  StoShift ile 80.001 × 16 durumda birebir aynı.
- **Durum:** Ömer, 02.11. Birim hazır (`rtl/clu_yuvarlama/`, `models/clu_yuvarlama/`). Egemen'in `clu_top.v`'si
  hâlâ (a); son aşamaya bağlanması bekliyor.

### D58 — BP stride 2 akışları ve dolgu: ön-getirme golden'ı doğrulandı (D18, D19, D20 için)
- **Kanıt:** `[Ölçüldü]` Sistem golden'ın komut yorumlayıcısı ön-getirme
  mantığını (dolgu, çift/tek ayırma, BP s2 satır akışları, şerit yerleşimi ve
  kırpma) içeriyor. Katman fonksiyonlarıyla bit bit aynı çıkıyor: dolgu 0 (ag1,
  2. katman) ve dolgu 1 (ag2, 2. katman).
- **Durum:** Ön-getirme modülünün RTL'i için golden olarak kullanılacak.

---

## Adım 3 kararları (03.11.2026)

### D59 — SRU-a3 yeniden: doyma yok (D38 geri alındı)
- **Ne:** Alg. 1'in yukarı yuvarlaması 128 üretirse sonuç kırpılmaz, 8 bitte sarılır
  (+128 → −128). 28.10'daki "SRU-a3: YOK" kaydının davranışı.
- **Neden:** Ömer, 03.11: "makaleye sadık kalıp doymasız yapalım, en kötü sonra yine
  buraya döneriz". `[PDF tam]` Alg. 1'de (s. 256) kırpma adımı yok.
- **Bilinen bedeli (D38'deki ölçümler geçerli):** `[Ölçüldü]` ag1'de bu adımdaki tek
  taşma, 1. katmanın float'a göre en büyük sapmasını %1,3'ten %40'a çıkarıyor
  (Adım 4 sistem golden'ının OKUNUR.txt'si); 200 rastgele adımda sapması %10'u aşan adımlar %7 (ag1) ve
  %18,5 (ag2), doymayla hiç yok. Tez tartışmasında yer almalı.
- **D9 ile çelişki:** D9 "−127..127, −128 yok" diyor; doymasız SRU −128 üretebilir.
  `[Ölçüldü]` Alt bloklar −128'i doğru işliyor: PE (D23, vektörlerde var), ReLU ve WU
  (bütün 256 değer), Egemen'in CLU'su (a'da −128 olan 400 yeni vektörün hepsi
  golden'la aynı, 03.11).
- **Durum:** `sru_golden.py`'de `DOYMA = False`, ayar kodu `1 1 0 1`. Üretilen vektörler
  Egemen'in repodaki 28.10 vektörleriyle birebir aynı. Egemen'in `stochastic_round.v`'si
  değişmeden kullanılıyor. ±127'ye dönmek gerekirse: golden'da tek bayrak, RTL'de hazır
  4 satır (D38'deki `q[6:0] | {7{q[7]}}`).

### D60 — D8: şimdilik (a), en yakına yuvarlama (D57 askıda)
- **Ne:** CLU'nun son >>4'ü `(e + 8) >> 4` ile en yakına yuvarlanır (Egemen'in
  `clu_top.v`'si ve `golden_model.py`'si böyle).
- **Neden:** Ömer, 03.11. `[PDF tam: NITI §3.5, s. 3255]` "For a dataset with 1000
  classes like ImageNet, stochastic rounding is necessary to avoid round bias in e_i."
  Bizim ağlar 10 sınıflı; farkın etkisi ölçülmedi.
- **Durum:** `rtl/clu_yuvarlama/` (D57) hazır ama kullanılmıyor. Sistem golden'ındaki CLU yer
  tutucusu Adım 4'e geçerken (a)'ya döndürülecek; (a) hâli Egemen'in golden modeliyle
  1940 vektörde birebir aynı `[Ölçüldü]`.

### D61 — SRU'ya hedef girişi (D40'ın RTL'i)
- **Ne:** `lms_group16.v`, `global_max_b.v` ve `global_max_reducer16.v`'deki sabit 7
  yerine 3 bitlik `hedef` girişi; `sru_top.v`, `sru_channel.v` ve `sru_array.v` bunu
  aşağı iletir. a ve e için 7, g için m_u. Değer 1..7 olmalı ve bir iş boyunca sabit
  kalmalı (D56: İŞ_BAŞLA sürer).
- **Neden:** D40 (Ömer, 03.11: "aynen koruyalım").
- **Nasıl:** Egemen'in dosyalarının kopyası `rtl/sru_hedefli/` (modül adları aynı olduğu için `rtl/sru` ile
  aynı Vivado projesine eklenmemeli); başka satır değişmedi,
  her dosyanın başında değişiklik notu var. Asılları değişmedi; repoya Egemen'in onayıyla
  girer.
- **Kanıt:** `[Ölçüldü]`
  - Egemen'in bütün SRU testleri (hedef = 7 bağlanarak) aynen geçiyor: 154, 2297, 52,
    12, 52, 12.
  - Yeni `tb_sru_gradyan`: `wu_katman.txt`'nin 16 case'i (m_u 1..5), SRU + `wu_unit`,
    1865/1865.
  - Bilerek sokulan 4 hatanın 4'ü yakalandı.

### D62 — CLU'nun "hazır" sinyali: sabit gecikme, Egemen'in koduna dokunmadan
- **Ne:** `fe_top.v`, `clu_basla`'da girişleri tutuyor, 77 çevrim sayıp çıkışları yakalıyor
  ve `clu_bitti` veriyor. Egemen'in `valid`'i (ilk dolumdan sonra hep 1) kullanılmıyor.
- **Neden:** Ömer, 03.11 (seçenek a: "zorunda kalmadıkça değişiklik yok"). Egemen'in kendi
  testbench'i de sabit süre bekliyor.
- **77'nin kaynağı:** 10 kanal kenar 1..10'da bölücüye giriyor, 66 çevrim sonra (en geç
  kenar 76) yazılıyor; kenar 77'de yakalanıyor. `[Ölçüldü]` 77 ile 1940 vektörün hepsi
  doğru, 76 ile hatalı. Egemen'in `DIV_LATENCY = 66`'sına ve IP'nin 66 çevrimine bağlı.
- **Durum:** `tb_fe_top` 456.144/456.144: Icarus'ta davranışsal bölücüyle, Vivado'da gerçek
  IP'yle (Ömer, 03.11). `tb_sru_gradyan` de Vivado'da 1865/1865.

---

## Adım 4 kararları (03.11.2026)

### D63 — SRU tamponu 64 grup, grup sayaçları 7 bit (D30'daki MAX_GROUPS = 16'nın yerine)
- **Ne:** `sru_top.v` ve `sru_channel.v`'de `MAX_GROUPS = 64`; `wr_ptr`, `rd_ptr`, `n_groups`
  7 bit (`PW`). Başka satır değişmedi.
- **Neden:** Tek PE ile (D43) bir işte en çok 56 (ag1) ve 60 (ag2) grup oluşuyor `[Ölçüldü]`.
- **Nasıl:** D61'deki kopyanın kopyası, `rtl/sru_64/` (`rtl/sru/` ve `rtl/sru_hedefli/` ile aynı projeye eklenmemeli: aynı modül adları). Egemen'in asılları ve `rtl/sru_hedefli/`'deki
  kopya değişmedi.
- **Kanıt:** `[Ölçüldü]`
  - Yeni `tb_sru_buyuk` (64, 60, 56, 17, 1 grup ve boyu karışık 64 grup): 8508/8508.
  - Eski 16 gruplu SRU aynı testte 1241 hata veriyor.
  - Egemen'in altı SRU testi ve `tb_sru_gradyan` aynen geçiyor.

### D64 — Entegrasyonun arayüz sözleşmesi (Adım 4.0)
- **Ne:** `rtl/sistem/ARAYUZ_SOZLESMESI.md`. Özet:
  - **A1:** FSM değişmiyor; `maks_reg` çıkıyor, `maks_G` ← SRU `G_out`.
  - **A2:** Tek komut yürütücüsü, bütün `kom_bitti`'leri o veriyor.
  - **A3:** SRU'nun durdurulamayan GMS akışı 64 gruplu bir FIFO'ya yazılıyor; her KOPYA/WU
    bir grup alıyor.
  - **A4:** Son grup bir kayıtta bekletiliyor, ÖLÇEK onu `last_group` ile itiyor.
  - **A5:** Bellekler register dizisi; adres düzeni belgede.
  - **A6:** Psum FIFO düz int32 FIFO, derinlik 256 (ag2'de en çok 144).
  - **A7:** Tek kanal SRU, 64 grup (D63).
- **Neden:** Ömer, 03.11. A3 için "Egemen'in SRU'su değişmeden kalsın"; diğer maddelere itiraz
  yok. Shao arayüzleri tanımlamıyor; hepsi `[Çıkarım]`.
- **Not:** A3 GMS'i tüketiciye giderken değil, SRU'nun akışında yapıyor. Shao Fig. 6'ya geri
  basınç daha yakın olurdu; 16×16 ölçeğinde (Adım 5) yeniden düşünülebilir.

### D65 — Sistem golden'ında float kontrolü: sıkı eşikler doymalı referansta
- **Ne:** Yazılan vektörler doymasız (D59). Sıkı eşikler (FP sapması < 0,1, kosinüs > 0,95)
  aynı adımın doymalı bir referans çalıştırmasında denetleniyor; doymasız sonucun sapması
  yalnızca raporlanıyor.
- **Neden:** Ömer, 03.11: "ana şablonda ne ise öyle kalsın, Egemen'in sistemine uygun olanı al ve
  makaleye bağlı kal". `[Ölçüldü]` Doymasızda ag1'in 1. katman sapması 0,40 (eşik 0,1), ag2'de
  0,04; doymalı referansta en çok 0,035 ve 0,043.
- **Durum:** `sistem_golden.py` (Adım 4; III-a, III-b). `komutlar.txt`'ler değişmedi; `tb_fsm` yeni
  vektörlerle 6206/6206 (Icarus).

### D66 — PE motoru: satır tamponlu ön-getirme, golden'la çevrim çevrim aynı akış
- **Ne:** Bir PE komutu (`pe_motoru.v`) sırayla: 9 ağırlık (1 çevrim), 3 kaynak satır (3 çevrim;
  dolgu ve sütun kayması satır tamponuna yazılırken yerleşir), WG'de hata satırı (1 çevrim),
  `ilk = 0` ise kısmi toplamlar Psum FIFO'dan, akış, sonra `son = 0` ise çıkışlar FIFO'ya ya da
  `son = 1` ise grup. Akışın t. çevriminde golden'ın t. çevrim girişi verilir; golden'ın t. çevrim
  çıkışı bir sonraki çevrimde alınır.
  - BP s2'de 4 şerit Psum FIFO'da art arda durur (şerit 0'ın n değeri, sonra 1, 2, 3); okuma da
    aynı sırayla.
  - BP s2 grubu, şeritlerden dX koordinatlarına yerleştirilip dolgu kırpılarak kurulur (D52'nin RTL'i).
- **Kanıt:** Shao Fig. 8'de Input/Weight Prefetch var, zamanlaması yok: `[Çıkarım]`. Çevrim kuralı
  `[Ölçüldü]`: `tb_veriyolu` her akış çevriminde PE'nin 13 girişini, her geçerli çıkışı ve her grubu
  golden'ın izine (`pe_izi.txt`) karşı karşılaştırıyor; ag1'de 944, ag2'de 1908 geçişin hepsi aynı.
  D16'daki "kayma 2/1" Egemen'in testbench'lerinin dizinlemesi; RTL çıkışı golden'ın figür çevrimiyle aynı.
- **Sınırlar (test sistemi):** w ve wo ≤ 16 (bir satır tek okumada), w + 2p ≤ 30, grup ≤ 16 eleman,
  bir geçişin kısmi toplamı ≤ 64 int32. 16×16 dizide (Adım 5) yeniden tasarlanacak.
- **Durum:** Claude, 03.11, Paket 2. Icarus'ta ve Vivado'da (Ömer, 03.11, gerçek bölücü IP'siyle) geçti.

### D67 — Test belleği ve komut yürütücüsünün ayrıntıları (A2, A5'in uygulanması)
- **Ne:**
  - Tek bayt dizisi (`bellek.v`, 8 KB). Bir çevrimde art arda 16 bayt okunur ya da yazılır. İki
    okuma portu (A: PE motoru ve yürütücü, B: CLU'nun etiketi), bir yazma portu. Bölge tabanları
    yapılandırma portlarından (`cfg_taban_*`); adres düzeni sözleşmenin Bölüm 4'ündeki gibi.
  - BP s2'de bir grubun iki dX satırı bellekte bitişik: KOPYA tek yazmayla (2w ≤ 16 bayt) yazar,
    ReLU-geri maskesini de tek okumayla alır.
  - Her KOPYA ve WU 1 çevrimde GMS FIFO'dan bir grup alır; ReLU ya da w − g fonksiyon motorunda
    saatsiz, yazma bir sonraki kenarda.
  - ÖLÇEK'te bekleyen grup yoksa yürütücü takılmadan bitirir ve hata bayrağı verir. FIFO'ların
    taşma/eksik bayrakları da dışarı veriliyor; testte hepsi 0.
- **Neden:** Shao'nun çok bankalı tamponları (III-D) 16×16 diziyle birlikte Adım 5'in işi; bu bellek
  yalnızca test ağının (~2 KB) simülasyonu için. `[Çıkarım]`
- **Not:** Test, bölgeler arasına 16 baytlık boşluk koyuyor; boşluklar ve çıkış bölgeleri başlangıçta
  sabit bir desenle dolu. Satır dışını okumak ya da yazılmamış yeri okumak böylece sonuca yansıyor.
- **Durum:** Claude, 03.11, Paket 2.

### D68 — Egemen'in `stochastic_round.v`'sinde latch uyarısı — AÇIK (Egemen'in kararı)
- **Ne:** `top` ve `bot`, `always @(*)` içinde yalnızca `eff_bp != 0` dalında atanıyor; Yosys bu iki
  değişken için latch çıkarıyor `[Ölçüldü, Yosys, 03.11]`.
- **Etkisi:** İşlevsel değil. Tutulan değer hiçbir yerde kullanılmıyor (yalnızca aynı dalda okunuyor);
  bütün SRU testleri geçiyor. FPGA sentezinde de latch uyarısı beklenir `[Emin değilim]`; kaynak
  raporunu ve zamanlama analizini kirletebilir.
- **Öneri:** Bloğun başında `top = 0; bot = 0;` atanması. Dosyaya dokunulmadı; karar Egemen'in.
- **Durum:** Açık.

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
  dönmesine yol açabiliyor — makalenin kendi eksiği, bkz. yukarı (02.11'de
  D38 ile ±127 doymaya çevrildi; 03.11'de geri alındı, D59)

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
7. **Vivado'da proje yolunda boşluk varsa `-testplusarg` ile verilen klasör yolu
   bozulur**, testbench dosyayı bulamaz. Çözüm: testbench dosyayı bulamazsa
   çalışma klasörüne baksın; Vivado script'i vektörleri oraya da kopyalasın
   (`rtl/fe` ve `rtl/clu_yuvarlama` script'leri böyle).
8. **Testbench'te bir darbeyi verdiğin kenarda DUT'un register'ını okursan eski
   değeri görürsün.** Örnek: `basla`'dan hemen sonra `bitti` hâlâ önceki turun
   1'i. Çözüm: bir kenar daha bekleyip sonra kontrol et.
9. **İşaretli bir karşılaştırıcıya mutlak değer verilirse |−2^31| = 2^31 negatif
   görünür.** Örnek: `lms_group16.v`'de mutlak değerler işaretli `max_tree`'ye
   gidiyor; [−2^31, 5] grubunda B = 3 çıkıyor, 32 olmalı `[Ölçüldü]`. Çözüm:
   mutlak değerleri işaretsiz karşılaştır. PE çıktıları pratikte bu değere
   ulaşmaz, düşük öncelikli.
10. **XSIM, geniş bir task girişine doğrudan verilen karşılaştırma ifadesini bozuk
   değerlendirebiliyor.** Örnek: `tb_pe_blok`'ta `kontrol_et(f_bos, (k_say == 0), ...)`,
   288 bitlik girişte Icarus'ta doğru, Vivado XSIM'de anlamsız bir değer (`1b13...XXXz...`)
   verdi; DUT doğruydu `[Ölçüldü, 03.11]`. Çözüm: beklenen değeri önce bir değişkene ata,
   task'a değişkeni ver.
