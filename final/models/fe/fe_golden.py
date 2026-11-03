# =============================================================================
#  fe_golden.py  —  Fonksiyon motoru (function engine) golden modeli:
#                   ReLU (ileri + geri) ve ağırlık güncelleme (Weight Update, WU)
# -----------------------------------------------------------------------------
#  Shao       : Fig. 8 ve III-D (s. 258) — ReLU ve Weight Update fonksiyon motorunda;
#               PE dizisinin tüm çıkışları (g dahil) SRU'dan geçer. Davranış yazılmamış.
#  NITI       : Kural "Shao sessizse NITI" (Ömer, 31.10). Alg. 1 satır 12-14 ve §3.3
#               (s. 3252-3253); kod ti_torch.py: TiReLU (268-290), UpdateWeight (16-21),
#               grad_calc (135-147), int8_clip (71-72).
#  Bağımlılık : sru_golden.py — Alg. 1 ve B(m) için tek kaynak (SRU kararları orada).
#               Bu dosya sru_golden.py'yi DEĞİŞTİRMEZ, yalnızca fonksiyonlarını kullanır.
#  Hazırlayan : Claude (Ömer'in isteğiyle), 31.10.2026
#  Çalıştırma : python3 fe_golden.py   (sru_golden.py aynı klasörde olmalı)
#  Kütüphane  : yalnızca Python'un kendi modülleri (os, random, math)
# =============================================================================

import os          # os.makedirs: klasör oluşturur; os.path.join: dosya yolunu birleştirir
import random      # random.seed(n): üreteci sabitler (her çalıştırmada AYNI vektörler)
                   # random.randint(a, b): a..b arası tamsayı
import sru_golden as SRU   # import ... as: modülü kısa adla (SRU.) kullan

# ----------------------------------------------------------------------------
# KARARLAR
# ----------------------------------------------------------------------------
# K1  (Ömer, 31.10): Pooling şimdilik yok -> bu dosyada Pooling modeli yok.
HEDEF_G = "m_u"         # K2a (Ömer, 31.10): g32 SRU'dan hedef m_u bitle geçer (NITI §3.3)
                        #     "7" = a ve e gibi 7 bit (alternatif, seçilmedi)
WU_DOYMA = True         # K2b (Ömer, 31.10): w - g sonucu ±127'ye doyurulur (NITI int8_clip)
GMS_WU_ONCESI = True    # K3  (Claude, Ömer'in "Shao'ya en uygun olanı seç" talimatıyla, 31.10):
                        #     g'ye ağırlık güncellemeden önce GMS de uygulanır

KLASOR = "fe_vektorleri"


def fe_ayar_kodu():
    """Vektör dosyalarına yazılan 3 sayı: hedef_g (1 = m_u), wu_doyma (1/0), gms_wu (1/0)."""
    return [1 if HEDEF_G == "m_u" else 0, 1 if WU_DOYMA else 0, 1 if GMS_WU_ONCESI else 0]


# ----------------------------------------------------------------------------
# 1) ReLU
# ----------------------------------------------------------------------------
def relu_ileri(a):
    """FP: a <- max(0, a). a int8'dir; SRU ±127'ye doyurduğu için (SRU-a3) -128 gelmez, ama birim
    -128..127 aralığının tamamında doğru çalışır.
    Ölçek üssü s_a değişmez."""
    if a > 0:
        return a
    return 0


def relu_geri(e, a):
    """BP: hata yalnızca ileri geçişte a > 0 olan konumdan geçer (NITI: act > 0, kesin büyük).
    a, maskenin kaynağıdır: ReLU'nun girişi de çıkışı da olabilir, çünkü a > 0 ile
    relu_ileri(a) > 0 her değer için aynıdır (öz kontrolde 256 değerin hepsi denenir)."""
    if a > 0:
        return e
    return 0


def relu_ileri_ref(a):
    """Bağımsız, bit düzeyinde tanım (yalnızca kontrol için): işaret biti 1 ya da değer 0 ise 0."""
    bayt = a & 0xFF                       # & 0xFF: değerin 8 bitlik ikiye tümleyen hali
    if (bayt & 0x80) != 0 or bayt == 0:   # 0x80: işaret biti
        return 0
    return bayt


def relu_geri_ref(e, a):
    bayt = a & 0xFF
    if (bayt & 0x80) == 0 and bayt != 0:
        return e
    return 0


