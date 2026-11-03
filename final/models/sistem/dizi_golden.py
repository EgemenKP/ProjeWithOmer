# =============================================================================
#  dizi_golden.py — Adım 5b golden modeli: 16x16 PE dizisiyle BİR eğitim adımı
# -----------------------------------------------------------------------------
#  sistem_golden.py'nin (Adım 4, tek PE) dizi karşılığı. Konvolüsyon aritmetiği aynı; değişen
#  şey işin PE'lere dağılımı ve SRU gruplarının içeriği (LMS grup başına yuvarladığı için
#  sonuçlar Adım 4'ün sayılarıyla aynı DEĞİL).
#
#  Eşleme (DEVIATIONS D72, D73, D76):
#    FP    : PE satırı i = çıkış satırı r, PE sütunu j = çıkış kanalı o. Toplama c boyunca
#            (Psum FIFO). Geçiş döngüsü: o-karosu -> c -> b -> r-karosu (D47'nin dizi hâli).
#    BP s1 : satır = dX satırı m, sütun = giriş kanalı c. Toplama o boyunca.
#    BP s2 : satır = geçiş p (her geçiş 2 dX satırı, D51), sütun = giriş kanalı c.
#    WG    : satır = giriş kanalı c, sütun = çıkış kanalı o (D73). Her PE (c, o) gradyanını
#            kendi akümülatörlerinde (b, r) boyunca biriktirir; hata sütun hattından.
#  Grup (D76): bir PE satırının bir çevrimde verdiği, sütun başına bir değer:
#    FP/BP: aynı (b, konum)daki en çok 16 kanal;  WG: aynı (c, ki, kj)deki en çok 16 çıkış kanalı.
#    Satır i'nin grupları i. SRU kanalına gider; G bütün kanallarda ortak (D30).
#    BP s2'de dolguya düşen konumlar gruba girmez (D52).
#
#  Doğrulama:
#    (I')  DİZİ YORUMLAYICI: geçiş geçiş, her etkin PE için pe_golden'ın çevrim modeli, PE başına
#          Psum FIFO (D74), satır başına grup kurulumu, SRU (LMS -> G -> GMS), ReLU, WU.
#    (II') TENSÖR DÜZEYİ: katman fonksiyonları (ref_fp/bp/wg) + aynı grup tanımıyla SRU.
#          (I') ile (II') bit bit aynı olmalı.
#    (III) FLOAT: sistem_golden.float_kontrol (doymalı referansta sıkı eşikler, D65).
#  Ek: tek PE'li Adım 4 ile farkın büyüklüğü raporlanır (yalnızca bilgi).
#
#  Hazırlayan: Claude, 04.11.2026 (final/, Adım 5b)
#  Çalıştırma: python dizi_golden.py   (sistem_golden.py ve onun modülleri aynı klasörde)
# =============================================================================

import sistem_golden as S
from sistem_golden import PE, SRU, FE, FAZ_FP, FAZ_BP, FAZ_WG

DR = 16                 # dizinin satır sayısı
DC = 16                 # dizinin sütun sayısı
PS_DERINLIK = 64        # D74: PE başına Psum FIFO derinliği (kayıt)
SRU_MAKS_GRUP = 64      # D63: SRU kanalı başına bir işteki en çok grup


def karolar(n, boy):
    """0..n-1'i boy'luk karolara böler: [(baş, adet), ...]"""
    return [(t, min(boy, n - t)) for t in range(0, n, boy)]


# ----------------------------------------------------------------------------
# Ortak: SRU (LMS -> G -> GMS) grup listesine uygulanır
# ----------------------------------------------------------------------------
def sru_is(gruplar, hedef):
    """gruplar: [(anahtar, int32 değerler)]. Dönüş: (G, {anahtar: gms8}, olaylar)
    olaylar: anahtar -> (M, l, Δ). G bütün grupların (bütün SRU kanallarının) ortak kaydırması."""
    lms = {}
    for a, g in gruplar:
        lms[a] = FE.lms_hedefli(g, hedef)               # (cikis8, tasma, M, B, l)
    B_global = max(v[3] for v in lms.values())
    G = max(0, B_global - hedef)
    cikis, olay = {}, {}
    for a, (c8, _, M, _, l) in lms.items():
        d = G - l                                        # SRU-a8
        cikis[a] = [SRU.sru_yuvarla(v, d)[0] for v in c8]
        olay[a] = (M, l, d)
    return G, cikis, olay


