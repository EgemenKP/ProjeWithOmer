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
**D108**), asla eskisini silme veya numarayı tekrar kullanma — eski bir D
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
| **`final/`: tek PE, 9 MAC (D69)** | Tamamlandı; sistemde sarmalayıcının yerinde | 80.357/80.357 eskiye karşı; Egemen'in PE testleri 176/176 (eski ve yeni PE); sistem testlerinin hepsi aynı sayılarla PASS. Vivado'da gerçek bölücü IP'siyle doğrulandı (Ego, 04.11) | `final/rtl/pe/pe_birlesik.v` |
| **`final/`: tek SRU (D70) + D68 + D71** | Tamamlandı | SRU testleri hepsi PASS, `tb_lms_uc` 20.013/20.013; Vivado'da doğrulandı (Ego, 04.11) | `final/rtl/sru/` |
| **`final/`: `run_sim.tcl` (sistem, pe, sru, clu, fe)** | Tamamlandı | Beşi de Vivado'da gerçek bölücü IP'siyle PASS (Ego, 04.11); `tb_sru_gradyan` yalnızca `sru` script'inde (aşağıda 04.11 notu) | `final/rtl/*/run_sim.tcl` |
| **Adım 5a: 16×16 PE dizisi (D72–D75)** | Tamamlandı; D104/D105 ile güncellendi | `tb_pe_dizi` 2.363.392/2.363.392 (XSIM CLI, D105 sonrası davranışsal DSP modeliyle), 7 mutasyonun 7'si yakalandı | `final/rtl/dizi/pe_dizi.v` |
| **Adım 5b: 16×16 dizili tam sistem (D76–D93)** | Tamamlandı | ag1–ag4 golden'la bit bit (04.11); bugün ag1–ag6 için aşağıdaki satır geçerli. Vivado'da gerçek bölücü IP'siyle henüz koşulmadı (Ego) | `final/rtl/dizi/`, `final/models/sistem/` |
| **Adım 5c: donanımlaştırma (D94–D100) + Faz 2–4 (D103–D107)** | Tamamlandı | XSIM CLI, ag1–ag6: `tb_dizi_motoru` 57.957/57.957, `tb_sistem_dizi` 65.142/65.142 (419.000 çevrim); Egemen'in PE testleri DSP modeliyle PASS; Adım 4'ün 6 testi PASS (D107 kaydı). Sentez (`flatten none`): LUT 422.611 (%97,6), RAMB36 824, DSP 2.359, WNS −12,2 ns (D107 öncesi) | `final/rtl/dizi/`, `final/rtl/pe/mac_dsp.v` |
| **Adım 6: CIFAR-10 (Fig. 9) (D87–D89, D101, D102)** | Sürüyor | `kontrol_hizli.py` 6/6 (hizli_model golden'la bit bit); çerçeve NITI'nin vggsmall7'siyle doğrulandı (30 epoch test %76,45); VGG16-like 200 epoch koşusu sürüyor, VGG16 referansı sırada | `final/models/cifar/` |

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
- **03.11 (akşam): KAPANDI, `final/`'de.** Egemen'in kararıyla öneri uygulandı (`final/rtl/sru/stochastic_round.v`,
  2 satır). `[Ölçüldü]` Bütün SRU testleri aynen geçiyor (154, 12, 2297, 12, 52, 52, gradyan 1865).
  Vivado 2026.1 sentezi (OOC, xc7vx690t) eski ve yeni dosyada 0 latch, aynı LUT sayısı veriyor: latch
  yalnızca Yosys'te görülüyordu, Vivado kullanılmayan değeri zaten atıyor. Düzeltme yine de kalıyor
  (kod her araçta temiz).

---

## Adım 5 öncesi düzeltmeler — `final/` klasörü (03.11.2026, akşam)

Ego'nun kararı: projenin kalanı Ego + Claude. Mevcut `rtl/` ve `models/` `final/` altına kopyalandı;
değişiklikler yalnızca `final/`'de, eski düzen karşılaştırma için değişmeden duruyor. Doğrulama:
Claude Vivado 2026.1 XSIM'i komut satırından (xvlog/xelab/xsim, davranışsal bölücü) çalıştırdı; gerçek
bölücü IP'li `run_sim.tcl` koşusu Ego'da (Claude'un başlattığı batch Vivado'da `launch_simulation`
"Spawn failed" veriyor).

### D69 — Tek PE: Shao Fig. 2'nin 9 MAC'i, 6 mod (`final/rtl/pe/pe_birlesik.v`)
- **Ne:** Sistemdeki PE, Egemen'in beş ayrı devresini (45 MAC) seçen `pe_sarmalayici` yerine 9 MAC'lik
  tek bir yeniden yapılandırılabilir PE. Portları sarmalayıcıyla aynı; `pe_motoru.v`'de yalnızca modül
  adı değişti. `mac.v` değişmedi.
- **Kanıt:** `[PDF tam]` Shao III-A (s. 256): "nine multiply-accumulate units (MACs), several
  multiplexers, and a partial sum (Psum) FIFO queue". `[PDF şekil]` Fig. 2: MAC'in dış portları
  1 = Weights/Errors, 2 = Activations/Errors; iç portları 3 = Partial sum, 4 = Passed value/0,
  5 = Accumulated value; satır sonlarında iki toplayıcı ve Psum FIFO'ya giden mux'lar.
- **Eşleme (Fig. 2 yorumu, `[Çıkarım]`):** port 3 yalnızca zincir başlarında Psum FIFO'dan (FP/BP s1:
  r0c0; BP s2: A/B zincirlerinin satır 0-1 başları); port 4 soldaki MAC'in sonucu ya da 0 (satır 1-2
  başları, BP s2'nin B zinciri); port 5 WG akümülatörü. WG'de port 1 = hata (c çevrim gecikmeli),
  port 2 = aktivasyon (Egemen'in WG devrelerinde tersiydi; çarpım aynı). Çıkışta iki toplayıcı:
  FP/BP s1 `(m02 + m12) + m22`, BP s2 `m01 + m21` ve `m02 + m22`.
- **Fark (`[Çıkarım]`):** zincir, mavi D ve hata gecikme register'ları modlar arasında ortak. Mod
  değişince önceki modun değerleri en çok 3 çevrimde 0 akışla temizleniyor; PE motoru her komuttan önce
  en az 4 çevrim 0 akış veriyor (D_AGIRLIK + D_SATIR). WG akümülatörleri boşta (mod 6/7) korunur ama
  başka bir modda çalışılınca bozulur; PE motoru bir WG işinin komutları arasına başka mod koymuyor (D47).
- **Kanıt:** `[Ölçüldü]`
  - `tb_pe_birlesik` (yeni): eski sarmalayıcıya karşı adım adım, PE motorunun komut düzeniyle; 3000
    komut, 6 mod, 1255 mod geçişi: 80.357/80.357. Bilerek sokulan 5 hatanın 5'i yakalandı.
  - Egemen'in PE testbench'leri değişmeden, `pe_birlesik_kabuklar.sv` üzerinden: 38+38+34+24+32+5+5.
  - Sistem: `tb_veriyolu` 71.048/71.048 (PE girişleri ve çıkışları golden izine karşı çevrim çevrim),
    `tb_sistem` 21.415/21.415, `tb_pe_blok` 380.490, `tb_fsm` 6206, `tb_sru_buyuk` 8508.
  - Sentez (Vivado 2026.1, OOC, xc7vx690t): eski sarmalayıcı LUT 5127 / FF 1366, birleşik PE LUT 1445 /
    FF 360; ikisinde de DSP 0 (8×8 çarpımlar LUT'a eşleniyor), latch 0. Zamanlama analizi yapılmadı.
- **Durum:** Claude, 03.11, `final/`. Egemen'in beş devresi referans olarak duruyor (`tb_pe_blok`,
  `tb_pe_birlesik`). 16×16 dizi (Adım 5) bu PE'den kurulacak.

### D70 — Tek SRU: `rtl/sru_hedefli/` ve `rtl/sru_64/` kopyaları `final/rtl/sru/`'da birleşti
- **Ne:** D61 (hedef girişi) ve D63 (64 grup, 7 bitlik sayaçlar) kopyalarının son hâli
  (`rtl/sru_64/`) `final/rtl/sru/`'ya taşındı; iki kopya klasörü `final/`'de yok. Egemen'in değişmeyen
  alt blokları (`bit_length32`, `gms_group16`, `stochastic_round`) aynı klasörde. Egemen'in SRU
  testbench'lerine yalnızca `.hedef(3'd7)` bağlandı; `tb_sru_gradyan` `rtl/sru/`'ya taşındı.
- **Neden:** Aynı modül adlarıyla üç klasör aynı projeye eklenemiyordu (D61, D63 notları); Adım 5'te
  16 kanal (`sru_array`) hedef girişi ve 64 grupla gerekiyor. `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` Egemen'in altı SRU testi (154, 12, 2297, 12, 52, 52), `tb_sru_gradyan` 1865,
  `tb_sru_buyuk` 8508, sistem testleri: hepsi PASS.
- **Durum:** Claude, 03.11, `final/`.

### D71 — LMS'te |−2^31|: mutlak değerler 33 bitle karşılaştırılıyor (araç tuzağı 9'u kapatır)
- **Ne:** `final/rtl/sru/lms_group16.v`: mutlak değerler `{1'b0, |x|}` olarak 33 bitlik işaretli
  `max_tree`'ye veriliyor. 32 bitte |−2^31| = 2^31 negatif görünüyordu.
- **Kanıt:** `[Ölçüldü]` Yeni `tb_lms_uc` (uç gruplar + 20.000 rastgele grup, hedef 1..7): yeni LMS
  20.013/20.013; eski LMS aynı testte [−2^31, 5] için B = 3 (doğrusu 32), [−2^31] için B = 0 veriyor.
  Diğer bütün SRU testleri değişmedi. `global_max_reducer16` yalnızca 6 bitlik pozitif B'leri
  karşılaştırdığı için etkilenmiyor.
- **Durum:** Claude, 03.11, `final/`. PE çıktıları pratikte −2^31'e ulaşmaz; düzeltme doğruluk için.

### 04.11 notu — `final/` Vivado koşusu (gerçek bölücü IP'si, Ego)
- `[Ölçüldü]` sistem: fsm 6206, sru_buyuk 8508, pe_blok 380.490, pe_birlesik 80.357, veriyolu 71.048,
  sistem 21.415. pe: ASIL ve BIRLESIK 38+38+34+24+32+5+5 = 176/176 (D69'daki "138" yanlış toplamdı).
  sru: 154, 12, 2297, 12, 52, 52, lms_uc 20.013, gradyan 1865. clu 40/40. fe: relu 196.608, wu 65.536,
  fe_top 456.144. Hepsi PASS.
- `tb_sru_gradyan` `fe/run_sim.tcl`'den çıkarıldı (D70 ile `rtl/sru/`'ya taşınmıştı, `sru` script'inde
  geçiyor). fe script'inin tek `sim_1` fileset'inde `launch_simulation` "failed due to earlier errors"
  verdi; log'larda ERROR yoktu, kök neden bulunamadı. Aynı dosya setiyle komut satırında xsim 1865/1865.
  Tasarım değişikliği değil, test düzeni.

---

## Adım 5 kararları — 16×16 PE dizisi (04.11.2026, `final/`)

Ego'nun talimatı: tercihler makaleye sadık seçilsin, şekiller tek başına değil Shao'nun metniyle
birlikte yorumlansın. Kaynaklar: III-A (s. 256), III-B (s. 257), III-D, Fig. 8 ve Table I (s. 258).

**D30 Fig. 8'le teyit edildi (yeni madde değil):** Fig. 8'de her PE satırının çıkışları (yeşil)
satırın sonundaki tek bir SRU'ya giriyor; 16 satır, 16 SRU, hepsi çıkış tamponuna yazıyor. III-D:
"The outputs of PE array are scaled and rounded by SRU before transmitted to the output buffer."
Grup = bir satırın 16 PE çıkışı (sütunlar farklı çıkış kanalları), tek paylaşılan G (Fig. 6).

### D72 — FP ve BP'de PE satırlarına çıkış satırı (row), sütunlara çıkış kanalı açılır
- **Ne:** Satır r'deki PE'ler çıkış haritasının r. satırını, sütun c'dekiler c. çıkış kanalını
  hesaplar. Satır r'nin 16 PE'si aynı 3 giriş satırını, sütun c'nin 16 PE'si c kanalının 9
  ağırlığını alır.
- **Kanıt:** `[PDF tam]` III-D (s. 258): "each row shares the same input and each column shares the
  same weight"; "Inputs are unrolled along the batch or row dimensions for different PE rows,
  meanwhile, weights are unrolled along the output channel dimension for different PE columns."
  `[PDF şekil]` Fig. 8: giriş tamponunun her bankası bir satıra (mavi, yatay), ağırlık tamponunun
  her bankası bir sütuna (kırmızı, dikey). III-A + Fig. 3: bir PE 3 giriş satırından bir çıkış
  satırı üretiyor.
- **Seçim:** Metindeki iki seçenekten (batch ya da row) "row". Test ağlarında batch 2–3; batch
  açılımı 16 satırın 13–14'ünü boş bırakırdı. Sapma değil, metindeki seçeneklerden biri. `[Çıkarım]`
- **Durum:** Claude, Ego'nun onayıyla, 04.11. Dizi modülü (`pe_dizi.v`) açılımdan bağımsız; açılım
  ön-getirmenin (5b) işi.

### D73 — WG'de PE satırlarına giriş kanalı açılır (Shao'nun metni bu fazı çözmüyor) — AÇIK SORU
- **Ne:** WG'de PE (r, c) giriş kanalı r ile çıkış kanalı c arasındaki 3×3 gradyanı kendi
  akümülatörlerinde batch ve konum üzerinden tam biriktirir. Satıra r kanalının aktivasyonu,
  sütun boyunca c kanalının hatası gelir.
- **Neden:** WG'de toplama batch ve konum üzerinden. Satırlara batch ya da row açılırsa her PE satırı
  aynı gradyanın bir parçasını hesaplar ve parçaların satırlar arasında toplanması gerekir; Fig. 8'de
  satırlar arası toplayıcı yok. Parçaları satırların ayrı SRU'larından geçirmek de olmaz (farklı ölçek).
- **Kanıt:** `[PDF tam]` III-A: WG output-stationary. `[PDF şekil]` Fig. 2: port 1 "Weights/Errors"
  (WG'de hata), port 5 akümülatör; Fig. 8: satırlar arası toplayıcı yok. III-D'deki "batch or row"
  cümlesi FP/BP için yazılmış sayıldı; bu bir yorum. `[Çıkarım]`
- **Not:** Fig. 8'de sütunlara giden hat ağırlık tamponundan geliyor; WG'de hatanın hangi tampondan
  geleceği metinde yok. Shao'ya sorulabilir (D5'teki gibi).
- **Durum:** Claude, Ego'nun onayıyla, 04.11. 5b'de ön-getirme ve golden'da uygulanacak.

### D74 — Psum FIFO her PE'nin içinde; kayıt 128 bit (4 şerit), derinlik 64
- **Ne:** `pe_dizi.v`'de her PE'nin kendi FIFO'su (`psum_fifo`, `GENISLIK = 128`). Bir kayıt PE'nin
  bir çevrimlik çıkışı (`cikis_flat`): FP/BP s1'de yalnızca şerit 0, BP s2'de 4 şerit. Okumada BP
  s2'nin B şeritleri (1, 3) bir çevrim gecikmeli verilir; tek PE'deki (D66) psA(t) = psum[t],
  psB(t) = psum[t − 1] ile aynı. Kontroller (yaz, oku, seç, temizle) dizi geneli.
- **Kanıt:** `[PDF tam]` III-A: PE "nine MACs, several multiplexers, and a partial sum (Psum) FIFO
  queue" içeriyor. `[PDF şekil]` Fig. 2'de FIFO PE'nin içinde; Fig. 8'de PE dışında FIFO yok.
  Adım 4'teki tek dış FIFO (D64 A6) tek PE içindi.
- **Derinlik:** Hâlâ açık (D12). 64: satır açılımında (D72) PE başına bir kanal geçişi için batch × wo
  kayıt (test ağında ≤ 3 × 16 = 48). `[Çıkarım]`
- **Durum:** Claude, 04.11.

### D75 — MAC'ler DSP'ye eşlenir (`use_dsp`)
- **Ne:** `final/rtl/pe/mac.v` modülüne `(* use_dsp = "yes" *)`. Davranış aynı.
- **Kanıt:** `[PDF tam]` IV + Table I (s. 258): 2324 DSP, "the MACs in PE array consume the most DSP";
  256 × 9 = 2304 MAC. `[Ölçüldü]` Vivado 2026.1 OOC, xc7vx690t: `pe_birlesik` DSP 0 → 9, LUT 1445 →
  723, FF 360 → 72 (MAC'in toplayıcısı ve register'ı da DSP'ye giriyor). DSP'siz 256 PE ≈ 370 bin LUT
  olurdu (VC709: 433 bin).
- **Durum:** Claude, 04.11.

### Adım 5a — `pe_dizi.v` (16×16) ve testi
- **Ne:** `final/rtl/dizi/pe_dizi.v`: 256 `pe_birlesik`, satır başına akış, sütun başına ağırlık,
  PE içi Psum FIFO (D74). Grubun SRU'ya kurulması ve dizi kontrolü 5b'de.
- **Kanıt:** `[Ölçüldü]` `tb_pe_dizi`: 256 ayrı `pe_birlesik` + testbench'te SV kuyruklarıyla yazılmış
  FIFO/B gecikmesi referansına karşı, her satıra ve sütuna her çevrim farklı rastgele değer, 400
  rastgele komut (6 mod, rastgele FIFO kontrolleri), her çevrim 256 PE'nin bütün çıkışları:
  2.363.392/2.363.392 (XSIM CLI).
- **Mutasyon:** `[Ölçüldü]` Bilerek sokulan 7 hatanın 7'si yakalandı (60 komutluk kısa testle): akış
  satır yerine sütun indisiyle, ağırlık sütun yerine satır indisiyle, B gecikmesi yok, `ps_sec`
  yok sayılıyor, BP s2 şeritleri yer değiştirmiş, FIFO'ya şerit 0 yazılmıyor, akis3 komşu satırdan.
- **Sentez:** `[Ölçüldü]` Vivado 2026.1 OOC, xc7vx690t, `pe_dizi` 16×16: DSP 2304 (%64; Shao Table I
  bütün sistem için 2324), LUT 243.689 (%56; 199.657 mantık + 44.032 LUTRAM, PE içi FIFO'lar), FF
  27.808, BRAM 0, latch 0. Zamanlama analizi yapılmadı.
- **Not (karşılaştırma):** Shao'nun bütün sistemi 171.248 LUT; bizim yalnızca dizimiz bunu aşıyor.
  Muhtemel nedenler `[Çıkarım]`: PE'deki 6 modluk mux'lar (PE başına ~780 LUT) ve FIFO'ların LUTRAM'de
  olması (Shao'nun 896 BRAM'i tamponlar için). FIFO'yu BRAM'e taşımak 5b'de değerlendirilebilir.
- **Durum:** Claude, 04.11, `final/rtl/dizi/`. `dizi/run_sim.tcl` Vivado'da 2.363.392/2.363.392 PASS (Ego, 04.11).

### D73 eki (04.11, 5b) — WG'de hata sütun hattından geliyor
- **Ne:** D73'e göre PE (c, o) o kanalının hatasını almalı, yani hata sütuna göre değişir. 5a'daki
  `pe_dizi.v` hatayı satır hattından veriyordu; düzeltildi: WG s1/s2'de PE'nin hata girişi (pe_birlesik'in
  akis2/akis3'ü) sütun hattının alt 24 bitinden sürülüyor.
- **Kanıt:** `[PDF şekil]` Fig. 2: port 1 "Weights/Errors" — aynı port FP/BP'de ağırlığı, WG'de hatayı
  alıyor; Fig. 8'de bu port sütun hattına (kırmızı) bağlı. `[Ölçüldü]` `tb_pe_dizi`'nin referansı da
  bağımsız olarak güncellendi: 2.363.392/2.363.392; eski bağlantı (hata satırdan) mutasyon olarak 55.808 hata verdi.

### D76 — Dizide SRU grubu: bir PE satırının bir çevrimde verdiği, sütun başına bir değer (D30'u daraltır)
- **Ne:** Satır i'nin grubu, sütunlardan birer değer (en çok 16):
  - FP / BP: aynı (örnek, konum)daki en çok 16 kanal. BP s2'de dolguya düşen konumlar gruba girmez (D52).
  - WG: aynı (giriş kanalı, ki, kj)deki en çok 16 çıkış kanalı (bir satırın 9 grubu).
  Satır i'nin grupları i. SRU kanalına gider, G bütün kanallarda ortak (D30).
- **Neden:** D30 "bir PE satırının bir geçişte ürettikleri" diyordu; tek PE'de (Adım 4) bu wo değerdi.
  16×16'da bir satır bir geçişte 16 × wo değer üretiyor, ama Egemen'in SRU kanalı (`lms_group16`) en çok 16
  değerlik grup alıyor. `[PDF şekil]` Fig. 8: satırın 16 PE çıkışı aynı anda satırın SRU'suna gidiyor.
  `[PDF tam]` III-B: "a group of int32 output data, which is part of the full-layer outputs". Grubun
  boyu metinde yok; 16 = satırın sütun sayısı = Egemen'in SRU genişliği. `[Çıkarım]`
- **Sonucu:** LMS grup başına yuvarladığı için sonuçlar Adım 4'ün (tek PE) sayılarıyla aynı değil
  `[Ölçüldü]`: ag1'de AKT1 %3, AKT2 %22, AKT3 %80 (son katman: Adım 4'te her sınıf ayrı grup, şimdi 10
  sınıf tek grup), son ağırlıklar %32 farklı; ag2'de %1, %7, %23, %10. s_a'lar aynı.
- **Kanıt (golden):** `[Ölçüldü]` `final/models/sistem/dizi_golden.py`:
  - (I') dizi yorumlayıcı (geçiş geçiş, PE başına pe_golden çevrim modeli ve Psum FIFO, satır başına grup)
    ile (II') tensör düzeyi (ref_fp/bp/wg + aynı grup tanımı) ag1 ve ag2'de bit bit aynı (8 iş, 324 grup).
  - Float (doymalı referans, D65): FP sapması ≤ 0,047, kosinüs ≥ 0,968. Doymasız ag1'de 0,402 (D59, Adım
    4'teki ile aynı).
  - SRU kanalı başına bir işte en çok 30 grup (≤ 64, D63); PE başına Psum FIFO en çok 15 kayıt (≤ 64, D74).
- **Durum:** Claude, 04.11, 5b. RTL'de grup kurulumu sıradaki adım.

### D77 — Grup kurucu: satır başına son grup bekletilir, iş sonunda bütün satırlar birlikte last_group ile iter
- **Ne:** `final/rtl/dizi/grup_kurucu.v`. Moda göre her satırın grubunu seçer (PE şeridi ya da WG
  akümülatörü, D76), dolu sütunların dışını 0 yapar ve `sru_array`'e verir. Her satırın en son grubu bir
  kayıtta bekletilir: yeni grup gelince bekleyen itilir, `son_it`'te bekleyenlerin hepsi aynı çevrimde
  `last_group = 1` ile itilir.
- **Neden:** Egemen'in `sru_array`'i bütün kanalların son grubunu aynı çevrimde varsayıyor (paylaşılan G,
  "lockstep", D30). Dizide satırların grup sayısı farklı olabiliyor (BP s2'de dolgu kırpması D52, boş
  satırlar), son grupları farklı çevrimlere düşüyor. Adım 4'teki A4 (D64) çözümünün dizi hâli. `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` `tb_grup_kurucu` (`grup_kurucu` + `sru_array`, dizi golden'ının
  `adim5_vektorleri/dizi_grup.txt`'sine karşı; kayıtta olmayan PE'ler ve dolu sütunların dışı rastgele):
  ag1 + ag2, 16 iş, 648 grup + 16 G: 664/664 (XSIM CLI). Bilerek sokulan 6 hatanın 6'sı yakalandı (sütun
  maskesi yok, şerit seçimi yok, akümülatör indisi 3 bit, son grup itilmiyor, satır/sütun indisi ters,
  last_group yalnızca satır 0'ın maskesiyle).
- **Durum:** Claude, 04.11, 5b. `dizi/run_sim.tcl`'ye eklendi; Vivado GUI'de `tb_pe_dizi` 2.363.392/2.363.392 ve
  `tb_grup_kurucu` 664/664 PASS (Ego, 04.11, araç tuzağı 13'ün düzeltmesinden sonra).

### 5b-3 kararları (04.11, Ego): tam Shao sistemi
Ego'nun seçimi: 5b'nin kalanı Fig. 8'in tam yapısıyla (ayrı giriş/ağırlık/çıkış tamponları, çok bankalı,
dizi için yeni FSM komutları, tam sistem testi). NITI'nin kaynak kodu bu kararlar için incelendi
(`github.com/wangmaolin/niti`: README, `ti_torch.py`, `ti_net.py`, `ti_loss.py`, 04.11): NITI GPU üzerinde
çalışan bir PyTorch/CUDA eğitim kodu; tampon, bank, ön-getirme, PE dizisi ya da döngü çizelgesi içermiyor.
Ölçekleme bütün tensör için tek kaydırmayla yapılıyor (`RangeEstimate`, `act_calc`, `err_calc`,
`grad_calc`); grup kavramı yok. Bu yüzden aşağıdaki kararlarda NITI hakem olamıyor `[NITI GitHub]`.

### D78 — GMS, Fig. 6'daki yerinde: tampondan PE'ye giderken uygulanır (D44'ü geri alır)
- **Ne:** SRU'nun LMS çıkışı (int8) çıkış tamponuna yazılır, grubun l'si saklanır. Sonraki işte ön-getirme
  her değere kendi grubunun Δ = G − l kaydırmasını uygulayarak PE'ye verir. Adım 4'teki ayrı KOPYA
  geçişi (D44, D64 A3) dizi sisteminde yok.
- **Kanıt:** `[PDF tam]` III-B (s. 257): "Before the int8 values are passed to PEs for the next stage
  computation, they need to be scaled by the second stage (GMS)". `[PDF şekil]` Fig. 6: GMS tampon ile PE
  arasında. ReLU ile GMS'in sırası sonucu değiştirmiyor (D53), ReLU LMS çıkışında uygulanabilir.
- **Durum:** Ego, 04.11 ("Fig. 6: PE'ye giderken"). Uygulama 5b-3'te.

### D79 — Giriş tamponu: giriş satırı r, bank (r mod 16)'da; ön-getirme satırları PE satırlarına dağıtır
- **Ne:** III-D'deki "each bank corresponds to one PE row" için: 16 bank, satır r → bank r mod 16. Stride 1'de
  PE satırı i, i, i+1, i+2 satırlarını ister; ön-getirme modülü bankları PE satırlarına yönlendirir, kopya
  yok. Ağırlık tamponu: bank j = dizinin j. sütunu (çıkış kanalı, D72; WG'de hata, D73).
- **Kanıt:** `[PDF tam]` III-D: "multi-bank manner, and each bank corresponds to one PE row or column".
  `[PDF şekil]` Fig. 8: Input Prefetch Module tampon ile PE'ler arasında; III-A: ön-getirme "arranges the
  input data in an appropriate manner according to the computation patterns". Örtüşen satırların bankalara
  nasıl yerleştiği metinde yok. `[Çıkarım]`
- **Durum:** Ego, 04.11. Uygulama 5b-3'te.

### D80–D86 — Dizili sistemin tampon, ön-getirme ve komut kararları (Ego onayı, 04.11)
Ayrıntı ve gerekçeler: `final/rtl/dizi/TASARIM_DIZI.md` (§2–§7). Hepsi `[Çıkarım]`; Shao'nun dayanak cümleleri
belgede. Özet:
- **D80:** Fig. 8'in giriş ve çıkış tamponları aynı çok bankalı veri tamponunun okuma (ön-getirme) ve yazma
  (SRU) yüzleri; bölgeler AKT[0..L], HATA[1..L], GRAD[1..L]. Ayrı tamponlar katmanlar arası kopya isterdi,
  Shao kopyayı yazmıyor.
- **D81:** Kelime = bir grup (D76: bir konumdaki 16 kanal) + grubun l'si (Fig. 6'nın Max Regs'i kelimenin
  yanında). Bank = satır mod 16 (D79); FP/BP s1'de SRU i doğrudan bank i'ye yazar. Bölgenin G'si ayrı register.
- **D82:** Ağırlık bankı = o mod 16, kelime = w[o][c] (9 bayt). FP'de 1, BP'de 16 çevrimlik yükleme.
- **D83:** Tam sistemde `sru_channel`'ın GMS tamponu kullanılmaz: satır sonunda `lms_group16` + paylaşılan
  `global_max_reducer16`, LMS çıkışı (ReLU/ReLU-geri ile) doğrudan tampona; GMS ön-getirmede (D78). Shao'nun
  "Both two stages ... implemented by this unit" cümlesiyle Fig. 8 arasındaki gerilim belgede (§4, §10) açık
  soru olarak duruyor. BP s2'de bank çakışması: şerit adımı iki yarıda yazılır.
- **D84:** Ön-getirmede satır register'ları (W + 2p ≤ 18) ve bank başına `gms_group16`; dolgu, çift/tek ayırma,
  BP s2 sıfır ekleme akışa geçerken (D66'nın zamanlaması).
- **D85:** Komut seti: KOPYA yok; DİZİ geçiş komutu (faz, l, b, x = k0 karosu, y = k1, z = satır karosu / WG'de
  satır, ilk, son); WU komutu (l, o karosu, c) 9 kelime. Döngüler: FP o-karo → c → b → r-karo; BP c-karo → o →
  b → m/p-karo; WG c-karo → o-karo → b → r.
- **D86:** BP'nin ReLU-geri maskesi AKT[l−1]'in GMS'ten geçmiş değerinden (GMS küçük pozitif değeri 0'a
  yuvarlayabilir). D53 ile birlikte, LMS çıkışında uygulanan ReLU/ReLU-geri ile Adım 4'ün "önce GMS" sırası aynı
  sonucu verir. `[Ölçüldü]` Maske olarak kullanılan aktivasyonlardan ag1'de 464'ün 7'sinde, ag2'de 462'nin
  4'ünde ham LMS değeriyle GMS'li değerin işareti farklı (pozitif → 0): maske ham değerden alınsa sonuç değişirdi.

### Adım 5b-3a — Dizili sistemin golden'ı (`dizi_sistem_golden.py`)
- **Ne:** D85'in komut listesi + (III'') tampon modelli komut yorumlayıcı: veri tamponu (16 bank, kelime = 16
  kanal + l, D80/D81), bölge G'leri, ağırlık tamponu (D82), GMS'li ön-getirme (D78, D84), LMS'in ReLU/ReLU-geri
  ile doğrudan yazılması (D83, D86), WU.
- **Kanıt:** `[Ölçüldü]` Tamponun son hâli çözülünce `dizi_golden.py`'nin tensör düzeyiyle (II') bit bit aynı:
  aktivasyonlar, hatalar, son ağırlıklar, s_a ve iş başına G + grup olayları (M, l, Δ), ag1 ve ag2. Bu,
  D53/D86'nın (ReLU'yu LMS çıkışında uygulamak = Adım 4'ün "önce GMS"i) uçtan uca kontrolü.
- **Sayılar:** ag1 102 komut (Adım 4'te 1186: dizi geçişleri 944 PE komutunun yerine 70 DİZİ; KOPYA yok), ag2
  150 komut. Veri tamponu ag1'de 424 kelime (bank başına 85 adres), ağırlık 64 kelime.
- **Vektörler:** `adim5_vektorleri/` (ve `ag2/`): `komutlar_dizi.txt`, `bolgeler.txt`, `veri_baslangic.txt`,
  `veri_beklenen.txt`, `agirlik_baslangic.txt`, `agirlik_beklenen.txt`.
- **Durum:** Claude, 04.11.

### D90 — Ön-getirme RTL'i (`on_getirme.v`) ve tamponlar (Adım 5b-3b)
- **Ne:** `veri_tamponu.v` (16 bank, 134 bitlik kelime = 16 × int8 + l, eşzamanlı okuma), `agirlik_tamponu.v`
  (16 bank, 72 bit), `on_getirme.v`. Ön-getirme bir DİZİ komutunda:
  - **AGR:** FP'de 16 bank paralel 1 okuma; BP'de bank (o mod 16)'dan 16 ardışık okuma, s1'de 180° döndürme, s2'de
    Fig. 4(b) yüklemesi (D82).
  - **SATIR:** FP/BP'de okunan kanalın **bütün haritası** satır register'larına (H ≤ HMAX = 16, W ≤ WMAX = 16);
    WG'de 3 aktivasyon satırı (bir kelime 16 PE satırının kanallarını verir) ve hata satırı (16 sütunun kanalları).
    Her kelime okunurken bank başına bir `gms_group16`'dan geçer (D78).
  - **AKIŞ:** T çevrim; dolgu, çift/tek ayırma (FP s2, WG s2), BP s2 sıfır ekleme satır register'larından akışa
    geçerken. Etkin olmayan satır ve sütunlar 0.
  - Bir okuma fazından sonraki faza geçerken 1 çevrim bekleme (son okumanın yakalanması sırasında bölge ve G
    değişmesin).
- **Neden "bütün harita":** Test ağında haritalar ≤ 7×7. Satır karosu (D79'un 16 satırdan büyük haritalar için
  pencere yüklemesi) ve W > 16 kapsam dışı; CIFAR boyutunda RTL gelecek iş. `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` `tb_on_getirme`: tamponlar golden'ın hâliyle yüklenip (veri: son hâl, her bölge bir kez
  yazılıyor; ağırlık: başlangıç hâli, D46), her DİZİ komutunun akışının her çevriminde 16 satırın akis1/2/3'ü,
  16 sütunun hattı, mod ve T golden'ın `onget_izi.txt`'sine karşı: ag1 + ag2, 184 komut, 6 mod:
  241.128/241.128 (XSIM CLI; ag3 eklenince 489.430/489.430, D91). Bilerek sokulan 8 hatanın 8'i yakalandı (GMS yok, BP s1 döndürme yok, BP s2
  yükleme sırası, FP s2 tek akış kayık, BP s1 dolgusu, WG hata kayık, WG hata bölgesine geçmiyor (zaman aşımı),
  kanal baytı seçimi yok).
- **Durum:** Claude, 04.11.

### D91 — Dizi motoru (`dizi_motoru.v`, Adım 5b-3c)
- **Ne:** Bir DİZİ komutunu yürütür: ön-getirme → `pe_dizi` → (son = 1) grup → satır başına `lms_group16` (B'ler
  paylaşılan `global_max_reducer16`'ya) → ReLU / ReLU-geri (maske GMS'li AKT[l−1], D86) → veri tamponuna kelime + l.
  - Zamanlama D66'nın dizi hâli: akışın t. çevriminde golden'ın t. adım girişi, t. adım çıkışı t + 1. çevrimde;
    akıştan sonra 1 yakalama çevrimi (mod tutulur, girişler 0). Psum: ilk = 0 ise t < T − 2 (BP s2'de T − 1)
    çevrimlerinde FIFO okunur; son = 0 ise geçerli çıkışlar FIFO'ya yazılır.
  - **BP s2, son = 1:** bir çevrimde satır başına 4 grup çıkıyor, LMS ve tampon çevrim başına satır başına bir grup
    alıyor. Çıkışlar satır başına bir kayıt tamponunda (q ≤ WMAX/2 + 2) bekletilip (q, şerit) sırasıyla
    boşaltılıyor; 8'den fazla satır etkinse her adım iki yarıda (satır i ve i + 8 aynı banka yazıyor, D83).
    Shao bu durumu yazmıyor (yalnızca "The Psum FIFO queue receives four partial sums in parallel").
    Bedeli: 16 satır × 16 PE × 128 bit × q kayıt. `[Çıkarım]`
  - **WG, son = 1:** akıştan sonra mod tutulur (girişler 0, akümülatörler sabit), 9 çevrimde akümülatör grupları.
  - İŞ_BAŞLA: hedef tutulur, G toplayıcı ve Psum FIFO'lar sıfırlanır. Komutlar sırayla (D50).
- **AG3 (yeni test ağı, yalnızca dizi sistemi için):** 16×16 giriş, 4 katman (2→3 s1p1, 3→4 s2p1, 4→5 s2p0,
  5→10 s1p0). 1. katmanda 16 PE satırının hepsi dolu; 2. katmanın BP s2'sinde 9 geçiş (iki yarı yolu). ag1 ve ag2'de
  en çok 4 satır etkin olduğu için bu yollar sınanmıyordu.
- **Kanıt:** `[Ölçüldü]` `tb_dizi_motoru`: golden'ın komut listesi sırayla (İŞ_BAŞLA, DİZİ, ÖLÇEK'te motorun G'si
  ve Psum FIFO'ların boşluğu), sonunda veri tamponunun golden'da yazılı bütün kelimeleri (tampon her ağdan önce
  sıfırlanıyor): ag1 + ag2 + ag3, 306 DİZİ komutu, 2784 kelime: 2841/2841 (XSIM CLI). `tb_on_getirme` de ag3 ile:
  489.430/489.430. Bilerek sokulan 9 hatanın 9'u yakalandı (maske GMS'siz, FP ReLU yok, Psum okuma sayısı,
  son'da FIFO'ya yazma (FIFO boşluğu kontrolü eklenince), BP s2 geçerlilik başlangıcı, WG sıfırlama yok, l
  yazılmıyor, m_u yok sayılıyor, BP s2 kayıt indisi).
- **`pe_dizi.v`'ye ek:** `ps_bos` çıkışı (bütün FIFO'lar boş).
- **Durum:** Claude, 04.11.

