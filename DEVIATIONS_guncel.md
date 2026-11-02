# Sapma ve Karar Günlüğü — Shao/NITI Gerçekleme

Makalenin belirsiz bıraktığı veya kendi içinde çelişen her nokta burada
D-numarasıyla kayıtlı. Yeni blok (PE, SRU, ...) eklendikçe bu dosyaya
D10, D11, ... diye devam edin — numarayı tekrar 1'den başlatmayın.

Format: her madde için **ne**, **neden**, **kanıt**, **durum**.

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
- **Kanıt:** NITI GitHub kodu (`ti_loss.py`, satır 15-18):
  `s*2**out_exp if out_exp>=0 else s/2**-out_exp`.
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

### D8 — Son >>4 kaydırmada LFSR'li stokastik yuvarlama (önceden: düz yuvarlama)
- **Ne:** D5'teki son >>4 kaydırmanın yuvarlama tipi.
- **Neden:** NITI gerçek kodu bu adımda stokastik yuvarlama yapıyor; ilk
  sürümde basitlik için düz round-to-nearest kullanılmıştı.
- **Kanıt:** NITI `ti_loss.py` satır 35: `StoShift(out_grad, 4)`. Bu
  gerçek stokastik yuvarlama (rastgele sayı `torch.randint` ile
  üretiliyor; `ti_torch.py` satır 33-46), Algoritma 1 / `PstoShift` değil.
  NITI'nin ortamı PyTorch 1.7 (Dockerfile); bu sürümde `//` sıfıra doğru
  kestiği için StoShift işaret-büyüklükle çalışıyor: q = |x| >> 4,
  f = |x| mod 16, f > r ise q + 1; ardından ±127 (D9).
- **Durum:** Kesinleşti, **NITI** (Ömer, 02.11): seçenek (c). Rastgele
  sayı üreteci iki kaynakta da tanımlı olmadığı için **Alternatif**:
  - 16 bit Fibonacci LFSR, x^16 + x^14 + x^13 + x^11 + 1 (periyot 65535)
  - r = durumun alt 4 biti; her kullanımdan sonra 4 adım ilerler
  - kanal başına ayrı LFSR (Fig. 7, D3); tohumlar i · 6553 adım aralıklı
  - aynı r verildiğinde NITI StoShift ile birebir aynı (80.001 x 16 durum)

  Birim hazır: `clu_yuvarlama` paketi (`stok_yuvarla.v`, Icarus ve Vivado'da
  40.960/40.960). **Egemen'in CLU golden modeline ve RTL'ine eklenecek.**

### D9 — int8 aralığı simetrik: −127..127 (−128 değil)
- **Kanıt:** NITI metni açıkça "±127" doyma ve "$a_i\le127$" diyor.
- **Durum:** Kesinleşti.

---

## Numaralama notu (02.11.2026)

Yeni maddeler **D29'dan** başlıyor. Egemen tarafında B(m) kararı D28 numarasıyla
verildi; onun dosyasında D10–D27 arası dolu olabilir, çakışma olmasın diye bu
aralık boş bırakıldı. Egemen'in dosyasıyla birleştirirken gerekirse yeniden
numaralanabilir.

Sınıf etiketleri: **Shao** = Shao'dan alındı · **NITI** = Shao sessiz, NITI'ye
dayanıldı · **Alternatif** = ikisinde de belirteç yok · **Karar** = ekip kararı.

---

## SRU (Scaling and Rounding Unit) — golden model ve vektörler hazır, RTL Egemen'de

### D28 — B(m) = bit_length (Egemen'in numarası, burada yalnızca atıf)
- **Ne:** B(m) = m'yi yazmak için gereken en az bit sayısı; m = 0 ise 0.
- **Kanıt:** Tanım Shao'dan değil NITI'den geliyor (§3.2, s. 3253). Shao
  yalnızca "en büyük etkin bit genişliği" diyor.
- **Durum:** Kesinleşti.

