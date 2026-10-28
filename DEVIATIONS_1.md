# Sapma ve Karar Günlüğü — Shao/NITI Gerçekleme

Makalenin belirsiz bıraktığı veya kendi içinde çelişen her nokta burada
D-numarasıyla kayıtlı. **Sıradaki numara: D38.** Yeni blok eklendikçe
oradan devam edin — numarayı tekrar başlatmayın.

Format: her madde için **ne**, **neden**, **kanıt**, **durum**.

> **28.10.2026 güncelleme notu:** Ömer Faruk'un kendi Claude oturumunda
> hazırladığı `PE_SRU_BASLANGIC.md` (bu sohbeti görmeden, yalnızca
> `TASKS.md`/`DEVIATIONS.md`'ye bakarak) birkaç gerçek hata buldu (PE'nin
> SiPS 2020 öncül makalesiyle karıştırılması, D2/D8'in yanlış GitHub
> dosyasına atfedilmesi) ve PE+SRU için 24 aday açık nokta çıkardı.
> Egemen'in bu oturumu, tüm bu iddiaları PDF'lerden (sayfa altlıkları,
> şekiller) ve NITI GitHub'dan (ti_loss.py, ti_torch.py tam metinleri)
> bağımsızca tekrar çekip doğruladı — hepsi doğru çıktı. Düzeltmeler
> aşağıya işlendi, adaylar D14-D37 olarak kalıcı numara aldı. Hem
> `PE_SRU_BASLANGIC.md` hem bu dosya artık güvenilir kabul edilebilir.

---

## CLU (Cross-Entropy Loss Unit) — tamamlandı, 40/40 test geçti

### D1 — gi = 2^ai − 1 (−1 dahil)
- **Ne:** Algoritma 2 satır 4'teki $g_i=2^{a_i}-1$ formülündeki "−1" terimi.
- **Neden karar gerekti:** Fig. 7'nin donanım şemasında (`1<<` bloğu) bu
  −1 hiç görünmüyor, sadece Algoritma 2'nin metninde var.
- **Kanıt:** Hem Shao'nun Algoritma 2'si HEM DE NITI'nin gerçek GitHub
  kodu (`ti_loss.py`: `out_grad = 2**s-1`) −1'i içeriyor. Yalnızca
  NITI'nin makale metnindeki (basitleştirilmiş) türetim −1'i atlıyor.
- **Durum:** Kesinleşti, −1 dahil edildi.

### D2 — EPU'nun Shift Unit'i iki yönlü
- **Ne:** EPU içindeki kaydırma biriminin $s_a$'nın işaretine göre hem
  sola hem sağa kayabilmesi.
- **Kanıt:** NITI GitHub kodu, **`ti_loss.py`** (satır ~15-18, `TiLoss.forward`
  içinde): `if out_exp>=0: s=s*2**out_exp else: s=s/(2**-out_exp)`.
  *(Düzeltme 28.10.2026: önceki sürümde dosya `ti_torch.py` olarak
  yanlış yazılmıştı — Egemen'in Claude'u GitHub'dan tekrar çekip
  doğruladı, kod satırı doğru ama dosya adı yanlıştı.)*
- **Durum:** Kesinleşti.

### D3 — TEU kanal başına ayrı örnek (paylaşımlı değil)
- **Ne:** Fig. 7'de TEU'nun N kere mi çizildiği, yoksa zaman-paylaşımlı
  tek bir TEU mu olduğu.
- **Kanıt:** Fig. 7'de TEU, EPU ile AYNI çizim kuralıyla (N kez
  stacklenmiş) gösterilmiş.
- **Durum:** Kesinleşti, N ayrı örnek.

### D4 — EPU'da log2(e) ≈ 184/2^7 (Algoritma 2'nin 47274/2^15'i DEĞİL)
- **Ne:** $\log_2 e$ sabiti için iki farklı değer: Algoritma 2 metninde
  $47274/2^{15}$, Fig. 7'nin donanım bloğunda $184/2^7$.