# ----------------------------------------------------------------------------
# (II') TENSÖR DÜZEYİ
# ----------------------------------------------------------------------------
def tensor_adimi_dizi(AKT0, W0, etiket):
    L, B_, K = S.L, S.BATCH, S.KATMANLAR
    AKT = [S.kopya(AKT0)] + [None] * L
    HATA = [None] * (L + 1)
    W = S.kopya(W0)
    s_a = S.S_A0
    s_a_list = [s_a]
    G32 = [None] * L
    isler = []
    lfsr = S.CY.kanal_tohumlari(S.N_SINIF)
    for li, k in enumerate(K):                               # ---- İleri
        Y = {}
        for b in range(B_):
            for o in range(k["cout"]):
                for c in range(k["cin"]):
                    Yc = PE.ref_fp(AKT[li][b][c], W[li][o][c], k["s"], k["p"])
                    Y[(b, o)] = Yc if c == 0 else PE.matris_topla(Y[(b, o)], Yc)
        gruplar = []
        for o0, no in karolar(k["cout"], DC):
            for b in range(B_):
                for r in range(k["ho"]):
                    for x in range(k["wo"]):
                        gruplar.append(((o0, b, r, x), [Y[(b, o)][r][x] for o in range(o0, o0 + no)]))
        G, cik, olay = sru_is(gruplar, S.HEDEF_AKT)
        isler.append((FAZ_FP, li + 1, G, olay))
        AKT[li + 1] = [[PE.sifir_matris(k["ho"], k["wo"]) for _ in range(k["cout"])] for _ in range(B_)]
        for (o0, b, r, x), v8 in cik.items():
            for j, v in enumerate(v8):
                AKT[li + 1][b][o0 + j][r][x] = FE.relu_ileri(v) if k["relu"] else v
        s_a = s_a + k["sw"] + G
        s_a_list.append(s_a)
    HATA[L] = [[[[0]] for _ in range(S.N_SINIF)] for _ in range(B_)]   # ---- CLU
    for b in range(B_):
        e = S.clu_yer_tutucu([AKT[L][b][o][0][0] for o in range(S.N_SINIF)], s_a, etiket[b], lfsr)
        for o in range(S.N_SINIF):
            HATA[L][b][o] = [[e[o]]]
    for li in reversed(range(L)):                            # ---- Geri
        k = K[li]
        l = li + 1
        if l > 1:
            dX = {}
            for b in range(B_):
                for c in range(k["cin"]):
                    for o in range(k["cout"]):
                        d = PE.ref_bp(HATA[l][b][o], W[li][o][c], k["s"], k["p"], k["h"], k["w"])
                        dX[(b, c)] = d if o == 0 else PE.matris_topla(dX[(b, c)], d)
            gruplar = []
            for c0, nc in karolar(k["cin"], DC):
                for b in range(B_):
                    for R in range(k["h"]):
                        for C in range(k["w"]):
                            gruplar.append(((c0, b, R, C), [dX[(b, c)][R][C] for c in range(c0, c0 + nc)]))
            G, cik, olay = sru_is(gruplar, S.HEDEF_AKT)
            isler.append((FAZ_BP, l, G, olay))
            HATA[l - 1] = [[PE.sifir_matris(k["h"], k["w"]) for _ in range(k["cin"])] for _ in range(B_)]
            for (c0, b, R, C), v8 in cik.items():
                for j, v in enumerate(v8):
                    if K[li - 1]["relu"]:
                        v = FE.relu_geri(v, AKT[l - 1][b][c0 + j][R][C])
                    HATA[l - 1][b][c0 + j][R][C] = v
        G32[li] = [[None] * k["cin"] for _ in range(k["cout"])]
        for o in range(k["cout"]):
            for c in range(k["cin"]):
                Gm = None
                for b in range(B_):
                    g = PE.ref_wg(AKT[li][b][c], HATA[l][b][o], k["s"], k["p"])
                    Gm = g if Gm is None else PE.matris_topla(Gm, g)
                G32[li][o][c] = Gm
        anahtarlar, g_gr, w_gr = [], [], []
        for o0, no in karolar(k["cout"], DC):
            for c in range(k["cin"]):
                for ki in range(3):
                    for kj in range(3):
                        anahtarlar.append((o0, c, ki, kj))
                        g_gr.append([G32[li][o][c][ki][kj] for o in range(o0, o0 + no)])
                        w_gr.append([W[li][o][c][ki][kj] for o in range(o0, o0 + no)])
        G, _, son = FE.wu_katman(g_gr, w_gr, S.M_U)
        olay = {}
        for (o0, c, ki, kj), s_ in zip(anahtarlar, son):
            olay[(o0, c, ki, kj)] = (s_["M"], s_["l"], s_["delta"])
            for j, w in enumerate(s_["w_yeni"]):
                W[li][o0 + j][c][ki][kj] = w
        isler.append((FAZ_WG, l, G, olay))
    return dict(AKT=AKT, HATA=HATA, W=W, s_a=s_a_list, isler=isler, G32=G32)


