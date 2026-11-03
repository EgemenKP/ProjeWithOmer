# Adım 4.0: Arayüz Sözleşmesi

> **Onay (Ömer, 03.11.2026):** A3 için GMS çıkış FIFO'su seçildi ("Egemen'in SRU'su değişmeden kalsın"). A1, A2 ve A4–A7'ye itiraz gelmedi; bu hâliyle uygulanıyor. Karar dosyasında D64.

> **Uygulama (Paket 2, 03.11.2026):** `rtl/komut_yurutucu.v`, `rtl/pe_motoru.v`, `rtl/grup_fifo.v`, `rtl/bellek.v`, `rtl/sistem_veriyolu.v`. Sözleşmeden sapma yok. Belgenin bıraktığı ayrıntılar karar dosyasında: D66 (ön-getirmenin çevrim kuralı, BP s2'de Psum FIFO'nun şerit şerit düzeni), D67 (bellek portları, ÖLÇEK'te bekleyen grup yoksa hata bayrağı).

> **Uygulama (Paket 3, 03.11.2026):** `rtl/sistem_ust.v` (FSM + veri yolu). Bölüm 1'deki şema birebir; `maks_reg` kullanılmıyor (A1).

> **Hazırlayan:** Claude (Ömer'in isteğiyle), 03.11.2026
>
> **Amaç:** 4.5 entegrasyonunda blokların nasıl bağlanacağını önceden sabitlemek: kim hangi komutu yürütür, kim `kom_bitti` verir, veriler hangi sinyallerle akar, bellekler nasıl düzenlenir.
>
> **Dayanak:** Bloklar: Egemen'in PE, SRU, CLU'su (kopyalar, D61, D62); bizim FSM (`master_controller.v`, 6206/6206), `fe_top.v` (Adım 3). Davranışın golden'ı `sistem_golden.py`'deki komut yorumlayıcı (`yorumla`). Shao bu arayüzlerin hiçbirini tanımlamıyor (III-D'de master controller için tek cümle var); buradaki her şey **[Çıkarım]**, yani mühendislik tercihi.

## 1. Blok şeması

```
                     kom (10 x 16 bit), kom_gecerli
 master_controller ─────────────────────────────────▶ komut_yurutucu ──── kom_bitti ───▶ FSM
 (FSM, DEĞİŞMEDİ) ◀── maks_G = SRU.G_out ──┐               │
                                            │               ├─▶ PE yolu: ön-getirme ─▶ pe_sarmalayici ─▶ grup toplayıcı
                                            │               │            ▲   │ psum                      │ son = 1
                                            │               │            │   ▼                           ▼ 
                                            │               │       Psum FIFO (256 int32)        bekleyen grup (1 kayıt)
                                            │               │                                         │ push_group
                                            │               │                                         ▼
                                            └───────────────┼──────────────────────────────── sru_top (hedef, 64 grup)
                                                            │                                         │ GMS akışı (durdurulamaz)
                                                            │                                         ▼
                                                            │                               GMS çıkış FIFO'su (64 grup)
                                                            │                                         │ KOPYA/WU başına 1 grup
                                                            ├─▶ fe_top akış yolu (ReLU / geçir / w − g) ◀┘
                                                            ├─▶ fe_top CLU yolu
                                                            └─▶ bellekler: AKT, HATA, AGR, ETIKET
```

## 2. Kararlar

| # | Karar | Neden | Alternatif |
|---|---|---|---|
| A1 | **FSM değişmiyor.** `maks_reg.v` çıkarılıyor; FSM'in `maks_G` girişi SRU'nun `G_out`'una bağlanıyor | D49. FSM G'yi ÖLÇEK'in `kom_bitti`'sinde örnekliyor; SRU'nun G'si o anda hazır ve bir sonraki `rst`'e kadar sabit | — |
| A2 | **Tek bir `komut_yurutucu`** bütün komutları alıp ilgili bloğa yönlendiriyor ve her komut için `kom_bitti`'yi o veriyor | D50 (tek komut, tek bitti) korunur; FSM'e tek muhatap | Her blok kendi bitti'sini verir, OR'lanır |
| A3 | **GMS çıkış FIFO'su:** SRU'nun durdurulamayan GMS akışı 64 grupluk bir FIFO'ya yazılıyor; her KOPYA ya da WU komutu FIFO'dan bir grup alıyor | Egemen'in SRU'su değişmeden kalır. Golden'da tüketici sırası grup sırasıyla aynı (kontrol ediliyor), bu yüzden sıra bilgisi gerekmiyor | **SRU'ya geri basınç (hazır girişi)**: FIFO gerekmez, GMS tüketiciye giderken yapılır (Shao Fig. 6'ya daha yakın), ama Egemen'in `sru_top`'u değişir |
| A4 | **Son grup:** `son = 1` olan her PE geçişinin grubu bir kayıtta bekletiliyor; yeni grup gelince öncekisi `last_group = 0` ile SRU'ya itiliyor. ÖLÇEK komutu bekleyeni `last_group = 1` ile itiyor, SRU'nun `layer_done`'ını bekleyip `kom_bitti` veriyor | Egemen'in SRU'su son grubu itilirken bilmek istiyor; böylece grup sayısını ayrıca hesaplamak gerekmiyor. ÖLÇEK'in `a1` alanı (grup sayısı) testte SRU'nun saydığıyla karşılaştırılıyor | Yürütücü grup sayısını katman tablosundan hesaplar (FSM'deki formülün kopyası) |
| A5 | **Bellekler** test sisteminde bayt dizisi (register); bir çevrimde bir satır (en çok 16 bayt) okunur ya da yazılır. Adres düzeni Bölüm 4'te | Test ağında toplam ~1,8 KB. Shao'nun çok bankalı tamponları (III-D) 16×16 diziyle birlikte Adım 5'in işi | — |
| A6 | **Psum FIFO:** düz bir int32 FIFO, derinlik parametre, varsayılan 256 | Golden'da FIFO'dan hep baştaki kayıt alınıyor (kontrol ediliyor); anahtar gerekmiyor. En çok doluluk ag1'de 128, ag2'de 144 int32 (OKUNUR.txt) | Derinlik 128: yalnızca ag1 |
| A7 | **SRU:** tek kanal `sru_top` (hedef girişli kopya), MAX_GROUPS = 64, sayaçlar 7 bit | Tek PE (D43); en çok grup 56 (ag1), 60 (ag2) | — |

## 3. Komutların yürütülmesi

`kom` alanları: `op faz katman b x y z a1 a2 a3` (TASARIM_FSM.md Bölüm 3).

| op | Komut | Yürütücünün yaptığı | `kom_bitti` ne zaman |
|---|---|---|---|
| 8 | İŞ_BAŞLA | `hedef ← x`; SRU'ya 1 çevrim `rst`; GMS çıkış FIFO'su ve Psum FIFO boşaltılır; bekleyen grup kaydı temizlenir | 1 çevrim sonra |
| 1 | PE | Ön-getirme bellekten satırları okur ve PE moduna göre akışları sürer (dolgu, çift/tek, BP s2 akışları); `ilk = 0` ise kısmi toplamları Psum FIFO'dan alır; `son = 0` ise çıkışları Psum FIFO'ya yazar, `son = 1` ise grup toplayıcı çıkışları gruba çevirir (BP s2'de şerit yerleşimi ve dolgu kırpma) ve grubu A4'teki kayda koyar. WG'de akümülatörler `ilk`'te sıfırlanır, `son`'da 9 değer grup olur | Geçişin son çıkışı alındığında |
| 2 | ÖLÇEK | A4: bekleyen grubu `last_group = 1` ile iter | SRU `layer_done` verdikten sonra (bütün GMS grupları FIFO'da, G hazır) |
| 4 | SA | Bir şey yapmaz (s_a FSM'de tutuluyor; CLU komutu s_a'yı `x`'te taşıyor) | 1 çevrim sonra |
| 3 | KOPYA | FIFO'dan bir grup alır. `z` (işlem) 0: geçir, 1: ReLU ileri, 2: ReLU geri (maske AKT[l−1]'den aynı satır(lar)). FP: AKT[l][b][kanal][satır]'a yazar. BP: HATA[l−1][b][kanal]'a, stride 1'de satır `y`, stride 2'de `bp_s2_satirlari(y)` satırları | Yazma bitince |
| 5 | CLU | AKT[L][b]'nin 10 değerini, `x`'teki s_a'yı ve ETIKET[b]'yi `fe_top`'a verir; `clu_bitti` gelince e'yi HATA[L][b]'ye yazar | Yazma bitince (CLU 77 çevrim) |
| 6 | WU | FIFO'dan bir grup (9 değer, g8) alır; AGR[l][o][c]'yi okur; `fe_top` mod 3 ile w − g8 (±127); sonucu AGR'ye geri yazar | Yazma bitince |
| 7 | BİTTİ | — | 1 çevrim sonra |

## 4. Bellek düzeni

Bütün tensörler işaretli int8, satır öncelikli. Her bölge kendi taban adresinden başlar; adresler bayt cinsinden.

| Bölge | İçerik | Adres (bölge içi) | ag1 boyutu |
|---|---|---|---|
| AKT[l], l = 0..L | l. katmanın çıkışı (l = 0: giriş), ReLU ve GMS sonrası | `((b · C_l + c) · H_l + r) · W_l + k` | 196 + 392 + 72 + 20 = 680 |
| HATA[l], l = 1..L | δ_l | `((b · C_l + c) · H_l + r) · W_l + k` | 392 + 72 + 20 = 484 |
| AGR[l], l = 1..L | W_l | `((o · Cin_l + c) · 3 + i) · 3 + j` | 72 + 144 + 360 = 576 |
| ETIKET | doğru sınıf, örnek başına | `b` | 2 |

C_l, H_l, W_l: AKT/HATA[l]'nin kanal, yükseklik, genişlik değerleri (l = 0 için ağın girişi). Taban adresleri katman tablosundan sırayla toplanarak bulunur; RTL'de parametre.

**Testbench'in erişimi:** Başlangıçta `baslangic.txt` belleklere hiyerarşik yazmayla yüklenir; BİTTİ'den sonra AKT[1..L], HATA[1..L], AGR ve FSM'in s_a'ları `beklenen_sonuc.txt` ile bit bit karşılaştırılır.

## 5. Sinyaller ve genişlikler

| Arayüz | Sinyaller |
|---|---|
| FSM → yürütücü | `kom[159:0]` (10 × 16 bit), `kom_gecerli`; yürütücü → FSM: `kom_bitti` (1 çevrimlik darbe) |
| SRU → FSM | `G_out[5:0]` → `maks_G` |
| Yürütücü → SRU | `rst`, `hedef[2:0]`, `push_group`, `group_in_flat[16·32−1:0]`, `group_n[4:0]`, `last_group` |
| SRU → GMS FIFO | `group_out_valid`, `group_out_flat[16·8−1:0]`, `group_out_n[4:0]`, `layer_done` |
| Yürütücü ↔ fe_top | Adım 3'teki portlar (`mod`, `veri_flat`, `maske_flat`, `w_flat`, `cikis_flat`, `clu_*`) |
| Yürütücü ↔ PE sarmalayıcısı | `mod[2:0]` (0 FP s1, 1 FP s2, 2 BP s1, 3 BP s2, 4 WG s1, 5 WG s2), ağırlıklar (9 × 8), satır akışları, kısmi toplam girişleri, çıkışlar (Paket 1'de yazılıyor) |

Bütün bloklar tek saat, eşzamanlı aktif-yüksek `rst`.

## 6. Bu sözleşmenin dışında kalanlar

- Shao'nun 16×16 dizisi, çok bankalı tamponlar, boru hattı (D50): Adım 5.
- Ön-getirmenin çevrim düzeyi zamanlaması (PE'nin mod başına 1–2 çevrimlik çıkış kayması, D16): Paket 2'de golden'ın PE modeline göre belirlendi (D66).
