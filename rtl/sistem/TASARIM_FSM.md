# Adım 4: Master Controller (FSM) ve Max Regs Tasarımı

> **Güncelleme (03.11.2026):** Adım 3 kararları golden'a işlendi: SRU-a3 yeniden doymasız (D59; Bölüm 10 artık geçmiş kaydı), D8 = (a) en yakına (D60; T11). Float kontrolünün sıkı eşikleri doymalı bir referans çalıştırmada denetleniyor (D65). Entegrasyonun arayüzleri `ARAYUZ_SOZLESMESI.md`'de (D64): FSM değişmiyor, `maks_reg` çıkarılıyor ve G SRU'dan geliyor. Ayrıntı: `README_ADIM4.md`.
>
> **Durum:** RTL (4.4) yazıldı; Icarus Verilog'da ve Vivado XSIM'de PASS (Vivado: Ömer, 02.11). Bölüm 9'da üç karar değişti (T1, T4, T8) ve bir yeni madde var (T12); dördü de Ömer tarafından onaylandı (02.11). SRU-a3, 02.11'de ±127 doymaya çevrildi (Bölüm 10).
>
> **Hazırlayan:** Claude (Ömer'in isteğiyle), 02.11.2026
>
> **Dayanak:** Shao III-D'de master controller için tek cümle var: "PE'leri ve ön-getirme modüllerini eğitim fazına göre yapılandırır" (s. 258). Fig. 8'de controller'ın hiçbir bağlantısı çizilmemiş.
>
> **Karar kuralı (Ömer, 02.11.2026):** T maddelerinde önce Shao'ya bakılır. Shao bir şey söylemiyorsa NITI'ye dayanılır. İkisinde de belirteç yoksa uygun bir alternatif seçilir. Her maddenin hangi gruba girdiği Bölüm 9'daki tabloda.
>
> **Verilen kararlar:** K4+K5 (1 PE, son katman 3×3 conv), K6a (kopyalama geçişi), K6b (doğrudan ağırlık yazma), K9 (grup = bir PE satırının bir geçişi). Kural gereği NITI'den: K7 (faz sırası) ve m_u.

## 0. FSM ne yapıyor

FSM'i bir orkestra şefi gibi düşün. Kendisi hesap yapmaz. Her adımda bir bloğa ne yapacağını bir **komutla** söyler, blok "bitti" deyince sıradakine geçer. Bir eğitim adımı şu sırayla ilerler:

```
İLERİ  katman 1 → 2 → 3   İŞ_BAŞLA → PE geçişleri → SRU(LMS) → ÖLÇEK → s_a güncelle → KOPYA (ReLU, sonra GMS)
CLU    örnek 0, 1          son katman aktivasyonları + s_a → δ_3
GERİ   katman 3 → 2 → 1   [İŞ_BAŞLA → BP → ÖLÇEK → KOPYA (ReLU-geri, sonra GMS)]   (1. katmanda BP yok)
                           İŞ_BAŞLA → WG → ÖLÇEK → WU (GMS + w − g + geri yazma)
```

## 1. Test ağları (4.1)

**ag1, ana test ağı.** Batch 2, m_u = 5, giriş ölçek üssü s_a0 = −7. Altı PE modunun hepsi kullanılıyor. 4.5 entegrasyonu bunu kullanacak.

| Katman | Cin → Cout | Giriş → çıkış | Stride | Dolgu | ReLU | s_w | Kullanılan modlar |
|---|---|---|---|---|---|---|---|
| 1 | 2 → 4 | 7×7 → 7×7 | 1 | 1 | var | −8 | FP s1, WG s1 (BP yok) |
| 2 | 4 → 4 | 7×7 → 3×3 | 2 | 0 | var | −8 | FP s2, BP s2, WG s2 |
| 3 | 4 → 10 | 3×3 → 1×1 | 1 | 0 | yok | −8 | FP s1, BP s1, WG s1 |

3\. katman 3×3 girişte dolgusuz 3×3 conv; matematiksel olarak 36 girişli bir FC katmanı (K5). Çıkışı CLU'ya gidiyor (N = 10).

**ag2, yalnızca FSM testi için ikinci yapılandırma.** Batch 3, tohum 2026.

| Katman | Cin → Cout | Giriş → çıkış | Stride | Dolgu | ReLU | s_w |
|---|---|---|---|---|---|---|
| 1 | 3 → 4 | 5×5 → 5×5 | 1 | 1 | var | −8 |
| 2 | 4 → 6 | 5×5 → 3×3 | 2 | 1 | var | −7 |
| 3 | 6 → 10 | 3×3 → 1×1 | 1 | 0 | yok | −9 |

- **Neden gerekti:** ag1'de son iki katmanda s_w + G = −8 + 8 = 0. Bu yüzden s_a değişmiyor ve CLU'ya yanlış s_a gitse bile test fark etmiyordu (RTL mutasyon testinde ortaya çıktı). Ayrıca 2. katmanda Cin = Cout olduğu için kanal sırası hataları o katmanda görünmüyordu.
- **ag2'de:** Her katmanda Cin ≠ Cout ve s_w'ler farklı. Dolgulu stride 2 sayesinde BP'de T6 atlaması da çalışıyor (3 geçiş; He + 1 = 4 değil). s_a her katmanda değişiyor: −7 → −5 → −4 → −5.

## 2. Bloklar ve el sıkışma

| Blok | Aldığı | Verdiği |
|---|---|---|
| PE + ön-getirme | PE komutu (faz, katman, örnek, kanallar, satır, ilk, son) | `kom_bitti`; `son` = 1 olan geçişte grubun yerel maksimumu (Max Regs'e) |
| Max Regs (`maks_reg`) | Komut yolunu dinler: İŞ_BAŞLA'dan hedef, KOPYA/WU'dan grup numarası; PE tarafından yerel maksimum | LMS kaydırması `l` ve GMS kaydırması `Δ` (SRU'ya); `G` (FSM'e) |
| SRU (LMS ve GMS) | Veri + Max Regs'ten kaydırma miktarı | 8 bitlik sonuç |
| Fonksiyon motoru | KOPYA (ReLU), CLU, WU komutları | `kom_bitti` |
| FSM | `kom_bitti`, ÖLÇEK'te `G` | Komutlar; s_a (SA ve CLU komutlarında) |

- **El sıkışma (T5):**
  - FSM bir komutu `kom_gecerli` ile verir; komut, `kom_gecerli` 1 olduğu sürece sabit kalır.
  - İşi yapan blok bitirince 1 çevrimlik `kom_bitti` darbesi verir.
  - FSM bunun üzerine `kom_gecerli`'yi indirir, en az 1 çevrim bekler ve sıradaki komutu verir. Aynı anda tek komut var, boru hattı yok.
- **Kim `kom_bitti` verecek:** Her op için hangi bloğun cevap vereceği 4.0 arayüz sözleşmesinde belirlenecek. İç komutlara (İŞ_BAŞLA, ÖLÇEK, SA, BİTTİ) Max Regs ya da FSM'in kendisi tek çevrimde cevap verebilir. Testbench'te hepsine sahte blok cevap veriyor.

**Plandaki bir boşluk:** Fig. 8'deki *Input Prefetch* ve *Weight Prefetch* modülleri ile çıkış adres üreteci, 5 adımlı planda yer almıyor. Bunlar 4.5 entegrasyonunda gerekecek. Ne yapmaları gerektiği zaten belli: `sistem_golden.py` içindeki komut yorumlayıcı her komut için akışları hazırlıyor (dolgu, çift/tek ayırma, BP s2 akışları, kısmi toplam zamanlaması) ve sonuçları adreslere yazıyor. Bu kod, o modüllerin golden modeli olarak kullanılabilir.

## 3. Komut seti

Her komut 10 tamsayıdan oluşur: `op faz katman b x y z a1 a2 a3`. Bu biçim `komutlar.txt` ile aynı. RTL'de her alan 16 bit, ikiye tümleyen.

| op | Ad | faz | katman | b | x | y | z | a1 | a2 | a3 |
|---|---|---|---|---|---|---|---|---|---|---|
| 8 | İŞ_BAŞLA | faz | l | 0 | hedef (7 ya da m_u) | 0 | 0 | 0 | 0 | 0 |
| 1 | PE | 0 FP / 1 BP / 2 WG | l | örnek | FP: o · BP: c · WG: o | FP: c · BP: o · WG: c | FP: r · BP: p · WG: r | ilk | son | grup (son = 0 ise −1) |
| 2 | ÖLÇEK | faz | l | 0 | 0 | 0 | 0 | grup sayısı | 0 | 0 |
| 4 | SA | 0 | l | 0 | yeni s_a | 0 | 0 | 0 | 0 | 0 |
| 3 | KOPYA | 0 FP / 1 BP | l | örnek | kanal | satır (BP s2'de p) | işlem: 0 yok, 1 ReLU, 2 ReLU-geri | grup | 0 | 0 |
| 5 | CLU | 0 | L | örnek | s_a | 0 | 0 | 0 | 0 | 0 |
| 6 | WU | 2 | l | 0 | o | c | 0 | grup | 0 | 0 |
| 7 | BİTTİ | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Alanların anlamı:
- **ilk:** FP/BP'de kısmi toplam FIFO'dan alınmaz, 0 verilir. WG'de akümülatörler sıfırlanır.
- **son:** Çıktılar nihai; SRU'ya gider ve bir grup oluşturur.
- **Veriye bağlı alan yalnızca s_a** (SA ve CLU komutlarında). G ve Δ artık komutun içinde değil; Max Regs bloğunun çıkışları ve `maksreg.txt` ile ayrıca kontrol ediliyor.
- **Sayılar (ag1):** Bir eğitim adımı 1186 komut. Dağılım:
  - 8 İŞ_BAŞLA
  - 944 PE
  - 8 ÖLÇEK
  - 3 SA
  - 156 KOPYA
  - 2 CLU
  - 64 WU
  - 1 BİTTİ

  ag2'de 2261 komut.

## 4. İşler ve döngüler

```
for l = 1..L:                                         # İLERİ
    İŞ_BAŞLA(FP, l, hedef 7)
    for o, c, b, r:   PE(FP, l, b, o, c, r, ilk = c==0, son = c==Cin-1)
    ÖLÇEK(FP, l);  SA(l)
    for o, b, r:      KOPYA(FP, l, b, o, r, işlem = l'de ReLU varsa 1, yoksa 0)
for b:                CLU(b, s_a)
for l = L..1:                                         # GERİ
    if l > 1:
        İŞ_BAŞLA(BP, l, hedef 7)
        for c, o, b, p:   PE(BP, l, b, c, o, p, ilk = o==0, son = o==Cout-1)
        ÖLÇEK(BP, l)
        for c, b, p:      KOPYA(BP, l, b, c, p, işlem = l-1'de ReLU varsa 2, yoksa 0)
    İŞ_BAŞLA(WG, l, hedef m_u)
    for o, c, b, r:   PE(WG, l, b, o, c, r, ilk = b==0 && r==0, son = b==B-1 && r==Ho-1)
    ÖLÇEK(WG, l)
    for o, c:         WU(l, o, c)
BİTTİ
```

- **Örnek döngüsü kanal çiftinin içinde (T1):** Ağırlıklar (FP, BP) ya da akümülatörler (WG) bir kanal çifti boyunca sabit kalıyor ve o sürede batch'teki bütün örnekler işleniyor.
- **Tüketici döngüsü:** KOPYA ve WU döngüleri, PE işinin `son` geçişlerini üretildikleri sırayla dolaşıyor. Bu yüzden RTL'de aynı dört sayaç kullanılıyor: FP/BP'de k1'in, WU'da k2 ile k3'ün sınırı 1 yapılıyor.
- **Geçiş sayıları:**
  - FP: çıkış satırı başına bir geçiş (Ho).
  - BP stride 1: dX satırı başına bir geçiş (H).
  - BP stride 2: geçiş başına 2 dX satırı; ⌈(H + p)/2⌉ geçiş (T6).
  - WG: hata satırı başına bir geçiş (Ho).

## 5. Max Regs ve s_a

- **Max Regs (`maks_reg`, T4):**
  - Her grubun 32 bitlik yerel maksimumunu (M) saklar.
  - Derinlik 64 grup. En çok grup sayısı ag1'de 56 (FP katman 1), ag2'de 60.
  - Global maksimum, gruplar geldikçe güncellenen bir register'da tutuluyor. Sonuç, katman sonunda register dosyasını taramakla aynı.
- **Hesaplar** (B(m): m'yi yazmak için gereken bit sayısı, D28):
  - **İŞ_BAŞLA:** hedef ← x (7 ya da m_u); global maksimum ← 0.
  - **Grup geldiğinde:** LMS kaydırması l = max(0, B(M) − hedef). SRU'nun LMS girişine gider.
  - **ÖLÇEK:** G = max(0, B(M_global) − hedef). FSM bu değeri örnekler.
  - **KOPYA ve WU:** Grup g için Δ_g = G − max(0, B(M_g) − hedef) (SRU-a8). SRU'nun GMS girişine gider.
- **SA (yalnızca FP, FSM'in içinde):** s_a ← s_a + s_w(l) + G. CLU bu s_a'yı kullanır (Shao III-C: CLU, a ile s_a'yı alır).
  - ag1'de s_a = −7 → −5 → −5 → −5.
  - ag2'de s_a = −7 → −5 → −4 → −5.

## 6. Bellek bölgeleri (1 PE, ag1)

| Bölge | İçerik | Boyut |
|---|---|---|
| AKT | Her katmanın aktivasyonu, her örnek için (ReLU ve GMS sonrası); 0 = giriş | 196 + 392 + 72 + 20 = 680 bayt |
| HATA | δ_l, her örnek için | 392 + 72 + 20 = 484 bayt |
| AGR (ağırlık tamponu) | W_l | 72 + 144 + 360 = 576 bayt |
| CIK (çıkış tamponu) | Bir işin LMS çıktıları, grup sırasıyla | en çok 392 bayt (FP 1 ve BP 2) |
| Psum FIFO (PE içinde) | Kanallar arası kısmi toplamlar | en çok 128 int32 (BP s2, katman 2) |
| Max Regs | Grup başına yerel maksimum | 56 × 32 bit (RTL'de 64 × 32 bit) |

- **Psum FIFO büyüdü:** T1'de örnek döngüsü içeri alındığı için FIFO B kat büyüdü (64 → 128 int32).
  - Shao'nun 16×16 dizisinde her PE satırı ayrı bir örneği işliyor (III-D). O yüzden orada PE başına FIFO büyümüyor.
  - Bizdeki büyüme, 16 satırı tek PE ile taklit etmemizden (K4) kaynaklanıyor. [Shao III-D cümlesinden benim çıkarımım]
- **WG için aktivasyonlar:** İleri yayılımdan geri yayılıma kadar AKT'de saklanıyor. VGG ölçeğinde bu çip içine sığmaz; nerede tutulacağı Adım 5'in sorusu.

## 7. Durumlar

```
BOSTA --basla--> İŞ_BAŞLA -> PE (döngü) -> ÖLÇEK -> [SA, yalnızca FP] -> TÜKET (KOPYA/WU döngüsü) --+
                     ^                                                                               |
                     +------------------------------- sıradaki iş --------------------------------+
                                                                                                     |
                     İŞ_BAŞLA (BP L ya da WG L) <-- CLU (örnek döngüsü) <-- FP L bitti ----------------+
                                                                                                     |
                                       SON <-- BİTTİ <-- WG 1 bitti ---------------------------------+
```

- **İş sırası:** FP 1…L → CLU → BP L, WG L, BP L−1, WG L−1, …, WG 1. BP 1 yok.
- **Komut verme:** Her durumda komut `kom_gecerli` ile verilir. `kom_bitti` gelince sayaçlar ve durum ilerler; `kom_gecerli` bir çevrim 0 olur.
- **Döngü sayaçları:** Dört sayaç var; k0 en dış, k3 en iç. Sınırları katman tablosundan ve fazdan gelir (Bölüm 4).

## 8. RTL (4.4)

| Dosya | İçerik |
|---|---|
| `rtl/master_controller.v` | FSM: iş sıralayıcı, 4 sayaçlı döngü motoru, s_a register'ı, komut çıkışı, el sıkışma |
| `rtl/maks_reg.v` | Max Regs: 64 × 32 bit register dosyası, B(m) öncelik kodlayıcısı, l, G ve Δ |
| `tb/tb_fsm.sv` | Sahte bloklu testbench |
| `run_sim.tcl` | Vivado script'i (geçici projede çalışır) |

- **Kaynak kullanımı:** İkisi de saf Verilog-2001.
  - Yosys'te latch çıkmadı.
  - master_controller 228 hücre ve 13 grup flip-flop.
  - maks_reg bir register dosyası ve 2 register.
- **Testbench'in yaptıkları:**
  - **Gecikme:** Sahte blok her komuta rastgele 1–5 çevrim sonra `kom_bitti` verir (LFSR).
  - **Yerel maksimum:** `son` geçişlerde sahte PE grubun yerel maksimumunu `maksreg.txt`'ten okuyup Max Regs'e verir.
  - **Kontroller:**
    - FSM'in her komutu, `komutlar.txt`'teki sıradaki satırla 10 alanın hepsinde aynı mı
    - komut geçerliyken sabit kalıyor mu
    - Max Regs'in l, G ve Δ çıkışları doğru mu
    - komut ve olay sayıları tam mı
    - BİTTİ'den sonra FSM duruyor mu
  - **Turlar:** Üç tur çalışır: ag1, ag2, yine ag1. Böylece yeniden başlatma ve yapılandırma değişikliği de sınanıyor.

## 9. Kararlar ve dayanakları

Sınıf: **Shao** = Shao'dan alındı · **NITI** = Shao sessiz, NITI'ye dayanıldı · **Alternatif** = ikisinde de belirteç yok · **Karar** = sizin verdiğiniz karar.

| # | Karar | Sınıf | Dayanak | Durum |
|---|---|---|---|---|
| T1 | Döngü sıraları: FP o→c→b→r, BP c→o→b→p, WG o→c→b→r (örnek döngüsü kanal çiftinin içinde) | Shao | III-D (s. 258): girişler batch ya da satır boyunca PE satırlarına, ağırlıklar çıkış kanalı boyunca PE sütunlarına açılır. III-A-1: ağırlıklar kanal bitene kadar sabit | **Değişti, onaylandı** (Ömer, 02.11; eski: FP b→o→c→r, BP b→c→o→p). Psum FIFO B kat büyüdü (Bölüm 6) |
| T2 | Bir katman, sonrakine geçmeden batch'teki tüm örnekler için bitirilir | Shao + NITI | Shao III-D: örnekler aynı ağırlıklarla birlikte işlenir. NITI: ölçek tüm batch'in maksimumundan, katman başına tek üs | Değişmedi |
| T3 | İş sırası Bölüm 4'teki gibi; BP'nin çıktısı WG başlamadan kopyalanır | NITI | K7 (NITI kod sırası: BP eski ağırlıkla, sonra WG, sonra WU; 1. katmanda BP yok). Shao iş sırasını yazmıyor | Değişmedi |
| T4 | Max Regs ayrı blok ve grubun yerel maksimumunu (32 bit) saklar. B, l, G, Δ hesabı bu blokta; global maksimum yürüyen bir register'da; s_a FSM'de | Shao (blok ve içeriği) + Alternatif (hesabın yeri) | Shao III-B ve Fig. 6 (s. 257): "the local maximum is reserved in a register file"; Fig. 6'da Max Regs, PE'den yerel maksimum alan ve iki SRU aşamasına bilgi veren ayrı bir blok. Hesabın nerede yapılacağı iki kaynakta da yok | **Değişti, onaylandı** (Ömer, 02.11; eski: FSM içinde 6 bitlik B). Maliyet 56 × 6 bitten 56 × 32 bite çıktı |
| T5 | Tek komut, tek bitti; boru hattı yok; komutlar arasında en az 1 çevrim boşluk | Alternatif | İki kaynak da kontrol arayüzünü tanımlamıyor. Hız şimdilik hedef değil | Değişmedi |
| T6 | BP s2'de tamamen kırpılacak geçişler atlanır: ⌈(H + p)/2⌉ geçiş | Shao (ilke) | Shao'nun açık tasarım amacı stride 2 katmanlarda boşa giden (dummy) işlemleri ayıklamak (I. bölüm katkılar, III-A, V. sonuç). Kırpılacak geçişi atlamak aynı ilkenin uygulaması; geçişin kendisi Shao'da yazmıyor | Değişmedi |
| T7 | Dolgu bölgesine düşen BP s2 çıktıları SRU grubuna girmez, yazılmaz | Shao | III-B / Fig. 6: grup, PE'lerin ürettiği çıktıların bir parçası. Var olmayan değerler grubun yerel maksimumunu belirlememeli | Değişmedi |
| T8 | KOPYA'da önce ReLU, sonra GMS; ReLU-geri maskesi AKT'deki a_{l−1}'den alınır | Shao | Fig. 8: fonksiyon motoru (ReLU) yalnızca çıkış tamponuna bağlı. Fig. 6: GMS, tampondan PE'ye giden yolda. Sonuç bit bit aynı: 49.152 durumda ve sistem düzeyinde uçtan uca kontrol edildi | **Değişti, onaylandı** (Ömer, 02.11; eski: GMS, sonra ReLU) |
| T9 | WU, GMS + w − g + geri yazmayı tek geçişte yapar | Karar (K6b) | — | Değişmedi |
| T10 | Katman tablosu FSM'e giriş portlarından gelir; testbench dosyadan sürer, 4.5'te bir yapılandırma register'ı sürecek | Alternatif | İki kaynak da yazmıyor | Değişmedi (ifade netleşti) |
| T11 | CLU golden'da **yer tutucu**: Shao Alg. 2 ve D1–D9'dan yeniden yazıldı; D8 (c) 02.11'de uygulandı: >>4, LFSR'li stokastik yuvarlama (`clu_yuvarlama.py`). **03.11:** D8 = (a), en yakına (D60); yer tutucu Egemen'in golden modeliyle 1940 vektörde aynı | — | Gerçek CLU modeliniz yok. FSM'in komut sırası CLU'ya bağlı değil; yalnızca veriye bağlı alanlar (s_a, M, G, Δ) değişebilir ve dosyalar yeniden üretilir | Değişmedi |
| T12 | **Yeni:** İŞ_BAŞLA komutu. Her PE işinden önce gelir; tamponları sıfırlar ve SRU hedef genişliğini (7 ya da m_u) Max Regs'e bildirir | Alternatif | LMS kaydırması ilk gruptan itibaren hedefe ihtiyaç duyuyor (T4'ün sonucu). Hedefin nasıl iletileceği iki kaynakta da yok | **Yeni, onaylandı** (Ömer, 02.11) |

## 10. SRU-a3: ±127 doyma (02.11.2026) — 03.11'de geri alındı (D59)

> 03.11: Ömer makaleye sadakat için doymasıza döndü. Aşağıdaki ölçümler kayıt için duruyor. Golden artık `DOYMA = False` ile çalışıyor; float kontrolünün sıkı eşikleri doymalı referans çalıştırmada (D65), bu yüzden "Geri almak gerekirse" paragrafındaki durma artık yok.

**Karar:** SRU'da yuvarlama sonucu 128'e ulaşırsa ±127'ye doyuruluyor: +128 → 127, −128 → −127 (Ömer, 02.11).
- 28.10 kaydı "doyma yok" idi: o gün verilen "Doyurma" cevabını Claude "doyurma yapma" diye okumuştu.
- Bu seçim, karar dosyasındaki D9 ile de çelişiyordu.

**Dayanak:**
- **D9 (karar dosyası, kesinleşti):** int8 aralığı simetrik, −127..127. Shao'nun Alg. 1'i ±128 üretebildiği için D9'a uymanın yolu doyurmak.
- **Shao Alg. 1 (s. 256):** Taşmayı tanımlamıyor; çıkışı yalnızca "rounded 8-bit integer" olarak veriyor.
- **NITI kodu:** RoundShift, StoShift ve PstoShift sonucu `int8_clip` ile ±127'ye kırpıyor (`ti_torch.py` satır 23–72).

**Doyma yokken ne oluyordu (ölçüm):**
- **Taşma sıklığı:** Taşma değerlerin %0,01–0,03'ünde oluyor. Taşan değerlerin %98–100'ü grubun en büyük değeri; doyma yoksa bu değer işaret değiştiriyor (+128 → −128).
- **ag1'in bu adımında:** 1. katmanda +0,997 olması gereken bir aktivasyon 0 çıkıyordu; FP sapması %40'a varıyordu (tablo).
- **200'er rastgele başlangıçta:**
  - Aktivasyon sapması %10'u aşan adımlar doyma yokken ag1'de 14 (%7), ag2'de 37 (%18,5) idi; doymayla hiç yok.
  - En kötü sapma doyma yokken %147 ve %183, doymayla %6,9 ve %7,0.

| Ölçüm (ag1, bu eğitim adımı) | Kararla (±127 doyma) | Doymasız olsa |
|---|---|---|
| FP katman 1: en büyük sapma / en büyük değer | %1,3 | %40,2 |
| FP katman 2 | %3,1 | %18,5 |
| FP katman 3 | %3,5 | %16,5 |
| Geri yayılım ve gradyan kosinüsleri | 0,984–0,998 | 0,974–0,996 |

**Donanım:** Alg. 1'deki gibi işaret-büyüklükle çalışılırken, işaret uygulanmadan önce `q[6:0] | {7{q[7]}}` (yaklaşık 7 OR kapısı). q en fazla 128 olabildiği için bu, min(q, 127) ile aynı. FSM ve Max Regs RTL'i değişmedi.

**Etkilenen dosyalar:**
- **SRU golden:** `DOYMA = True`, vektörlerin ayar kodu `1 1 1 1`. Yalnızca taşma satırları değişti: yuvarlamada 48 satır, katmanda 1 değer.
- **Egemen'in SRU RTL'i:** Doyurma eklenmeli ve yeni vektörlerle yeniden test edilmeli.
- **Fonksiyon motoru:** `relu.hex` ve `wu_cikarma.hex` değişmedi; ReLU/WU RTL'inin Vivado testi geçerli. `wu_katman.txt`'de yalnızca ayar kodu değişti.
- **Sistem vektörleri:**
  - ag1'de komut dizisi aynı; beklenen sonuçlar ve Max Regs olayları değişti.
  - ag2'de veri dosyaları aynı kaldı. Oradaki tek taşma negatifti ve ReLU onu her iki durumda da sıfırlıyor.

**Geri almak gerekirse:** `sru_golden.py`'de `DOYMA = False` yapılır. `sistem_golden.py` bu durumda açık bir mesajla durur, çünkü float kontrolünün sıkı eşikleri doymaya göre konmuş; iki dosya birlikte değiştirilmeli. `OKUNUR.txt`'deki "doymasız olsa" sütunu, karşılaştırma için her çalıştırmada üretiliyor.

## 11. Doğrulama durumu

**Golden model (`sistem_golden.py`):**
- **(I) ve (II) bit bit aynı:** Komut yorumlayıcı (I) ile tensör düzeyi (II), ag1 ve ag2'de aynı sonucu veriyor. Karşılaştırılanlar:
  - aktivasyonlar, hatalar ve son ağırlıklar
  - s_a
  - iş başına yerel maksimum listeleri ve G'ler
  - Max Regs olaylarının tamamı

  (I), çevrim düzeyi PE modeli ve ön-getirme mantığıyla çalışıyor ve KOPYA'yı Shao sırasıyla yapıyor (ReLU, sonra GMS). (II), katman fonksiyonları ve iki aşamalı SRU ile NITI sırasıyla yapıyor (GMS, sonra ReLU).
- **Regresyon:**
  - Döngü sırası değişikliği veri sonuçlarını değiştirmedi; ag1'in sonuçları önceki sürümle bayt bayt aynı çıktı, iş başına B değerleri de aynı çoklu küme. Değişen yalnızca sıra.
  - SRU-a3 değişikliğinin etkisi yalnızca Bölüm 10'da anlatılan dosyalarda görüldü.
- **Float kontrolü:** Kararlarla (±127 doyma) FP sapması en çok %3,5 (ag1) ve %4,3 (ag2); kosinüsler en az 0,984 ve 0,967. Sıkı eşiklerle kontrol ediliyor: sapma < %10, kosinüs > 0,95.
- **Yapısal kontroller:** Komut şablonu çalıştırılmadan önce, her iş için aşağıdakiler kontrol ediliyor:
  - kanal çiftinin yalnızca Cin·Cout kez değişmesi
  - her grubun ilk ve son geçişinin doğru işaretlenmesi
  - grup numaralarının sırası
  - tüketicinin grupları aynı sırayla ve aynı koordinatla işlemesi
- **Psum FIFO:** Yorumlayıcı FIFO'dan her okumada başta beklenen (örnek, satır) kısmi toplamının durduğunu kontrol ediyor. Yani yeni döngü sırasında düz bir FIFO yetiyor.
- **Mutasyon testi:** Bilerek sokulan 16 hatanın 16'sı yakalandı. Örnekler:
  - tüketici sırası
  - akümülatör sıfırlama
  - Max Regs'in B saklaması
  - G'nin son gruptan alınması
  - WG hedefi
  - BP s2 geçiş sayısı

**RTL (Icarus Verilog 12):**
- **Testbench:** `SONUC tb_fsm: PASS 6206/6206`. 3 tur, toplam 4633 komut ve 1564 Max Regs olayı.
- **Mutasyon testi:** RTL'e bilerek sokulan 23 hatanın 23'ü yakalandı. İlk turda "CLU'ya yeni s_a" hatası kaçmıştı. Sebebi ag1'de s_a'nın son iki katmanda değişmemesiydi; ag2 bunun için eklendi. Örnekler:
  - döngü sınırları
  - ilk/son bayrakları
  - Ho ve BP s2 geçiş formülleri
  - WG hedefi
  - s_a hesabı
  - iş sırası
  - komutlar arası boşluk
  - B(m)
  - global maksimum
  - Δ
- **`run_sim.tcl`:** Vivado komutlarının sahte karşılıklarıyla ve Icarus ile dört senaryoda denendi:
  - normal çalışma
  - plusarg ayarlanamazsa
  - açık proje varsa
  - yolda boşluk varsa
- **Vivado XSIM (Ömer, 02.11):** `SONUC tb_fsm: PASS 6206/6206 (3 tur: ag1, ag2, ag1; 4633 komut, 1564 Max Regs olayi)`.

**Kapsam dışı (Egemen'in dosyaları gelince):** gerçek PE ve SRU ile entegrasyon (4.5), `kom_bitti`'nin hangi bloktan geleceği (4.0), gerçek CLU golden modeli.