- **Neden:** Bu, makalenin KENDİ İÇİNDE bir tutarsızlığı — iki değer
  farklı hassasiyette ($184/128=1.4375$ vs $47274/32768\approx1.4426$,
  gerçek değer $\approx1.4427$).
- **Durum:** Donanım şemasına (Fig.7) sadık kalındı, 184/2^7 kullanıldı.

### D5 — Son >>4 kaydırma + int8 kırpma (Shao'da çizilmemiş)
- **Ne:** CLU çıkışının ($e_i$) son mux'tan sonra hâlâ ~12-bit (±2048
  civarı) olması, int8'e (−127..127) hiç indirgenmemesi.
- **Kanıt:** NITI kodunda son adım `StoShift(out_grad, 4)` + int8 clip
  var, ama Fig. 7'nin son mux'ından direkt $e_i$ çıkıyor, ara blok yok.
  Ayrıca Shao'nun metninde "CLU yazılımla aynı sonucu veriyor" cümlesi
  de bu adımın bir yerde olması gerektiğini destekliyor.
- **Durum:** EKLENDİ ama **HENÜZ KESİNLEŞMEDİ** — Shao'ya mail atıldı
  (hkshao@smail.nju.edu.cn), cevap bekleniyor. SRU'dan geçmediği Fig.8
  + metninden kesin (SRU yalnızca PE çıktıları için).

### D6 — N (sınıf sayısı) = 10, sabit
- **Ne:** CIFAR-10 için N=10, henüz parametrik değil.
- **Durum:** Geçici, ileride parametrize edilebilir.

### D7 — Bölmede yuvarlama yok (truncate)
- **Ne:** `(gi<<11)/sum1` bölme işleminin yuvarlama davranışı.
- **Neden:** Makalede bu bölme için ayrı bir yuvarlama şeması
  belirtilmiyor.
- **Durum:** Varsayım, düz bölme (aşağı yuvarlama) kullanıldı.