### D92 — FSM'in dizi hâli (`master_controller_dizi.v`, Adım 5b-3d) ve AG4
- **Ne:** Adım 4'ün `master_controller.v`'sinin (değişmeden duruyor) D85 komut setiyle kopyası: KOPYA yok, PE
  komutu yerine DİZİ geçişi ve karo döngüleri (FP o-karo → c → b → r-karo; BP c-karo → o → b → m/p-karo; WG c-karo
  → o-karo → b → r; WU o-karo → c), ÖLÇEK'ten sonra FP → SA, BP → aynı katmanın WG'si, WG → WU'lar. Portlar ve el
  sıkışma aynı.
- **AG4 (yeni test ağı):** 3→20 (s1p1), 20→18 (s2p0), 18→10 (s1p0), 7×7 giriş, batch 2. 16'dan fazla kanal: FP'de 2
  o-karosu, BP'de 2 c-karosu, WG'de 2×2 karo, WU'da 2 o-karosu. ag1–ag3'te bütün karo sayıları 1'di; karo
  döngüleri RTL'de ilk kez AG4 ile sınandı (hızlı model 2–3 karoyu `kontrol_hizli.py`'de sınamıştı, D89).
- **Kanıt:** `[Ölçüldü]` `tb_fsm_dizi`: FSM'in her komutu (10 alan) golden'ın listesine karşı, ÖLÇEK'te golden G'si,
  s_a FSM'de hesaplanıyor; ag1–ag4 art arda, aralarında reset yok: 799 komut, 7998/7998. AG4 ile `tb_on_getirme`
  890.446/890.446 (602 DİZİ komutu), `tb_dizi_motoru` 4000/4000 (3926 kelime). Bilerek sokulan 7 FSM hatasının 6'sı
  yakalandı; yakalanmayan (BP s1'de satır karosu h yerine geçiş sayısından) D90'ın H ≤ 16 sınırı içinde eşdeğer:
  desteklenen her ağda iki sayı da 1 karo.
- **Durum:** Claude, 04.11.

### D93 — Dizili tam sistem (`sistem_dizi.v`, Adım 5b-3e): bir eğitim adımı uçtan uca
- **Ne:** Fig. 8'in bütün blokları: `master_controller_dizi` (D92) + komut yürütücü + `dizi_motoru` (D91) +
  `veri_tamponu` / `agirlik_tamponu` (D80–D82) + fonksiyon motoru (Egemen'in CLU'su `fe_top` üzerinden, D60/D62;
  `wu_unit`, D41). Yürütücü:
  - ÖLÇEK: motorun G'si işin yazdığı bölgenin G register'ına (FP l → AKT[l], BP l → HATA[l−1], WG l → GRAD[l]).
  - CLU: AKT[L] kelimesi (örnek b) GMS'ten geçer → CLU (s_a komuttan, etiket yapılandırmadan) → HATA[L] kelimesi
    (l = 0, HATA[L]'nin G'si 0; CLU çıkışı SRU'dan geçmez, D30).
  - WU (l, o-karo, c): 16 sütun bankasından ağırlık kelimeleri, bank (c mod 16)'dan 9 GRAD kelimesi (GMS, G = GRAD[l]
    bölgesininki), 9 `wu_unit`, 16 bankaya geri yazma.
  - Etiketler yapılandırma portundan (`cfg_etiket`, örnek başına 4 bit). `[Çıkarım]` (Adım 4'te bellekteydi.)
- **Kanıt:** `[Ölçüldü]` `tb_sistem_dizi`: başlangıçta yalnızca AKT0 ve ağırlıklar; sistem `basla` ile bir eğitim
  adımını kendi FSM'iyle koşturuyor; bitince veri tamponunun golden'da yazılı bütün kelimeleri (aktivasyonlar,
  hatalar, CLU çıkışı, gradyanlar; 16 int8 + l), ağırlık tamponunun bütün kelimeleri (WU sonrası) ve bölge
  G'leri golden'la karşılaştırılıyor. ag1–ag4 art arda, aralarında reset yok: 4829/4829, 4774 kelime (XSIM CLI,
  davranışsal bölücü). Bilerek sokulan 6 hatanın 5'i yakalandı; yakalanmayan (WU'da ağırlığı bir çevrim geç
  yakalamak) eşdeğer: WU boyunca ağırlık okuma adresi sabit.
- **Süre (çevrim, eğitim adımı başına):** ag1 2448 (Adım 4'ün tek PE'li sistemi 25.434), ag2 3608 (Adım 4: 48.828),
  ag3 5614, ag4 9450.
- **Durum:** Claude, 04.11. `dizi/run_sim.tcl` gerçek bölücü IP'siyle (Adım 4'ün script'iyle aynı IP üretimi).

## Adım 5c — Donanımlaştırma (05.11.2026, `final/`)

3f'nin sentezi (04.11 gece): `pe_dizi` tek başına LUT 251.531, DSP 2304, BRAM 0, sentez sonrası WNS +1,067 ns
(200 MHz), vektörsüz güç 13,6 W. Sistemin geri kalanı (`pe_dizi` kara kutu; `-directive RuntimeOptimized
-no_timing_driven`, varsayılan ayarla Timing Optimization 2 sa 13 dk'da bitmedi) LUT 1.498.830 (VC709'un %346'sı),
RAMB36 496 (448'i BP s2 kayıt belleği), DSP 31, WNS −55 ns. `[Ölçüldü]` (`final/rtl/dizi/sentez.tcl`, raporlar
`sentez_cikti/`, git dışı). Nedenler (kodda): değişkene bölmeler (`/ s`), `adres()`'teki 32 bit değişkenli
çarpmalar, ön-getirmenin 256'ya 1 mux'lu saatsiz akışı. RTL simülasyonda bit bit doğru ama bu yazımla FPGA'ya
sığmıyor. Plan: (e) döngü sırası, (a) sabitler register'da, (b) sayaçlı adres, (c) kaydırmalı line buffer
(WMAX 32), (d) BP s2 kayıt belleği. Her adımda davranış aynı kalır, 6 testbench bit bit.

### D94 — FP/BP'de toplanan kanal döngüsü en içte (Psum FIFO derinliği batch'ten bağımsız)
- **Ne:** D85'in karo döngüleri: FP `o-karo → b → r-karo → c` (önceden `o-karo → c → b → r-karo`), BP
  `c-karo → b → m/p-karo → o` (önceden `c-karo → o → b → m/p-karo`). WG ve WU değişmedi. `ilk` / `son` aynı
  (toplanan kanalın ilki / sonuncusu). `master_controller_dizi.v`'de sayaç iç içeliği FP/BP için k1 en içte;
  golden `dizi_sistem_golden.py` `is_komutlari()`.
- **Neden:** Eski sırada toplanan kanal batch'in ve satır karosunun dışındaydı: her PE bir sonraki kanal gelene
  kadar bütün batch'in kısmi toplamlarını tutmalıydı, B × ⌈Ho/16⌉ × T kayıt. Test ağlarında ≤ 48 (FIFO 64),
  CIFAR VGG16 benzeri ağda (batch 256, 32×32) ≈ 256 × 2 × 34 ≈ 17.400 kayıt, PE başına; hiçbir FPGA'ya sığmaz.
  Yeni sırada PE başına en çok bir geçişin çıkışları bekler (T ≤ W + 4), batch'ten bağımsız. Çevrim maliyeti yok:
  ön-getirme her geçişte zaten yeni bir harita ve sütun ağırlıkları yüklüyor (D90).
- **Kanıt:** `[PDF tam]` III-A: "The Psum FIFO queue saves the partial sum of convolution until the final outputs
  are obtained" (PE içinde, Fig. 2); döngü sırasını Shao vermiyor. `[Çıkarım]` PE içi bir kuyruğun batch'le
  büyümemesi gerekir. `[Ölçüldü]` golden: PE başına en çok bekleyen geçiş 1 (ag1–ag4; eski sırada B × karo).
  Beklenen veri ve ağırlık dosyaları değişmedi (yalnızca `komutlar_dizi.txt`, `onget_izi.txt`). XSIM CLI:
  `tb_fsm_dizi` 7998/7998, `tb_on_getirme` 890446/890446, `tb_dizi_motoru` 4000/4000, `tb_sistem_dizi`
  4829/4829, 21120 çevrim (önceki sırayla aynı). Eski FSM yeni vektörlere karşı: 730 hata / 7998 (test sırayı
  yakalıyor). `tb_pe_dizi`, `tb_grup_kurucu` bu değişiklikten etkilenmiyor (kendi vektörleri).
- **FIFO derinliği (D12, D74):** 64 kalıyor; T ≤ 64 olan her harita için batch'ten bağımsız yeter (WMAX 32'de
  T ≤ 36). (c) adımında WMAX'e göre yeniden boyutlanacak.
- **Durum:** Claude, 05.11.

### D95 — Komut sabitleri basla'da register'a, "/ s" kaydırma (Adım 5c-a)
- **Ne:** `on_getirme.v` ve `dizi_motoru.v`: katmanın boyutları (cin, cout, h, w, s, p, Ho, Wo), ön-getirmede
  etkin satır/sütun sayıları (nr, nc ≤ 16) ve akış boyu T, motorda ReLU bayrakları komutun `basla`'sında komut
  girişlerinden bir kez hesaplanıp register'da tutulur. `s ∈ {1, 2}` olduğundan Ho = (H + 2p − 3)/s + 1 bir
  kaydırma: s2 ? ((H + 2p − 3) >> 1) + 1 : H + 2p − 2. `s·z` çarpımı da mux (s2 ? 2z : z). Önceden bu değerler
  her çevrimde `ll`'den 32 bit `integer` aritmetiğiyle, değişkene bölmeyle hesaplanıyordu.
- **Neden:** 3f sentezinde `/ s` her modülde ayrı bir 32 bit kombinasyonel bölücüye dönüşüyordu (Adım 5c girişi).
  Değerler komut boyunca sabit; Shao'nun FSM'i PE'leri ve ön-getirmeyi "according to different training phases"
  yapılandırıyor (IV), yani komut başında yapılandırma. `[Çıkarım]`
- **Varsayım:** s ∈ {1, 2} (3×3 conv, D87; Shao Fig. 3–5 yalnızca s1 ve s2). s başka bir değer alırsa s1 gibi
  davranır; test ağları ve VGG16 benzeri ağ yalnızca 1 ve 2 kullanıyor.
- **Kanıt:** `[Ölçüldü]` XSIM CLI: `tb_on_getirme` 890446/890446, `tb_dizi_motoru` 4000/4000, `tb_sistem_dizi`
  4829/4829 (21120 çevrim, öncekiyle aynı). Mutasyon: BP s2'de T − 1 → 210 hata; ReLU-geri maskesinin katmanı
  bir kayık → 1462 hata (ikisi de yakalandı). Kaynak etkisi ayrı ölçülmedi: tam sistem sentezi 1,5 sa ve
  13 GB sürüyor; (a) + (b) birlikte ölçülecek.
- **Durum:** Claude, 05.11.

### D96 — Adresler sayaçla, çarpımlar yalnızca komut başında (Adım 5c-b)
- **Ne:** D81'in adres formülü (taban + ((b·n_karo + karo)·⌈H/16⌉ + satır/16)·W + x) artık her çevrimde ve her
  bank/satır için ayrı ayrı 32 bit `integer` çarpımlarıyla hesaplanmıyor:
  - `on_getirme.v`: bölge tabanları (AKT[l−1], HATA[l]), ağırlık adresi, WG'nin 3 aktivasyon satırının ve hata
    satırının satır payı `basla`'da bir kez (AW bit). FP/BP SATIR'da 16 bankın adresi aynı (satır = 16·tur + k,
    k < 16 → satır/16 = tur) ve ardışık: taban + `o_say` (her SATIR çevriminde +1). WG: taban + satır payı + x.
  - `dizi_motoru.v`: yazma tabanı (FP AKT[l], BP HATA[l−1], WG GRAD[l]) ve BP maske tabanı (AKT[l−1]) `basla`'da;
    akışta taban + sütun (BP s2: satır bloğu 2z − 1 / 2z / 2z + 1 → −W / 0 / +W). Bank = satır[3:0].
  - `sistem_dizi.v`: CLU adresleri taban + b; WU adresleri komut alanlarından tek kopya.
  - Adres AW bitte sarar; önceki 32 bit hesabın alt AW biti ile aynı (yalnızca + ve ·).
- **Neden:** 3f sentezinde `adres()` motorda 48, ön-getirmede 16'dan fazla kopya 32 bit değişkenli çarpıma
  dönüşüyordu (sistemde yalnızca 31 DSP). Donanımda adres üreteci sayaç + toplayıcıdır. `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` XSIM CLI: `tb_on_getirme` 890446/890446, `tb_dizi_motoru` 4000/4000, `tb_sistem_dizi`
  4829/4829 (21120 çevrim). Mutasyon: WU GRAD adresinde c/16 yok → 78 hata; BP ağırlık adresinde c-karosu yok →
  8250 hata (yakalandı). BP s2'de ikinci satır bloğunun +W payı 0 → yakalanmadı: H ≤ 16 sınırında (D90) satır
  hep ilk blokta, eşdeğer. Aynı nedenle WG satır payı ve hata satırı payı bugünkü testlerde hep 0; bu yollar
  (c) adımının H = 32'lik test ağıyla kapsanacak.
- **Durum:** Claude, 05.11.

**Ara ölçüm, (a) + (b) sonrası sistem sentezi (05.11 gece):** aynı ayarlar (`pe_dizi` kara kutu, RuntimeOptimized,
`-flatten_hierarchy none` ile modül başına doğru döküm; `sentez.tcl` `duzlestir`). LUT 1.498.830 → 1.315.312
(−%12), TNS −656.210 → −208.706 ns, WNS −55,3 → −54,5 ns, RAMB36 ve DSP aynı (496 + 16 RAMB18, 31). Modül başına:
`dizi_motoru`'nun kendi mantığı 930.251 LUT (toplamın %71'i; 448 RAMB36'lık BP s2 kayıt belleği de burada),
`on_getirme` 127.357, 16 LMS + 32 GMS grubu ≈ 167.000, CLU 11.834, FSM 338. `[Ölçüldü]` Bu koşu (c)'yi içermiyor.
Sonuç: asıl alan motorun yazma/seçme mantığında; (d) ve ardından motorun çıkış yolu ele alınmalı. Sentez 56 dk;
sentez sonrası `report_power` iki koşuda da 25 dk'dan fazla ilerlemedi, durduruldu (güç place & route'tan alınacak).

