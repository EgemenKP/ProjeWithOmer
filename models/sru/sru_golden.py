# =============================================================================
#  sru_golden.py  —  SRU (Scaling and Rounding Unit) için Python golden model
# -----------------------------------------------------------------------------
#  Kaynak     : Shao vd., ISVLSI 2021 — Bölüm II-B-1 (s. 255), Algoritma 1 (s. 256),
#               Bölüm III-B ve Fig. 6 (s. 257), Fig. 8 (s. 258)
#  Hakem      : NITI, IEEE TPDS 2022 — Bölüm 3.2, 3.4, Alg. 1-3 (s. 3252-3254)
#  Hazırlayan : Claude (Ömer'in isteğiyle), 28.10.2026
#
#  Bu dosya dört iş yapar:
#    1) MODEL        : B(m), Algoritma 1, LMS, GMS ve iki aşamalı katman ölçeklemesi.
#    2) KENDİNİ KONTROL: modeli, makaleyi satır satır izleyen ayrı bir uygulamaya ve
#                       bağımsız hesaplanan ölçeklere karşı test eder.
#    3) TEST VEKTÖRLERİ: sru_vektorleri/ klasörüne testbench dosyaları yazar.
#    4) İSTATİSTİK   : seçilen kararların sonuçlarını (sapma, taşma oranı) ölçer.
#
#  Çalıştırma : python3 sru_golden.py
#  Kütüphane  : yok; yalnızca Python'un kendi 'os' ve 'random' modülleri.
# =============================================================================

import os        # os.makedirs: klasör oluşturur; os.path.join: dosya yolunu birleştirir
import random    # random.seed(n): üreteci sabitler (her çalıştırmada AYNI vektörler)
                 # random.randint(a, b): a..b arası tamsayı; random.choice(liste): rastgele eleman
                 # random.gauss(ort, std): normal dağılımlı ondalıklı sayı

# ----------------------------------------------------------------------------
# KARARLAR — değiştirmek için yalnızca bu satırları düzenle
# ----------------------------------------------------------------------------
ALT_YARI = "shao"        # SRU-a1 (Ömer, 28.10): "shao" = f[bp/2, 0] | "niti" = f[bp/2-1, 0]
TEK_BP = "makale"        # SRU-a2 (Ömer, 28.10): "makale" = f >>= 1, bp -= 1
                         #                       | "niti_kod" = NITI kodundaki yöntem (alt yarı x2)
DOYMA = False            # SRU-a3 (Ömer, 28.10): False = kırpma yok, sonuç 8 bitte sarılır
                         #                       (128 -> -128) | True = ±127'ye kırp
GMS_KAYDIRMA = "fark"    # SRU-a8 (Ömer, 28.10): "fark" = Δ = G - l | "bit_farki" = B(M) - B(Mg)
HEDEF = 7                # SRU-a4: bp = max(0, B - HEDEF); a ve e için 7 (g için m_u verilebilir)
# SRU-a5 / D28 (Egemen tarafı): B(m) = m.bit_length()  -> aşağıdaki B() fonksiyonu

KLASOR = "sru_vektorleri"


def ayar_kodu():
    """Dosyaların ilk satırına yazılan 4 sayı: alt_yari, tek_bp, doyma, gms (1/0)."""
    return [1 if ALT_YARI == "shao" else 0,
            1 if TEK_BP == "makale" else 0,
            1 if DOYMA else 0,
            1 if GMS_KAYDIRMA == "fark" else 0]


# ----------------------------------------------------------------------------
# 1) MODEL
# ----------------------------------------------------------------------------
def B(m):
    """D28: m >= 0 sayısını temsil etmek için gereken en az bit sayısı (m = 0 -> 0).
    Donanımda öncelik kodlayıcı (priority encoder): en soldaki 1'in konumu + 1."""
    return m.bit_length()          # bit_length(): sayının ikili gösterimindeki bit sayısı


def sarma8(q):
    """Tamsayının 8 bitlik ikiye tümleyen karşılığı (-128..127). Örnek: 128 -> -128."""
    return ((q + 128) % 256) - 128  # % : mod alma; Python'da sonuç hep 0..255 aralığında


