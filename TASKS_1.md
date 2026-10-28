# PE + SRU Görev Listesi — Shao/NITI Gerçekleme

Yöntem CLU'da kanıtlandı, aynısını tekrarlıyoruz: **önce Python golden
model + test vektörleri (Ömer Faruk), sonra Verilog RTL + testbench
(Ego)**. Her iki taraf da kendi Claude oturumunda çalışabilir; bu dosya
ortak referans.

## Ortak hatırlatmalar (ikiniz için)

- Makaleye sadakat önceliği: kod ilkeleri sırası → arayüz tablosu → onay
  → test vektörleri/testbench → RTL → simülasyon
- Her belirsiz/çelişkili noktayı **D-numarası** ile işaretleyip gerekçesini
  yaz (CLU'daki D1-D8 formatı gibi) — sessizce varsayım yapma
- NITI yalnızca **hakem/çapraz-kontrol** kaynağı, tasarım kaynağı değil
  (Shao'nun kendi şeması/metni öncelikli)
- Lisans tuzağı: Xilinx IP core'ları (divider, çarpıcı vb.) tek başına
  binlerce "instance" — N paralel kopya yerine **tek paylaşımlı +
  zaman-paylaşımlı** tasarım düşün (CLU'da divider için yaptığımız gibi)
- Verilog tuzağı: `{concatenation}` HER ZAMAN unsigned sonuç verir —
  işaretli sayı içeren ifadelerde mutlaka `$signed()` sarmalayın
- Vivado XSIM, port olarak tanımlanmış diziyi (`input [W-1:0] x[0:N-1]`)
  kabul etmiyor — flat bus (`input [N*W-1:0] x_flat`) kullanın
- Yeni `.v` dosyaları Vivado'da **File Type: SystemVerilog** olarak
  işaretlenmeli

---

## ÖMER FARUK — Python (golden model + test vektörleri)

### PE (Processing Element) — Fig. 2 (s.256), Fig. 3-5 (s.257)
PE **9 MAC** (3×3 dizi), "birkaç" (several) mux ve **Psum FIFO kuyruğu**
içeriyor — Shao'nun kendi metni: *"nine multiply-accumulate units
(MACs), several multiplexers, and a partial sum (Psum) FIFO queue"*
(s.256, doğrudan metinden). `mac.v` bu tanımla (9 MAC) zaten yazıldı.
**6 çalışma modu** var: FP/BP/WG × stride1/2 (1x1 conv modu Shao'da
YOK). (a)-(f) alt şekil etiketleri Fig.1'de (s.255); Fig.3/4/5'in her
biri yalnızca (a)(b) alt şekli içeriyor.
- [ ] Fig. 2, Fig. 3, Fig. 4, Fig. 5 oku
- [ ] 6 çalışma modunu ayrı ayrı modelle: FP/stride1, FP/stride2,
      BP/stride1, BP/stride2, WG/stride1, WG/stride2
- [ ] Her modun giriş/çıkış ilişkisini (hangi mux hangi veriyi seçiyor,
      Psum FIFO'nun partial sum biriktirme davranışı) Python fonksiyonu
      olarak yaz
- [ ] Her mod için test vektörleri üret
- [ ] Açık noktaları D-numarasıyla işaretle (örn: mux kontrol sinyalinin
      tam ne zaman değiştiği makalede yok — bu bir D olacak). Bkz.
      `DEVIATIONS.md`'deki D14-D23: PE için zaten tespit edilmiş 10 açık
      nokta var, sıfırdan başlamana gerek yok.

### SRU (Scaling and Rounding Unit) — algoritma: Shao II-B-1 (s.255) +
Algoritma 1 (s.256); donanım: Shao III-B + Fig. 6 (s.257)
- [ ] LMS (Local Maximum Scaling) ve GMS (Global Maximum Scaling)
      fonksiyonlarını ayrı ayrı yaz
- [ ] Algoritma 1'i (pseudo-stokastik yuvarlama) birebir uygula — CLU'da
      D8 olarak ertelediğimiz nokta, burada gerçek uygulaması lazım
      (NOT: NITI'nin loss kodu `StoShift` — gerçek rastgele — kullanıyor,
      Algoritma 1/`PstoShift` değil; SRU'da Algoritma 1'i uygularken bu
      ayrımı bilerek yapıyoruz, D8'in NITI'yle "aynı" olduğunu sanma)
- [ ] Test vektörleri üret
- [ ] Açık noktalar: bkz. `DEVIATIONS.md`'deki D24-D37, SRU için zaten
      14 aday açık nokta tespit edildi (grup tanımı, bp formülü, doyma,
      iki-aşamalı/tek-aşamalı fark, vb.) — oradan devam et

---

## EGO — Verilog (yapısal RTL)

### PE
- [ ] Ömer Faruk'un modelini bekle (ya da paralel: Fig.2'den geçici
      arayüz varsayımıyla başla, model gelince senkronize et)
- [ ] Yapısal modüller: `mac.v` (hazır), mux katmanları, `psum_fifo.v`
      (FIFO — Shao "regfile" değil "FIFO queue" diyor), `pe_top.v`
- [ ] `tb_clu.sv`'nin mantığını uyarla (vectors.txt oku, DUT besle,
      karşılaştır)
- [ ] Vivado/XSIM'de doğrula

### SRU
- [ ] `lms.v`, `gms.v`, `stochastic_round.v` (Algoritma 1), `sru_top.v`
- [ ] Shao'nun SRU tanımında (III-B, Fig.6) **hiç bölücü (divider) yok**,
      yalnızca kaydırma + yuvarlama var — bölücü yalnızca CLU'da (Fig.7).
      ("Batch size 2'nin kuvvetiyse shifter yeterli" notu SiPS 2020
      öncül makalesinin BN STAT bloğuna aitti, Shao'nun SRU'suyla
      ilgisi yok — bu yüzden SRU'da muhtemelen divider lisans sorunu
      hiç çıkmayacak, ama LMS/GMS'in kendi kaydırma miktarını hangi
      donanımın hesapladığına dikkat et, D29 bkz.)
- [ ] Testbench + Vivado doğrulama

---

## Sona kalan (ikiniz birlikte)
- [ ] PE + SRU arayüzlerini birbirine bağlama
- [ ] Master Controller (FSM) — makalede hiç detay yok, sıfırdan tasarım
- [ ] ReLU, Pooling, Weight Update blokları
- [ ] 16×16 PE dizisi + VGG16-benzeri ağ kablolama
- [ ] CIFAR-10 ile uçtan uca koşum

---

## Paylaşım
- [ ] CLU dosyalarını GitHub'a push'la (`rtl/clu/`, `models/clu/`)
- [ ] Bu dosyayı (`TASKS.md`) repo köküne koy, ikiniz de güncelleyin
- [ ] Yeni D-numaralı kararları `DEVIATIONS.md`'ye ekleyin (CLU'dakiler
      zaten var, PE/SRU eklendikçe büyüsün)