# ----------------------------------------------------------------------------
# 2) AĞIRLIK GÜNCELLEME (WU)
#    g32 (WG çıkışı, int32) -> SRU 1. aşama (LMS, hedef m_u) -> SRU 2. aşama (GMS)
#    -> g8 -> w_yeni = doyur(w - g8)
# ----------------------------------------------------------------------------
def g_hedefi(m_u):
    """K2a: gradyanın SRU hedef genişliği."""
    if HEDEF_G == "m_u":
        return m_u
    return 7


def lms_hedefli(grup, hedef):
    """SRU 1. aşama (LMS), hedef genişlik parametreli.
    sru_golden.lms ile aynı mantık; hedef = 7'de birebir aynı olduğu öz kontrolde test edilir.
    Dönüş: (cikislar8, tasmalar, M_yerel, B_yerel, l)"""
    M_yerel = 0
    for x in grup:                        # yerel maksimum: mutlak değerlerin en büyüğü
        if abs(x) > M_yerel:
            M_yerel = abs(x)
    B_yerel = SRU.B(M_yerel)              # D28: bit_length
    l = max(0, B_yerel - hedef)           # NITI: b - m_u bit kaydırma (Alg. 1 satır 13)
    cikislar = []
    tasmalar = []
    for x in grup:
        c, t = SRU.sru_yuvarla(x, l)      # Shao Alg. 1 (SRU kararlarıyla)
        cikislar.append(c)
        tasmalar.append(t)
    return cikislar, tasmalar, M_yerel, B_yerel, l


def agirlik_guncelle(w, g8):
    """Alg. 1 satır 14: w <- w - g. Fark -255..255 aralığında (9 bit işaretli yeter).
    K2b: ±127'ye doyur (NITI int8_clip); False olursa 8 bitte sarılır."""
    fark = w - g8
    if WU_DOYMA:
        return max(-127, min(127, fark))
    return SRU.sarma8(fark)


def wu_katman(g_gruplar, w_gruplar, m_u):
    """Bir katmanın ağırlık güncellemesi.
      g_gruplar : WG'nin int32 çıktıları, SRU gruplarına bölünmüş (liste listesi)
      w_gruplar : aynı düzende int8 ağırlıklar
      m_u       : güncelleme bit genişliği (NITI'de 5 -> 4 -> 3)
    Dönüş: (G, B_global, sonuclar); sonuclar[i] = {"M","B","l","delta","g8_lms","g8","w_yeni"}"""
    hedef = g_hedefi(m_u)
    lms_sonuc = []
    for g in g_gruplar:
        lms_sonuc.append(lms_hedefli(g, hedef))
    B_global = max(s[3] for s in lms_sonuc)   # B monoton: B(global maks) = yerel B'lerin en büyüğü
    G = max(0, B_global - hedef)              # katmanın toplam kaydırması
    sonuclar = []
    for (g8_lms, tasma_lms, M, B_yerel, l), w_grup in zip(lms_sonuc, w_gruplar):
        if hedef <= 6:                        # hedef <= 6 iken |q| en fazla 2^hedef <= 64: taşma olamaz
            assert sum(tasma_lms) == 0
        if GMS_WU_ONCESI:
            d = SRU.gms_kaydirma_miktari(G, l, B_global, B_yerel)   # SRU-a8: Δ = G - l
            g8 = []
            for z in g8_lms:
                c, t = SRU.sru_yuvarla(z, d)                        # SRU 2. aşama (GMS)
                if hedef <= 6:
                    assert t == 0
                g8.append(c)
        else:
            d = 0
            g8 = list(g8_lms)                 # list(): kopya
        w_yeni = []
        for w, g in zip(w_grup, g8):
            w_yeni.append(agirlik_guncelle(w, g))
        sonuclar.append({"M": M, "B": B_yerel, "l": l, "delta": d,
                         "g8_lms": g8_lms, "g8": g8, "w_yeni": w_yeni})
    return G, B_global, sonuclar