def sru_yuvarla(q32, bp):
    """Shao Algoritma 1 (s. 256): int32 -> int8, bp bit sağa kaydırıp sözde-stokastik yuvarlar.
    Dönüş: (cikis8, tasma)
      cikis8 : 8 bitlik ikiye tümleyen sonuç (-128..127); RTL'in 8 bitlik çıkışı
      tasma  : 1 ise yuvarlamadan sonra büyüklük 128'e ulaştı (int8'in ±127 aralığı dışı)"""
    isaret = -1 if q32 < 0 else 1           # sgn(q32); sıfır için +1 (sonuç zaten 0)
    mutlak = abs(q32)                       # algoritma işaret-büyüklük gösterimiyle çalışır
    # Satır 2: q <- |q32|[bp+7, bp],  f <- |q32|[bp-1, 0]
    q = (mutlak >> bp) & 0xFF               # >> : sağa kaydır; & 0xFF : alttaki 8 biti al
    f = mutlak & ((1 << bp) - 1)            # (1 << bp) - 1 : alttaki bp bitin hepsi 1
    yukari = False
    if TEK_BP == "makale":
        if bp % 2 == 1:                     # Satır 3-5: bp tekse f'nin en alt bitini at
            f = f >> 1
            bp = bp - 1
        h = bp // 2                         # yarı uzunluk
        if bp > 0:
            ust = f >> h                    # f[bp-1, bp/2]  (üst yarı, h bit)
            if ALT_YARI == "shao":
                alt = f & ((1 << (h + 1)) - 1)   # f[bp/2, 0]   (Shao'daki yazım, h+1 bit)
            else:
                alt = f & ((1 << h) - 1)         # f[bp/2-1, 0] (NITI Alg. 3, h bit)
            yukari = ust > alt              # Satır 6
    else:                                   # "niti_kod": ti_torch.py PstoShift (satır 48-69)
        h = bp // 2
        if bp > 0:
            ust = f >> h
            alt = f & ((1 << h) - 1)
            if bp % 2 == 1:
                alt = alt * 2               # tek kaydırmada alt yarı 2 ile çarpılır
            yukari = ust > alt
    if yukari:
        q = q + 1                           # Satır 7
    q = q * isaret                          # Satır 9: işareti geri koy
    tasma = 1 if abs(q) >= 128 else 0
    if DOYMA:
        q = max(-127, min(127, q))          # SRU-a3 alternatifi: ±127'ye kırp
    return sarma8(q), tasma


def lms(grup):
    """1. aşama, Local Maximum Scaling (III-B, Fig. 6).
    grup: int32 değer listesi (grubun nasıl oluştuğu açık nokta, SRU-a7).
    Dönüş: (cikislar8, tasmalar, M_yerel, B_yerel, l)"""
    M_yerel = 0
    for x in grup:                          # yerel maksimum: mutlak değerlerin en büyüğü (SRU-a6)
        if abs(x) > M_yerel:
            M_yerel = abs(x)
    B_yerel = B(M_yerel)
    l = max(0, B_yerel - HEDEF)             # SRU-a4 (NITI Alg. 1 satır 4)
    cikislar = []
    tasmalar = []
    for x in grup:
        c, t = sru_yuvarla(x, l)
        cikislar.append(c)                  # tampona (buffer) giden 8 bitlik değer
        tasmalar.append(t)
    return cikislar, tasmalar, M_yerel, B_yerel, l


def gms_kaydirma_miktari(G, l, B_global, B_yerel):
    """SRU-a8: GMS'de grubun kaydırma miktarı."""
    if GMS_KAYDIRMA == "fark":
        return G - l                        # kaydırma miktarlarının farkı
    return max(0, B_global - B_yerel)       # metnin harfiyen okuması (alternatif)


def katman(gruplar):
    """İki aşamalı ölçekleme (Fig. 6): önce her grup LMS'ten geçer; katman bitince
    global maksimum bulunur ve tampondaki 8 bitlik değerler GMS'ten geçer.
    Dönüş: (G, B_global, grup_sonuclari)
      grup_sonuclari[i] = {"M", "B", "l", "delta", "lms8", "lms_tasma", "gms8", "gms_tasma"}"""
    lms_sonuc = [lms(g) for g in gruplar]
    M_global = max(s[2] for s in lms_sonuc)   # global maksimum = yerel maksimumların en büyüğü
    B_global = B(M_global)
    G = max(0, B_global - HEDEF)              # katmanın toplam kaydırması; s_çıkış = s_giriş + G
    sonuclar = []
    for (lms8, lms_t, M_yerel, B_yerel, l) in lms_sonuc:
        d = gms_kaydirma_miktari(G, l, B_global, B_yerel)
        gms8 = []
        gms_t = []
        for z in lms8:                         # GMS, tamponda saklanan 8 bitlik değeri okur
            c, t = sru_yuvarla(z, d)
            gms8.append(c)
            gms_t.append(t)
        sonuclar.append({"M": M_yerel, "B": B_yerel, "l": l, "delta": d,
                         "lms8": lms8, "lms_tasma": lms_t, "gms8": gms8, "gms_tasma": gms_t})
    return G, B_global, sonuclar


