# Sonuçlar: Shao (ISVLSI 2021) çıktılarının yeniden üretimi — TASLAK (06.11.2026)

Hedef (Ego, 06.11): Shao'nun kurduğu sistemi birebir gerçekleyip makalenin üç çıktısına (Table I, Table II, Fig. 9) en
yakın sonucu almak; NITI yalnızca Shao'nun sessiz kaldığı yerde hakem. Kararların kaydı: `DEVIATIONS.md` (D1–D108).
Etiketler: `[Ölçüldü]` araçla ölçülen sayı; `[Çıkarım]` makalede yazmayan, bizim yorumumuz; `[Bekliyor]` henüz yok.

## 1. Table I — VC709 (XC7VX690T) kaynak kullanımı

| Kaynak | Shao | Bizim | Not |
|---|---|---|---|
| LUT | 171.248 (%39,5) | 436.340 (%100,7) | `[Ölçüldü]` zamanlamaya duyarlı sentez, `flatten none`, D107 dahil: pe_dizi 148.214 + sistem 288.126 (hızlı sentezde 274.397; toplam 422.611, %97,6) |
| LUTRAM | 24.704 | 45.174 | `[Ölçüldü]` pe_dizi 44.032 (256 PE'nin Psum FIFO'ları) + sistem 1.142 |
| FF | 143.565 | 68.368 | `[Ölçüldü]` pe_dizi 40.192 + sistem 28.176 |
| BRAM (RAMB36) | 896 | 824 | `[Ölçüldü]`; tampon boyu Shao'da yok, Table I'e yakın seçildi (D103, `[Çıkarım]`) |
| DSP | 2.324 | 2.354 | `[Ölçüldü]` 2304 MAC (D105, DSP48E1'de) + 50 (SRU/CLU) |

- Sentez sonrası rapor; place & route yapılmadı (LUT %100,7: tasarım VC709'a sığmıyor; yerleştirme için ~%85 gerekir).
- LUT farkının büyük kalemleri (D103–D106 ölçümü): 16 LMS ≈ 97k, ön-getirme + 16 GMS 86k, motor 68k. Shao'nun
  bu bloklar için ayrıntı vermemesi yüzünden farkın tam nedeni bilinmiyor `[Çıkarım]`.

## 2. Table II — 200 MHz'de başarım, güç, verim

| | Shao | Bizim | Not |
|---|---|---|---|
| Frekans | 200 MHz | WNS −11,85 ns @ 5 ns → ~59 MHz | `[Ölçüldü]` sentez sonrası tahmin (D107 öncesi −12,23). pe_dizi tek başına +1,0 ns (200 MHz tutuyor) |
| Tepe | — (yazılmamış) | 921,6 GOPS | 2304 MAC × 2 × 200 MHz |
| Başarım | 771 GOPS | 54,4 GOPS (etkin, VGG16-like, batch 256) | `[Ölçüldü]` model, RTL'e komut komut eşit (D108) |
| Güç | 16,27 W | 24,3 W | `[Ölçüldü]` sentez sonrası vektörsüz `report_power` @ 200 MHz (güven "Medium"): dinamik pe_dizi 9,03 + sistem 14,64, statik 0,62 (bir kez) |
| Verim | 47,38 GOPS/W | 2,24 GOPS/W (tepe ile 37,9) | etkin GOPS / güç |

- 200 MHz: D107 motordaki yolu kırdı; en kötü yol artık CLU'da: `u_fe/a_r` → bölücü IP'sinin girişi, 68 seviye
  (46 CARRY4). Shao CLU için "multi-stage pipelines" eklediğini yazıyor (CLU bölümü, s. 5); bizim CLU'da bu yolda register yok.
  Sınırlama olarak yazıldı, değiştirilmedi (durdurma kuralı).
- Güç: sentez sonrası ve gerçek anahtarlama verisi olmadan; tasarım 200 MHz'i tutmadığı halde 200 MHz'de hesaplandı
  (Shao'yla aynı frekansta kıyas için). Shao ölçüm mü tahmin mi yazmıyor.

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
5. ~~Gerçek bölücü IP'siyle sistem koşusu~~ kapandı: Ego, 07.11, Vivado'da `dizi/run_sim.tcl`, gerçek IP'yle altı test
   PASS (`tb_sistem_dizi` 65.142/65.142, 419.000 çevrim; CLI'daki davranışsal modelle aynı sayılar).

## 5. Ego için: neyi kendin biliyorsun, ne Claude'dan geldi
- **Senin işin / bizzat doğrulanabilir:** PE ve SRU modülleri (Egemen'in testleri), Vivado'daki run_sim koşuları,
  makale okuması (Fig. 2, 3–6, 8, Table I/II).
- **Claude'dan gelen, sunmadan önce kendin kontrol et:** D72–D108 kararlarının çoğu (dizi eşlemesi, tampon düzeni,
  donanımlaştırma, D101/D102 eğitim kararları), GOPS modeli (D108) ve "771 = tepenin %83,7'si" yorumu, Fig. 9
  farkının yorumu. Danışmana sunarken bunların hangisinin makaleden, hangisinin bizim çıkarımımız olduğunu söyle.