### D97 — Ön-getirmede satır başına line buffer, WMAX 32 (Adım 5c-c)
- **Ne:** `on_getirme.v`: Haritanın tamamını tutan yazmaç dizisi (LR / LRW / LE) ve her tap'i 256'ya 1 mux'la okuyan
  akış kaldırıldı. Yerine:
  - **Pencere:** LP = 33 satırlık line buffer; satır K, harita satırı `taban + K`'yı tutar (FP s1 16z − p, FP s2
    32z − p, BP s1 16z − 2 + p, BP s2 16z − 1). Her satır W × 8 bit bir bellek (1 yazma, 2 okuma portu: s2'de
    çift ve tek sütun). Haritanın dışındaki satırlar (`r_satir_gec`, `basla`'da) 0 okunur.
  - **Yazma:** SATIR okumasında bank k'nin kanal baytı, harita satırı 16·tur + k pencereye düşüyorsa satır
    16·tur + k − taban'a, sütun x'e yazılır.
  - **Okuma:** her çevrimde tek sütun (iki port), sütun t'den (FP s1 t − p, s2 2t − p ve 2t − 1 − p, BP s1
    t − 2 + p, BP s2 t − 1). PE satırı i'nin q. tap'i sabit kablolu pencere satırına bağlı (s1 i + q, FP s2 2i + q,
    BP s2 q = 2 ? i : i + 1). Mux yalnızca mod seçimi kadar.
  - **WG:** 3 aktivasyon satırı ve hata satırı birer W × 128 bit bellek (`lw`, `le_m`).
  - `WMAX` 16 → 32 (`on_getirme.v`, `dizi_motoru.v`); H için sınır yok (satır karoları). Test ağı AG5 (golden'da,
    `adim5_vektorleri/ag5/`): 32×32 giriş, s1/s2, p 0/1, 6 katman, 223 komut. Testbench'lerde `LMAX` 4 → 8.
