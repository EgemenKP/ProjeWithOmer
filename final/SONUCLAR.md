# Sonuçlar: Shao (ISVLSI 2021) çıktılarının yeniden üretimi — TASLAK (06.11.2026)

Hedef (Ego, 06.11): Shao'nun kurduğu sistemi birebir gerçekleyip makalenin üç çıktısına (Table I, Table II, Fig. 9) en
yakın sonucu almak; NITI yalnızca Shao'nun sessiz kaldığı yerde hakem. Kararların kaydı: `DEVIATIONS.md` (D1–D108).
Etiketler: `[Ölçüldü]` araçla ölçülen sayı; `[Çıkarım]` makalede yazmayan, bizim yorumumuz; `[Bekliyor]` henüz yok.

## 1. Table I — VC709 (XC7VX690T) kaynak kullanımı

| Kaynak | Shao | Bizim | Not |
|---|---|---|---|
| LUT | 171.248 (%39,5) | 422.611 (%97,6) | `[Ölçüldü]` sentez, `flatten none`; pe_dizi 148.214 + sistem 274.397 (D103–D106 sonrası) |
| LUTRAM | 24.704 | 45.182 | `[Ölçüldü]` pe_dizi 44.032 (256 PE'nin Psum FIFO'ları) + sistem 1.150 |
| FF | 143.565 | 68.234 | `[Ölçüldü]` pe_dizi 40.192 + sistem 28.042 (D107'nin ~100 FF'i hariç) |
| BRAM (RAMB36) | 896 | 824 | `[Ölçüldü]`; tampon boyu Shao'da yok, Table I'e yakın seçildi (D103, `[Çıkarım]`) |
| DSP | 2.324 | 2.359 | `[Ölçüldü]` 2304 MAC (D105, DSP48E1'de) + 55 (SRU/CLU) |

- Sentez sonrası rapor; place & route yapılmadı (Kapı B: LUT %97,6 yerleştirmeye uygun değil, ~%85 gerekir).
- LUT farkının büyük kalemleri (D103–D106 ölçümü): 16 LMS ≈ 97k, ön-getirme + 16 GMS 86k, motor 68k. Shao'nun
  bu bloklar için ayrıntı vermemesi yüzünden farkın tam nedeni bilinmiyor `[Çıkarım]`.

## 2. Table II — 200 MHz'de başarım, güç, verim

| | Shao | Bizim | Not |
|---|---|---|---|
| Frekans | 200 MHz | WNS −12,2 ns @ 5 ns (D107 öncesi) | `[Ölçüldü]`; D107 sonrası `[Bekliyor]` |
| Tepe | — (yazılmamış) | 921,6 GOPS | 2304 MAC × 2 × 200 MHz |
| Başarım | 771 GOPS | 54,4 GOPS (etkin, VGG16-like, batch 256) | `[Ölçüldü]` model, RTL'e komut komut eşit (D108) |
| Güç | 16,27 W | — | `[Bekliyor]` sentez sonrası `report_power` (vektörsüz tahmin) |
| Verim | 47,38 GOPS/W | — | `[Bekliyor]` |

- Shao GOPS'un hesabını yazmıyor; 771, tepenin %83,7'si `[Çıkarım]`.
- Bizim etkin GOPS'un düşük olma nedeni (D108): çevrimlerin %80'i yükleme ve komut başı/sonu (komutlar sırayla,
  D50; yükleme akışla örtüşmüyor), akış sırasında MAC kullanımı %29,5 (derin katmanlarda 4×4 / 2×2 haritalar 16
  satırı doldurmuyor). Yükleme tam örtüşseydi üst sınır 272 GOPS. Harici bellek modellenmedi (veri çip üstünde varsayıldı).

## 3. Fig. 9 — CIFAR-10 top-1 test hatası

| | Shao (şekilden okunmuş, yaklaşık) | Bizim |
|---|---|---|
| VGG16-like, 30. epoch | ~%20 | %77,1 (test doğruluğu %22,92) `[Ölçüldü]` |
| VGG16-like, 200. epoch | ~%12 | %78,4 (test doğruluğu %21,63; 30. epoch'tan beri %20–25 bandında, m_u 2 → 1) `[Ölçüldü]` |
| VGG16 (max-pool'lu), 200. epoch | ~%12–13 | koşulmadı (Ego kararı, 06.11: yalnızca kıyas eğrisi, D102'deki ezberleme testinde aynı derinlikte o da öğrenmedi) |

- Aritmetik çerçeve (hizli_model = golden = RTL, bit bit) NITI'nin kendi ağında doğrulandı: vggsmall7, 30 epoch test
  %76,45 (eşik %70; NITI'nin 200 epoch sonucu %90,7) `[Ölçüldü]`.
- VGG16-like'ın ~%25 doğrulukta kalması çerçevedeki bir hatadan değil, 14 katmanlı BN'siz ağın bu ayarlarla
  eğitilmesinden `[Çıkarım, D102]`. Shao'nun bu ağı nasıl eğittiği (m_u takvimi, başlatma, öğrenme ayarları) metinde yok.
- Ağın sonu: son max-pool + FC, Shao'nun kuralıyla tek s2 conv (D101) `[Çıkarım]`.

## 4. Bilinen sınırlamalar
1. Yerleştirme (place & route) yok; Table I sentez sonrası.
2. Pooling birimi yok (D39); VGG16 referansı yalnızca yazılımda (hizli_model'in maxpool/FC yolu).
3. Harici bellek / DDR yok; VGG ölçeği veri çip üstüne sığmaz (D103).
4. Komutlar sırayla, yükleme ile hesap örtüşmüyor (D50) → etkin GOPS düşük (D108).
5. Gerçek bölücü IP'siyle sistem koşusu Ego'da (bütün CLI koşuları davranışsal modelle).

## 5. Ego için: neyi kendin biliyorsun, ne Claude'dan geldi
- **Senin işin / bizzat doğrulanabilir:** PE ve SRU modülleri (Egemen'in testleri), Vivado'daki run_sim koşuları,
  makale okuması (Fig. 2, 3–6, 8, Table I/II).
- **Claude'dan gelen, sunmadan önce kendin kontrol et:** D72–D108 kararlarının çoğu (dizi eşlemesi, tampon düzeni,
  donanımlaştırma, D101/D102 eğitim kararları), GOPS modeli (D108) ve "771 = tepenin %83,7'si" yorumu, Fig. 9
  farkının yorumu. Danışmana sunarken bunların hangisinin makaleden, hangisinin bizim çıkarımımız olduğunu söyle.