# ----------------------------------------------------------------------------
# 3) BAĞIMSIZ KONTROLLER
# ----------------------------------------------------------------------------
def niti_wu(g32_liste, w_liste, mu):
    """NITI'nin ağırlık güncellemesinin saf Python yeniden yazımı (tek grup = tüm katman):
    ti_torch.py grad_calc (135-147) + PstoShift + UpdateWeight (21): int8_clip(w - g).
    RangeEstimate = ceil(log2(max|g|)); burada tamsayıyla: (M - 1).bit_length()."""
    M = max(abs(x) for x in g32_liste)
    bw = 0 if M == 0 else (M - 1).bit_length()
    shift = bw - mu
    if bw == 0:
        g = [0] * len(g32_liste)
    elif shift < 1:
        g = list(g32_liste)                    # NITI: kaydırmadan int8'e çevirir (değerler küçük)
    else:
        g = [SRU.niti_pstoshift(x, shift) for x in g32_liste]
    return [max(-127, min(127, w - gg)) for w, gg in zip(w_liste, g)]


def niti_kipine_gec():
    """SRU kararlarını geçici olarak NITI koduna çevirir; eski hali döndürür."""
    eski = (SRU.ALT_YARI, SRU.TEK_BP, SRU.DOYMA)
    SRU.ALT_YARI, SRU.TEK_BP, SRU.DOYMA = "niti", "niti_kod", True
    return eski


def niti_kipinden_cik(eski):
    SRU.ALT_YARI, SRU.TEK_BP, SRU.DOYMA = eski


def rastgele_g_gruplar(n_grup, boy, olcek_ust=24):
    """Farklı ölçeklerde gradyan grupları (int32 aralığında)."""
    gruplar = []
    for _ in range(n_grup):
        olcek = random.randint(0, olcek_ust)
        grup = []
        for _ in range(boy):
            x = int(random.gauss(0, 1) * (1 << olcek))      # gauss: normal dağılımlı sayı
            grup.append(max(-(2 ** 31) + 1, min(2 ** 31 - 1, x)))
        gruplar.append(grup)
    return gruplar


def rastgele_w(n):
    return [random.randint(-127, 127) for _ in range(n)]


def oz_kontrol():
    random.seed(101)
    # (a) ReLU: 256 x 256 girişin hepsi, bağımsız bit düzeyi tanımla
    for a in range(-128, 128):
        assert relu_ileri(a) == relu_ileri_ref(a)
        assert (a > 0) == (relu_ileri(a) > 0)           # maske kaynağı giriş ya da çıkış olabilir
        for e in range(-128, 128):
            assert relu_geri(e, a) == relu_geri_ref(e, a)
            assert relu_geri(e, a) == relu_geri(e, relu_ileri(a))
    # (b) LMS tutarlılığı: hedef = 7'de teslim edilen SRU modeliyle birebir aynı
    for _ in range(500):
        gruplar = rastgele_g_gruplar(random.randint(1, 6), random.randint(1, 16))
        for g in gruplar:
            assert lms_hedefli(g, 7) == SRU.lms(g)
        G_s, Bg_s, s_sru = SRU.katman(gruplar)
        hedef_eski = HEDEF_G
        globals()["HEDEF_G"] = "7"                          # geçici: hedef 7
        G_w, Bg_w, s_wu = wu_katman(gruplar, [[0] * len(g) for g in gruplar], 5)
        globals()["HEDEF_G"] = hedef_eski
        assert (G_w, Bg_w) == (G_s, Bg_s)
        if GMS_WU_ONCESI:
            for a, b in zip(s_wu, s_sru):
                assert a["g8"] == b["gms8"] and a["delta"] == b["delta"]
    # (c) NITI eşdeğerliği: SRU kararları NITI koduna çevrilince, tek grupta NITI ile birebir aynı.
    #     2'nin kuvveti olan ve 2^24'ü aşan maksimumlar hariç (orada B tanımları farklı, bkz. README).
    eski = niti_kipine_gec()
    sayac = 0
    while sayac < 3000:
        boy = random.randint(1, 32)
        olcek = random.randint(0, 23)
        g = [int(random.gauss(0, 1) * (1 << olcek)) for _ in range(boy)]
        M = max(abs(x) for x in g)
        if M == 0 or M >= (1 << 24) or (M & (M - 1)) == 0:   # (M & (M-1)) == 0: 2'nin kuvveti
            continue
        w = rastgele_w(boy)
        m_u = random.randint(1, 5)
        _, _, s = wu_katman([g], [w], m_u)
        assert s[0]["w_yeni"] == niti_wu(g, w, m_u), (g, w, m_u)
        sayac += 1
    niti_kipinden_cik(eski)
    # (d) Katman: global ölçek, sınırlar ve işaret
    for _ in range(500):
        m_u = random.randint(1, 5)
        gruplar = rastgele_g_gruplar(random.randint(1, 8), random.randint(1, 16))
        w_gruplar = [rastgele_w(len(g)) for g in gruplar]
        G, Bg, s = wu_katman(gruplar, w_gruplar, m_u)
        for g, w_grup, r in zip(gruplar, w_gruplar, s):
            for x, w, y, wy in zip(g, w_grup, r["g8"], r["w_yeni"]):
                assert abs(y) <= (1 << m_u)                          # en fazla 2^m_u
                assert y == 0 or (y > 0) == (x > 0)                  # işaret korunur
                assert abs(y - x / 2 ** G) < 2                       # tek (global) ölçek: 2^G
                assert -127 <= wy <= 127
                assert wy == sorted([-127, w - y, 127])[1]           # bağımsız doyma (ortanca)


