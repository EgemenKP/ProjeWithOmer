# PE Golden Model — Testbench Kullanım Notu

> **Hazırlayan:** Claude (Ömer'in isteğiyle), 28.10.2026
>
> **Kaynak:** Shao vd., ISVLSI 2021, Bölüm III-A ve Fig. 2–5 (s. 256–257)
>
> **Durum:** Python'da doğrulandı (Bölüm 8). Verilog/XSIM testbench'iyle **henüz denenmedi**.

## 0. İlk iş: arayüzü karşılaştır

- Makaledeki PE'de **9 MAC (3×3)** var. Her MAC'in içinde 1 mux bulunuyor; sağda satır çıkışlarını toplayan toplayıcılar ve bir **Psum FIFO** var. `TASKS.md`'deki "3 MAC, 4 mux, Psum regfile" tanımı yanlıştı. Taslak ona göre yazıldıysa önce burayı karşılaştırın.
- Vektörler PE'nin girişlerini **akış (stream)** olarak verir. Ön-getirme (prefetch) modülünün işi olan dolgu, çift/tek ayırma ve sıfır ekleme zaten yapılmış durumda. Yani bu vektörler yalnızca PE'yi test eder.

## 1. Dosyalar

| Dosya | İçerik |
|---|---|
| `pe_golden.py` | Model ve vektör üreteci. `python3 pe_golden.py` ile vektörleri yeniden üretir; ek kütüphane gerekmez. |
| `pe_vektorleri/pe_<mod>.txt` | Testbench vektörleri: `pe_fp_s1.txt`, `pe_fp_s2.txt`, `pe_bp_s1.txt`, `pe_bp_s2.txt`, `pe_wg_s1.txt`, `pe_wg_s2.txt` |
| `pe_vektorleri/OKUNUR_case0.txt` | Her modun el kontrolü case'i, çevrim çevrim tablo hâlinde (dalga formuyla karşılaştırmak için) |
| `pe_vektorleri/CASE_LISTESI.txt` | Tüm case'lerin açıklaması (boyut, kanal sayısı, uç değerler) |

## 2. Modelin varsaydığı donanım

- **Kısmi toplam zinciri (Fig. 3a):** mux → (+) → D → (+) → D → (+) → D. Her çevrimde bir basamağın yeni değeri = önceki basamağın **eski** register değeri + ağırlık × giriş.
- **Satırları toplayan sağdaki toplayıcılar** kombinasyonel kabul edildi, yani register yok. [Varsayım PE-a3]
- **Psum FIFO'dan gelen kısmi toplam** zincirin başındaki mux'tan girer. FP/BP s1–s2'de bu satır 0'ın mux'u; BP s2'de satır 0 ve 1'in A ve B zincirlerinin mux'ları. [Varsayım PE-a2]
- **Zamanlama:** t. çevrimde girişler uygulanır, çevrim sonundaki saat kenarında register'lar güncellenir. Dosyadaki çıkış, bu kenardan sonraki değerdir; buna "figür çevrimi" t diyoruz.

## 3. Modlar

| Mod (kod) | Çevrim başına giriş şeritleri | Çıkış şeritleri | Geçerli çıktılar | MAC[r][c]'ye yüklenen ağırlık |
|---|---|---|---|---|
| FP_S1 (0) | x_r0, x_r1, x_r2, psum | out | t = 2 … T−1 | W[r][c] |
| FP_S2 (1) | cift_r0, tek_r0, cift_r1, tek_r1, cift_r2, tek_r2, psum | out | t = 2 … T−1 | W[r][c] |
| BP_S1 (2) | e_r0, e_r1, e_r2, psum | out | t = 2 … T−1 | W[2−r][2−c] (180° döndürülmüş) |
| BP_S2 (3) | e_r0, e_r1, e_r2, psA0, psB0, psA1, psB1 | out0, out1, out2, out3 | t = 1 … T−1 | satır r: [W[r][2], W[r][0], W[r][1]] |
| WG_S1 (4) | a_r0, e_r0, a_r1, e_r1, a_r2, e_r2 | yok (case sonunda 9 akümülatör) | — | yok |
| WG_S2 (5) | cift_r0, tek_r0, e_r0, cift_r1, tek_r1, e_r1, cift_r2, tek_r2, e_r2 | yok (case sonunda 9 akümülatör) | — | yok |

**FP_S1 ve BP_S1:** x_r (BP'de e_r) satır r'deki 3 MAC'e yayınlanır (broadcast). Çıkış = satır 0 zinciri + satır 1 zinciri + satır 2 zinciri. psum, satır 0'ın zincirine girer.

**FP_S2:** MAC[r][0] çift akışı, MAC[r][1] tek akışı alır. MAC[r][2] ise çift akışı 1 çevrim geciktiren bir D register'ından alır (Fig. 3b'deki mavi D).

**BP_S2:** Her satırda iki zincir var ve ikisine de aynı e_r akışı girer:
- A zinciri: MAC[r][0] → MAC[r][1] (2 basamak)
- B zinciri: MAC[r][2] (1 basamak)

Çıkışlar:
- out0 = A(satır 0) + A(satır 2)
- out1 = B(satır 0) + B(satır 2)
- out2 = A(satır 1)
- out3 = B(satır 1)

psA0 ve psB0 satır 0'ın A ve B mux'larına, psA1 ve psB1 satır 1'inkilere girer. Satır 2'nin zincirlerine psum girmez.

**WG_S1 ve WG_S2:** MAC[r][c] kendi akümülatöründe a × e biriktirir (çıktı-durağan). Hata akışı satırdaki bir D zincirinden geçer: MAC[r][0] e'yi aynı çevrimde, MAC[r][1] 1 çevrim, MAC[r][2] 2 çevrim gecikmeli görür. WG_S2'de aktivasyon tarafı FP_S2 gibidir: MAC[r][0] çift, MAC[r][1] tek, MAC[r][2] gecikmeli çift akışı alır. Akümülatörler case başında sıfırlanır, case sonunda okunur.

**psum zamanlaması:**
- FP/BP s1–s2: j. çıktının psum'ı j. çevrimde verilir (son 2 çevrimde 0).
- BP_S2: q. sütun çiftinin psum'ı A şeritlerinde (psA0, psA1) q. çevrimde, B şeritlerinde (psB0, psB1) (q+1). çevrimde verilir.
- İlk kanalın geçişlerinde psum her zaman 0.

## 4. Dosya biçimi

Dosyada yalnızca tamsayılar var. Boşluk ve satır sonu fark etmez; SystemVerilog'da `$fscanf(fd, "%d", x)` ile sırayla okunabilir. Değerler ondalık ve işaretli.

```
MOD_KODU  CASE_SAYISI
  her case : CASE_NO  GECIS_SAYISI  KANAL_SAYISI
  her geçiş: GECIS_NO  T  N_CIKTI  N_GIRIS  N_CIKIS
             9 ağırlık: MAC[0][0] MAC[0][1] ... MAC[2][2]   (WG'de 9 sıfır)
             T satır, her biri N_GIRIS sayı                 (Bölüm 3'teki şerit sırasıyla)
             N_CIKTI satır, her biri: FIGUR_CEVRIMI + N_CIKIS sayı (beklenen çıkışlar)
  WG'de case sonunda: 9 beklenen akümülatör G[0][0] ... G[2][2]
```

`pe_fp_s1.txt`'nin başı (case 0), açıklamalı:

```
0 8            <- mod FP_S1, 8 case
0 1 1          <- case 0: 1 geçiş, 1 kanal
0 5 3 4 1      <- geçiş 0: T=5 çevrim, 3 çıktı, 4 giriş şeridi, 1 çıkış şeridi
1 2 3 4 5 6 7 8 9   <- MAC ağırlıkları
0 1 2 0        <- t=0: x_r0 x_r1 x_r2 psum
1 2 3 0        <- t=1
2 3 4 0        <- t=2
3 4 0 0        <- t=3
4 0 1 0        <- t=4
2 114          <- figür çevrimi 2'de beklenen out = 114
3 114
4 89
```

Elle kontrol: 114 = (1·0 + 2·1 + 3·2) + (4·1 + 5·2 + 6·3) + (7·2 + 8·3 + 9·4) = 8 + 32 + 74.

## 5. Testbench önerisi

1. Her geçişin başında 9 ağırlığı yükle. WG'de case başında akümülatörleri sıfırla.
2. T çevrim boyunca giriş şeritlerini sür.
3. Geçerli çıkışları **sırayla** topla ve dosyadaki beklenen değerlerle karşılaştır. Tasarımında figürdekinden fazla register varsa gecikme farklı olur; o yüzden çevrim numarasıyla değil sırayla karşılaştır. Gecikmen figürle aynıysa FIGUR_CEVRIMI ile birebir de karşılaştırabilirsin.
4. Geçişleri arka arkaya, boşluksuz verebilirsin; geçiş başında ağırlıkları değiştirmek de sorun değil:
   - FP/BP'de geçerli çıkışlar zincirde önceki geçişten kalan değerlere bağlı değil (Bölüm 8). Geçişin ilk çevrimlerindeki geçersiz çıkışlar o kalıntıları gösterebilir; onlar karşılaştırılmaz.
   - WG'de akışların sonundaki sıfırlar hata zincirini boşaltıyor; bir sonraki geçiş temiz başlıyor. Bu yüzden WG akışlarındaki sondaki sıfırları atlama.
5. WG'de case sonunda 9 akümülatörü G00 … G22 sırasıyla oku ve karşılaştır.
6. Çıkışlar ve kısmi toplamlar int32. Girişler int8; birkaç case'te ilk katmanı temsil eden −128 aktivasyon var (`CASE_LISTESI.txt`).

## 6. Katman düzeyi: geçişler nasıl kuruldu (ön-getirme ne yapmalı)

Üreteç her case'i küçük bir katman olarak kurdu ve PE'nin sonucunu matematik referansıyla karşılaştırdı. Ön-getirme ve kontrolcüyü yazarken aynı sırayı kullanabilirsiniz.

- **FP:** Kanal dışta, çıktı satırı içte (ağırlıklar kanal bitene kadar sabit; III-A-1). i. geçişte satır r ← Xp[s·i + r]. k. kanaldaki i. satırın çıktısı FIFO'ya yazılır, (k+1). kanalın i. geçişinde psum olarak geri gelir. Son kanalın çıktısı nihai sonuçtur.
- **Stride 2'de çift/tek ayırma:** cift = x0, x2, x4, … ve sonuna 1 boşaltma sıfırı; tek = 0, x1, x3, … ve çift akışla aynı uzunluğa sıfırla tamamlanır.
- **BP_S1:** Hata haritası (2 − dolgu) kat sıfırla dolgulanır. m. geçişte satır r ← Ep[m + r]; MAC'lere 180° döndürülmüş çekirdek yüklenir.
- **BP_S2:** p = 0 … He için: satır 0 ve 1 ← [0] + E[p] + [0], satır 2 ← [0] + E[p−1] + [0]. Sınırlarda E[−1] ve E[He] sıfır satırdır. Çıkış koordinatları dolguya bağlı:
  - dolgu 0: out0 → dX[2p][2q], out1 → dX[2p][2q+1], out2 → dX[2p+1][2q], out3 → dX[2p+1][2q+1]
  - dolgu 1: aynı eşleme, her iki koordinattan 1 çıkarılmış hâli (dX[m][n] = dx0[m+1][n+1])
  - Yani hangi şeridin "çift" grup olduğu ileri geçişteki dolguya bağlı (PE-a5).
- **WG:** i. geçişte satır r ← Ap[s·i + r]; üç satırın hepsine aynı E[i] satırı gider, sonuna boşaltma sıfırları eklenir. Batch örnekleri arka arkaya verilir; akümülatör aralarda sıfırlanmaz.

## 7. Varsayımlar (D adayları)

Makale bu noktaları yazmıyor; model aşağıdaki seçimleri yaptı. Senin taslağında farklıysa vektörler değil yorum farklıdır: ikiniz karar verip D-numarasıyla `DEVIATIONS.md`'ye yazın.

| Kod | Modelin seçimi | Senin taslağında farklıysa |
|---|---|---|
| PE-a2 | psum zincirin başındaki mux'tan girer | psum'ı çıkıştaki toplayıcıda ekliyorsan psum şeridini yok say; çıktı = psum + PE sonucu olarak kontrol et |
| PE-a3 | Satır toplayıcısı kombinasyonel; geçerlilik FP/BP s1–s2'de t ≥ 2, BP_S2'de t ≥ 1; stride 2'de 1 boşaltma çevrimi | Gecikme farklıysa sırayla karşılaştır (Bölüm 5) |
| PE-a5 | BP_S2 şerit → koordinat eşlemesi dolguya bağlı (Bölüm 6) | PE düzeyindeki testi etkilemez |
| PE-a6 | BP_S2: satır 0 ve 1'e E[p], satır 2'ye E[p−1] (Fig. 4b'de e1x, e1x, e0x) | Ön-getirme tarafının kararı |
| PE-a7 | WG: r. satıra A[s·i + r], hepsine aynı E[i] | Stride 1 için diğer geçerli seçenek: hepsine aynı A[i], r. satıra E[i−r]. PE'nin davranışı ikisinde de aynı; yalnızca ön-getirme değişir |
| BP_S1 döndürme | Vektörde MAC'e yüklenen (döndürülmüş) ağırlık var | Döndürmeyi PE içinde yapıyorsan orijinal = 180° döndürülmüş yüklü ağırlık |
| BP_S2 yükleme | Satır r: [W[r][2], W[r][0], W[r][1]] (Fig. 4b) | Orijinal: W[r][0] = yüklü[r][1], W[r][1] = yüklü[r][2], W[r][2] = yüklü[r][0] |
| FIFO sırası | Kanal dışta, satır içte | Makaleye dayanıyor [PDF tam: III-A-1] |

**Kapsam dışı:** FC katmanları, SRU (çıkışlar SRU'dan önceki int32 değerler) ve 16×16 dizi.

## 8. Doğrulama durumu

- **Matematik referansı:** 300 rastgele eşlenik (adjoint) testinde ⟨FP(X), E⟩ = ⟨X, BP(E)⟩ = ⟨W, WG(X, E)⟩ tuttu. Bu, BP'deki döndürme/dolgunun ve WG'deki indislerin doğru olduğunu gösterir.
- **Her vektör case'i:** PE çevrim modeli = matematik referansı (birebir).
- **Dosya geri okuma:** Her dosya geri okundu ve model dosyadaki akışlarla yeniden çalıştırıldı; 1071 beklenen değerin hepsi tuttu.
- **Stres testi:** Her moddan 200 ek rastgele durum, hepsi referansla aynı.
- **Kesintisiz akış testi:** FP/BP'nin 128 geçişinin her biri, önüne rastgele değerli çevrimler eklenip register'lar rastgele bir durumdan başlatıldığında da aynı geçerli çıkışları verdi. Ağırlıkları geçişler boyunca aynı kalan 29 case, tüm geçişleri tek kesintisiz akış olarak verildiğinde de tuttu.
- **Mutasyon testi:** Modele bilerek sokulan 8 hatanın 8'i de yakalandı (satır toplamı eksik, psum zamanı kaymış, BP_S2 ağırlık sırası yanlış, WG gecikmesi eksik, boşaltma sıfırı yok, BP_S2 B şeridi zamanı, stride 2 gecikmeli D yok, BP_S1 döndürme yok).
- **Verilog ile test edilmedi.** İlk XSIM koşusunda çıkan bir fark ya RTL hatasıdır ya da Bölüm 7'deki seçimlerden biri sende farklıdır.