### D8 — Son kaydırmada stokastik değil, düz yuvarlama
- **Ne:** D5'teki son >>4 kaydırmanın yuvarlama tipi.
- **Neden:** Basitlik için düz round-to-nearest kullanıldı.
- **DÜZELTME (28.10.2026, Egemen'in Claude'u GitHub'dan doğrudan
  teyit etti):** Önceki not ("NITI kodu Alg.1/pseudo-stokastik
  kullanıyor") **yanlıştı**. `ti_loss.py` satır 35'te gerçekte
  `StoShift(out_grad.type(torch.int32), 4)` çağrılıyor, ve `StoShift`
  (`ti_torch.py`) içinde `torch.randint(...)` ile **gerçek rastgele
  sayı** üretiliyor — Algoritma 1/3'teki deterministik,
  bit-tabanlı `PstoShift` DEĞİL. İkisi tamamen farklı mekanizma.
- **Kapatma seçenekleri (karar bekliyor):**
  - (a) En-yakına yuvarlama kalsın (şimdiki basitleştirme)
  - (b) Algoritma 1 (`PstoShift` benzeri, deterministik) kullanılsın —
    donanım dostu ama NITI'nin **gerçek loss kodundan** (StoShift) ayrı
    bir sapma olur, kendi D'si gerekir
  - (c) Gerçek stokastik (LFSR tabanlı) yuvarlama — NITI'ye en sadık
    seçenek, ama bit-tam test için Python ve RTL'in AYNI LFSR'yi AYNI
    tohumla kullanması gerekir (zor, muhtemelen gerekmez)
- **Durum:** Basitleştirme, (a) ile devam ediliyor; SRU'da Algoritma 1
  başka bir yerde (D-numarası ayrı, bkz. SRU bölümü) zaten uygulanacak
  ama bu CLU'nun D8'ini otomatik çözmüyor çünkü CLU çıkışı SRU'dan
  geçmiyor (D5).

### D9 — int8 aralığı simetrik: −127..127 (−128 değil)
- **Kanıt:** NITI metni açıkça "±127" doyma ve "$a_i\le127$" diyor.
- **Durum:** Kesinleşti.

---

## PE (Processing Element) — başlandı

### D10 — MAC'ın mux seçim sinyali kodlaması/zamanlaması
- **Ne:** `sel` sinyalinin (partial_sum / passed_value / accumulated_value
  arası seçim) FP/BP/WG × stride1/2 fazlarına göre ne zaman/nasıl
  değiştiği.
- **Neden:** Fig. 2 sadece mux'ın VARLIĞINI gösteriyor, kontrol mantığı
  yok. Fig. 3/4/5'teki 6 farklı bağlantı şeması bundan çıkarılabilir
  ama henüz kodlanmadı.
- **Durum:** Açık — Ömer Faruk'un golden model'i bekliyor.

### D11 — Satır 2-3 arası toplayıcılar (Fig.2'deki iki "+" işareti)
- **Ne:** Hangi modda devrede oldukları.
- **Durum:** Açık.

### D12 — Psum FIFO queue derinliği/genişliği
- **Ne:** Makalede hiç sayı verilmemiş.
- **Durum:** Açık.

### D13 — mac.v'nin kendi `sel` kodlaması (yer tutucu)
- **Ne:** D10 netleşene kadar `mac.v`'de kullanılan 2-bit `sel`
  (00=partial_sum, 01=passed_value, 10=accumulated_value) geçici bir
  kodlama.
- **Durum:** D10 netleşince güncellenecek.

### Doğrulanan (varsayım değil): int32 iç hassasiyet
- **Kanıt:** Sayfa 255 metni: "The computation results of the int8
  parameters are accumulated in int32 precision and must be rounded
  back to int8 before being propagated to the next layer." — bu
  doğrudan makale metninden, MAC'ın iç toplama/mux yolu 32-bit.

### D14 (PE-a1) — MAC iç mux'u + sağdaki 3 mux + 2 toplayıcının her modda ne seçtiği
- **Ne:** Fig.2'deki tüm mux/toplayıcıların FP/BP/WG×s1/s2'ye göre tam
  davranışı.
- **Kanıt:** Metinde yok, Fig.2-5'ten kısmen çıkarılabilir [PDF şekil].
- **Durum:** Açık — D10 ile aynı konu, Ömer Faruk'un modelini bekliyor.

### D15 (PE-a2) — Fig.3'teki satır başı 2 girişli mux'un girişleri
- **Ne:** Her satırın başındaki küçük mux'a ne bağlı.
- **Öneri:** Muhtemelen 0 ve Psum FIFO geri beslemesi (kanal birikimi
  için) [Varsayım].
- **Durum:** Açık.

### D16 (PE-a3) — Mux kontrol zamanlaması, gecikme, boşaltma (flush) çevrimleri
- **Ne:** Kontrol sinyallerinin ne zaman değiştiği, stride=2'de kaç ek
  çevrim gerektiği.
- **Kanıt:** [Ölçüldü] (kontrol_pe.py): stride=2 modellerinde (FP ve WG)
  1 ek boşaltma çevrimi gerekti, referans fonksiyonla eşleşmesi için.
- **Durum:** Açık, ama davranış modeli doğrulandı.

### D17 (PE-a4) — Psum FIFO derinliği/genişliği
- **Ne:** Makalede hiç sayı yok.
- **Durum:** Açık (D12 ile aynı).

### D18 (PE-a5) — BP stride=2'de hangi çıktı grubu hangi çekirdek alt kümesini kullanıyor
- **Ne:** Çift/tek satır-sütun grubu (4 grup) ile kullanılan çekirdek
  satır/sütun alt kümesi arasındaki ilişki, ileri geçişteki dolguya
  (padding) bağlı.
- **Kanıt:** [Ölçüldü] (kontrol_pe.py, adjoint-özellik testiyle):
  dolgu=0'da çift grup çekirdek satır/sütun {0,2}'yi, dolgu=1'de {1}'i
  kullanıyor (4+2+2+1=9 MAC dağılımı). Shao dolguyu hiç yazmıyor; NITI
  kodunun varsayılan conv dolgusu 1 [NITI GitHub: ti_torch.py, TiConv2d].
- **Durum:** Matematiksel olarak doğrulandı (ileri geçişin eşleniği/adjoint
  özelliğiyle), dolgu varsayımı (1) hâlâ açık.

### D19 (PE-a6) — BP s2'de hangi hata satırının hangi PE satırına gittiği
- **Ne:** Fig.4(b)'deki satır-indis eşlemesi.
- **Kanıt:** [PDF şekil] — sıralama ön-getirme (input prefetch)
  modülünde yapılıyor, metinde detay yok.
- **Durum:** Açık.

### D20 (PE-a7) — WG'de MAC satırlarına a/e satırlarının veriliş sırası
- **Ne:** Fig.5'teki indis ataması.
- **Kanıt:** [PDF şekil], şematik.
- **Durum:** Açık, ama matematiksel sonuç (g[c]=Σa[s·τ+c]·e[τ]) [Ölçüldü]
  ile doğrulandı.

### D21 (PE-a8) — WG birikiminin int32'ye sığması, batch toplamanın yeri
- **Ne:** En kötü durum taşma riski ve batch boyutu üst sınırı.
- **Kanıt:** [Çıkarım+Ölçüldü] (kontrol_pe.py): 512 kanallı FP'de en
  kötü durum 74.322.432 < 2^31-1, güvenli. WG'de 32×32 haritada
  batch ≤ 130 olmalı (127²×32×32×B < 2^31-1 için B≤130). Shao batch
  boyutunu ve toplamanın tam yerini yazmıyor.
- **Durum:** Üst sınır hesaplandı, kesin batch boyutu açık.

### D22 (PE-a9) — Tam bağlantılı (FC) katmanların PE'ye eşlenmesi
- **Ne:** Metinde yalnızca "diğer desenler çıktı-durağan" deniyor
  [PDF tam], detay yok.
- **Durum:** Açık, düşük öncelik (CIFAR-10/VGG16-benzeri ağda FC var mı
  netleşince önem kazanır).

### D23 (PE-a10) — İlk katmanda −128 girişi
- **Ne:** D9 ile bağlantılı: NITI'nin `TiFloatToInt8` fonksiyonu girişi
  −128..127'ye (asimetrik) kırpıyor [NITI GitHub: ti_torch.py,
  `TiFloatToInt8`, doğrulandı], CLU/PE içindeki değerler ise −127..127
  simetrik (D9). İlk katman girişinde −128 görülebilir.