# ----------------------------------------------------------------------------
# 4) TEST DURUMLARI
# ----------------------------------------------------------------------------
def katman_vakalari():
    """Ağırlık güncelleme katman vakaları: (açıklama, m_u, g_gruplar, w_gruplar)."""
    random.seed(202)
    v = []
    v.append(("El kontrolü: 2 grup, m_u = 5. Büyük grup l = 4, küçük grup l = 0 -> G = 4, Δ = 0 ve 4",
              5, [[300, -200, 50], [31, -20, 17]], [[10, -10, 0], [5, 100, -100]]))
    for m_u in range(1, 6):
        v.append((f"Aynı gradyan, m_u = {m_u}: adım büyüklüğünü m_u belirler",
                  m_u, [[9000, -4500, 700, -1], [120, -60, 30, 0]], [[0, 0, 0, 0], [0, 0, 0, 0]]))
    v.append(("Doyma: w = 127 ve g < 0, w = -127 ve g > 0 (±127'ye doyar)",
              5, [[-30000, 30000, -15000, 15000]], [[127, -127, 120, -120]]))
    v.append(("Tek grup (Δ = 0)", 4, [[5000, -2500, 1234, -999, 0]], [[1, 2, 3, 4, 5]]))
    v.append(("Sıfır gradyan grubu (B = 0)", 5, [[0, 0, 0], [800, -400, 3]], [[7, -7, 0], [7, -7, 0]]))
    v.append(("B <= m_u: kaydırma yok, g aynen geçer", 5, [[3, -2, 1, 31]], [[10, 10, 10, 10]]))
    v.append(("Maksimum 2'nin kuvveti (1024): D28'de B = 11", 5, [[1024, -512, 1, 1023]], [[0, 0, 0, 0]]))
    v.append(("int32 uçları", 5, [[2 ** 31 - 1, -(2 ** 31) + 1, 1], [12345, -1, 0]],
              [[0, 50, -50], [0, 0, 0]]))
    for n_grup, boy in [(4, 16), (8, 16), (16, 16), (5, 7)]:
        m_u = random.randint(1, 5)
        gruplar = rastgele_g_gruplar(n_grup, boy)
        v.append((f"Rastgele: {n_grup} grup x {boy} değer, m_u = {m_u}",
                  m_u, gruplar, [rastgele_w(boy) for _ in range(n_grup)]))
    return v


# ----------------------------------------------------------------------------
# 5) DOSYA YAZMA / GERİ OKUMA
# ----------------------------------------------------------------------------
def h8(x):
    return format(x & 0xFF, "02X")        # 2 haneli hex, ikiye tümleyen