# ----------------------------------------------------------------------------
# 2) BAĞIMSIZ REFERANSLAR (yalnızca kontrol için)
# ----------------------------------------------------------------------------
def B_ref(m):
    """B'nin metin tabanlı bağımsız hesabı: bin(5) = '0b101' -> 3 bit."""
    if m == 0:
        return 0
    return len(bin(m)) - 2                  # bin(): sayının ikili metni ('0b' önekiyle)


def bitler(x, ust, alt):
    """x'in [ust, alt] bit aralığı; ust < alt ise boş aralık (0). Alg. 1'deki gösterim."""
    if ust < alt:
        return 0
    return (x >> alt) & ((1 << (ust - alt + 1)) - 1)


def alg1_satir_satir(q32, bp):
    """Shao Alg. 1'i satır satır, bit aralıklarıyla izleyen ayrı uygulama.
    Seçili kararları kullanır; kırpma yapmaz, sarmaz (ham tamsayı döndürür)."""
    a = abs(q32)
    q = bitler(a, bp + 7, bp)               # 2: q <- |q32|[bp+7, bp]
    f = bitler(a, bp - 1, 0)                #    f <- |q32|[bp-1, 0]
    if TEK_BP == "makale":
        if bp % 2 == 1:                     # 3-5
            f = f >> 1
            bp = bp - 1
        if ALT_YARI == "shao":
            alt = bitler(f, bp // 2, 0)     # 6: f[bp/2, 0]
        else:
            alt = bitler(f, bp // 2 - 1, 0) #    f[bp/2-1, 0]
        if bitler(f, bp - 1, bp // 2) > alt:
            q = q + 1                       # 7
    else:
        h = bp // 2
        alt = bitler(f, h - 1, 0)
        if bp % 2 == 1:
            alt = alt * 2
        if bitler(f, bp - 1, h) > alt:
            q = q + 1
    if q32 < 0:
        q = -q                              # 9
    return q


def niti_pstoshift(x, shift):
    """NITI ti_torch.py PstoShift'in (satır 48-69) PyTorch 1.7 (kesmeli //) davranışıyla
    elle yeniden yazımı. Yalnızca 'niti_kod' + doyma kontrolünde kullanılır."""
    def kes(a, b):                          # sıfıra doğru tamsayı bölme
        return abs(a) // b * (1 if a >= 0 else -1)
    rt = kes(x, 2 ** shift)
    prob = abs(x - rt * 2 ** shift)
    qp = kes(prob, 2 ** (shift // 2))
    pr = prob - qp * 2 ** (shift // 2)
    if shift % 2 == 1:
        pr = pr * 2
    karar = 0 if qp <= pr else 1
    isaret = (x > 0) - (x < 0)
    return max(-127, min(127, rt + karar * isaret))


def katman_kontrol(gruplar, G, B_global, sonuclar):
    """Katman sonucunu modelin iç değerlerinden bağımsız olarak kontrol eder:
      - G_ref ve l_ref ayrı hesaplanır,
      - her aşamanın çıkışı satır satır Alg. 1 ile yeniden üretilir,
      - taşma olmayan her çıkış gerçek değere (x / 2^G) 2 LSB'den yakın olmalı."""
    M_ref = 0
    for g in gruplar:
        for x in g:
            M_ref = max(M_ref, abs(x))
    G_ref = max(0, B_ref(M_ref) - HEDEF)
    assert G == G_ref and B_global == B_ref(M_ref), "G / B_global hatalı"
    for g, s in zip(gruplar, sonuclar):     # zip: iki listeyi eş eleman eş eleman gezer
        M_g = max(abs(x) for x in g)
        l_ref = max(0, B_ref(M_g) - HEDEF)
        assert s["M"] == M_g and s["l"] == l_ref, "yerel maksimum ya da l hatalı"
        d_ref = G_ref - l_ref if GMS_KAYDIRMA == "fark" else max(0, B_ref(M_ref) - B_ref(M_g))
        assert s["delta"] == d_ref, "GMS kaydırması hatalı"
        for x, z, zt, y, yt in zip(g, s["lms8"], s["lms_tasma"], s["gms8"], s["gms_tasma"]):
            ham = alg1_satir_satir(x, l_ref)
            beklenen_z = sarma8(max(-127, min(127, ham)) if DOYMA else ham)
            assert z == beklenen_z and zt == (1 if abs(ham) >= 128 else 0), "LMS hatalı"
            ham2 = alg1_satir_satir(z, d_ref)
            beklenen_y = sarma8(max(-127, min(127, ham2)) if DOYMA else ham2)
            assert y == beklenen_y and yt == (1 if abs(ham2) >= 128 else 0), "GMS hatalı"
            if zt == 0 and yt == 0 and GMS_KAYDIRMA == "fark":
                assert abs(y - x / 2 ** G_ref) < 2, "ölçek hatası: çıkış gerçek değerden uzak"


def oz_kontrol():
    """Modelin parçalarını bağımsız referanslara karşı test eder."""
    random.seed(11)
    # B(m): 0..2^20 tamamı + 2'nin kuvvetleri çevresi
    for m in list(range(0, 1 << 20)) + [(1 << k) + d for k in range(20, 32) for d in (-1, 0, 1)]:
        assert B(m) == B_ref(m), f"B hatalı: {m}"
    # Alg. 1: bp = 0..25, her bp için 4000 rastgele değer
    for bp in range(0, 26):
        for _ in range(4000):
            x = random.randint(-(1 << (bp + 7)) + 1, (1 << (bp + 7)) - 1)
            ham = alg1_satir_satir(x, bp)
            beklenen = sarma8(max(-127, min(127, ham)) if DOYMA else ham)
            c, t = sru_yuvarla(x, bp)
            assert c == beklenen and t == (1 if abs(ham) >= 128 else 0), (x, bp)
            assert sru_yuvarla(-x, bp)[1] == t                     # büyüklük simetrik
            if bp == 0:
                assert c == sarma8(x)                              # bp=0: değer aynen geçer
    # Katman: rastgele gruplar
    for _ in range(400):
        gruplar = rastgele_gruplar(random.randint(1, 6), random.randint(1, 16))
        G, Bg, s = katman(gruplar)
        katman_kontrol(gruplar, G, Bg, s)
        if len(set(r["B"] for r in s)) == 1:                       # tüm gruplar aynı B'de ise
            for g, r in zip(gruplar, s):                           # iki aşama = tek aşama
                assert r["gms8"] == [sru_yuvarla(x, G)[0] for x in g]


def niti_esdegerlik_kontrolu():
    """Parametre yolunun doğruluğu: kararlar NITI koduna çevrilince sonuç NITI PstoShift ile
    birebir aynı olmalı. (Kararlar sonra eski hâline döndürülür.)"""
    global ALT_YARI, TEK_BP, DOYMA         # global: fonksiyon içinden dosya düzeyi değişkeni değiştir
    eski = (ALT_YARI, TEK_BP, DOYMA)
    ALT_YARI, TEK_BP, DOYMA = "niti", "niti_kod", True
    random.seed(12)
    for bp in range(1, 26):
        for _ in range(2000):
            x = random.randint(-(1 << (bp + 7)) + 1, (1 << (bp + 7)) - 1)
            assert sru_yuvarla(x, bp)[0] == niti_pstoshift(x, bp), (x, bp)
    ALT_YARI, TEK_BP, DOYMA = eski


# ----------------------------------------------------------------------------
# 3) TEST DURUMLARI
# ----------------------------------------------------------------------------
def rastgele_gruplar(n_grup, boy):
    """Farklı ölçeklerde gruplar: her grubun değerleri ~ N(0, 2^olcek)."""
    gruplar = []
    for _ in range(n_grup):
        olcek = random.randint(0, 24)
        grup = []
        for _ in range(boy):
            x = int(random.gauss(0, 1) * (1 << olcek))
            grup.append(max(-(2 ** 31) + 1, min(2 ** 31 - 1, x)))   # int32 aralığında tut
        gruplar.append(grup)
    return gruplar


def bm_vakalari():
    """B(m) birimi için vakalar: 0, 2'nin kuvvetleri ve çevresi, 2^31, rastgele."""
    random.seed(21)
    vakalar = [0, 1, 2, 3]
    for k in range(2, 32):
        vakalar += [(1 << k) - 1, 1 << k, (1 << k) + 1]
    vakalar.append(1 << 31)                       # |-2^31| = 2^31 (B = 32)
    for _ in range(60):
        vakalar.append(random.randint(0, (1 << 31) - 1))
    sonuc = []
    for m in vakalar:
        if m <= (1 << 31):
            sonuc.append(m)
    return sonuc


def tasma_vakasi_bul(bp, isaret):
    """q = 127 iken yukarı yuvarlayan bir değer arar (128'e ulaşan vaka); yoksa None."""
    for f in range((1 << bp) - 1, -1, -1):        # range(a, b, -1): a'dan b'ye geri sayar
        x = isaret * ((127 << bp) + f)
        if sru_yuvarla(x, bp)[1] == 1:
            return x
    return None


def yuvarlama_vakalari():
    """Yuvarlama birimi (stochastic_round.v) için (q32, bp) çiftleri."""
    random.seed(31)
    vakalar = []
    # El kontrolü vakaları (PE_SRU_BASLANGIC.md 6.3 tablosundaki girişler)
    for x in [1846, 3218, -3218, 253, 338, 2044]:
        vakalar.append((x, max(0, B(abs(x)) - HEDEF)))
    # Uç değerler
    for x in [0, 1, -1, 127, -127, 128, -128, 255, -255, 256, -256,
              2 ** 31 - 1, -(2 ** 31) + 1, -(2 ** 31)]:
        vakalar.append((x, max(0, B(abs(x)) - HEDEF)))
    for bp in range(0, 26):                        # sıfır her bp ile
        vakalar.append((0, bp))
    # Eşitlik: seçili kurala göre üst yarı = alt yarı olan kesirler (karar sınırı)
    for bp in range(2, 13, 2):
        h = bp // 2
        bulunan = 0
        for f in range(1, 1 << bp):
            if ALT_YARI == "shao":
                alt = bitler(f, h, 0)
            else:
                alt = bitler(f, h - 1, 0)
            if bitler(f, bp - 1, h) == alt:
                vakalar.append((((64 + h) << bp) | f, bp))
                bulunan += 1
                if bulunan == 2:
                    break
    # Taşma: 127 + 1 = 128 (her iki işaret), bp = 2..24
    for bp in range(2, 25):
        for isaret in (1, -1):
            x = tasma_vakasi_bul(bp, isaret)
            if x is not None:
                vakalar.append((x, bp))
    # Rastgele: bp doğal (B'den) — 2000 vaka
    for _ in range(2000):
        bit = random.randint(1, 31)
        x = random.randint(-(1 << bit) + 1, (1 << bit) - 1)
        vakalar.append((x, max(0, B(abs(x)) - HEDEF)))
    # Rastgele: bp gerekenden büyük — 200 vaka (q küçülür, taşma olmaz)
    for _ in range(200):
        bit = random.randint(1, 24)
        x = random.randint(-(1 << bit) + 1, (1 << bit) - 1)
        vakalar.append((x, max(0, B(abs(x)) - HEDEF) + random.randint(1, 6)))
    return vakalar


def katman_vakalari():
    """LMS + GMS için katman vakaları: (açıklama, gruplar)."""
    random.seed(41)
    v = []
    v.append(("El kontrolü: 2 grup; büyük grup l=2, küçük grup l=0 -> G=2, Δ = 0 ve 2",
              [[300, -200, 50], [31, -20, 17]]))
    v.append(("Tüm gruplar aynı ölçekte (Δ = 0): iki aşama = tek aşama",
              [[20000, -15000, 3], [-25000, 1000, 7], [16384, -9999, 0]]))
    v.append(("Küçük grup (B < 7) ve büyük G: Δ = G",
              [[40, -63, 5], [5000000, -3000000, 123456]]))
    v.append(("Grup maksimumları 2'nin kuvveti: 128, 256, 2^20",
              [[128, -5], [256, 17], [-(1 << 20), 99]]))
    v.append(("Küçük Δ: Δ = 1 ve Δ = 2",
              [[1000, -700, 3], [2000, -1500, 9], [4000, 3001, -12]]))
    v.append(("Taşma: LMS'te 127 yukarı yuvarlanıp 128 olur (doyma yok -> 8 bitte -128)",
              [[(127 << 4) + 8, -100, 5], [3000, -50, 1]]))
    v.append(("Sıfır grup (B = 0)",
              [[0, 0, 0, 0], [500, -300, 2, 0]]))
    v.append(("int32 uçları",
              [[2 ** 31 - 1, -(2 ** 31) + 1, 1], [12345, -1]]))
    v.append(("Rastgele: 4 grup x 16 değer", rastgele_gruplar(4, 16)))
    v.append(("Rastgele: 8 grup x 16 değer", rastgele_gruplar(8, 16)))
    v.append(("Rastgele: 16 grup x 16 değer", rastgele_gruplar(16, 16)))
    v.append(("Rastgele: 5 grup x 7 değer (grup boyu 16 değilse)", rastgele_gruplar(5, 7)))
    return v


# ----------------------------------------------------------------------------
# 4) DOSYA YAZMA / GERİ OKUMA
# ----------------------------------------------------------------------------
def hex32(x):
    """İşaretli 32 bit sayıyı 8 haneli hex'e çevirir (ikiye tümleyen)."""
    return format(x & 0xFFFFFFFF, "08X")    # format(sayı, "08X"): 8 haneli büyük harf hex


def hex8(x):
    return format(x & 0xFF, "02X")


def dosyalari_yaz(bm, yuv, kat):
    os.makedirs(KLASOR, exist_ok=True)
    ayar = " ".join(str(a) for a in ayar_kodu())
    # B(m): ondalık ve hex
    with open(os.path.join(KLASOR, "sru_bm.txt"), "w") as f:
        f.write(f"{len(bm)}\n")
        for m in bm:
            f.write(f"{m} {B(m)}\n")
    with open(os.path.join(KLASOR, "sru_bm.hex"), "w") as f:
        for m in bm:
            f.write(hex32(m) + hex8(B(m)) + "\n")           # [39:8] m, [7:0] B
    # Yuvarlama birimi: ondalık ve hex
    with open(os.path.join(KLASOR, "sru_yuvarla.txt"), "w") as f:
        f.write(ayar + "\n")
        f.write(f"{len(yuv)}\n")
        for (x, bp) in yuv:
            c, t = sru_yuvarla(x, bp)
            f.write(f"{x} {bp} {c} {t}\n")
    with open(os.path.join(KLASOR, "sru_yuvarla.hex"), "w") as f:
        for (x, bp) in yuv:
            c, _ = sru_yuvarla(x, bp)
            f.write(hex32(x) + hex8(bp) + hex8(c) + "\n")   # [47:16] q32, [15:8] bp, [7:0] çıkış
    # Katman (LMS + GMS)
    with open(os.path.join(KLASOR, "sru_katman.txt"), "w") as f:
        f.write(ayar + "\n")
        f.write(f"{len(kat)}\n")
        for case_no, (_, gruplar) in enumerate(kat):
            G, Bg, sonuclar = katman(gruplar)
            f.write(f"{case_no} {len(gruplar)} {G} {Bg}\n")
            for grup_no, (g, s) in enumerate(zip(gruplar, sonuclar)):
                f.write(f"{grup_no} {len(g)} {s['M']} {s['B']} {s['l']} {s['delta']}\n")
                for i in range(len(g)):
                    f.write(f"{g[i]} {s['lms8'][i]} {s['lms_tasma'][i]} "
                            f"{s['gms8'][i]} {s['gms_tasma'][i]}\n")


def dosyalari_geri_oku():
    """Yazılan dosyaları geri okur ve modeli dosyadaki girişlerle yeniden çalıştırır."""
    def sayilar(ad):
        with open(os.path.join(KLASOR, ad)) as f:
            return iter([int(s) for s in f.read().split()])  # iter/next: sırayla tüketme
    # B(m)
    it = sayilar("sru_bm.txt")
    n = next(it)
    for _ in range(n):
        m, b = next(it), next(it)
        assert B(m) == b
    assert next(it, None) is None
    with open(os.path.join(KLASOR, "sru_bm.hex")) as f:
        satirlar = f.read().split()
    assert len(satirlar) == n
    for s in satirlar:
        m, b = int(s[0:8], 16), int(s[8:10], 16)          # int(metin, 16): hex'i sayıya çevir
        assert B(m) == b
    # Yuvarlama
    it = sayilar("sru_yuvarla.txt")
    assert [next(it) for _ in range(4)] == ayar_kodu()
    n = next(it)
    for _ in range(n):
        x, bp, c, t = next(it), next(it), next(it), next(it)
        assert sru_yuvarla(x, bp) == (c, t)
    assert next(it, None) is None
    with open(os.path.join(KLASOR, "sru_yuvarla.hex")) as f:
        satirlar = f.read().split()
    assert len(satirlar) == n
    for s in satirlar:
        x = int(s[0:8], 16)
        if x >= 2 ** 31:
            x -= 2 ** 32                                    # ikiye tümleyenden işaretliye
        bp = int(s[8:10], 16)
        c = int(s[10:12], 16)
        assert c == (sru_yuvarla(x, bp)[0] & 0xFF)
    # Katman
    it = sayilar("sru_katman.txt")
    assert [next(it) for _ in range(4)] == ayar_kodu()
    n_case = next(it)
    toplam = 0
    for case_no in range(n_case):
        assert next(it) == case_no
        n_grup, G_d, Bg_d = next(it), next(it), next(it)
        gruplar = []
        beklenen = []
        for grup_no in range(n_grup):
            assert next(it) == grup_no
            boy = next(it)
            bilgi = [next(it) for _ in range(4)]           # M, B, l, delta
            g = []
            satir = []
            for _ in range(boy):
                x, z, zt, y, yt = next(it), next(it), next(it), next(it), next(it)
                g.append(x)
                satir.append((z, zt, y, yt))
            gruplar.append(g)
            beklenen.append((bilgi, satir))
        G, Bg, sonuclar = katman(gruplar)
        assert (G, Bg) == (G_d, Bg_d)
        for s, (bilgi, satir) in zip(sonuclar, beklenen):
            assert [s["M"], s["B"], s["l"], s["delta"]] == bilgi
            yeniden = list(zip(s["lms8"], s["lms_tasma"], s["gms8"], s["gms_tasma"]))
            assert yeniden == satir
            toplam += len(satir)
    assert next(it, None) is None
    return toplam


# ----------------------------------------------------------------------------
# 5) OKUNUR DÖKÜM ve İSTATİSTİK
# ----------------------------------------------------------------------------
def adim_adim(q32, bp):
    """Alg. 1'in seçili kararlarla adım adım dökümü (metin satırları)."""
    s = []
    bp0 = bp                                # bp aşağıda değişebilir; sonuç için ilk değeri sakla
    a = abs(q32)
    s.append(f"q32 = {q32}, bp = {bp}, |q32| = {a} = {format(a, 'b')}₂")
    q = (a >> bp) & 0xFF
    f = a & ((1 << bp) - 1)
    s.append(f"  satır 2: q = |q32|[{bp + 7}, {bp}] = {q},  f = |q32|[{bp - 1}, 0] = {f}"
             f" = {format(f, 'b').zfill(max(bp, 1))}₂")              # zfill: başa 0 ekler
    if bp % 2 == 1:
        f = f >> 1
        bp = bp - 1
        s.append(f"  satır 3-5: bp tek -> f = f >> 1 = {f}, bp = {bp}")
    h = bp // 2
    if bp > 0:
        ust = f >> h
        alt = f & ((1 << (h + 1)) - 1) if ALT_YARI == "shao" else f & ((1 << h) - 1)
        aralik = f"[{h}, 0]" if ALT_YARI == "shao" else f"[{h - 1}, 0]"
        s.append(f"  satır 6: üst f[{bp - 1}, {h}] = {ust},  alt f{aralik} = {alt}  ->  "
                 f"{'yukarı yuvarla' if ust > alt else 'yuvarlama yok'}")
    else:
        s.append("  satır 6: bp = 0, karşılaştırılacak kesir yok -> yuvarlama yok")
    c, t = sru_yuvarla(q32, bp0)
    s.append(f"  sonuç: {c}" + ("  (taşma: büyüklük 128'e ulaştı, 8 bitte sarıldı)" if t else ""))
    return s


def istatistik(adet=200000):
    """Seçili kararlarla rastgele int32 değerlerde (bp doğal) yukarı yuvarlama oranı,
    ortalama hata ve 128 taşması oranı."""
    random.seed(51)
    yukari = 0
    tasma = 0
    hata_toplam = 0.0
    for _ in range(adet):
        bit = random.randint(8, 31)
        x = random.randint(1, (1 << bit) - 1)
        bp = max(0, B(x) - HEDEF)
        c, t = sru_yuvarla(x, bp)
        tasma += t
        gercek = x / 2 ** bp
        deger = 128 if t else c                        # sarmadan önceki değer
        if deger > (x >> bp):
            yukari += 1
        hata_toplam += deger - gercek
    return yukari / adet, hata_toplam / adet, tasma / adet


def okunur_yaz(kat):
    p = []
    p.append("SRU golden model — okunur döküm")
    p.append(f"Kararlar: ALT_YARI={ALT_YARI}, TEK_BP={TEK_BP}, DOYMA={DOYMA}, "
             f"GMS_KAYDIRMA={GMS_KAYDIRMA}, HEDEF={HEDEF}, B = bit_length (D28)")
    p.append("")
    p.append("== Alg. 1 adım adım (el kontrolü vakaları) ==")
    for x in [1846, 3218, 338, 2044]:
        p += adim_adim(x, max(0, B(abs(x)) - HEDEF))
        p.append("")
    p.append("== Katman case 0 ==")
    aciklama, gruplar = kat[0]
    G, Bg, sonuclar = katman(gruplar)
    p.append(f"{aciklama}")
    p.append(f"B_global = {Bg}, G = {G}  (ölçek üssü: s_çıkış = s_giriş + {G})")
    for i, (g, s) in enumerate(zip(gruplar, sonuclar)):
        p.append(f"-- grup {i}: M_yerel = {s['M']}, B_yerel = {s['B']}, l = {s['l']}, "
                 f"Δ = {s['delta']}")
        p.append(f"{'x (int32)':>12} {'LMS int8':>9} {'GMS int8':>9} {'gerçek x/2^G':>13}")
        for x, z, y in zip(g, s["lms8"], s["gms8"]):
            p.append(f"{x:>12} {z:>9} {y:>9} {x / 2 ** G:>13.3f}")
    with open(os.path.join(KLASOR, "OKUNUR.txt"), "w") as f:
        f.write("\n".join(p) + "\n")


def case_listesi_yaz(kat):
    with open(os.path.join(KLASOR, "CASE_LISTESI.txt"), "w") as f:
        for case_no, (aciklama, gruplar) in enumerate(kat):
            G, Bg, s = katman(gruplar)
            tasma = sum(sum(r["lms_tasma"]) + sum(r["gms_tasma"]) for r in s)
            f.write(f"katman case {case_no}: {len(gruplar)} grup, G = {G}, "
                    f"taşma sayısı = {tasma} — {aciklama}\n")


# ----------------------------------------------------------------------------
# Ana program
# ----------------------------------------------------------------------------
def main():
    oz_kontrol()
    print("1) Öz kontrol: B(m), Alg. 1 (bp = 0..25) ve katman, bağımsız referanslarla aynı.")
    niti_esdegerlik_kontrolu()
    print("2) Kararlar NITI koduna çevrilince sonuç NITI PstoShift ile birebir aynı.")

    bm = bm_vakalari()
    yuv = yuvarlama_vakalari()
    kat = katman_vakalari()
    for (_, gruplar) in kat:
        G, Bg, s = katman(gruplar)
        katman_kontrol(gruplar, G, Bg, s)
    dosyalari_yaz(bm, yuv, kat)
    n_kat = dosyalari_geri_oku()
    okunur_yaz(kat)
    case_listesi_yaz(kat)
    n_tasma_yuv = sum(sru_yuvarla(x, bp)[1] for (x, bp) in yuv)
    print(f"3) Vektörler yazıldı ve geri okunup doğrulandı: B(m) {len(bm)}, "
          f"yuvarlama {len(yuv)} (taşma {n_tasma_yuv}), katman {len(kat)} case / {n_kat} değer.")

    yukari, ort_hata, tasma = istatistik()
    print(f"4) Seçili kararlarla 200.000 rastgele değer: yukarı yuvarlama %{100 * yukari:.1f}, "
          f"ortalama hata {ort_hata:+.3f} LSB, 128 taşması %{100 * tasma:.2f}")


if __name__ == "__main__":
    main()