# ----------------------------------------------------------------------------
# (I') DİZİ YORUMLAYICI — geçiş geçiş, PE başına çevrim modeli ve Psum FIFO
# ----------------------------------------------------------------------------
class Dizi:
    """Dizinin durumu: PE başına Psum FIFO ve WG akümülatörleri, satır başına SRU grupları."""
    def __init__(self):
        self.fifo = {}            # (i, j) -> [(anahtar, kayıt)]
        self.akum = {}            # (i, j) -> 3x3
        self.fifo_en_cok = 0
        self.sru = [[] for _ in range(DR)]   # satır başına bu işin grupları: (anahtar, değerler)
        self.gecis = 0

    def yaz(self, ij, anahtar, kayit):
        """kayit: bir geçişin kısmi toplamları. RTL'de (D74) her çevrim bir kayıt (128 bit, 4 şerit):
        FP/BP s1'de wo/w, BP s2'de şerit boyu kadar kayıt. Doluluk bu birimle ölçülür."""
        f = self.fifo.setdefault(ij, [])
        f.append((anahtar, kayit))
        n = sum(len(v[0]) if isinstance(v[0], list) else len(v) for (_, v) in f)
        self.fifo_en_cok = max(self.fifo_en_cok, n)

    def oku(self, ij, anahtar):
        a, kayit = self.fifo[ij].pop(0)
        assert a == anahtar, f"PE {ij} Psum FIFO sırası bozuk: {a} != {anahtar}"
        return kayit


def fp_pe(k, X, Wk, psum):
    """Bir PE'nin FP geçişi (sistem_golden.yorumla'daki gibi). X: dolgulu girişin 3 satırı."""
    if k["s"] == 1:
        T = len(X[0])
        _, cik = PE.pe_gecis_s1(X, Wk, PE.ps_akisi_s(psum, T))
    else:
        cift, tek = zip(*[PE.cift_tek_ayir(s_) for s_ in X])
        T = len(cift[0])
        _, cik = PE.pe_gecis_s2(list(cift), list(tek), Wk, PE.ps_akisi_s(psum, T))
    return [d[0] for (_, d) in cik]


def dizi_fp(D, k, AKT_l, Wl):
    B_ = S.BATCH
    for o0, no in karolar(k["cout"], DC):
        for c in range(k["cin"]):
            ilk, son = c == 0, c == k["cin"] - 1
            for b in range(B_):
                Xp = PE.dolgu_ekle(AKT_l[b][c], k["p"])
                for r0, nr in karolar(k["ho"], DR):
                    D.gecis += 1
                    cikis = {}
                    for i in range(nr):
                        r = r0 + i
                        X = [Xp[k["s"] * r + q] for q in range(3)]
                        for j in range(no):
                            psum = [0] * k["wo"] if ilk else D.oku((i, j), (o0, b, r0))
                            cikis[(i, j)] = fp_pe(k, X, Wl[o0 + j][c], psum)
                    for i in range(nr):
                        if son:                          # satır i'nin grupları: x sırasıyla
                            for x in range(k["wo"]):
                                D.sru[i].append(((o0, b, r0 + i, x), [cikis[(i, j)][x] for j in range(no)]))
                        else:
                            for j in range(no):
                                D.yaz((i, j), (o0, b, r0), cikis[(i, j)])


