# Adım 5b-3: 16×16 Dizili Sistemin Tasarımı (tamponlar, ön-getirme, komutlar)

Bu belge, Adım 4'ün tek PE'li sistemini (`rtl/sistem/TASARIM_FSM.md`, `ARAYUZ_SOZLESMESI.md`) Shao Fig. 8'in
tam yapısına taşır. Kararların kaydı `DEVIATIONS.md`'de; burada **önerilen** maddeler (D80–D86) Ego onaylayınca
oraya yazılacak.

Kaynaklar: Shao III-A (s. 256), III-B ve Fig. 6 (s. 257), III-D, Fig. 8 ve Table I (s. 258). NITI bu
bölümdeki kararlarda hakem olamıyor: donanım içermiyor (DEVIATIONS, 5b-3 kararları).

Kesinleşmiş girdiler: D72 (FP/BP satır = çıkış satırı, sütun = çıkış kanalı), D73 (WG satır = giriş kanalı,
sütun = çıkış kanalı, hata sütun hattından), D74 (PE içi Psum FIFO), D75 (DSP), D76 (grup = satırın bir
çevrimlik 16 sütun değeri), D78 (GMS PE'ye giderken), D79 (giriş bankı = satır mod 16).

---

## 1. Fig. 8'den bloklara

| Fig. 8 | Bu tasarımda | Not |
|---|---|---|
| Master Controller | `master_controller` (dizi komutlarıyla yeniden, §7) | Adım 4'ün FSM'i karo döngüleriyle |
| Input Buffer (çok bankalı) | **Veri tamponu**, okuma yüzü (§2) | 16 bank, satır mod 16 (D79) |
| Weight Buffer (çok bankalı) | **Ağırlık tamponu** (§3) | 16 bank, sütun başına |
| Input / Weight Prefetch Module | `on_getirme` (§5) | GMS burada (D78) |
| PE dizisi | `pe_dizi` (5a) | değişmiyor |
| SRU (satır başına) | 16 × LMS + paylaşılan G (§4) | Egemen'in `lms_group16`, `global_max_reducer16` |
| Output Buffer | **Veri tamponu**, yazma yüzü (§2) | SRU i → bank i |
| Function Engine | `fe` (§6): ReLU, ReLU-geri, CLU, WU | Adım 3'ün birimleri |

---

## 2. Veri tamponu (önerilen D80, D81)

**Tek bir çok bankalı tampon, iki yüz.** Aktivasyonlar, hatalar ve gradyanlar bir eğitim adımı boyunca
saklanmalı: BP, AKT[l−1]'i (ReLU maskesi) ve WG, AKT[l−1] ile HATA[l]'yi geri okuyor. Fig. 8'deki giriş ve
çıkış tamponlarını aynı belleğin okuma (ön-getirme) ve yazma (SRU) yüzleri olarak kuruyorum. Ayrı iki
fiziksel tampon, katmanlar arasında bir kopya geçişi gerektirirdi; Shao bu kopyayı yazmıyor. `[Çıkarım]`

**Kelime = bir grup (D76).** Bir kelime, bir konumdaki 16 kanalın int8 değeri + o grubun l'si (6 bit):

```
kelime(bölge, b, karo, satır r, sütun x) = { l[5:0], kanal[karo*16 + 15] ... kanal[karo*16 + 0] }   (134 bit)
bank = r mod 16 (D79)       adres (bank içinde) = bölge tabanı + ((b * n_karo + karo) * ceil(H/16) + r div 16) * W + x
```

Neden böyle:
- SRU satır i'nin grubu tam olarak bir kelime: FP'de (b, r0+i, x) konumundaki 16 kanal, r0 16'nın katı olduğu
  için bank = i. **Her SRU kendi bankasına yazar**, yazmada çakışma yok (BP s2 hariç, §4).
- l kelimenin yanında: Fig. 6'nın Max Regs'i ("local maximum is reserved in a register file") grup başına bir
  değer saklıyor; grup = kelime olunca l'yi kelimenin yanına koymak aynı şey. GMS'te (§5) okunan her kelime
  kendi l'siyle kaydırılır. (D36: Max Regs B saklıyor, l = max(0, B − hedef) ondan türer; kelimede doğrudan l.)
- Katmanın G'si bölge başına bir register'da (ÖLÇEK komutu yazar).
- CLU'nun çıkışı (HATA[L]) SRU'dan geçmiyor (D30): l = 0 ve bölgenin G'si 0 yazılır, Δ = 0.

Bölgeler (bir eğitim adımı): AKT[0..L], HATA[1..L], GRAD[1..L] (WG'nin LMS çıktısı, WU okuyana kadar).
GRAD kelimesi: (c, ki, kj) konumundaki 16 çıkış kanalı (D76), bank = c mod 16 (WG'de satır i = c).

Test ağı boyutu: ag2'de en büyük bölge 3 örnek × 1 karo × 5 satır × 5 sütun; bütün adım birkaç yüz kelime.

---

## 3. Ağırlık tamponu (önerilen D82)

16 bank, **bank j = o mod 16**. Kelime = w[o][c] (9 × int8). Adres = katman tabanı + (o div 16) * Cin + c.

| Faz | Sütun j'nin istediği | Okuma |
|---|---|---|
| FP | w[o0 + j][c] | 16 bank paralel, 1 çevrim |
| BP | dondur_180(w[o][c0 + j]) | hepsi bank (o mod 16)'da: 16 çevrim |
| WG | (ağırlık yok; sütun hattı hatayı taşır, D73) | — |
| WU | w[o0 + j][c][ki][kj] yaz | 16 bank paralel |

BP'de 16 çevrimlik yükleme: ağırlıklar bir geçiş boyunca sabit (III-A-1), geçiş ≥ W + 3 çevrim; yükleme bir
önceki geçişin akışıyla örtüşebilir ama ilk sürümde örtüştürmüyorum. `[Çıkarım]`

---

## 4. SRU tarafı: LMS doğrudan veri tamponuna (önerilen D83)

D78 ile GMS, PE'ye giderken yapılıyor. Bu yüzden Egemen'in `sru_channel`'ındaki 64 gruplu GMS tamponu tam
sistemde **kullanılmıyor**; yerine Fig. 6'nın iki yarısı ayrı yerlerde:
- Satır sonunda (Fig. 8'in SRU'ları): `grup_kurucu` (5b-2, yalnızca seçim kısmı) → `lms_group16` → (FP'de ReLU,
  BP'de ReLU-geri, §6) → veri tamponuna kelime + l; B → `global_max_reducer16` (paylaşılan G).
- Ön-getirmede: `gms_group16` (Δ = G − l), §5.

Shao'da bir gerilim var, not ediyorum: III-B "Both two stages of the scheme are implemented by this unit"
(aynı SRU), ama Fig. 8'de tampondan PE'ye giden yolda SRU yok. Egemen'in SRU'su zaten LMS ve GMS'i ayrı alt
modüllerle yapıyor; GMS alt modülünü ön-getirmeye koymak iki şekli de kısmen karşılıyor. `[Çıkarım]`

`grup_kurucu`'nun son-grup bekletmesi (D77) `sru_channel` içindi; tam sistemde gerekmiyor (LMS her grubu
anında yazıyor). D77 bileşen testi olarak geçerli kalır.

**BP s2'de yazma çakışması:** PE satırı i, p = p0 + i geçişinin dX satırlarını (2p, 2p+1) − dolgu üretiyor;
bunlar bank i'ye değil (2i + δ − dolgu) mod 16'ya düşüyor, i ve i + 8 aynı bankı istiyor. Bir şerit adımında
satırları iki yarıda (i < 8, i ≥ 8) yazarak çözüyorum (en çok 2 çevrim). Test ağlarında en çok 4 BP s2 geçişi
var, çakışma oluşmuyor ama mantık genel. `[Çıkarım]`

---

## 5. Ön-getirme (önerilen D84)

Bir geçişin başında, PE satırlarının ihtiyaç duyduğu giriş satırları yerel **satır register'larına**
yüklenir (pe_motoru'nun 3 satırlık `rb`'sinin 16 satırlık hâli). Yükleme sırasında her kelime **GMS'ten**
geçer (`gms_group16`, kelimenin l'si ve bölgenin G'siyle), sonra istenen kanalın baytı alınır.

| Faz | PE satırı i'nin akışları | Okunan kelimeler | Yükleme |
|---|---|---|---|
| FP s1 | girdi satırları r+0..2 (r = r0 + i), kanal c | (b, kanal karosu, satır, x), x = 0..W−1 | 18 satır, banklar paralel: W çevrim × 2 |
| FP s2 | satırlar 2r+0..2, çift/tek ayrık (Fig. 3b) | aynı | 33 satır: W × 3 |
| BP s1 | hata satırları m+0..2 (dolgu 2 − p), kanal o | HATA[l] kelimeleri | 18 satır |
| BP s2 | hata satırları p, p, p−1 (sıfır ekli, Fig. 4b) | HATA[l] | 17 satır |
| WG | aktivasyon satırları s·r+0..2, kanal c0 + i (satıra göre farklı kanal!) | bir kelime 16 kanalı birden verir: **bir okuma 16 PE satırının hepsini besler** | 3 satır × W |
| WG (sütun) | hata satırı r, kanal o0 + j | HATA[l] kelimesi 16 sütunu birden besler | W |

- Dolgu, çift/tek ayırma ve BP s2 sıfır ekleme satır register'larından akışa geçerken yapılır (pe_motoru'nun
  D66'daki zamanlamasıyla aynı: akışın t. çevriminde golden'ın t. çevrim girişi).
- Satır register'ı genişliği: W + 2·dolgu ≤ 18 (test ağları W ≤ 16). Daha geniş haritalar sütun karosu
  gerektirir; kapsam dışı (Shao da yazmıyor).
- GMS birimleri: bank başına bir `gms_group16` (16 adet). Bir kelime okunduğunda 16 kanalın hepsi kaydırılır.

---

## 6. Fonksiyon motoru

- **ReLU (FP):** LMS çıkışında, yazmadan önce (D53: GMS ile sıra sonucu değiştirmiyor).
- **ReLU-geri (BP):** LMS çıkışında; maske = AKT[l−1]'in aynı kelimesi **GMS'ten geçmiş hâliyle** (GMS
  küçük pozitif bir aktivasyonu 0'a yuvarlayabilir, maske değişir). Maske okuması grubun yazıldığı çevrimde
  aynı bankın okuma portundan.
- **CLU:** AKT[L] kelimesi (10 kanal, GMS'li) → CLU → HATA[L] kelimesi (l = 0).
- **WU (WG işinin ÖLÇEK'inden sonra):** GRAD kelimesi + l → GMS (hedef m_u) → w − g (D41) → ağırlık tamponuna
  16 bank paralel. Kelime başına 1 çevrim; bir katmanın WU'su Cin × 9 × ceil(Cout/16) kelime.

---

## 7. Komut seti ve FSM döngüleri (önerilen D85)

Adım 4'ün 10 alanlı biçimi korunuyor (`op faz katman b x y z a1 a2 a3`). KOPYA kalkıyor (D78).

| op | Ad | Alanlar |
|---|---|---|
| 8 | İŞ_BAŞLA | faz, l, x = hedef; G toplayıcıyı ve Psum FIFO'ları sıfırlar |
| 1 | DİZİ (geçiş) | faz, l, b, x = k0 karosu, y = k1 kanalı/akım, z = satır karosu, a1 = ilk, a2 = son |
| 2 | ÖLÇEK | faz, l: G ← paylaşılan toplayıcı, bölgenin G register'ına |
| 4 | SA | l, x = s_a |
| 5 | CLU | b, x = s_a |
| 6 | WU | l, x = o karosu, y = c (bir komut 9 kelime) |
| 7 | BİTTİ | — |

Döngüler (D47'nin dizi hâli; test ağlarında bütün karolar tek):
- FP: o karosu → c → b → r karosu (ilk = c == 0, son = c == Cin − 1)
- BP: c karosu → o → b → m (s1) / p (s2) karosu
- WG: c karosu → o karosu → b → r (ilk = b, r ilk; son = b, r son)

`master_controller.v` bu döngülerle yeniden yazılacak; golden (`dizi_golden.py`) komut listesini üretip
FSM'i satır satır denetleyecek (Adım 4'teki `tb_fsm` gibi).

---

## 8. Doğrulama planı (paketler)

| Paket | İş | Golden'a karşı | Tahmin |
|---|---|---|---|
| 3a | `dizi_golden.py`: komut listesi, veri/ağırlık tamponlarının başlangıç ve beklenen son hâli (bu düzende), geçiş izleri | (I') = (II') korunuyor | ~3 saat |
| 3b | Veri + ağırlık tamponu RTL, ön-getirme (GMS'li), birim testleri | geçiş izlerinin akışları | ~5 saat |
| 3c | Dizi motoru: tampon → ön-getirme → `pe_dizi` → grup → LMS → yazma; `tb_dizi_motoru` | geçiş izleri + yazılan kelimeler | ~5 saat |
| 3d | FSM (dizi komutları) + `tb_fsm_dizi` | `komutlar.txt` | ~3 saat |
| 3e | Fonksiyon motoru bağlantıları (ReLU-geri maskesi, CLU, WU) + tam sistem `tb_sistem_dizi` | son tampon hâlleri, s_a | ~4 saat |

Toplam ~2,5 gün (benim yazma + XSIM süresi; senin Vivado koşuların hariç).

---

## 9. Önerilen yeni kararlar (Ego onaylarsa DEVIATIONS'a)

| No | Karar | Kanıt |
|---|---|---|
| D80 | Giriş ve çıkış tamponu aynı çok bankalı veri tamponunun iki yüzü; bölgeler AKT/HATA/GRAD | `[Çıkarım]` (Fig. 8 iki ayrı kutu çiziyor; aradaki kopyayı Shao yazmıyor) |
| D81 | Kelime = grup (16 kanal, bir konum) + l; bank = satır mod 16; SRU i → bank i | D76, D79, Fig. 6 Max Regs; `[Çıkarım]` |
| D82 | Ağırlık bankı = o mod 16; BP'de 16 çevrimlik yükleme | III-D "bank per column"; `[Çıkarım]` |
| D83 | Tam sistemde `sru_channel`'ın GMS tamponu kullanılmaz; LMS doğrudan tampona, GMS ön-getirmede; BP s2 yazma çakışması iki yarıda | III-B, Fig. 6, D78; `[Çıkarım]` |
| D84 | Ön-getirmede satır register'ları + bank başına `gms_group16`; W + 2p ≤ 18 | III-A (ön-getirme), Fig. 3b/4b/5b; `[Çıkarım]` |
| D85 | Komut seti: KOPYA yok, DİZİ geçiş komutu, karo döngüleri | D47, D78; `[Çıkarım]` |
| D86 | ReLU-geri maskesi GMS'li aktivasyondan | D53'ün maske tarafı; `[Ölçülecek]` golden'da |

## 10. Açık sorular

1. **Fig. 6 / Fig. 8 gerilimi (§4):** GMS'i SRU'nun bir parçası sayıp ön-getirmeye koymak yorum. Tezde
   açıkça yazılmalı.
2. **Sütun karosu:** W > 16 haritalar için satır register'ı yetmez. Test ağı ve Shao'nun CIFAR-10 ağı
   (32×32) için 32'ye çıkarmak gerekir mi? Şimdilik parametre, test ağında 18.
3. **Tampon boyutu:** Shao 896 BRAM (Table I). Bizim test ağı için birkaç yüz kelime; BRAM'e eşleme sentezde
   kontrol edilecek.