def dosyalari_yaz(kat):
    os.makedirs(KLASOR, exist_ok=True)
    # ReLU: 65536 satır, tüm (a, e) çiftleri
    with open(os.path.join(KLASOR, "relu.hex"), "w") as f:
        for a in range(-128, 128):
            for e in range(-128, 128):
                f.write(h8(a) + h8(e) + h8(relu_ileri(a)) + h8(relu_geri(e, a)) + "\n")
    # Çıkarma + doyma: 65536 satır, tüm (w, g) çiftleri
    with open(os.path.join(KLASOR, "wu_cikarma.hex"), "w") as f:
        for w in range(-128, 128):
            for g in range(-128, 128):
                f.write(h8(w) + h8(g) + h8(agirlik_guncelle(w, g)) + "\n")
    # Katman (LMS + GMS + çıkarma)
    sru_ayar = " ".join(str(x) for x in SRU.ayar_kodu())
    fe_ayar = " ".join(str(x) for x in fe_ayar_kodu())
    with open(os.path.join(KLASOR, "wu_katman.txt"), "w") as f:
        f.write(sru_ayar + "\n" + fe_ayar + "\n" + f"{len(kat)}\n")
        for case_no, (_, m_u, gruplar, w_gruplar) in enumerate(kat):
            G, Bg, s = wu_katman(gruplar, w_gruplar, m_u)
            f.write(f"{case_no} {m_u} {len(gruplar)} {G} {Bg}\n")
            for grup_no, (g, w_grup, r) in enumerate(zip(gruplar, w_gruplar, s)):
                f.write(f"{grup_no} {len(g)} {r['M']} {r['B']} {r['l']} {r['delta']}\n")
                for i in range(len(g)):
                    f.write(f"{g[i]} {w_grup[i]} {r['g8_lms'][i]} {r['g8'][i]} {r['w_yeni'][i]}\n")


def isaretli8(h):
    """2 haneli hex -> işaretli sayı (-128..127)."""
    x = int(h, 16)                          # int(metin, 16): hex'i sayıya çevir
    return x - 256 if x >= 128 else x


def dosyalari_geri_oku():
    """Dosyaları geri okuyup modeli dosyadaki girişlerle yeniden çalıştırır."""
    with open(os.path.join(KLASOR, "relu.hex")) as f:
        satirlar = f.read().split()
    assert len(satirlar) == 65536
    for s in satirlar:
        a, e, ac, ec = (isaretli8(s[i:i + 2]) for i in (0, 2, 4, 6))
        assert relu_ileri(a) == ac and relu_geri(e, a) == ec
    with open(os.path.join(KLASOR, "wu_cikarma.hex")) as f:
        satirlar = f.read().split()
    assert len(satirlar) == 65536
    for s in satirlar:
        w, g, wy = (isaretli8(s[i:i + 2]) for i in (0, 2, 4))
        assert agirlik_guncelle(w, g) == wy
    with open(os.path.join(KLASOR, "wu_katman.txt")) as f:
        it = iter([int(x) for x in f.read().split()])   # iter/next: sırayla tüket
    assert [next(it) for _ in range(4)] == SRU.ayar_kodu()
    assert [next(it) for _ in range(3)] == fe_ayar_kodu()
    n_case = next(it)
    toplam = 0
    for case_no in range(n_case):
        assert next(it) == case_no
        m_u, n_grup, G_d, Bg_d = next(it), next(it), next(it), next(it)
        gruplar, w_gruplar, beklenen = [], [], []
        for grup_no in range(n_grup):
            assert next(it) == grup_no
            boy = next(it)
            bilgi = [next(it) for _ in range(4)]
            g, w, satir = [], [], []
            for _ in range(boy):
                x, ww, z, y, wy = (next(it) for _ in range(5))
                g.append(x)
                w.append(ww)
                satir.append((z, y, wy))
            gruplar.append(g)
            w_gruplar.append(w)
            beklenen.append((bilgi, satir))
        G, Bg, s = wu_katman(gruplar, w_gruplar, m_u)
        assert (G, Bg) == (G_d, Bg_d)
        for r, (bilgi, satir) in zip(s, beklenen):
            assert [r["M"], r["B"], r["l"], r["delta"]] == bilgi
            assert list(zip(r["g8_lms"], r["g8"], r["w_yeni"])) == satir
            toplam += len(satir)
    assert next(it, None) is None
    return toplam