- **Öneri:** PE test vektörlerine −128'i de ekleyin; int8×int8 en büyük
  çarpım değeri (−128)×(−128)=16384 olur, genişlik hesaplarını buna göre
  kontrol edin.
- **Durum:** Not edildi, test kapsamına eklenmeli.

---

## SRU (Scaling and Rounding Unit) — başlanmadı, açık noktalar hazır

Kaynaklar: Shao II-B-1 (s.255, algoritma) + Algoritma 1 (s.256) + III-B
ve Fig.6 (s.257, donanım). NITI hakem: bp formülü ve B(V) tanımı (NITI
s.3252-3253), ShiftAndRound/Algoritma 2 (s.3253), pseudo-stokastik
algoritma/Algoritma 3 (s.3254).

**Doğrulanan (varsayım değil, metinden/şekilden birebir):**
- SRU, int32/int8 veri + shifting-bit alıp int8 üretiyor; LMS ve GMS
  AYNI donanım birimiyle yapılıyor [PDF tam: III-B].
- Fig.6 bit alanı: 32-bit = [üst bitler | 8 | shift-bit]; shift-bit
  alanı üst yarı (a) ve alt yarı (b)'ye ayrılıyor; a>b ise +1
  [PDF şekil — Egemen bizzat şekli yeniden inceleyip doğruladı, 28.10.2026].