- **Neden:** 3f sentezinde haritanın tamamı yazmaçtı ve her PE tap'i 256'ya 1 mux'tan okunuyordu; bu yapıyla
  harita 16×16'dan büyüyemiyordu (CIFAR 32×32). Shao Fig. 2 / III-A: ön-getirme "line buffer" ile PE dizisine
  satır satır veri akıtıyor. `[PDF şekil]` `[Çıkarım]` Satır başına bellek ve sabit kablolu tap'ler bu yapının
  donanımdaki karşılığı.
- **Kanıt:** `[Ölçüldü]` XSIM CLI (5 ağ): `tb_on_getirme` 1595333/1595333 (759 DIZI komutu), `tb_fsm_dizi`
  10230/10230 (1022 komut), `tb_dizi_motoru` 10001/10001, `tb_sistem_dizi` 10961/10961 (34584 çevrim). Mutasyon
  (yakalandı): BP s2 pencere tabanı −1 → 0 (5176 hata), BP s2 tap satırı (1856), pencere dışı satır 0'lanmıyor
  (1642), WG'de geçersiz satır 0'lanmıyor (398), BP s1 sütun bir kayık (6572), motorda BP s2 ikinci bloğun +W payı
  0 (1850; D96'da H ≤ 16 yüzünden kaçan mutant artık yakalanıyor).
- **Bilinen sınır:** FP s2 penceresinin z ≥ 1 tabanı (32z − p) test edilmiyor: mutant (32z → 16z) yakalanmadı.
  Bu yol yalnızca H ≥ 34'lük s2 katmanında çalışır (Ho > 16). Test ağlarında da VGG16 benzeri CIFAR ağında da
  (D87) en büyük H 32, yani kullanılmıyor.
- **PE Psum FIFO (D94):** T ≤ W + 4 = 36 ≤ 64; derinlik 64 kalıyor.
- **Durum:** Claude, 05.11. Kaynak etkisi (c) + (d) sonrası sentezde ölçülecek.

### D98 — BP s2 son geçişinin çıkışları PE'nin Psum FIFO'sunda (ayrı kayıt belleği kaldırıldı, Adım 5c-d)
- **Ne:** BP s2'de PE bir çevrimde 4 çıkış (çift-çift, çift-tek, tek-çift, tek-tek) üretiyor; LMS ve tampon satır
  başına çevrimde bir grup aldığı için son geçişin çıkışları bekletilmeli. Önceden `dizi_motoru.v`'de satır başına
  ayrı bir kayıt belleği vardı (`bufr`, 16 × 18 × 2048 bit; sentezde 448 RAMB36, VC709'un %30'u). Artık son geçişin
  çıkışları da ara geçişlerdeki gibi PE'nin kendi Psum FIFO'suna (128 bit = 4 şerit, D74) yazılıyor. Akıştan sonra
  motor FIFO başını (`pe_dizi` yeni çıkışı `ps_bas_flat`) okuyor, kayıt q'nun 4 şeridi (ve 8'den fazla satırda
  iki yarısı) bitince çıkarıyor. Boşaltma sırası ve çevrim sayısı aynı.
