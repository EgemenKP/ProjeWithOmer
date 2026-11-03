# CLU Çıkışı İçin Stokastik Yuvarlama (D8 = c)

> **Hazırlayan:** Claude (Ömer'in isteğiyle), 02.11.2026
>
> **Güncelleme (03.11.2026):** Ömer D8 için şimdilik (a)'yı seçti (en yakına yuvarlama; Egemen'in CLU'su böyle). Bu birim **kullanılmıyor**, gerekirse diye hazır duruyor (karar dosyası D60).
>
> **Durum:** Golden model ve RTL, Icarus Verilog'da ve Vivado XSIM'de PASS (Vivado: Ömer, 02.11, 40960/40960). Egemen'in CLU'suna henüz bağlanmadı (dosyaları bekleniyor).

## Ne yapıyor

CLU'nun son adımında (D5) yaklaşık ±2048 aralığındaki e_i değeri 4 bit sağa kaydırılıp int8'e indiriliyor. Bu birim o kaydırmayı NITI'deki gibi stokastik yuvarlıyor:

```
q = |x| >> 4,   f = |x| mod 16,   r = LFSR'in alt 4 biti (0..15)
f > r ise q = q + 1        -> yukarı yuvarlama olasılığı f/16, beklenen değer x/16
q = min(q, 127)            -> D9: ±127
y = işaret(x) · q
```

Örnek: x = 40 (40/16 = 2,5). f = 8 olduğu için kullanımların yaklaşık yarısında 3, yarısında 2 çıkar; ortalama 2,5. En yakına yuvarlama hep 3 verirdi.

## Dayanak

| Konu | Seçim | Kaynak |
|---|---|---|
| Yuvarlama türü | Stokastik, işaret-büyüklükle | **NITI**: `ti_loss.py` satır 35 `StoShift(out_grad, 4)`, `ti_torch.py` satır 33–46. NITI'nin ortamı PyTorch 1.7 (Dockerfile); bu sürümde `//` sıfıra doğru keser |
| Taşma | ±127'ye kırpma | **NITI** `int8_clip` + D9 |
| Rastgele sayı üreteci | 16 bit Fibonacci LFSR, x^16 + x^14 + x^13 + x^11 + 1 | **Alternatif**: NITI `torch.randint` kullanıyor, Shao CLU'da yuvarlamayı hiç çizmiyor |
| Kullanım başına ilerleme | 4 adım (ardışık r'ler örtüşmez) | **Alternatif** |
| Kanal başına ayrı LFSR | 10 kanal, tohumlar aynı dizide i · 6553 adım aralıklı | **Alternatif**; Fig. 7'de CLU yolu kanal başına çizili (D3) |

Kanal tohumları (hex): `ACE1 166E 490B F205 0A65 3F3B E338 5B00 A0EA DD68`.

NITI'nin rastgele sayıları farklı bir üreteçten geldiği için NITI'yle **bit bit** aynı sonuç beklenemez; aynı istatistik beklenir. Aynı r verildiğinde birimin sonucu NITI StoShift'le birebir aynı (aşağıda).

## Vivado'da çalıştırma

1. Repo klasörünü boşluk ve Türkçe karakter içermeyen bir yola koy, örneğin `C:/ProjeWithOmer-main`.
2. Vivado'yu aç; açık proje varsa kapat (File > Close Project).
3. Tcl Console'a yaz:
   ```
   source C:/ProjeWithOmer-main/rtl/clu_yuvarlama/run_sim.tcl
   ```
4. En sonda beklenen satır:
   ```
   SONUC tb_stok_yuvarla: PASS 40960/40960
   ```

## Dosyalar

| Dosya | İçerik |
|---|---|
| `models/clu_yuvarlama/clu_yuvarlama.py` | Golden model, öz kontroller ve vektör üreteci: bu klasörde `python3 clu_yuvarlama.py` (ek kütüphane gerekmez) |
| `rtl/clu_yuvarlama/stok_yuvarla.v` | Tek kanallık birim (Verilog-2001) |
| `rtl/clu_yuvarlama/tb_stok_yuvarla.sv` | 10 kanallı testbench |
| `rtl/clu_yuvarlama/run_sim.tcl` | Vivado script'i |
| `models/clu_yuvarlama/vektorler/stok_yuvarla.txt` | 1. satır `N T 4`, 2. satır N tohum, sonra T satır: `x_0 y_0 … x_9 y_9` |
| `models/clu_yuvarlama/vektorler/OKUNUR.txt` | Tohumlar ve kanal 0'ın ilk kullanımlarının adım adım dökümü |

## Modül

`stok_yuvarla #(W = 16, TOHUM = 16'hACE1)`

| Port | Yön | Genişlik | Açıklama |
|---|---|---|---|
| `clk`, `rst` | giriş | 1 | Saat; eşzamanlı, aktif-yüksek reset (LFSR ← TOHUM) |
| `ilerle` | giriş | 1 | 1 ise bu çevrimin sonucu kullanıldı; saat kenarında LFSR 4 adım ilerler |
| `x` | giriş | W | İşaretli giriş (CLU'nun e_i'si, >>4'ten önce) |
| `y` | çıkış | 8 | İşaretli sonuç, −127..127; saatsiz |

**CLU'ya bağlarken:**
- Her sınıf kanalı için bir örnek kullanılır; kanal i'nin `TOHUM`'u yukarıdaki listenin i. değeri.
- Her CLU işleminde (örnek başına) her kanalın `ilerle`'si bir kez verilir.
- CLU çıkışları paralel değil de sırayla (paylaşılan bölücüyle) üretiliyorsa, kanal başına LFSR durumunu saklayıp kanala göre seçmek aynı sonucu verir. Hangisinin uygun olduğu Egemen'in CLU yapısına bağlı.

## Doğrulama durumu

- **Golden model öz kontrolleri:**
  - **LFSR:** En uzun periyotlu (65535); 4'er adım ilerletilince de bütün durumları dolaşıyor.
  - **r'nin dağılımı:** Düzgün. 0000 bir eksik çıkıyor; bu yüzden yukarı yuvarlama olasılığı f/16'dan en fazla 1,4·10⁻⁵ sapıyor.
  - **NITI ile karşılaştırma:** Aynı r ile NITI StoShift'in bağımsız yeniden yazımıyla x = −40.000…40.000 ve bütün r değerlerinde birebir aynı.
- **Vektörler:** 4096 CLU işlemi × 10 kanal = 40.960 değer; geri okunup modelle yeniden hesaplandı. Kenar değerleri var: 0, ±15, ±16, ±2047, ±2048, ±32767, −32768.
- **Icarus Verilog 12:** PASS 40.960/40.960. Satırlar arasına boş çevrimler konuyor; LFSR'in yalnızca `ilerle` ile ilerlediği de test ediliyor.
- **Hata yakalama testi:** RTL'e bilerek sokulan 9 hatanın 9'u yakalandı:
  - yuvarlama koşulu
  - geri besleme biti
  - adım sayısı
  - r'nin bitleri
  - doyma ve doyma sınırı
  - işaret
  - `ilerle`
  - tohum
- **Sentez:** Verilog-2001 kipinde derleniyor. Yosys'te 23 hücre ve tek bir 16 bitlik register çıkıyor, latch yok.
- **`run_sim.tcl`:** Sahte Vivado komutlarıyla dört senaryoda denendi (normal, plusarg yok, açık proje, yolda boşluk). Gerçek Vivado'da da geçti (02.11).