- Shao'nun SRU'sunda **hiç bölücü yok**, yalnızca kaydırma+yuvarlama
  [PDF tam: III-B, III-C — CLU'daki tek bölücüyle karıştırmayın].

### D24 (SRU-a1) — Alg.1'in alt yarı aralığı: Shao'nun kendi yazımı muhtemelen hatalı
- **Ne:** Shao Alg.1 satır 6 `f[bp/2, 0]` yazıyor (bp/2. bit iki yarıda
  birden sayılıyor); NITI Alg.3/Fig.2(b) ise `f[bp/2−1, 0]` diyor
  [NITI makale: s.3254].
- **Kanıt:** [Ölçüldü] (kontrol_sru.py): Shao'nun yazımı birebir
  uygulanırsa bp=2'de hiç yukarı yuvarlamıyor (oran 0.000); NITI
  aralığıyla oran 0.249. bp=8'de ort. hata Shao-yazımı −0.28 LSB,
  NITI aralığı −0.03 LSB.
- **Öneri:** NITI aralığını kullanın (Shao'da muhtemelen yazım hatası).

### D25 (SRU-a2) — Tek bp'de Algoritma 1 ile NITI kodu farklı davranıyor
- **Ne:** Tek bp'de makale f'nin en düşük bitini atıyor, NITI kodu alt
  yarıyı 2 ile çarpıyor.
- **Kanıt:** [Ölçüldü]: örneklerin %26-50'si farklı sonuç veriyor
  (bp=1'de en kötü, bp=11'e doğru azalıyor). bp=1'de Alg.1 keser
  (126.5→126), NITI kodu yuvarlar (→127).
- **Öneri:** Shao'ya sadık kalın: Algoritma 1'i birebir uygulayın, NITI
  kodunu bu noktada örnek almayın.

### D26 (SRU-a3) — Doyma (saturation) eksik: 127+1=128 olabiliyor
- **Ne:** Algoritma 1'in kendisi doyma içermiyor.
- **Kanıt:** [Ölçüldü]: rastgele 200.000 değerin ~%0.8'inde klipsiz
  sonuç 128 çıkıyor. NITI kodu `int8_clip` ile ±127'ye kırpıyor
  [NITI GitHub: ti_torch.py, `int8_clip`, varsayılan `clip_val=127`,
  doğrulandı].
- **Öneri:** ±127 doyma ekleyin (D9 ile tutarlı).

### D27 (SRU-a4) — bp formülü Shao'da yazmıyor
- **Ne:** `bp`'nin nasıl hesaplandığı Shao'da yok.
- **Kanıt:** NITI metni: "If b=B(V)>7, shifted right by b−7"
  [NITI makale s.3253, doğrudan alıntılandı ve doğrulandı]. Yani
  bp = max(0, B−7).
- **Öneri:** NITI formülünü kullanın — Shao'nun II-B'si zaten NITI'ye
  dayandığını söylüyor ("NITI Training Framework" başlığı altında).

### D28 (SRU-a5) — B(V) (effective bitwidth) tanımı: "gereken en az bit" mi, ceil(log2) mi?
- **Ne:** Makale "en büyük değeri temsil etmek için gereken en az bit"
  diyor; NITI kodu `ceil(log2(max))` kullanıyor.
- **Kanıt:** [Ölçüldü]: yalnızca 2'nin tam kuvvetlerinde (1..2^20
  arası 20 değer) ayrışıyor. max=128 olduğunda NITI kodu kaydırma
  yapmıyor ve bu durumda 128 int8'e sığmıyor [NITI GitHub, çıkarım —
  gerçek PyTorch ile çalıştırılmadı].
- **Öneri:** Python'da `bit_length()` kullanın (Shao'nun tanımına daha
  yakın).

### D29 (SRU-a6) — "Maksimum" işaretsiz mutlak değerin maksimumu mu?
- **Ne:** Shao ve NITI "maximum value" diyor ama işaretli mi işaretsiz
  mi belirtmiyor.
- **Kanıt:** NITI kodu `torch.max(torch.abs(input))` kullanıyor
  [NITI GitHub, doğrulandı]. İşaretli maksimum kullanılırsa negatif
  ağırlıklı verilerde (hatalar gibi) yanlış ölçek çıkar [Çıkarım].