- **Kanıt:** `[PDF tam]` III-A (Fig. 4(b) açıklaması): "The Psum FIFO queue receives four partial sums in parallel
  when the PE works in this case." `[Çıkarım]` FIFO başının PE dışına (satırın LMS'ine) çıkması Fig. 2'deki Psum
  FIFO'nun yorumu; Shao boşaltma sırasını vermiyor. FIFO'da bir geçişten fazlası beklemez (D94): T − 1 ≤ 17 ≤ 64.
  `[Ölçüldü]` XSIM CLI (5 ağ): `tb_dizi_motoru` 10001/10001 (iş sonunda FIFO boş, taşma / eksik yok),
  `tb_sistem_dizi` 10961/10961, 34584 çevrim (D97 ile aynı), `tb_pe_dizi` 2363392/2363392 (yeni port, davranış aynı). Mutasyon (yakalandı): FIFO'dan
  hiç çıkarılmıyor (3214 hata), çıkarma şerit 3 yerine 2'de (2229), son geçişte FIFO'ya yazılmıyor (3283).
- **Durum:** Claude, 05.11.

**Ara ölçüm, (c) + (d) sonrası sistem sentezi (05.11 gece):** LUT 1.315.312 → 1.235.919, RAMB36 496 → 48 (D98),
`on_getirme`'nin kendi mantığı 14.997 LUT (D97; GMS takımı hariç), WNS −53,9 ns. `dizi_motoru`'nun kendi mantığı
hâlâ 893.203 LUT. `[Ölçüldü]` Önce tahmin edilen neden (BP s2 şerit seçiminin 8 bitlik sayaçla 256'ya 1 mux'a
açılması) yalnızca ~37k LUT'luk etki gösterdi (yine de düzeltildi, D99). Checkpoint'te motorun kendi seviyesindeki
LUT hücreleri sinyal adına göre sayıldı: ~1.024.000 hücre `v_yaz_veri` (tampona yazma), ~55.000 `lms`, gerisi
< 10.000. Sentez 33 dk, bellek tepesi 7,2 GB (önceki 56 dk, 13,2 GB).