# ----------------------------------------------------------------------------
# 6) OKUNUR DÖKÜM
# ----------------------------------------------------------------------------
def okunur_yaz(kat):
    p = ["Fonksiyon motoru golden modeli — okunur döküm",
         f"SRU kararları: ALT_YARI={SRU.ALT_YARI}, TEK_BP={SRU.TEK_BP}, DOYMA={SRU.DOYMA}, "
         f"GMS_KAYDIRMA={SRU.GMS_KAYDIRMA}; B = bit_length (D28)",
         f"FE kararları : HEDEF_G={HEDEF_G}, WU_DOYMA={WU_DOYMA}, GMS_WU_ONCESI={GMS_WU_ONCESI}",
         "", "== ReLU örnekleri =="]
    p.append(f"{'a':>6} {'e':>6} {'relu(a)':>8} {'e_geri':>7}")
    for a, e in [(57, 33), (-20, 33), (0, 33), (1, -128), (-128, 77), (127, -1)]:
        p.append(f"{a:>6} {e:>6} {relu_ileri(a):>8} {relu_geri(e, a):>7}")
    # SRU taşması + ReLU zinciri (SRU-a3 kararının sonucu)
    z, t = SRU.sru_yuvarla(2040, 4)
    p.append("")
    if SRU.DOYMA:
        p.append(f"Zincir örneği: x32 = 2040, LMS (l = 4) -> {z} (taşma = {t}, ±127'ye doyuruldu) "
                 f"-> ReLU -> {relu_ileri(z)}")
        p.append("  (Gerçek değer 2040/16 = 127,5; SRU 127'ye doyurduğu için değer korunur.)")
    else:
        p.append(f"Zincir örneği: x32 = 2040, LMS (l = 4) -> {z} (taşma = {t}, 8 bitte sarıldı) "
                 f"-> ReLU -> {relu_ileri(z)}")
        p.append("  (Gerçek değer 2040/16 = 127,5; SRU'da doyma olmadığı için pozitif değer ReLU'dan 0 çıkar.)")
    p.append("")
    p.append("== Ağırlık güncelleme, katman case 0 ==")
    aciklama, m_u, gruplar, w_gruplar = kat[0]
    G, Bg, s = wu_katman(gruplar, w_gruplar, m_u)
    p.append(aciklama)
    p.append(f"m_u = {m_u}, B_global = {Bg}, G = {G}  (g'nin ölçeği 2^G)")
    for i, (g, w_grup, r) in enumerate(zip(gruplar, w_gruplar, s)):
        p.append(f"-- grup {i}: M = {r['M']}, B = {r['B']}, l = {r['l']}, Δ = {r['delta']}")
        p.append(f"{'g32':>8} {'g8 LMS':>7} {'g8':>4} {'g32/2^G':>9} {'w':>5} {'w - g8':>7}")
        for x, z, y, w, wy in zip(g, r["g8_lms"], r["g8"], w_grup, r["w_yeni"]):
            p.append(f"{x:>8} {z:>7} {y:>4} {x / 2 ** G:>9.3f} {w:>5} {wy:>7}")
    p.append("")
    p.append("== Doyma örneği (katman case 6) ==")
    aciklama, m_u, gruplar, w_gruplar = kat[6]
    G, Bg, s = wu_katman(gruplar, w_gruplar, m_u)
    p.append(f"{aciklama}; m_u = {m_u}, G = {G}")
    for x, y, w, wy in zip(gruplar[0], s[0]["g8"], w_gruplar[0], s[0]["w_yeni"]):
        p.append(f"  g32 = {x:>7} -> g8 = {y:>4};  w = {w:>4} -> w - g8 = {w - y:>4} -> doyma -> {wy:>4}")
    with open(os.path.join(KLASOR, "OKUNUR.txt"), "w") as f:
        f.write("\n".join(p) + "\n")


def case_listesi_yaz(kat):
    with open(os.path.join(KLASOR, "CASE_LISTESI.txt"), "w") as f:
        f.write("relu.hex      : 65536 satır, tüm (a, e) int8 çiftleri\n")
        f.write("wu_cikarma.hex: 65536 satır, tüm (w, g8) int8 çiftleri\n")
        for case_no, (aciklama, m_u, gruplar, _) in enumerate(kat):
            f.write(f"wu_katman case {case_no}: {len(gruplar)} grup, m_u = {m_u} — {aciklama}\n")


# ----------------------------------------------------------------------------
# Ana program
# ----------------------------------------------------------------------------
def main():
    oz_kontrol()
    print("1) Öz kontrol: ReLU (65536 çift), LMS tutarlılığı (SRU modeliyle), NITI eşdeğerliği "
          "(3000 vaka), katman ölçeği ve doyma: hepsi geçti.")
    kat = katman_vakalari()
    dosyalari_yaz(kat)
    n = dosyalari_geri_oku()
    okunur_yaz(kat)
    case_listesi_yaz(kat)
    print(f"2) Vektörler yazıldı ve geri okunup doğrulandı: relu.hex 65536, wu_cikarma.hex 65536, "
          f"wu_katman {len(kat)} case / {n} değer.")


if __name__ == "__main__":
    main()
