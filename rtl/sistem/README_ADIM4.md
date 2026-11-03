# Adım 4: Entegrasyon — FSM, komut yürütücüsü, PE motoru

> **Hazırlayan:** Claude (Ömer'in isteğiyle), 02.11.2026
>
> **Durum (03.11):** Adım 4 tamamlandı. FSM (02.11), Paket 1, Paket 2 ve Paket 3 (tam sistem) Vivado'da gerçek bölücü IP'siyle PASS.
>
> **Repo düzeni (03.11):** Aşağıdaki güncelleme notları Adım 4 paketinin (`adim4/`) yollarıyla yazıldı. Repodaki yerleri:
> - `adim4/rtl/*.v` ve `adim4/tb/*.sv` → `rtl/sistem/` (bu klasör; testbench'ler RTL'in yanında, repodaki diğer klasörler gibi)
> - `adim4/rtl/sru/` (hedef girişli + 64 grup) → `rtl/sru_64/`. `rtl/sru/` ve `rtl/sru_hedefli/` ile aynı projeye eklenmemeli (aynı modül adları)
> - `adim4/rtl/egemen/` (değişmemiş kopyalar) → kopya yok; script Egemen'in asıllarını kullanıyor (`rtl/pe/`, `rtl/sru/`, `rtl/clu/`)
> - `adim4/rtl/fe/` → `rtl/fe/`; `adim4/ip/` ve `adim4/sim_model/` → `rtl/clu/ip/`, `rtl/clu/sim_model/`
> - Python dosyaları ve `adim4_vektorleri/` → `models/sistem/`. `pe_golden.py`, `sru_golden.py`, `fe_golden.py`, `clu_yuvarlama.py` oradaki kopyalar (`models/pe`, `models/sru`, `models/fe`, `models/clu_yuvarlama` ile aynı; `models/fe`'deki gibi, sistem modeli bunları aynı klasörden okuyor)
>
> Tasarımın ayrıntısı ve kararlar `TASARIM_FSM.md`'de. Bölüm 9'daki değişen ve yeni maddeler (T1, T4, T8, T12) 02.11'de onaylandı.
>
> **02.11 güncellemeleri:**
> - SRU-a3 ±127 doymaya çevrildi (`TASARIM_FSM.md` Bölüm 10).
> - D8 (c): CLU yer tutucusundaki >>4 artık LFSR'li stokastik yuvarlanıyor (`clu_yuvarlama.py`).
>
> Vektörler iki değişikliğe göre yeniden üretildi. FSM ve Max Regs RTL'i değişmedi, beklenen `SONUC` satırı da aynı.
>
> **03.11 güncellemeleri (Adım 4, Paket 1):**
> - **Golden, Adım 3 kararlarına göre:** SRU'da doyma yok (D59), CLU'nun son >>4'ü en yakına (D60). `sru_golden.py` 03.11 sürümü; `sistem_golden.py`'de `D8_YUVARLAMA = "a"`. Vektörler yeniden üretildi; `komutlar.txt`'ler aynı kaldı, `maksreg.txt`'ler ve beklenen sonuçlar değişti. `tb_fsm` yeni vektörlerle Icarus'ta 6206/6206.
> - **Float kontrolü (D65):** Yapı aynı kaldı (Ömer: "ana şablonda ne ise öyle kalsın"). Sıkı eşikler (FP sapması < 0,1, kosinüs > 0,95) doymalı bir referans çalıştırmada denetleniyor; yazılan vektörler doymasız. Doymasız sonucun sapması yalnızca raporlanıyor: ag1'de 1. katmanda 0,40, ag2'de 0,04.
> - **Arayüz sözleşmesi (4.0, D64):** `ARAYUZ_SOZLESMESI.md`. GMS çıkış FIFO'su seçildi; Egemen'in SRU'su değişmiyor, FSM de değişmiyor.
> - **SRU tamponu 64 grup (D63):** `rtl/sru/` (Adım 3'teki hedef girişli kopya + MAX_GROUPS 64, 7 bit sayaçlar). Yeni test `tb_sru_buyuk`.
> - **PE sarmalayıcısı ve Psum FIFO:** `rtl/pe_sarmalayici.v` (Egemen'in 5 PE devresi, mod girişiyle), `rtl/psum_fifo.v` (256 int32). Yeni test `tb_pe_blok`.
> - Egemen'in değişmemiş dosyaları `rtl/egemen/` altında.
>
> **03.11 güncellemeleri (Adım 4, Paket 2):**
> - **Komut yürütücüsü (A2):** `rtl/komut_yurutucu.v`. FSM'in bütün komutlarını alır, ilgili bloğa yaptırır ve her komut için `kom_bitti`'yi verir. İçinde PE motoru, SRU (`rtl/sru/`), GMS çıkış FIFO'su (A3) ve fonksiyon motoru (`rtl/fe/fe_top.v`, CLU dahil) var.
> - **PE motoru:** `rtl/pe_motoru.v`. Bir PE geçişini yürütür: ağırlık ve satırların ön-getirmesi (dolgu, çift/tek, BP s2 akışları), Psum FIFO, grup toplayıcı (BP s2'de şerit yerleşimi ve dolgu kırpma). D66.
> - **Bellek:** `rtl/bellek.v` (AKT, HATA, AGR, ETIKET tek bayt dizisinde, taban adresleri yapılandırmadan). Yürütücünün testi bellek gerektirdiği için Paket 3'ten buraya alındı. D67.
> - **`rtl/sistem_veriyolu.v`:** yürütücü + bellek. Paket 3'te FSM'e bağlanacak.
> - **Yeni test `tb_veriyolu`:** FSM'in yerine komutlar.txt'i FSM'in el sıkışmasıyla veriyor; ag1 ve ag2'nin bir eğitim adımı uçtan uca. Icarus'ta PASS 71.048/71.048.
> - **Paket 3'e kalan:** FSM + üst modül + son test (FSM'in ürettiği komutlarla aynı eğitim adımı).
>
> **03.11 güncellemeleri (Adım 4, Paket 3):**
> - **Üst modül `rtl/sistem_ust.v`:** FSM (`master_controller.v`, değişmedi) + `sistem_veriyolu`. FSM'in `maks_G`'si SRU'nun G'si; `maks_reg.v` kullanılmıyor (A1). Yalnızca `tb_fsm` için klasörde duruyor.
> - **Yeni test `tb_sistem`:** Komutları artık FSM kendisi üretiyor. Üç tur (ag1, ag2, ag1), aralarında reset yok. Icarus'ta PASS 21.415/21.415.

## Vivado'da çalıştırma

1. Repoyu boşluk ve Türkçe karakter içermeyen bir yola koy, örneğin `C:/ProjeWithOmer-main`.
2. Vivado'yu aç. Açık bir proje varsa kapat (File > Close Project).
3. Alttaki Tcl Console'a şunu yaz (ters bölü değil, düz bölü kullan):
   ```
   source C:/ProjeWithOmer-main/rtl/sistem/run_sim.tcl
   ```
4. En sonda `OZET` başlığı altında şu satırları görmelisin:
   ```
   BOLUCU: gercek IP (rtl/clu/ip/div_gen_0Z.xci, parca xc7vx690tffg1761-2)
   SONUC tb_fsm: PASS 6206/6206 (3 tur: ag1, ag2, ag1; 4633 komut, 1564 Max Regs olayi)
   SONUC tb_sru_buyuk: PASS 8508/8508
   SONUC tb_pe_blok: PASS 380490/380490
   SONUC tb_veriyolu: PASS 71048/71048
   SONUC tb_sistem: PASS 21415/21415 (3 tur: ag1, ag2, ag1, aralarinda reset yok)
   ```
   `BOLUCU` satırı CLU'nun bölücüsünü söyler. Gerçek IP üretilemezse davranışsal model kullanılır ve satır bunu yazar; o durumda da test geçmeli.
   Bu satırları bana gönder. Hata çıkarsa konsolun son 30 kadar satırını gönder.

Script, ReLU/WU testindeki gibi kendi klasöründe geçici bir proje (`vivado_sim/`) kurar, testbench'leri çalıştırır ve projeyi kapatır. `vivado_sim/` sonradan silinebilir.

**03.11 eki 2 (Paket 2):**
- Her test artık kendi simülasyon kümesinde (`sim_tb_fsm`, `sim_tb_veriyolu` ...) ve kendi klasöründe çalışıyor. Neden: ilk Vivado koşusunda (Ömer, 03.11) üç test geçti, dördüncüsü `tb_veriyolu` derleme adımında `USF-XSim-62` verdi; `xvlog.log`, `xvhdl.log` ve `compile.log`'da hiç hata satırı yoktu, bütün dosyalar sorunsuz analiz edilmişti. En olası açıklama, aynı klasörü kullanan önceki testlerden kalan dosyalar [Emin değilim].
- Yalnızca bazı testleri çalıştırmak için: `set sadece {tb_sistem} ; source C:/ProjeWithOmer-main/rtl/sistem/run_sim.tcl`
- Bir test çalışmazsa `OZET`, klasördeki bütün log'larda `ERROR` geçen satırları yazıyor (önceden yalnızca `compile.log`'a bakıyordu).

**03.11 eki:**
- **Başlangıçta:** Script önceki çalıştırmadan kalan `vivado_sim/`'i siler. Silemezse yeni adlı bir klasör kullanır ve bunu yazar.
- **Bir test derlenemez ya da çalıştırılamazsa:** Script durmaz. `OZET`'e `CALISTIRILAMADI` yazar, altına `compile.log` / `elaborate.log` / `simulate.log`'daki ilk `ERROR` satırlarını ekler ve sıradaki teste geçer. Proje her durumda kapanır.
- **Vivado'da görülen bir sorun:** İkinci çalıştırmada `tb_pe_blok`'un elaborate adımı `USF-XSim-62` hatası verdi. Bu sürüm o yüzden yazıldı. Vivado tamamen kapatılıp temiz bir klasörle yeniden çalıştırılınca üç test de geçti. Bu, önceki çalıştırmadan kalan dosyaların kilitli kaldığı tahminiyle uyumlu, ama asıl hata satırı görülmedi [Emin değilim]. Böyle bir hatada önce Vivado'yu tamamen kapatıp açmayı deneyin.

## Golden modeli yeniden üretmek (isteğe bağlı)

```
cd models/sistem
python3 sistem_golden.py
python3 veriyolu_vektor_uret.py
python3 sru_buyuk_uret.py
```

Python 3 ve numpy gerekir. `pe_golden.py`, `sru_golden.py`, `fe_golden.py` ve `clu_yuvarlama.py` aynı klasörde olmalı. Çıktı `adim4_vektorleri/` klasörüne yazılır; dosyalar her seferinde aynı çıkar.

## Dosyalar

Yol yazmayan dosyalar bu klasörde (`rtl/sistem/`); `.py` dosyaları `models/sistem/`'de.

| Dosya | İçerik |
|---|---|
| `TASARIM_FSM.md` | Tasarım belgesi: komut seti, döngüler, Max Regs, kararlar ve dayanakları, doğrulama durumu |
| `master_controller.v` | FSM (Verilog-2001) |
| `maks_reg.v` | Max Regs (Verilog-2001). Yalnızca `tb_fsm` kullanıyor; üst modülde yok, G SRU'dan geliyor (D49, sözleşme A1) |
| `ARAYUZ_SOZLESMESI.md` | 4.0 arayüz sözleşmesi (onaylı, 03.11) |
| `rtl/sru_64/` | Egemen'in SRU'su: hedef girişi (D61) + 64 grup (D63). Her dosyanın başında değişiklik notu |
| `pe_sarmalayici.v` | Egemen'in beş PE devresini `mod` girişiyle seçen sarmalayıcı (kayıt eklemez) |
| `psum_fifo.v` | Psum FIFO, int32, derinlik 256 |
| `rtl/pe/`, `rtl/sru/`, `rtl/clu/` | Egemen'in değişmemiş dosyaları; script asıllarını kullanıyor |
| `komut_yurutucu.v` | Paket 2: komut yürütücüsü (A2); PE motoru, SRU, GMS FIFO ve fonksiyon motorunu bağlar |
| `pe_motoru.v` | Paket 2: bir PE geçişi (ön-getirme + PE sarmalayıcısı + Psum FIFO + grup toplayıcı) |
| `grup_fifo.v` | Paket 2: GMS çıkış FIFO'su, 64 grup (A3) |
| `bellek.v` | Paket 2: test belleği, satır başına 16 bayt, iki okuma ve bir yazma portu (A5) |
| `sistem_veriyolu.v` | Paket 2: yürütücü + bellek (FSM'siz veri yolu) |
| `sistem_ust.v` | Paket 3: üst modül, FSM + veri yolu |
| `rtl/fe/` | Adım 3'ün fonksiyon motoru (`fe_top.v`, `relu_unit.v`, `wu_unit.v`), değişmedi |
| `rtl/clu/ip/div_gen_0Z.xci` | CLU'nun bölücü IP'si (Ömer); script geçici projeye kopyalayıp üretir |
| `rtl/clu/sim_model/div_gen_0Z_davranissal.v` | IP yoksa kullanılan davranışsal bölücü (Adım 3'teki) |
| `tb_veriyolu.sv` | Paket 2 testi: bir eğitim adımı, PE izi, SRU olayları, son bellek |
| `tb_sistem.sv` | Paket 3 testi: tam sistem, FSM'in komutları, G'ler, el sıkışma, son bellek |
| `veriyolu_vektor_uret.py` | `veriyolu_duzen.txt` ve `veriyolu_bellek.txt` üreteci (bellek düzeni ve başlangıç/beklenen bellek) |
| `tb_sru_buyuk.sv` | 64 gruplu SRU testi (`adim4_vektorleri/sru_buyuk.txt`) |
| `tb_pe_blok.sv` | PE sarmalayıcısı (Egemen'in modüllerine karşı adım adım) ve Psum FIFO (kuyruk modeline karşı) |
| `pe_sarmalayici_simler.sv` | Yalnızca Icarus testi için: Egemen'in PE testbench'lerini sarmalayıcıdan geçiren kabuklar |
| `sru_buyuk_uret.py` | `sru_buyuk.txt` üreteci (`sru_golden.py` ile) |
| `tb_fsm.sv` | Sahte bloklu testbench (SystemVerilog) |
| `run_sim.tcl` | Vivado script'i |
| `sistem_golden.py` | Sistem golden modeli: komut sırası, Max Regs olayları ve bir eğitim adımının beklenen sonuçları |
| `pe_golden.py`, `sru_golden.py`, `fe_golden.py` | Önceki adımların golden modelleri; sistem modeli bunları kullanıyor. `pe_golden.py` ve `fe_golden.py` değişmedi; `sru_golden.py` 03.11 sürümü (D59, doyma yok) |
| `clu_yuvarlama.py` | CLU çıkışının stokastik yuvarlaması (D57); şu an kullanılmıyor (D60), `D8_YUVARLAMA = "c"` ile devreye girer |
| `models/sistem/adim4_vektorleri/` | ag1 (ana test ağı) dosyaları |
| `models/sistem/adim4_vektorleri/ag2/` | ag2 (yalnızca FSM testi için ikinci yapılandırma) dosyaları |

Vektör klasöründeki dosyalar (ag1 ve ag2 için aynı adlarla):

| Dosya | İçerik |
|---|---|
| `komutlar.txt` | FSM'in üretmesi gereken komutlar: ilk satır sayı; sonra her satır `op faz katman b x y z a1 a2 a3` |
| `maksreg.txt` | Max Regs olayları: ilk satır sayı; sonra `1 grup M l` (grubun yerel maksimumu ve LMS kaydırması), `2 0 G 0` (ÖLÇEK), `3 grup Δ 0` (KOPYA/WU) |
| `ag_yapilandirma.txt` | Katman tablosu: ilk satır `L B m_u s_a0 N`; sonra katman başına `cin cout h w s p relu s_w` |
| `baslangic.txt`, `beklenen_sonuc.txt` | Bir eğitim adımının başlangıç belleği ve beklenen sonuçları (4.5 entegrasyonu için) |
| `OKUNUR.txt` | Özet: iş listesi, komut sayıları, bellek boyutları, float kontrolü |
| `pe_izi.txt` | Paket 2: her PE komutunda PE'nin çevrim çevrim girişleri, çıkışları ve grubu (`sistem_golden.py` yazar) |
| `veriyolu_duzen.txt`, `veriyolu_bellek.txt` | Paket 2: bellek düzeni (taban adresleri) ve her baytın başlangıç/beklenen değeri (`veriyolu_vektor_uret.py` yazar) |

## Modüller

**`master_controller #(AW=16, LMAX=8, CW=8, HEDEF_AKT=7)`**

| Port | Yön | Genişlik | Açıklama |
|---|---|---|---|
| `clk`, `rst` | giriş | 1 | Saat; eşzamanlı, aktif-yüksek reset |
| `basla` | giriş | 1 | 1 çevrimlik darbe; eğitim adımını başlatır |
| `cfg_L`, `cfg_batch`, `cfg_m_u`, `cfg_s_a0` | giriş | 4, 8, 4, 8 | Ağ parametreleri (`cfg_s_a0` işaretli) |
| `cfg_cin` … `cfg_sw` | giriş | LMAX×8 | Katman tablosu; katman l, `[8*(l-1) +: 8]` bitlerinde |
| `maks_G` | giriş | 6 | Max Regs'in G çıkışı |
| `kom_bitti` | giriş | 1 | 1 çevrimlik darbe: komutun işi bitti |
| `kom_gecerli` | çıkış | 1 | Komut geçerli; her komut için bir kez yükselir |
| `kom` | çıkış | 10×AW | Komut; alan i `[AW*i +: AW]` bitlerinde (0 op … 9 a3) |
| `mesgul`, `bitti` | çıkış | 1 | Çalışıyor / BİTTİ tamamlandı |

**`maks_reg #(AW=16, AD=6)`**

| Port | Yön | Genişlik | Açıklama |
|---|---|---|---|
| `clk`, `rst` | giriş | 1 | Saat; eşzamanlı, aktif-yüksek reset |
| `kom_gecerli`, `kom` | giriş | 1, 10×AW | FSM'in komut yolu (yalnızca dinler) |
| `yerel_gecerli`, `yerel_grup`, `yerel_maks` | giriş | 1, AW, 32 | Grubun yerel maksimumu (PE tarafından) |
| `lms_kaydirma` | çıkış | 6 | l = max(0, B(M) − hedef); SRU'nun LMS girişine |
| `G` | çıkış | 6 | max(0, B(global maks) − hedef); FSM'e |
| `gms_kaydirma` | çıkış | 6 | KOPYA/WU'daki grubun Δ'sı; SRU'nun GMS girişine |

## Doğrulama durumu

- **Icarus Verilog 12:** `tb_fsm` PASS 6206/6206.
- **Hata yakalama testi:** RTL'e bilerek sokulan 23 hatanın 23'ü yakalandı. Golden modele sokulan 16 hatanın 16'sı yakalandı.
- **Sentez:** RTL, Verilog-2001 kipinde derleniyor. Yosys'te latch çıkmadı.
- **`run_sim.tcl`:** Vivado komutlarının sahte karşılıklarıyla ve Icarus ile dört senaryoda denendi:
  - normal çalışma
  - plusarg ayarlanamazsa
  - açık proje varsa
  - yolda boşluk varsa

  Gerçek Vivado'da da çalıştı (02.11): PASS 6206/6206.

## Kapsam dışı

- **Paket 3 sonrası (03.11, yapıldı):** IP çıktılarının yolu düzeltildi (bu script ve `rtl/fe/run_sim.tcl`); Adım 4 dosyaları repo düzenine taşındı.
- **Adım 5:** Shao'nun 16×16 dizisi, çok bankalı tamponlar, boru hattı (D50, D66'daki sınırlar).
- `kom_bitti`'nin kaynağı (A2) ve gerçek PE/SRU/CLU ile entegrasyon Paket 2'de yapıldı. Sistem golden'ındaki CLU, Egemen'in CLU'suyla 1940 vektörde birebir aynı (D60).

## Paket 1 doğrulaması (03.11)

- **`tb_sru_buyuk`:** 6 case (64, 60, 56, 17, 1 grup ve boyu karışık 64 grup), 8508 kontrol.
  - Her grubun LMS çıkışı, GMS çıkışı, eleman sayısı ve sırası, G, `layer_done` ve fazla çıkış olmadığı kontrol ediliyor.
  - Eski 16 gruplu SRU'yla aynı test 1241 hata veriyor.
  - Bilerek sokulan hatalar yakalandı: MAX_GROUPS 60, sayaçlar 5 bit.
- **Regresyon:** Egemen'in altı SRU testi (hedef = 7) ve Adım 3'ün `tb_sru_gradyan`'ı yeni kopyada aynen geçiyor.
- **`tb_pe_blok`, 380.490 kontrol:**
  - Sarmalayıcı, Egemen'in beş modülüne karşı adım adım karşılaştırılıyor: 400 bölüm, 8 modun hepsi, mod değişimleri, WG `rst`.
  - Psum FIFO bir kuyruk modeline karşı karşılaştırılıyor: 60.000 çevrim. Dolu (5567 çevrim), boş, doluyken yazma ve boşken okuma durumlarının hepsi görüldü.
  - Bilerek sokulan 9 hatanın 9'u yakalandı. Örnekler: çift/tek ya da kısmi toplam girişlerinin yer değiştirmesi, WG `rst`'ünün ya da girişinin kapısız kalması, ağırlık sırası, FIFO'da doluluk sayımı, doluyken yazma, eksik bayrağı.
- **Anlamsal kontrol (yalnızca Icarus):** Egemen'in kendi PE testbench'leri, `pe_sarmalayici_simler.sv`'deki kabuklarla sarmalayıcıdan geçirildi.
  - Testbench kopyalarında yalnızca modül adı değişti; vektörler `models/pe/pe_vectors`.
  - FP s1 38/38, BP s1 34/34, FP s2 24/24, BP s2 32/32, WG s1 5/5, WG s2 5/5.
  - Çıkış kaymaları değişmedi: FP s1, BP s1 ve FP s2'de 2, BP s2'de 1 (D16).
- **Sentez:** Yeni RTL Verilog-2001. Yosys `check` sorunsuz. Sarmalayıcıda 45 çarpıcı var (5 devre × 9 MAC). Psum FIFO tek bir bellek olarak çıkıyor.
- **`run_sim.tcl`:** Sahte Vivado komutlarıyla dört senaryoda denendi (normal, plusarg yok, yolda boşluk, açık proje).
- **Vivado (Ömer, 03.11), son koşu: üç test de PASS** (`tb_fsm` 6206/6206, `tb_sru_buyuk` 8508/8508, `tb_pe_blok` 380.490/380.490). **Paket 1 tamamlandı.**
- **Vivado (Ömer, 03.11), ilk koşu:** `tb_fsm` 6206/6206 ve `tb_sru_buyuk` 8508/8508 geçti. `tb_pe_blok` 120.000 hata verdi: hepsi FIFO'nun `bos`/`dolu` kontrolünde, her çevrimde 2. DUT'un değerleri doğruydu; XSIM, task'a doğrudan verilen `(k_say == 0)` gibi ifadeleri bozuk değerlendiriyordu (karar dosyası, araç tuzağı 10). Beklenen değerler değişkene alındı; RTL değişmedi. Icarus'ta yine 380.490/380.490; `bos`/`dolu` hataları hâlâ yakalanıyor.

## Paket 2 doğrulaması (03.11)

**`tb_veriyolu`** FSM'in yerine geçiyor: `komutlar.txt`'teki komutları FSM'in el sıkışmasıyla veriyor (`kom_gecerli` seviye; `kom_bitti`'yi gördüğü kenarda iner, 1 çevrim sonra sonraki komut). Sırayla ag1 ve ag2. Kontroller:
1. **PE izi** (`pe_izi.txt`): her PE komutunda PE'ye giden mod, akış uzunluğu T ve 9 ağırlık; her akış çevriminde 13 giriş (3 satır akışı × 3 PE satırı + 4 kısmi toplam); her geçerli çıkış; `son = 1` ise SRU'ya gidecek int32 grup.
2. **SRU** (`maksreg.txt`): itilen her grubun LMS kaydırması l ve yerel B'si; ÖLÇEK'te G ve SRU'nun saydığı grup sayısı (ÖLÇEK'in a1'i, A4); GMS'te her grubun kaydırması Δ = G − l.
3. **Bellek** (`veriyolu_bellek.txt`): BİTTİ'den sonra kullanılan her bayt beklenen değerde; AKT[1..L], HATA[1..L] ve AGR'nin her baytı tam bir kez yazılmış, diğer baytlar hiç. Bölgeler arasında 16 baytlık boşluk var; boşluklar ve çıkış bölgeleri başlangıçta sıfır değil, sabit bir desenle dolu. Böylece bir satırın dışını okumak ya da yazılmamış bir yeri okumak sonucu bozar.
4. Yürütücünün hata bayrakları (FIFO taşma/eksik, ÖLÇEK'te grup yok) 0. Belleğin hiyerarşik yüklemesinin tuttuğu da kontrol ediliyor.

Sonuçlar:
- **Icarus Verilog 12:** PASS 71.048/71.048.
  - ag1: 1186 komut, 944 PE geçişi, 25.432 çevrim.
  - ag2: 2261 komut, 1908 PE geçişi, 48.826 çevrim.
- **Hata yakalama testi:** RTL'e bilerek sokulan 32 hatanın 30'u yakalandı. Örnekler: BP s1'de ağırlık döndürme, BP s2'de ağırlık sırası, satır kayması, BP s2'nin 3. satırı, kısmi toplam zamanı, WG'de `rst`, BP s2 şerit yerleşimi, kısmi toplam tamponunun temizlenmemesi, Psum FIFO derinliği 128, ReLU ileri/geri, maske katmanı, KOPYA/WU adresleri, CLU etiketi ve s_a, ÖLÇEK'in son grubu, WG hedefi (m_u), GMS FIFO derinliği 32, İŞ_BAŞLA temizliği, BP s2'de grubun ikinci satırının yazılmaması, bellek okuması.
  - Yakalanmayan 2 hata davranışı değiştirmiyor: kısmi toplamı bir çevrim fazla vermek (o konumda tampon zaten 0) ve okunan satırın 16. baytını bozmak (test ağlarında hiçbir okuma 16 bayt kullanmıyor; aynı hata 9. ve 14. baytta yakalandı).
- **Sentez (Yosys, yapısal):** Yeni RTL'de latch yok, `check` 0 sorun. Egemen'in `stochastic_round.v`'sinde `top` ve `bot` için latch uyarısı var (D68; dosyaya dokunulmadı).
- **`run_sim.tcl`:** Sahte Vivado komutlarıyla ve Icarus ile üç senaryoda denendi: normal, IP yok, yolda boşluk.
- **Vivado (Ömer, 03.11), ikinci koşu: dört test de PASS**, gerçek bölücü IP'siyle (`tb_veriyolu` 71.048/71.048). **Paket 2 tamamlandı.**
- **Vivado, ilk koşu:** ilk üç test geçti; `tb_veriyolu` derleme adımında `USF-XSim-62` verdi, log'larda hata satırı yoktu. Testler ayrı simülasyon kümelerine alınınca geçti (yukarıda, "03.11 eki 2").

## Paket 3 doğrulaması (03.11)

**`tb_sistem`** yalnızca yapılandırmayı ve belleği hazırlıyor, `basla` verip bekliyor. Komutları FSM üretiyor, G'yi gerçek SRU'dan alıyor. Üç tur çalışıyor (ag1, ag2, ag1), aralarında reset yok. Her turdan önce bellek, FSM `SON` durumundayken yeniden yükleniyor. Kontroller:
1. **Komutlar:** FSM'in her komutu `komutlar.txt`'teki sıradaki satırla 10 alanın hepsinde aynı olmalı. SA ve CLU komutlarındaki s_a, FSM'in SRU'dan aldığı G'lerle hesaplanıyor; yani bu kontrol s_a'ları da kapsıyor. Komut, `kom_gecerli` 1 iken değişmemeli.
2. **ÖLÇEK:** SRU'nun G'si (`maksreg.txt`) ve saydığı grup sayısı (ÖLÇEK'in a1'i).
3. **El sıkışma:** Yürütücü her komutu tam bir kez almalı ve aldığı komut FSM'in o anki komutu olmalı.
4. **Bellek:** BİTTİ'den sonra kontrol, `tb_veriyolu`'daki gibi: her bayt beklenen değerde, her çıkış baytı tam bir kez yazılmış.
5. **Durum:** Hata bayrakları 0; FSM'in `bitti`'si 1, `mesgul`'ü 0.

Sonuçlar:
- **Icarus Verilog 12:** PASS 21.415/21.415. Bir eğitim adımı, `basla`'dan `bitti`'ye: ag1'de 1186 komut ve 25.434 çevrim, ag2'de 2261 komut ve 48.828 çevrim.
- **Hata yakalama testi:** Bilerek sokulan 6 hatanın 6'sı yakalandı:
  - FSM'in `maks_G`'si 0
  - FSM'e ReLU tablosunun gitmemesi
  - FSM'in `kom_bitti`'yi 1 çevrim geç görmesi
  - FSM'in s_a'yı güncellememesi
  - yürütücünün hedefinin hep 7 olması
  - yürütücünün `kom_bitti`'den sonra 1 çevrim beklememesi

  İki el sıkışma hatası (3. ve 6.) ilk sürümde yalnızca ÖLÇEK'teki grup sayısı kontrolüyle yakalanıyordu. Komut akışı ve bellek her ikisinde de doğru çıkıyordu. Bunun üzerine 3. kontrol (el sıkışma) eklendi; ikisi artık doğrudan yakalanıyor.
- **Sentez (Yosys, yapısal, Verilog kipinde):** Üst modül dahil `check` 0 sorun. Yeni latch yok; Egemen'in `stochastic_round.v`'sindeki uyarı duruyor (D68).
- **`run_sim.tcl`:** Sahte Vivado komutlarıyla ve Icarus ile beş test birlikte denendi, hepsi geçti.
- **Vivado (Ömer, 03.11): beş test de PASS**, gerçek bölücü IP'siyle (`tb_sistem` 21.415/21.415). **Paket 3 ve Adım 4 tamamlandı.**
- **Sonrası (03.11):** `run_sim.tcl`, IP'nin kopyasındaki göreli `gen_directory`'yi IP'nin yanındaki `gen/` klasörüne çeviriyor; böylece üretilen dosyalar geçici projenin içinde kalıyor (önceden `C:/project_2.gen`'e yazılıyordu). Vivado'da denendi (Ömer, 03.11): bu script ve `rtl/fe/run_sim.tcl` gerçek IP'yle bütün testlerde PASS.