### D99 — Motorun çıkış yolu: tampona yazma bank tarafından, değişken indisli seçimler daraltıldı (Adım 5c)
- **Ne:** `dizi_motoru.v`:
  - **Tampona yazma (asıl kalem):** önceden her satır kendi B_bank'ına değişken indisle yazıyor, ReLU-geri
    maskesini de değişken indisle 16 bankın GMS çıkışından seçiyordu. Artık bank kb kendi kaynağını seçiyor:
    B_bank'ı kb olan son geçerli satır (önceki "son yazan kazanır" ile aynı), veri 16'ya 1; maske kb'nin kendi
    GMS çıkışı (maske aynı banktan okunduğu için değişken seçim gereksiz).
  - BP s2 boşaltmasında şerit `ds[1:0]` ile (4'e 1; önceden 8 bitlik `ds` × 32 → 256'ya 1), WG akümülatörü
    `akum_sec` ile 9'a 1 (önceden 4 bitlik `wq` × 32 → 16'ya 1, komşu PE'ye taşan indisler dahil).
- **Neden:** Mimari aynı (satır başına SRU → tampon bankı, D79/D83); yalnızca seçicilerin yazımı. `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` yukarıdaki LUT dökümü. XSIM CLI (5 ağ): `tb_dizi_motoru` 10001/10001, `tb_sistem_dizi`
  10961/10961, 34584 çevrim (aynı). Mutasyon: maske kaynak satırın bankından (kb yerine) → 2986 hata (yakalandı).
  Kaynak etkisi aşağıda (D100 ile birlikte ölçüldü).
- **Durum:** Claude, 05.11.

