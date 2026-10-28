# PE + SRU Görev Listesi — Shao/NITI Gerçekleme

Yöntem CLU'da kanıtlandı, aynısını tekrarlıyoruz: **önce Python golden
model + test vektörleri (Ömer Faruk), sonra Verilog RTL + testbench
(Ego)**. Her iki taraf da kendi Claude oturumunda çalışabilir; bu dosya
ortak referans.

## Ortak hatırlatmalar (ikiniz için)

- Makaleye sadakat önceliği: kod ilkeleri sırası → arayüz tablosu → onay
  → test vektörleri/testbench → RTL → simülasyon
- Her belirsiz/çelişkili noktayı **D-numarası** ile işaretleyip gerekçesini
  yaz (CLU'daki D1-D9 formatı gibi) — sessizce varsayım yapma
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

### PE (Processing Element) — Fig. 2-5, sayfa 256-257
- [ ] Fig. 2 (PE mimarisi: 9 MAC (3×3 dizi), her MAC'te 1 mux, sağda
      3 çıkış mux'ı + 2 toplayıcı, Psum FIFO kuyruğu) oku
- [ ] 6 çalışma modunu ayrı ayrı modelle: FP/stride1, FP/stride2,
      BP/stride1, BP/stride2, WG/stride1, WG/stride2 (Fig. 3-5, her birinde
      (a) stride 1 ve (b) stride 2; makalede 1x1 conv modu yok)
- [ ] Her modun giriş/çıkış ilişkisini (hangi mux hangi veriyi seçiyor,
      Psum FIFO'nun partial sum biriktirme davranışı) Python fonksiyonu
      olarak yaz
- [ ] Her mod için test vektörleri üret
- [ ] Açık noktaları D-numarasıyla işaretle (örn: mux kontrol sinyalinin
      tam ne zaman değiştiği makalede yok — bu bir D olacak)

### SRU (Scaling and Rounding Unit) — Bölüm II-B-1 + Alg. 1 (s. 255-256), Bölüm III-B + Fig. 6 (s. 257)
- [ ] LMS (Local Maximum Scaling) ve GMS (Global Maximum Scaling)
      fonksiyonlarını ayrı ayrı yaz
- [ ] Algoritma 1'i (pseudo-stokastik yuvarlama) birebir uygula. Not: bu,
      CLU'daki D8'i kendiliğinden çözmez — CLU çıkışı SRU'dan geçmiyor (D5)
      ve NITI kodu o adımda StoShift (gerçek stokastik) kullanıyor
- [ ] Test vektörleri üret
- [ ] Açık noktalar (CLU sürecinden hatırlatma): "grup" tam olarak ne
      (PE satırı mı?), `bp` (binary point) nasıl hesaplanıyor — bunlar
      hâlâ makalede yok, D-numarası ver

---

## EGO — Verilog (yapısal RTL)

### PE
- [ ] Ömer Faruk'un modelini bekle (ya da paralel: Fig.2'den geçici
      arayüz varsayımıyla başla, model gelince senkronize et)
- [ ] Yapısal modüller: `mac.v`, mux katmanları, `psum_regfile.v`,
      `pe_top.v`
- [ ] `tb_clu.sv`'nin mantığını uyarla (vectors.txt oku, DUT besle,
      karşılaştır)
- [ ] Vivado/XSIM'de doğrula

### SRU
- [ ] `lms.v`, `gms.v`, `stochastic_round.v` (Algoritma 1), `sru_top.v`
- [ ] Divider gerekip gerekmediğini kontrol et — Shao'nun SRU tanımında bölme
      yok, yalnızca kaydırma + yuvarlama (III-B); "batch size 2'nin kuvvetiyse
      shifter yeterli" ifadesi Shao'da, NITI makalesinde ve tezinde
      bulunamadı. Gerekirse CLU'daki tek-paylaşımlı yaklaşımı tekrarla,
      lisans sınırına tekrar çarpma
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
