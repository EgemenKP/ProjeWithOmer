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

### D8 — Son kaydırmada stokastik değil, düz yuvarlama
- **Ne:** D5'teki son >>4 kaydırmanın yuvarlama tipi.
- **Neden:** NITI gerçek kodu bu adımda yuvarlama yapıyor; biz basitlik
  için düz round-to-nearest kullandık.
- **Kanıt:** NITI `ti_loss.py` satır 35: `StoShift(out_grad, 4)`. Bu
  gerçek stokastik yuvarlama (rastgele sayı `torch.randint` ile
  üretiliyor; `ti_torch.py` satır 33-46), Algoritma 1 / `PstoShift` değil.
- **Durum:** Basitleştirme, **açık**. CLU çıkışı SRU'dan geçmediği için
  (D5) SRU'daki Algoritma 1 bu adımı kendiliğinden çözmez. Seçenekler:
  (a) round-to-nearest kalsın, (b) Algoritma 1, (c) LFSR ile gerçek
  stokastik. Karar verilmedi.

### D9 — int8 aralığı simetrik: −127..127 (−128 değil)
- **Kanıt:** NITI metni açıkça "±127" doyma ve "$a_i\le127$" diyor.
- **Durum:** Kesinleşti.

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