### D100 — Tek GMS takımı: tampon okuma portunda bank başına bir GMS (Fig. 6)
- **Ne:** Önceden aynı tampon okuma portunun çıkışını üç ayrı 16'lık `gms_group16` takımı işliyordu: ön-getirmede
  (PE'ye giden veri, D78), motorda (ReLU-geri maskesi AKT[l−1], D86) ve yürütücüde (CLU'nun AKT[L]'si, WU'nun
  GRAD'ı). Tamponun tek okuma portu olduğundan üçü hiçbir zaman aynı anda gerçek veri işlemiyordu. Artık yalnızca
  ön-getirmedeki takım var; G, okuma portunu bir önceki çevrimde kullanan birimin G'si (veri bir çevrim sonra
  geldiği için sahip bir register'da): ön-getirmenin yükleme fazı → kendi G'si, motorun maske okuması →
  G_akt[l−1], yürütücü → CLU'da G_akt[L], WU'da G_grad[l].
- **Kanıt:** `[PDF şekil]` Fig. 6: tek "SRU (GMS)" bloğu, Buffer → GMS → PE yolunda; `[PDF tam]` III-B: "Before
  the int8 values are passed to PEs for the next stage computation, they need to be scaled by the second stage
  (GMS)". `[Çıkarım]` Maske ve CLU / WU okumalarının da aynı GMS'ten geçmesi Fig. 6'da yok; veri aynı tampondan
  geldiği için ortak kullanıldı. Fig. 6'ya önceki yapıdan daha yakın (iki ek takım şekilde yoktu).
  `[Ölçüldü]` XSIM CLI (5 ağ): `tb_on_getirme` 1595333/1595333, `tb_dizi_motoru` 10001/10001, `tb_sistem_dizi`
  10961/10961, 34584 çevrim. Mutasyon: maske G'si ön-getirmenin G'si → 3817 hata; yürütücünün G'si seçilmiyor →
  3426 hata (yakalandı). Sahibin register'sız (aynı çevrimin) seçimi → yakalanmadı: bugünkü komut akışında sahip
  hiçbir zaman bir okuma ile verisinin arasında değişmiyor (ön-getirmenin son verisi D_BEKLE'de, motorun son maske
  verisi M_SON'da, sonraki okuma ancak yeni komutla), iki yazım eşdeğer; register'lı hâl her akış için doğru
  olduğundan o tutuldu.
- **Durum:** Claude, 05.11.

### D103 — VGG ölçeği parametreler: kanal ve batch alanları 16 bit, LMAX 15, AW 13 (Faz 2)
- **Ne:** VGG16-like'ın (D101: 14 katman, 512 kanal, batch 256) donanımın yapılandırma alanlarına sığması için:
  - `cfg_cin`, `cfg_cout` katman başına 8 → 16 bit; `cfg_batch` 8 → 16 bit; komutun k1'i (FP/BP kanal, WG o-karo,
    WU kanal) 8 → 16 bit. `cfg_h/w/s/p/relu/sw`, b, k0, z 8 bitte kaldı (VGG16-like'ta en çok 32, 255, 32, 1).
  - FSM sayaçları (CW) 8 → 16 bit. **Hata düzeltmesi:** `karo()` 8 bitte n + 15 hesaplıyordu, n ≥ 241'de taşıyordu
    (karo(255) = 0); artık 17 bit.
  - LMAX 4 (FSM'de 8) → 15 (4 bitlik katman alanının sınırı), BMAX 8 → 256, AW 9 → 13 (tampon bank başına 8192
    kelime; tahmin ≈ 832 RAMB36, Shao Table I 896 — Shao tampon boyutu vermiyor, kıyaslanabilir boyut `[Çıkarım]`).
  - Sentez ve 4 testbench artık aynı parametrelerle (önceden sentez LMAX 4, testbench'ler 8).
  - Testbench'lerdeki komut dizileri 1024 → 32768, katman başına G dizileri 9 → 16; aşılırsa `$fatal` (önceden
    sessizce taşardı).
- **Sınırlama (değişmedi):** batch 256'lık VGG16-like'ın çalışma kümesi tampona sığmaz (ağırlıkları bile ≈ 151 Mbit,
  VC709'un BRAM'i ≈ 53 Mbit); harici bellek (DDR) yok, Shao da anlatmıyor.
- **Kanıt:** `[Ölçüldü]` XSIM CLI, ag1–ag5: `tb_fsm_dizi` 10230/10230, `tb_on_getirme` 1595333/1595333,
  `tb_dizi_motoru` 10001/10001, `tb_sistem_dizi` 10961/10961 (34584 çevrim, aynı). Yeni AG6 (golden'da;
  3 → 40 → 33 → 48 → 36 → 20 → 17 → 16 → 10 kanal, 32×32 → 1×1, batch 4, 8 katman, D101'in 2×2 → 1×1 s2 sonu; 7060 komut,
  bank başına 3307 adres) dahil ag1–ag6: `tb_fsm_dizi` 80832/80832 (8082 komut), `tb_on_getirme` 25054785/25054785,
  `tb_dizi_motoru` 57957/57957, `tb_sistem_dizi` 65142/65142 (411757 çevrim). İlk kez denenen birleşimler: 3 kanal
  karosu × iki satır karosu, batch 4, 8 katman, 1×1 çıkışlı s2 son katman.
- **Durum:** Claude, 05.11.

### D104 — PE'de gereksiz sıfırlama kapıları kaldırıldı (Faz 3, yazım küçültmesi)
- **Ne:** (1) `pe_birlesik.v`: seçili olmayan modda `cikis_flat` / `g_flat`'ı 0'a çeken kapılar kalktı; çıkış
  `{m5, m4, top2, bp2 ? top1 : top2}`, akümülatörler doğrudan. (2) `pe_dizi.v`: Psum FIFO başının üst şeritlerini
  (1–3) BP s2 dışında 0'a çeken 96 bitlik mux kalktı. İlk geçişte kısmi toplamı 0 yapan `ps_sec` ve `b_gec`
  sıfırlamaları (işlevsel) kaldı.
- **Neden:** Shao Fig. 2'de bu kapılar yok; tüketiciler moda göre doğru şeridi zaten seçiyor (motor FP / BP s1'de
  şerit 0, BP s2'de 4 şerit, WG'de akümülatör; pe_birlesik'te port 3'ü yalnızca FP/BP zincir başı (0,0) ve BP s2'nin
  zincir başları seçer). Tek PE ölçümü (sentez, `flatten none`): 1006 → 622 LUT. Mimari aynı. `[Ölçüldü]` `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` Egemen'in 7 PE testi (kendi vektörleri, kabuklarla) 38/38, 38/38, 34/34, 24/24, 32/32, 5/5,
  5/5; `tb_pe_dizi` 2363392/2363392 (referansı kısmi toplamı kendisi kurduğu için (2)'yi bağımsız sınar);
  `tb_dizi_motoru` 57957/57957, `tb_sistem_dizi` 65142/65142 (411757 çevrim, aynı). Not: `tb_pe_dizi`'nin referansı
  `pe_birlesik`'in kendisi, (1) için tek başına kanıt değil. Mutasyon (yakalandı): FP/BP s1'de şerit 0 = top1 →
  PE testlerinde 21–32 hata; (2)'de şerit 1 b_gec yerine a_ps → 430043 hata; şerit 0 a_ps yerine b_gec → 1895162 hata.
  Kaynak etkisi Faz 3 ölçüm kapısı A'da (sentez, eğitim koşuları arasında).
- **Durum:** Claude, 05.11.

### D105 — MAC'in 3'e 1 seçicisi DSP48E1'in Z seçicisinde (Faz 3 adım 3, yazım küçültmesi)
- **Ne:** Yeni `final/rtl/pe/mac_dsp.v`: P = Z + A·B tek bir DSP48E1'de; Fig. 2'nin port 3'ü (Psum FIFO) → C girişi
  (Z = 011), port 4 (soldaki MAC'in sonucu) → PCIN, DSP zinciri (Z = 001; c = 0'da ve BP s2'nin c = 2'sinde 0,
  Z = 000), port 5 (kendi sonucu, WG) → P geri beslemesi (Z = 010). `pe_birlesik.v` artık mac_dsp kullanıyor;
  Egemen'in `mac.v`'si kendi 5 PE devresi (ASIL testler) için değişmeden duruyor. Çıkış P[31:0]: 48 bitlik toplamın
  alt 32 biti 32 bitte sarmalı toplamla aynı (+ ve · modüler).
- **Simülasyon notu:** Xilinx `glbl` modülü simülasyonun ilk 100 ns'inde GSR'yi tutar; DSP'nin P register'ı ilk
  hesabı kaçırır (yalnızca simülasyonda; donanımda GSR konfigürasyon sırasında biter). Bu yüzden `mac_dsp.v`'de
  `SIM_DAVRANISSAL` tanımlıyken aynı veri yolunun davranışsal hâli kullanılır; Vivado `run_sim.tcl`'leri bunu tanımlar
  (`xsim.compile.xvlog.more_options -d SIM_DAVRANISSAL`). Sentez her zaman primitifi kullanır.
- **Neden:** Tek PE sentezi (`flatten none`): 622 → 273 LUT, DSP 9 (aynı). Shao Table I: LUT 171k, DSP 2324 — DSP'nin
  iç seçicisinin kullanıldığını düşündürüyor `[Çıkarım]`. Mimari aynı (Fig. 2'nin 3 girişi ve seçim kuralı).
- **Kanıt:** `[Ölçüldü]` Egemen'in 7 PE testi hem primitifle (XSIM CLI, unisims_ver, ROC_WIDTH = 0'lı glbl) hem
  davranışsal modelle 38/38, 38/38, 34/34, 24/24, 32/32, 5/5, 5/5 (orijinal glbl ile primitifte her testte tam 1 hata,
  ilk kontrol — GSR hipotezi ROC_WIDTH = 0 ile doğrulandı). Mutasyon (PE testleri, yakalandı): port 4'te Z = P →
  166 hata; PCIN yanlış komşudan → 134; BP s2'nin B zincirinde 0 yerine PCIN → 24. Sistem testleri (davranışsal
  modelle; 2304 primitifle XSIM'de `tb_pe_dizi` tek başına 46 dakikayı geçti, durduruldu): `tb_pe_dizi`
  2363392/2363392, `tb_dizi_motoru` 57957/57957, `tb_sistem_dizi` 65142/65142 (411757 çevrim, aynı). Primitif ile
  davranışsal model PE testlerinde aynı; sistem testlerinin sınadığı bağlantılar (zsel, PCIN zinciri) iki modda ortak.
- **Durum:** Claude, 05.11–06.11.

### D106 — Motorda zamanlama: komut başı sınırlar register'da, LMS önüne P aşaması (Faz 4)
- **Ne:** `dizi_motoru.v`: (1) Etkin satır/sütun sayıları (nr, nc) ve BP s2'nin satır/sütun sınırları, satır payı eşiği
  komutun `basla`'sında bir kez register'a (r_nr, r_nc, r_umin = p − 32z, r_umax = h + p − 32z, r_vmax = w + p,
  r_p16 = p + 16); boşaltmada satır içi u = 2i + ds[1], sütun v = 2q + ds[0] ile küçük karşılaştırmalar (önceden her
  satırda 32 bit R = 2(16z + i) + ds/2 − p, e = R − 32z). (2) Aşama A'nın çıkışları (grup, geçerli, adres, maske adresi,
  bank) bir P register'ında; LMS, global G'ye gönderim ve maske okuması P'den, B bir çevrim sonra. Son grup için
  M_SON'dan önce bir bekleme durumu (M_BEK): DIZI komutu başına +1 çevrim, veri aynı.
- **Neden:** (c) + (d) sonrası sistem sentezinde en kötü yol r_h → BP s2 sınır kontrolü → A_gec → LMS → global G'nin
  CE'si, 72 mantık seviyesi, WNS −18,2 ns (200 MHz). Shao 200 MHz'de çalışıyor (IV); boru hattının ayrıntısını vermiyor.
  `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` XSIM CLI, ag1–ag6: (1) sonrası `tb_dizi_motoru` 57957/57957, `tb_sistem_dizi` 65142/65142
  (411757 çevrim); (2) sonrası `tb_dizi_motoru` 57957/57957, `tb_sistem_dizi` 65142/65142, 419000 çevrim
  (= 411757 + 7243 DIZI komutu, beklenen +1). Mutasyon (`tb_dizi_motoru`, yakalandı): r_umax bir fazla → 3339 hata;
  satır payı eşiği p + 15 → 4725; B'nin adresi P yerine A'dan → 51203. Zamanlama etkisi Faz 3/4 sentezinde.
- **Durum:** Claude, 06.11.

**Faz 3/4 ölçümü (D103–D106 sonrası sentez, 06.11 gece; `flatten none`, sistem RuntimeOptimized):** `pe_dizi` LUT
315.801 → 148.214 (PE başına 862 → 271; LUTRAM 44.032 aynı), DSP 2304, WNS +1,000 ns. Sistem parçası LUT 274.397
(motorun kendi mantığı 68.284, on_getirme 86.405 — 16 GMS'i dahil, 16 LMS ≈ 97k), RAMB36 824 (AW 13; tahmin 832),
DSP 55, WNS −12,234 ns (önceki −18,198; en kötü yol artık P_grup → LMS → global G'nin CE'si, 51 seviye). **Toplam:**
LUT 422.611 (VC709'un %97,6'sı; Shao 171.248), RAMB36 824 (%56; Shao 896), DSP 2.359 (Shao 2.324). `[Ölçüldü]`
Kapı B: hedef ~%85 tutmadı → Ego kararı (LMS/GMS yazım küçültmesi ya da bitirme yolu). Sentez süresi pe_dizi 8 dk 43 sn,
sistem 9 dk 19 sn, bellek tepesi 6,6 GB.

### D107 — LMS'in B çıkışı global G'ye bir register üzerinden (Faz 4, zamanlama)
- **Ne:** `dizi_motoru.v`: P aşamasındaki LMS'in B'leri ve geçerli bitleri (Q_B, Q_gec) bir register'dan sonra
  `global_max_reducer16`'ya gider. G yalnızca işin sonunda (ÖLÇEK, bitti'den sonra) okunduğu için bir çevrim gecikme
  sonucu değiştirmez; son gönderim M_SON çevrimine düşer, çevrim sayısı değişmez.
- **Neden:** D106 sonrası sentezde en kötü yol P_grup → LMS → G'nin CE'si (51 seviye, WNS −12,2 ns). `[Çıkarım]`
- **Kanıt:** `[Ölçüldü]` `tb_dizi_motoru` 57957/57957, `tb_sistem_dizi` 65142/65142 (419000 çevrim, aynı). Mutasyon:
  gönderim P'den, B Q'dan (hizasız) → 14 hata (yakalandı). Zamanlama etkisi bir sonraki sentezde.
- **Regresyon (D104/D105 etkisi, aynı commit):** Adım 4 (`final/rtl/sistem/run_sim.tcl`) listesine `mac_dsp.v` +
  `SIM_DAVRANISSAL`; `tb_pe_birlesik` ve `tb_veriyolu` yalnızca modun okunan şeritlerini karşılaştırıyor (D104
  sonrası seçilmeyen şeritler 0 değil). XSIM CLI: `tb_fsm` 6206, `tb_sru_buyuk` 8508, `tb_pe_blok` 380490,
  `tb_pe_birlesik` 80357, `tb_veriyolu` 71048, `tb_sistem` 21415 — altısı PASS (run_sim.tcl'deki beklenenlerle aynı).
- **Tam regresyon (Faz 7, 06.11 öğleden sonra):** kalan dört klasör XSIM CLI ile, run_sim.tcl'lerin dosya listeleriyle
  (bölücü davranışsal model): sru `tb_bm_official` 154, `tb_global_max_b` 12, `tb_sround_official` 2297, `tb_sru_array`
  12, `tb_sru_katman` 52, `tb_sru_top` 52, `tb_lms_uc` 20013, `tb_sru_gradyan` 1865; clu `tb_clu` 40; clu_yuvarlama
  `tb_stok_yuvarla` 40960; fe `tb_relu` 196608, `tb_wu` 65536, `tb_fe_top` 456144 — 13'ü PASS. Böylece yedi klasörün
  (pe, sru, clu, clu_yuvarlama, fe, sistem, dizi) hepsi D107 sonrası PASS. Gerçek bölücü IP'siyle Vivado koşusu: Ego.
- **Durum:** Claude, 06.11.

---

## Adım 6 — CIFAR-10 deneyi (Shao Fig. 9'un karşılığı, 04.11.2026)

Shao IV (s. 258): VGG16 benzeri ağ CIFAR-10'da eğitiliyor, test hata eğrisi NITI ile karşılaştırılıyor (Fig. 9);
eğitimin FPGA'da mı yazılım modelinde mi yapıldığı metinde yazmıyor. NITI kodu ve makalesi bu bölümde hakem
(Shao ağın ayrıntısını ve eğitim ayarlarını vermiyor). NITI kaynakları okundu: `ti_vgg.py`, `main.py`, `options.py`,
`data.py`, `ti_net.py`, `ti_torch.py`, `train_vgg_cifar10.sh`; NITI makalesi §4.3, Tablo 5–6.

### D87 — VGG16 benzeri ağın tanımı
- **Ne:** VGG16 (CIFAR): 64,64,M,128,128,M,256×3,M,512×3,M,512×3,M + FC. Her "M + ardından gelen s1 conv" bir s2 conv
  olur: conv64, conv64, conv128/s2, conv128, conv256/s2, conv256, conv256, conv512/s2, conv512, conv512, conv512/s2,
  conv512, conv512, maxpool (2×2 → 1×1), FC 512 → 10. Bütün conv 3×3, dolgu 1, ReLU'lu; FC'den sonra ReLU yok.
- **Kanıt:** `[PDF tam]` Shao IV: "replace the max-pooling layer and its subsequent convolutional layer (stride=1)
  with a convolutional layer (stride=2)". Son max-pool'un ardından conv yok; onu bıraktım: Fig. 8'in fonksiyon
  motorunda "Pooling" birimi var `[PDF şekil]`. FC başlığı (tek FC) `[NITI GitHub]` `ti_vgg.py`. NITI'nin FC öncesi
  dropout'u alınmadı: Shao'nun donanımında dropout birimi yok. `[Çıkarım]`
- **Fig. 9'un "VGG16" eğrisi:** aynı ağın max-pool'lu hâli (`vgg16`); NITI'nin deposunda VGG16 yok (yalnızca
  VGG-small-7/8/9, NITI makalesi Tablo 5), Shao'nun NITI ile eğittiği VGG16'nın tanımını vermiyor.

### D88 — Eğitim ayarları NITI'den
- **Ne:** batch 256, 200 epoch, m_u 5 → 4 (100. epoch) → 3 (150. epoch), ağırlık başlatma xavier-uniform →
  `weight_quant` (round(W / max|W| · 127), s_w = ⌈log2 max|W|⌉ − 7), giriş `TiFloatToInt8` (batch başına,
  −128..127, D23), veri çoğaltma: 4 piksel dolgulu rastgele kırpma + yatay çevirme + normalizasyon. Öğrenme oranı
  yok (w − g, D41). Float referans: SGD momentum 0.9, lr 0.01 → 0.001 → 0.0001 (100., 150. epoch).
- **Kanıt:** `[NITI GitHub]` `ti_vgg.py` (regime), `options.py` (batch 256, epoch 200), `data.py`, `ti_torch.py`;
  `[PDF tam]` NITI §4.3 (s. 3255).

### D89 — Hızlı model (`final/models/cifar/hizli_model.py`)
- **Ne:** Dizi golden'ının tensör düzeyinin (II') GPU'daki kopyası: konvolüsyonlar im2col + `torch._int_mm`
  (int8 × int8 → int32 birikim, PE'nin MAC'i gibi taşmada sarar), SRU (D76 grupları, Alg. 1, doymasız), CLU yer
  tutucusu, ReLU-geri maskesi (D86), WU (D41). Max-pool (FP: en büyük, BP: hata en büyüğün konumuna) ve FC (çıktı
  grupları 16 sınıf, gradyan grupları 16 çıkış) golden'da yok, bu dosyada eklendi.