def dizi_bp(D, k, HATA_l, Wl):
    B_ = S.BATCH
    if k["s"] == 1:
        for c0, nc in karolar(k["cin"], DC):
            for o in range(k["cout"]):
                ilk, son = o == 0, o == k["cout"] - 1
                for b in range(B_):
                    Ep = PE.dolgu_ekle(HATA_l[b][o], 2 - k["p"])
                    for m0, nm in karolar(k["h"], DR):
                        D.gecis += 1
                        cikis = {}
                        for i in range(nm):
                            X = [Ep[m0 + i + q] for q in range(3)]
                            T = len(X[0])
                            for j in range(nc):
                                psum = [0] * k["w"] if ilk else D.oku((i, j), (c0, b, m0))
                                _, cik = PE.pe_gecis_s1(X, PE.dondur_180(Wl[o][c0 + j]), PE.ps_akisi_s(psum, T))
                                cikis[(i, j)] = [d[0] for (_, d) in cik]
                        for i in range(nm):
                            if son:
                                for x in range(k["w"]):
                                    D.sru[i].append(((c0, b, m0 + i, x), [cikis[(i, j)][x] for j in range(nc)]))
                            else:
                                for j in range(nc):
                                    D.yaz((i, j), (c0, b, m0), cikis[(i, j)])
        return
    He, We = k["ho"], k["wo"]
    n = We + 1
    sifir = [0] * We
    npass = S.bp_gecis_sayisi(k)
    for c0, nc in karolar(k["cin"], DC):
        for o in range(k["cout"]):
            ilk, son = o == 0, o == k["cout"] - 1
            for b in range(B_):
                E = HATA_l[b][o]
                for p0, np_ in karolar(npass, DR):
                    D.gecis += 1
                    serit = {}
                    for i in range(np_):
                        p = p0 + i
                        e_p = E[p] if p < He else sifir
                        e_once = E[p - 1] if p >= 1 else sifir
                        akislar = [PE.bp_s2_akisi(e_p), PE.bp_s2_akisi(e_p), PE.bp_s2_akisi(e_once)]
                        T = len(akislar[0])
                        for j in range(nc):
                            Wk = Wl[o][c0 + j]
                            w_yuklu = [[Wk[q][2], Wk[q][0], Wk[q][1]] for q in range(3)]   # Fig. 4(b)
                            psum4 = [[0] * n for _ in range(4)] if ilk else D.oku((i, j), (c0, b, p0))
                            _, cik = PE.pe_gecis_bp_s2(akislar, w_yuklu, PE.ps_akisi_bp_s2(psum4, T))
                            serit[(i, j)] = [[d[s_] for (_, d) in cik] for s_ in range(4)]
                    for i in range(np_):
                        p = p0 + i
                        if son:                          # geçerli dX konumları (D52)
                            for R in S.bp_s2_satirlari(k, p):
                                for C in range(k["w"]):
                                    C0 = C + k["p"]
                                    s_ = (0 if R + k["p"] == 2 * p else 2) + (C0 % 2)
                                    D.sru[i].append(((c0, b, R, C), [serit[(i, j)][s_][C0 // 2] for j in range(nc)]))
                        else:
                            for j in range(nc):
                                D.yaz((i, j), (c0, b, p0), serit[(i, j)])


def dizi_wg(D, k, AKT_l, HATA_l):
    B_ = S.BATCH
    for c0, nc in karolar(k["cin"], DR):                 # D73: satır = giriş kanalı
        for o0, no in karolar(k["cout"], DC):            #      sütun = çıkış kanalı
            for i in range(nc):
                for j in range(no):
                    D.akum[(i, j)] = PE.sifir_matris(3, 3)
            for b in range(B_):
                for r in range(k["ho"]):
                    D.gecis += 1
                    for i in range(nc):
                        Ap = PE.dolgu_ekle(AKT_l[b][c0 + i], k["p"])
                        a_sat = [Ap[k["s"] * r + q] for q in range(3)]
                        for j in range(no):
                            e_sat = HATA_l[b][o0 + j][r]       # sütun hattından (D73)
                            if k["s"] == 1:
                                T = len(a_sat[0])
                                PE.pe_gecis_wg_s1(a_sat, [e_sat + [0] * (T - len(e_sat))] * 3, D.akum[(i, j)])
                            else:
                                cift, tek = zip(*[PE.cift_tek_ayir(s_) for s_ in a_sat])
                                T = len(cift[0])
                                PE.pe_gecis_wg_s2(list(cift), list(tek), [e_sat + [0] * (T - len(e_sat))] * 3,
                                                  D.akum[(i, j)])
            for i in range(nc):
                for ki in range(3):
                    for kj in range(3):
                        D.sru[i].append(((o0, c0 + i, ki, kj), [D.akum[(i, j)][ki][kj] for j in range(no)]))


def yorumla_dizi(AKT0, W0, etiket):
    L, B_, K = S.L, S.BATCH, S.KATMANLAR
    AKT = [S.kopya(AKT0)] + [None] * L
    HATA = [None] * (L + 1)
    W = S.kopya(W0)
    s_a = S.S_A0
    s_a_list = [s_a]
    isler, istat = [], []
    lfsr = S.CY.kanal_tohumlari(S.N_SINIF)

    def is_bitir(D, faz, l, hedef):
        """SRU: satırların grupları -> LMS, ortak G, GMS. Dönüş: (G, {anahtar: gms8}, olay)."""
        assert all(not f for f in D.fifo.values()), "iş bittiğinde Psum FIFO'lar boş olmalı"
        kanal_grup = [len(g) for g in D.sru]
        assert max(kanal_grup) <= SRU_MAKS_GRUP, (faz, l, kanal_grup)
        assert D.fifo_en_cok <= PS_DERINLIK, (faz, l, D.fifo_en_cok)
        G, cik, olay = sru_is([g for kanal in D.sru for g in kanal], hedef)
        istat.append(dict(faz=faz, l=l, gecis=D.gecis, kanal_grup=kanal_grup, fifo=D.fifo_en_cok, G=G))
        return G, cik, olay

    for li, k in enumerate(K):                                   # ---- İleri
        D = Dizi()
        dizi_fp(D, k, AKT[li], W[li])
        G, cik, olay = is_bitir(D, FAZ_FP, li + 1, S.HEDEF_AKT)
        isler.append((FAZ_FP, li + 1, G, olay))
        AKT[li + 1] = [[PE.sifir_matris(k["ho"], k["wo"]) for _ in range(k["cout"])] for _ in range(B_)]
        for (o0, b, r, x), v8 in cik.items():
            for j, v in enumerate(v8):
                AKT[li + 1][b][o0 + j][r][x] = FE.relu_ileri(v) if k["relu"] else v
        s_a = s_a + k["sw"] + G
        s_a_list.append(s_a)
    HATA[L] = [[[[0]] for _ in range(S.N_SINIF)] for _ in range(B_)]   # ---- CLU
    for b in range(B_):
        e = S.clu_yer_tutucu([AKT[L][b][o][0][0] for o in range(S.N_SINIF)], s_a, etiket[b], lfsr)
        for o in range(S.N_SINIF):
            HATA[L][b][o] = [[e[o]]]
    for li in reversed(range(L)):                                # ---- Geri
        k = K[li]
        l = li + 1
        if l > 1:
            D = Dizi()
            dizi_bp(D, k, HATA[l], W[li])
            G, cik, olay = is_bitir(D, FAZ_BP, l, S.HEDEF_AKT)
            isler.append((FAZ_BP, l, G, olay))
            HATA[l - 1] = [[PE.sifir_matris(k["h"], k["w"]) for _ in range(k["cin"])] for _ in range(B_)]
            for (c0, b, R, C), v8 in cik.items():
                for j, v in enumerate(v8):
                    if K[li - 1]["relu"]:
                        v = FE.relu_geri(v, AKT[l - 1][b][c0 + j][R][C])
                    HATA[l - 1][b][c0 + j][R][C] = v
        D = Dizi()
        dizi_wg(D, k, AKT[li], HATA[l])
        G, cik, olay = is_bitir(D, FAZ_WG, l, S.M_U)
        isler.append((FAZ_WG, l, G, olay))
        for (o0, c, ki, kj), g8 in cik.items():                  # WU: w - g
            for j, g in enumerate(g8):
                W[li][o0 + j][c][ki][kj] = FE.agirlik_guncelle(W[li][o0 + j][c][ki][kj], g)
    return dict(AKT=AKT, HATA=HATA, W=W, s_a=s_a_list, isler=isler, istat=istat)


# ----------------------------------------------------------------------------
# Ana program
# ----------------------------------------------------------------------------
def fark_orani(a, b):
    """İki iç içe int listesinde farklı eleman oranı."""
    fa, fb = duz(a), duz(b)
    return sum(1 for x, y in zip(fa, fb) if x != y) / len(fa)


def duz(x):
    if isinstance(x, list):
        return [v for e in x for v in duz(e)]
    return [x]


def calistir(ag):
    S.ag_kur(ag)
    ad = ag["ad"]
    AKT0, W0, etiket = S.baslangic_verisi()
    y = yorumla_dizi(AKT0, W0, etiket)
    t = tensor_adimi_dizi(AKT0, W0, etiket)
    L = S.L
    for l in range(1, L + 1):
        assert S.esit_mi(y["AKT"][l], t["AKT"][l]), f"{ad}: AKT {l} farklı"
        assert S.esit_mi(y["HATA"][l], t["HATA"][l]), f"{ad}: HATA {l} farklı"
    assert S.esit_mi(y["W"], t["W"]), f"{ad}: son ağırlıklar farklı"
    assert y["s_a"] == t["s_a"], f"{ad}: s_a farklı"
    assert [(f, l, G, o) for (f, l, G, o) in y["isler"]] == t["isler"], f"{ad}: G ya da grup olayları farklı"
    assert not S.esit_mi(t["W"], W0), "ağırlıklar hiç değişmedi"
    n_grup = sum(len(o) for (_, _, _, o) in t["isler"])
    print(f"[{ad}] 1) Dizi yorumlayıcı (I') ile tensör düzeyi (II') bit bit aynı: {len(t['isler'])} iş, "
          f"{n_grup} grup; s_a = {t['s_a']}.")
    for s_ in y["istat"]:
        print(f"      {S.FAZ_ADI[s_['faz']]} {s_['l']}: {s_['gecis']} dizi geçişi, G {s_['G']}, "
              f"SRU kanalı başına grup en çok {max(s_['kanal_grup'])} (dolu kanal "
              f"{sum(1 for g in s_['kanal_grup'] if g)}), PE FIFO en çok {s_['fifo']} kayıt")
    # (III) float: sıkı eşikler doymalı referansta (D65)
    eski = SRU.DOYMA
    SRU.DOYMA = True
    t_ref = tensor_adimi_dizi(AKT0, W0, etiket)
    SRU.DOYMA = eski
    olcum_ref = S.float_kontrol(AKT0, W0, etiket, t_ref)
    for a, v in olcum_ref.items():
        assert (v > 0.95) if "kosinüs" in a else (v < 0.1), (ad, a, v)
    olcum = S.float_kontrol(AKT0, W0, etiket, t)
    print(f"[{ad}] 2) Float (doymalı referans): FP sapması <= "
          f"{max(v for a, v in olcum_ref.items() if 'kosinüs' not in a):.3f}, kosinüs >= "
          f"{min(v for a, v in olcum_ref.items() if 'kosinüs' in a):.3f}. Kararla (doymasız) FP sapması en çok "
          f"{max(v for a, v in olcum.items() if 'kosinüs' not in a):.3f} (yalnızca rapor).")
    # Adım 4 (tek PE, grup = kanalın bir satırı) ile fark: yalnızca bilgi
    t4 = S.tensor_adimi(AKT0, W0, etiket)
    print(f"[{ad}] 3) Adım 4'e göre farklı eleman oranı (grup tanımı değişti, beklenen): "
          + ", ".join(f"AKT{l} {fark_orani(t['AKT'][l], t4['AKT'][l]):.0%}" for l in range(1, L + 1))
          + f", W {fark_orani(t['W'], t4['W']):.0%}; s_a Adım 4 {t4['s_a']}")
    return y, t


def main():
    calistir(S.AG1)
    calistir(S.AG2)
    S.ag_kur(S.AG1)


if __name__ == "__main__":
    main()