- **Öneri:** Mutlak değerin maksimumu.

### D30 (SRU-a7) — "Grup" tam olarak ne?
- **Ne:** LMS'in üzerinde çalıştığı "grup"un tanımı.
- **Kanıt:** Shao: *"PEs finish their computation and produce a group
  of int32 output data, which is part of the full-layer outputs"*
  [PDF tam: III-B, doğrudan alıntılandı ve doğrulandı]. Fig.8'de SRU
  her PE satırının sonunda bir tane.
- **Öneri:** Parametre yapın; en olası yorum "bir PE satırının bir
  geçişte ürettikleri" (Fig.8'deki SRU-satır eşlemesiyle tutarlı).

### D31 (SRU-a8) — GMS kaydırma miktarı: (G−ℓ) mi, B(M)−B(Mg) mi?
- **Ne:** "Global ve yerel maksimum arasındaki fark" ifadesinin bit
  kaydırma miktarına çevrilme şekli.
- **Kanıt:** [Ölçüldü]: B(M)−B(Mg) okuması küçük gruplarda (B<7) yanlış
  sonuç veriyor — örnek: G=2 iken [31,−20,17] grubu için gerçek değer
  [7,−5,4], ama B(M)−B(Mg) okumasıyla [1,−2,1] çıkıyor (gerçek
  değerden çok uzak).
- **Öneri:** Δ = G − ℓ (kaydırma miktarlarının kendi farkı) kullanın,
  bit-genişliği farkı değil.

### D32 (SRU-a9) — Ölçek üssü s'nin güncellenmesi
- **Ne:** Shao'da bahsedilmiyor.
- **Kanıt:** NITI Alg.2 satır 1: *"sq ← sq32 + bp"* [NITI makale
  s.3253, doğrulandı].
- **Öneri:** İki aşamalı toplam kaydırma G için s_çıkış = s_giriş + G.

### D33 (SRU-a10) — a ve e için yuvarlama tipi
- **Ne:** Shao Alg.1 diyor (hem a hem e için); NITI kodunun varsayılanı
  aktivasyon/hata için `RoundShift` (en-yakına), yalnızca ağırlık
  gradyanı için `PstoShift` [NITI GitHub: `ACT_ROUND_METHOD =
  RoundShift`, `ERROR_ROUND_METHOD = RoundShift`,
  `GRAD_ROUND_METHOD = PstoShift`, doğrulandı].
- **Öneri:** Shao'ya sadık kalın: a ve e için de Algoritma 1.

### D34 (SRU-a11) — İki aşamalı (LMS+GMS) sonucu tek aşamalıdan farklı olabilir
- **Ne:** Gruplar farklı ölçekteyse iki yöntem bit-bit aynı sonucu
  vermeyebilir.
- **Kanıt:** [Ölçüldü, sentetik veri]: farklı ölçekli gruplarda
  değerlerin %10-26'sı 1 LSB farklı (daha fazla değil); hepsi aynı
  B'deyse fark 0.
- **Not:** Bu beklenen bir fark, hata değil — NITI ile karşılaştırırken
  (NITI'de LMS/GMS yok, tek aşamalı) bunu göz önünde bulundurun.

### D35 (SRU-a12) — WG çıktıları (g) SRU'dan geçiyor mu, kaydırma b−7 mi b−m_u mu?
- **Ne:** Ağırlık gradyanının SRU işlemi diğer verilerden farklı mı.
- **Kanıt:** NITI, g'yi b−m_u ile kaydırıyor (m_u=1-5 bit aralığında,
  deneysel olarak seçiliyor) [NITI makale s.3253, doğrudan alıntılandı
  ve doğrulandı]. Shao m_u'dan hiç bahsetmiyor; metninde PE dizisinin
  TÜM çıktıları SRU'dan geçiyor gibi anlatılıyor [PDF tam: III-D].
- **Öneri:** SRU'ya hedef genişlik parametresi olarak 7 ya da m_u
  verilebilsin; Shao'ya sadık kalmak isteniyorsa muhtemelen hep 7
  (ayrım yapılmıyor).