- **Kanıt:** `[Ölçüldü]` `kontrol_hizli.py`: ag1, ag2 ve 16'dan fazla kanallı (2–3 karolu) 4 rastgele ağda bir
  eğitim adımı golden'la bit bit aynı (aktivasyonlar, hatalar, son ağırlıklar, s_a, iş başına G).
- **Bilinen sınır:** WG birikimi int32'de; 32×32 haritada batch 256 en kötü durumda taşabilir (D21: batch ≤ 130).
  Donanım da int32 biriktirdiği için taşma aynı şekilde sarar; NITI de int32 biriktiriyor.
- **Süre:** RTX 3060 Laptop'ta VGG16 benzeri, int: 1,65 s/adım (200 epoch ≈ 18 saat); float: 0,16 s/adım.

### D101 — VGG16-like tamamen konvolüsyonel: son max-pool + FC yerine tek s2 conv (D87'nin sonunun yerine)
- **Ne:** D87'deki "maxpool (2×2 → 1×1), FC 512 → 10" çifti, Shao'nun kuralı aynen uygulanarak tek bir 3×3, s2, p1
  conv 512 → 10 (2×2 → 1×1, ReLU yok) olur. Ağ: 13 conv (D87'deki gibi) + bu son conv = 14 katman, hepsi 3×3 conv,
  s ∈ {1, 2}: her katman RTL'in modlarında, 4 bitlik katman alanına sığar. Eski hâli `egit.py --ag vgg16like_d87`.
  Fig. 9'un "VGG16" referans eğrisi (`vgg16`, max-pool'lu) değişmedi.
- **Neden:** Ego 05.11 (karar 2a): RTL'e max-pool / FC eklenmiyor (1a); D87'nin sonu yalnızca yazılımda kalırdı.
  Shao'nun kuralı "max-pool + ardından gelen katman → s2 conv"; son max-pool'un ardından gelen katman FC.
- **Kanıt:** `[PDF tam]` Shao IV: "replace the max-pooling layer and its subsequent convolutional layer (stride=1)
  with a convolutional layer (stride=2)". `[Çıkarım]` Kuralın FC'yi izleyen son max-pool'a da uygulanması (Shao son
  katmanları tarif etmiyor). `[Ölçüldü]` `kontrol_hizli.py`: bu sonla biten 4 katmanlı ağ (`d101_son`: 8 → 4 → 2 → 1,
  33 kanal) golden'la (II') bit bit aynı (6/6 PASS). `kontrol_maxpool_fc.py`: hizli_model'in max-pool ve FC yolları
  (yalnızca VGG16 referans eğrisi kullanıyor) döngülü bağımsız referansa karşı PASS (FC'de int32 taşması denenmedi;
  VGG16'nın FC'sinde K = 512, taşma olamaz).
- **Durum:** Claude, 05.11.

### D102 — m_u takvimi 14 katmanlı ağlar için 3 → 2 → 1 (D88'deki NITI 5 → 4 → 3 yerine)
- **Ne:** `egit.py --mu 3`: güncelleme bit genişliği m_u ilk yarıda 3, 100. epoch'ta 2, 150. epoch'ta 1 (NITI'nin takvim
  biçimi aynı, başlangıç 2 bit aşağıda). VGG16-like ve Fig. 9'un VGG16 referansı için. vggsmall7 için 5 kalır.
- **Neden:** İlk 2 epoch'luk deneme (m_u 5) öğrenmedi (test %11,2 / %9,8, rastgele %10). Kök neden araştırması
  (sabit 64'lük batch'i 40–60 adımda ezberleme testi, `[Ölçüldü]`):
  - NITI'nin 6 katmanlı vggsmall7'si bizim int8 aritmetiğimizle m_u 5'te 40 adımda %92 → aritmetik, CLU, WU doğru.
  - 14 katmanlı vgg16like, eski sonlu vgg16like_d87 ve max-pool'lu vgg16: m_u 5'te öğrenmiyor (%12–20), son katman
    çıkışı 0'a çöküyor, ReLU'lar ölüyor, her adımda ağırlıkların %5–90'ı değişiyor → D101 neden değil, derinlik.
  - Grup ölçeklemesi neden değil: `--grup 0` (NITI'nin tensör başına ölçeği) ile de öğrenmiyor.
  - vgg16like, yalnızca m_u değişerek: 5 → %14, **3 → %69**, **2 → %66**, 1 → %28 (60 adım).
  - Aynı ağın float hâli (xavier, SGD lr 0,01 momentum 0,9) de 80 adımda kaybı 2,302'den indiremedi: BN'siz derin
    düz VGG bu başlatmayla zor; sorun int aritmetiğine özgü değil.
- **Kanıt:** `[PDF tam]` NITI §3.3: "values of mu in the range of 1 to 5 bits performed well in general" (m_u ayarlanan
  bir hiperparametre). `[NITI GitHub]` 5 → 4 → 3 takvimi `ti_vgg.py`'de VGG-small için. Shao m_u'yu vermiyor.
  `[Ölçüldü]` yukarıdaki tablo; gerçek veriyle 2 epoch sonucu aşağıda.
- **Durum:** Claude, 05.11.
- **06.11 eki (gözlem ve sorun giderme, karar değişmedi):** m_u 3 koşusu 12 epoch'ta eğitim ~%21'de düzleşti; m_u 2
  ile yeniden başlatılan koşu 11. epoch'ta %28 / test %31'e çıkıp 24. epoch'ta ~%24'e geriledi (Ego onayıyla durduruldu,
  `sonuc/vgg16like_int/durum.pt`). Ortak aritmetik kararlar NITI'ye karşı incelendi:
  - SRU yuvarlaması (SRU-a1, `ALT_YARI = "shao"`): Shao Alg. 1 satır 6 `f[bp/2, 0]`, NITI Alg. 3 `f[bp/2 − 1, 0]`; Shao'nun
    yazımı her yuvarlamada sıfıra doğru −0,26..−0,38 LSB sapma veriyor (NITI ≈ 0; rastgele 200 bin değerle `[Ölçüldü]`).
  - D59 sarması: 24. epoch ağırlıklarıyla bir eğitim adımında 18.707 değer (+128 → −128), hepsi grup maksimumu.
  - 2 epoch'luk ablasyonlar (vgg16like, m_u 2, `--isci 1`, tohum 1), 2. epoch eğitim / test: taban %28,9 / %29,5;
    `--alt niti --doyma` %31,5 / %35,1; `--grup 0` %30,1 / %31,7; `--alt niti` %27,0 / %22,2; `--doyma` %19,9 / %21,5;
    `--ae round` %19,4 / %21,4. Aynı aritmetikle iki koşu arasında 1. epoch'ta ~4 puan fark (veri çoğaltması) →
    farkların çoğu gürültü bandında; açık ve tutarlı bir iyileşme yok. Karar: değişiklik yapılmadı (Ego ile 06.11 gece
    anlaşması: belirsiz sonuçta değiştirme). Yanlı yuvarlama kuramsal olarak gerçek; etkisini göstermek için daha uzun
    / çok tohumlu koşu gerekir. Ego'nun kararına bırakıldı.
- **06.11 NITI doğrulaması (çerçevenin kanıtı):** Aynı çerçeve (Shao'nun yazımıyla SRU, golden/RTL ile bit bit) NITI'nin
  kendi ağında (vggsmall7, NITI ayarları m_u 5 → 4 → 3; GPU belleği yüzünden batch 128, NITI 256) 30 epoch'ta test
  %76,45, eğitim %74,73 (1. epoch %36,1; 10. %68,2; 20. %71,8). Önceden belirlenen eşik ≥ %70 → çerçeve sağlam
  (NITI'nin 200 epoch sonucu %90,7). Sonuç: VGG16-like'ın ~%25'i çerçevedeki bir hatadan değil, 14 katmanlı BN'siz ağın
  bu ayarlarla eğitilmesinden. `[Ölçüldü]` `sonuc/niti_vggsmall7_b128/egri.csv` (30. epoch'ta durduruldu, durum.pt saklı).

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
   ulaşmaz, düşük öncelikli. **`final/`'de düzeltildi (D71).**
10. **XSIM, geniş bir task girişine doğrudan verilen karşılaştırma ifadesini bozuk
   değerlendirebiliyor.** Örnek: `tb_pe_blok`'ta `kontrol_et(f_bos, (k_say == 0), ...)`,
   288 bitlik girişte Icarus'ta doğru, Vivado XSIM'de anlamsız bir değer (`1b13...XXXz...`)
   verdi; DUT doğruydu `[Ölçüldü, 03.11]`. Çözüm: beklenen değeri önce bir değişkene ata,
   task'a değişkeni ver.
11. **XSIM (`xvlog`) UTF-8 BOM'lu kaynak dosyayı reddediyor** (`unexpected non-printable
   character with the hex value '0xef'`). Windows PowerShell 5.1'in `Set-Content -Encoding utf8`'i
   BOM ekler. Çözüm: dosyaları BOM'suz UTF-8 yaz (`[IO.File]::WriteAllText(..., UTF8Encoding($false))`)
   `[Ölçüldü, 03.11]`.
12. **Komut satırından `xsim.bat ... -testplusarg AD=deger` verilince `=` argümanı bölüyor** (cmd'nin
   `.bat` argüman ayrıştırması). Vivado GUI/Tcl'deki `xsim.simulate.xsim.more_options` yolu etkilenmez.
   Çözüm: komut satırında vektörleri çalışma klasörüne kopyala (testbench'lerin yedek yolu, tuzak 7).
13. **Vivado GUI'de `launch_simulation`, üst seviyedeki bütün sinyalleri dalga penceresine ekliyor; çok
   geniş register'lı (~100 bin bit) ve SV kuyruk dizili bir testbench'te GUI'nin dalga görünümü (Java)
   çöküyor** (`hs_err_pid*.log`: `WVExecutive_getGraphicsDataSize`, EXCEPTION_ACCESS_VIOLATION). Simülasyon
   değil arayüz çöküyor; `tb_grup_kurucu`'da görüldü `[Ölçüldü, 04.11]`. `xsim.simulate.custom_tcl` ayarı
   batch'te kabul edildi ama GUI koşusunda kullanılmadı (yine `add_wave /`). Çözüm: testbench'i sinyalsiz
   bir üst modülün içine koy (`module tb; tb_govde govde (); endmodule`); başlatma script'i üst seviyede
   sinyal bulamayınca dalga açmıyor (`get_objects` = 0, `[Ölçüldü]`).