### D29 — Alg. 1 alt yarı aralığı: f[bp/2, 0] (SRU-a1)
- **Ne:** Shao Alg. 1 satır 6, alt yarıyı f[bp/2, 0] yazıyor; bp/2. bit iki
  yarıda birden sayılıyor. NITI Alg. 3'te f[bp/2−1, 0].
- **Kanıt:** Shao'daki yazım birebir uygulanınca yuvarlama aşağı sapıyor:
  rastgele değerlerde ortalama hata −0,27 LSB; bp = 2'de hiç yukarı
  yuvarlamıyor. NITI aralığında hata ≈ −0,03 LSB.
- **Durum:** Kesinleşti, **Karar** (Ömer, 28.10): Shao'daki gibi. Bilinen
  sonuç: hafif aşağı sapma; küçük Δ'da (1–2) GMS neredeyse kesme gibi
  davranıyor (SRU-a14, açık gözlem).

### D30 — bp tek olunca: f'nin en alt biti atılır, bp − 1 (SRU-a2)
- **Ne:** Shao Alg. 1 satır 3–5 en alt biti atıyor; NITI kodu alt yarıyı
  2 ile çarpıyor.
- **Kanıt:** İki yöntem örneklerin %26–50'sinde farklı sonuç veriyor.
- **Durum:** Kesinleşti, **Karar** (Ömer, 28.10): makaledeki gibi.