### D36 (SRU-a13) — Yerel maksimumu kim hesaplıyor, Max Regs. ne saklıyor?
- **Ne:** Fig.6'da "local max" oku PE'den Max Regs.'e gidiyor
  [PDF şekil, doğrulandı].
- **Öneri (Egemen için mühendislik notu):** B(max)=max(B) olduğundan,
  32-bit maksimum değeri saklamak yerine yalnızca B'yi (6 bit yeter)
  saklamak donanımda yeterli [Çıkarım].

### D37 (SRU-a14) — GMS'de küçük Δ değerlerinde sapma
- **Ne:** Δ=1'de Algoritma 1 her zaman kesiyor (hiç yukarı
  yuvarlamıyor); Δ=2'de yalnızca kesir tam 0.5 olduğunda yukarı
  yuvarlıyor.
- **Kanıt:** [Ölçüldü]: küçük gruplarda ortalama hata sıfıra doğru
  sapıyor (bp=2'de ort. −0.125 LSB).
- **Not:** Bu bir kodlama hatası değil, yöntemin doğal özelliği — test
  ölçütü "gerçek değere yakınlık" değil, Python ile RTL'in bit-bit
  aynı olması.

---

## Mimari zayıflıklar (makalenin kendi sorunları, tez tartışması için)

- CLU'nun N paralel divider'ı sınıf sayısıyla ölçeklenmiyor (DOĞRULANDI:
  gerçek hayatta Vivado BASIC lisansının 50.000 instance sınırına
  çarptık, 10 paralel 64-bit divider 80.053 instance'a çıktı)
- GMS (SRU'nun ikinci aşaması) katmanın tamamı bitene kadar pipeline'ı
  durduruyor
- EPU ve TEU her zaman ikisi de hesaplanıyor, güç israfı
- 16×16 sabit PE dizisi, 16'nın katı olmayan kanal sayılarında yetersiz
  kullanılıyor
- Yalnızca düz SGD destekleniyor, momentum/Adam yok
- Batch-level paralellik hiç ele alınmamış
- TEU dalının ürettiği gi değerleri EPU'dan MİLYONLARCA kat büyük
  olabiliyor (ölçüldü: sa=−10'da ~2.2M vs EPU'nun max 1023) — ortak
  boru hattı TEU'nun en kötü durumuna göre boyutlanmak zorunda

---

## Araç/dil tuzakları (PE ve SRU'da da karşınıza çıkabilir)

1. **Verilog `{concatenation}` her zaman unsigned.** `ai * ({...} <<< x)`
   gibi bir ifadede negatif `ai` yanlış yorumlanır. Çözüm: `$signed(...)`
   ile sarmalayın. (TEU'da gerçek bir hataya yol açmıştı, testbench
   yakaladı.)
2. **Vivado XSIM, port olarak tanımlı diziyi kabul etmiyor**
   (`input [W-1:0] x[0:N-1]` port olarak yasak, Icarus'ta sorun yoktu).
   Çözüm: flat bus (`input [N*W-1:0] x_flat`) + modül içinde unpack.
3. **Xilinx IP core'ları (Divider Generator vb.) tek başına binlerce
   simülasyon "instance"ı.** N paralel kopya hızla BASIC/WebPACK
   lisansının 50.000 sınırını aşar. Çözüm: tek paylaşımlı IP + zaman
   paylaşımlı (round-robin) besleme, sonucu etiketli (tag) bir gecikme
   hattıyla doğru kanala geri yazma.
4. **`.v` uzantılı ama SystemVerilog sözdizimi (`longint`, dizi port
   vb.) kullanan dosyalar Vivado'da "File Type: SystemVerilog" olarak
   işaretlenmeli**, yoksa `xvlog` eski Verilog-2001 kurallarıyla
   derlemeye çalışıp hata verir.
5. **Divider Generator IP saatli (clocked), sabit latency'li.** IP
   kullanan her blok saatsiz (combinational) kalamaz — clk portu ve
   testbench'te sabit bekleme süresi (latency + pay) gerekir.