### D31 — 127 + 1 = 128 olursa ±127'ye doyurulur (SRU-a3)
- **Ne:** Alg. 1 yukarı yuvarlamadan sonra ±128 üretebiliyor; int8'e sığmıyor.
- **Kanıt:** Shao Alg. 1 taşmayı tanımlamıyor (çıkış: "rounded 8-bit
  integer"). NITI kodu RoundShift, StoShift ve PstoShift sonucunu `int8_clip`
  ile ±127'ye kırpıyor (`ti_torch.py` 23–72). D9 int8'i −127..127 yapıyor.
  Doyma yokken taşan değerin %98–100'ü grubun en büyük değeri ve işaret
  değiştiriyordu: 200'er rastgele adımda aktivasyon sapması %10'u aşan adım
  oranı %7 (ag1) ve %18,5 (ag2); doymayla hiç yok.
- **Donanım:** İşaret uygulanmadan önce `q[6:0] | {7{q[7]}}` (≈ 7 OR kapısı).
- **Durum:** Kesinleşti, **NITI + D9** (Ömer, 02.11). 28.10 kaydı "doyma yok"
  idi (Claude "Doyurma" cevabını yanlış okumuştu). Vektör ayar kodu
  `1 1 0 1` → `1 1 1 1`. **Egemen'in SRU RTL'ine doyurma eklenmeli.**

### D32 — Kaydırma miktarı: bp = max(0, B − hedef) (SRU-a4)
- **Ne:** Shao formül vermiyor ("en büyük etkin bit genişliğine göre sağa
  kaydırılır", II-B-1).
- **Kanıt:** NITI Alg. 1 satır 4 (s. 3252).
- **Durum:** Kesinleşti, **NITI**. Hedef: a ve e için 7, g için m_u (D38).

### D33 — Maksimum = mutlak değerlerin en büyüğü (SRU-a6)
- **Kanıt:** NITI kodu `torch.max(torch.abs(...))`. İşaretli maksimum, negatif
  ağırlıklı verilerde (ör. hatalar) yanlış ölçek verir.
- **Durum:** Kesinleşti, **NITI**.

### D34 — Grup = bir PE satırının bir geçişte ürettiği çıktılar (SRU-a7, K9)
- **Kanıt:** Shao III-B: "PEs … produce a group of int32 output data";
  Fig. 8'de SRU PE satırı başına çizilmiş.
- **Durum:** Kesinleşti, **Karar** (Ömer, Adım 4).

### D35 — GMS kaydırması: Δ = G − ℓ (SRU-a8)
- **Ne:** Shao "global ve yerel maksimum arasındaki farka göre" diyor.
- **Kanıt:** Harfiyen okuma (B(M_g) − B(M_yerel)), B < 7 olan grupları yanlış
  ölçekliyor: G = 2 iken [31, −20, 17] için doğrusu [7, −5, 4], harfiyen
  okumada [1, −2, 1].
- **Durum:** Kesinleşti, **Karar** (Ömer, 28.10).

### D36 — Ölçek üssü: s_a(l) = s_a(l−1) + s_w + G (SRU-a9)
- **Kanıt:** Shao'da yok; NITI Alg. 2 satır 1.
- **Durum:** Kesinleşti, **NITI**.

---

## Fonksiyon motoru (ReLU, Pooling, ağırlık güncelleme) — ReLU/WU RTL Vivado'da geçti

### D37 — Pooling birimi şimdilik yok (K1)
- **Kanıt:** Shao'nun eğittiği ağda max-pooling yerine stride 2 conv var (IV, s. 258).
- **Durum:** **Karar** (Ömer, 31.10). Gerekirse sonra eklenir.

### D38 — Gradyan SRU'dan m_u hedefiyle geçer (K2a)
- **Kanıt:** Shao sessiz; NITI Alg. 1 satır 13, §3.3. m_u takvimi 5 → 4 → 3.
- **Durum:** Kesinleşti, **NITI** (Ömer, 31.10). Bu yolda taşma olamaz (m_u ≤ 6).

### D39 — w − g taşarsa ±127'ye doyurulur (K2b)
- **Kanıt:** Shao sessiz; NITI `int8_clip` (`ti_torch.py` 21, 71–72). D9 ile uyumlu.
- **Durum:** Kesinleşti, **NITI** (Ömer, 31.10).

### D40 — GMS bütün tüketicilerden önce: PE'ye, ağırlık güncellemeye ve CLU'ya giden yolda (K3)
- **Kanıt:** Shao III-C: CLU son katman aktivasyonlarını tek bir s_a ile alıyor;
  farklı ölçekteki gruplar tek üsle ifade edilemez. III-B: birlikte işlenen
  değerler aynı maksimumla ölçeklenmeli.
- **Durum:** Kesinleşti, **Shao'dan çıkarım** (Claude, Ömer'in "Shao'ya en
  uygun olanı seç" talimatıyla, 31.10).

---

## Sistem ve Master Controller (FSM) — RTL Vivado'da geçti (6206/6206, 02.11)

Ayrıntı: `adim4/TASARIM_FSM.md` (Bölüm 9'daki T maddeleri burada D45–D54).

### D41 — 1 PE; son katman 3×3 conv = FC eşdeğeri (K4 + K5)
- **Durum:** **Karar** (Ömer, Adım 4). Sonuç: 16 PE satırı tek PE ile taklit
  edildiği için Psum FIFO B kat büyüyor (D45).

### D42 — GMS + ReLU ayrı bir kopyalama geçişinde, aktivasyon deposuna yazılır (K6a)
- **Not:** Shao Fig. 6'da GMS, tampondan PE'ye giden yolda anında yapılıyor;
  bu karar ondan sapıyor.
- **Durum:** **Karar** (Ömer, Adım 4).

### D43 — Ağırlık güncelleme ağırlık tamponuna doğrudan yazar; GMS + w − g + yazma tek geçişte (K6b, T9)
- **Durum:** **Karar** (Ömer, Adım 4).

### D44 — Faz sırası: BP eski ağırlıkla, sonra WG, sonra WU; 1. katmanda BP yok (K7, T3)
- **Kanıt:** Shao iş sırasını yazmıyor; NITI kod sırası.
- **Durum:** Kesinleşti, **NITI**.

### D45 — Döngü sırası: örnek döngüsü kanal çiftinin içinde (T1)
- **Ne:** FP o→c→b→r, BP c→o→b→p, WG o→c→b→r.
- **Kanıt:** Shao III-D (s. 258): girişler batch boyunca PE satırlarına,
  ağırlıklar çıkış kanalı boyunca sütunlara açılır. III-A-1: ağırlıklar kanal
  bitene kadar sabit.
- **Bedel:** Psum FIFO 64 → 128 int32 (K4'ün sonucu).
- **Durum:** Kesinleşti, **Shao** (Ömer, 02.11; eski hâli: FP b→o→c→r).

### D46 — Katman, sonrakine geçmeden batch'in tüm örnekleri için bitirilir (T2)
- **Kanıt:** Shao III-D + NITI'de katman başına tek ölçek üssü.
- **Durum:** **Shao + NITI**.

### D47 — Max Regs ayrı blok ve 32 bitlik yerel maksimumu saklar; B, ℓ, G, Δ bu blokta hesaplanır (T4)
- **Kanıt:** Shao III-B ve Fig. 6 (s. 257): "the local maximum is reserved in
  a register file"; Fig. 6'da Max Regs ayrı blok. Hesabın yeri iki kaynakta da yok.
- **Bedel:** 56 × 6 bit → 56 × 32 bit.
- **Durum:** Kesinleşti, **Shao** (blok) + **Alternatif** (hesabın yeri)
  (Ömer, 02.11; eski hâli: FSM içinde 6 bitlik B). SRU-a13'ü de kapatır.

### D48 — Tek komut, tek "bitti"; boru hattı yok; komutlar arası en az 1 çevrim boşluk (T5)
- **Durum:** **Alternatif**. Hangi bloğun "bitti" vereceği 4.0 arayüz sözleşmesinde.

### D49 — BP stride 2'de tamamen kırpılacak geçişler atlanır: ⌈(H + p)/2⌉ geçiş (T6)
- **Kanıt:** Shao'nun açık amacı stride 2'de boşa giden (dummy) işlemleri
  ayıklamak (I, III-A, V). Geçişin kendisi Shao'da yok.
- **Durum:** **Shao (ilke)**.

### D50 — Dolguya düşen BP stride 2 çıktıları SRU grubuna girmez, yazılmaz (T7)
- **Kanıt:** Var olmayan değerler grubun yerel maksimumunu belirlememeli (III-B).
- **Durum:** **Shao**.

### D51 — Kopyalama geçişinde önce ReLU, sonra GMS (T8)
- **Kanıt:** Fig. 8: ReLU fonksiyon motorunda, yalnızca çıkış tamponuna bağlı.
  Fig. 6: GMS tampondan PE'ye giden yolda. Sonuç bit bit aynı (49.152 durumda
  ve sistem düzeyinde kontrol edildi).
- **Durum:** Kesinleşti, **Shao** (Ömer, 02.11; eski hâli: önce GMS).

### D52 — Katman tablosu FSM'e giriş portlarından gelir (T10)
- **Durum:** **Alternatif**. Testbench dosyadan sürüyor; 4.5'te bir
  yapılandırma register'ı sürecek.

### D53 — CLU, sistem golden modelinde yer tutucu (T11)
- **Ne:** Shao Alg. 2 ve D1–D9'dan yeniden yazıldı; gerçek CLU golden modeli
  gelince değiştirilecek.
- **Durum:** **Geçici**. D8 (c) yer tutucuda uygulandı (02.11); D5 hâlâ açık.

### D54 — Yeni İŞ_BAŞLA komutu (T12)
- **Ne:** Her PE işinden önce gelir; tamponları sıfırlar, SRU hedef
  genişliğini (7 ya da m_u) Max Regs'e bildirir.
- **Kanıt:** LMS kaydırması ilk gruptan itibaren hedefe ihtiyaç duyuyor (D47'nin
  sonucu); hedefin nasıl iletileceği iki kaynakta da yok.
- **Durum:** Kesinleşti, **Alternatif** (Ömer, 02.11).

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
6. **Vivado'da proje yolunda boşluk varsa `-testplusarg` ile verilen klasör
   yolu bozulur.** Testbench dosyayı bulamaz. Çözüm: testbench dosyayı
   bulamazsa çalışma klasörüne baksın; Vivado script'i vektörleri oraya da
   kopyalasın (fe_rtl ve adim4 script'leri böyle).
7. **Testbench'te bir darbeyi verdiğin kenarda DUT'un register'ını okursan
   eski değeri görürsün.** Örnek: `basla`'dan hemen sonra `bitti` hâlâ önceki
   turun 1'i. Çözüm: bir kenar daha bekleyip sonra kontrol et.
