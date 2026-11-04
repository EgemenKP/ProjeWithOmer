# =============================================================================
#  dizi_sistem_golden.py — Adım 5b-3a: dizili sistemin komutları ve tampon düzeni
# -----------------------------------------------------------------------------
#  Tasarım: final/rtl/dizi/TASARIM_DIZI.md (D78–D86). Bu dosya:
#    1) FSM'in üretmesi gereken DİZİ komut listesini üretir (D85; KOPYA yok).
#    2) (III'') KOMUT YORUMLAYICI, tampon modeliyle: veri tamponu (16 bank, kelime = 16 kanal + l,
#       bank = satır mod 16, D80/D81), bölge başına G, ağırlık tamponu (bank = o mod 16, D82).
#       Ön-getirme her kelimeyi GMS'ten geçirir (D78, D84); LMS çıkışı ReLU / ReLU-geri ile doğrudan
#       tampona yazılır (D83, D86); WU, GRAD kelimelerini GMS'ten geçirip w − g yazar.
#    3) (III'')'nın son tampon hâli çözülünce dizi_golden'ın tensör düzeyiyle (II') bit bit aynı olmalı.
#       Bu, D53/D86'nın (ReLU'yu LMS çıkışında uygulamak = önce GMS) ve tampon düzeninin uçtan uca kontrolü.
#    4) Vektörler: komutlar_dizi.txt, bolgeler.txt, veri_baslangic.txt, veri_beklenen.txt,
#       agirlik_baslangic.txt, agirlik_beklenen.txt (biçimler yaz_* fonksiyonlarında).
#  Hazırlayan: Claude, 04.11.2026 (final/, Adım 5b-3a)
#  Çalıştırma: python dizi_sistem_golden.py
# =============================================================================

import os
import sistem_golden as S
import dizi_golden as DG
from sistem_golden import PE, SRU, FE, FAZ_FP, FAZ_BP, FAZ_WG

NB = 16                                   # bank sayısı (= dizi boyu)
OP_DIZI, OP_OLCEK, OP_SA, OP_CLU, OP_WU, OP_BITTI, OP_IS_BASLA = 1, 2, 4, 5, 6, 7, 8
OP_ADI = {1: "DIZI", 2: "OLCEK", 4: "SA", 5: "CLU", 6: "WU", 7: "BITTI", 8: "IS_BASLA"}


def tavan(a, b):
    return -(-a // b)


# ----------------------------------------------------------------------------
# Bölgeler ve adresler (D80, D81)
# ----------------------------------------------------------------------------
def bolgeleri_kur():
    """Bölge: ad -> dict(taban, B, C, H, W, n_karo). Kelime adresi bankta aynı formülle:
    adr = taban + ((b * n_karo + karo) * ceil(H/16) + r // 16) * W + x ; bank = r % 16.
    GRAD[l]: B = 1, 'satır' = giriş kanalı c, x = 3ki + kj (W = 9), karo = çıkış kanalı karosu."""
    K = S.KATMANLAR
    sira = [("AKT0", S.BATCH, K[0]["cin"], K[0]["h"], K[0]["w"])]
    for li, k in enumerate(K):
        sira.append((f"AKT{li + 1}", S.BATCH, k["cout"], k["ho"], k["wo"]))
    for li, k in enumerate(K):
        sira.append((f"HATA{li + 1}", S.BATCH, k["cout"], k["ho"], k["wo"]))
    for li, k in enumerate(K):
        sira.append((f"GRAD{li + 1}", 1, k["cout"], k["cin"], 9))
    bolge, taban = {}, 0
    for ad, B, C, H, W in sira:
        n_karo = tavan(C, NB)
        bolge[ad] = dict(taban=taban, B=B, C=C, H=H, W=W, n_karo=n_karo)
        taban += B * n_karo * tavan(H, NB) * W
    return bolge, taban


def adres(bg, b, karo, r, x):
    return bg["taban"] + ((b * bg["n_karo"] + karo) * tavan(bg["H"], NB) + r // NB) * bg["W"] + x


class Tampon:
    """Veri tamponu (bank -> adr -> [16 int8, l]), bölge G'leri, ağırlık tamponu (bank -> adr -> 9 int8)."""
    def __init__(self, bolge):
        self.bolge = bolge
        self.veri = [dict() for _ in range(NB)]
        self.G = {ad: 0 for ad in bolge}
        self.agr = [dict() for _ in range(NB)]
        self.n_oku = 0
        self.n_yaz = 0

    # ---- veri ----
    def kelime_yaz(self, ad, b, karo, r, x, degerler, l):
        bg = self.bolge[ad]
        w = list(degerler) + [0] * (NB - len(degerler))
        self.veri[r % NB][adres(bg, b, karo, r, x)] = (w, l)
        self.n_yaz += 1

    def kelime_oku_gms(self, ad, b, karo, r, x, hedef_G=None):
        """Ön-getirmenin okuması: kelime GMS'ten geçer (Δ = G − l, D78). Dönüş: 16 int8."""
        bg = self.bolge[ad]
        w, l = self.veri[r % NB][adres(bg, b, karo, r, x)]
        self.n_oku += 1
        G = self.G[ad] if hedef_G is None else hedef_G
        d = G - l
        assert d >= 0, (ad, b, karo, r, x, G, l)
        return [SRU.sru_yuvarla(v, d)[0] for v in w]

    def harita(self, ad, b, ch):
        """Bir kanalın H×W haritası, GMS'ten geçmiş (ön-getirmenin satır register'larına yüklediği)."""
        bg = self.bolge[ad]
        return [[self.kelime_oku_gms(ad, b, ch // NB, r, x)[ch % NB] for x in range(bg["W"])]
                for r in range(bg["H"])]

    # ---- ağırlık (D82) ----
    def agr_adres(self, l, o, c):
        return self.agr_taban[l] + (o // NB) * S.KATMANLAR[l - 1]["cin"] + c

    def agr_yaz(self, l, o, c, w9):
        self.agr[o % NB][self.agr_adres(l, o, c)] = list(w9)

    def agr_oku(self, l, o, c):
        w9 = self.agr[o % NB][self.agr_adres(l, o, c)]
        return [w9[0:3], w9[3:6], w9[6:9]]


def tampon_kur(AKT0, W0):
    bolge, _ = bolgeleri_kur()
    T = Tampon(bolge)
    T.agr_taban, t = {}, 0
    for li, k in enumerate(S.KATMANLAR):
        T.agr_taban[li + 1] = t
        t += tavan(k["cout"], NB) * k["cin"]
    for b in range(S.BATCH):                       # giriş: l = 0, G = 0 (Δ = 0)
        for r in range(S.KATMANLAR[0]["h"]):
            for x in range(S.KATMANLAR[0]["w"]):
                for karo in range(bolge["AKT0"]["n_karo"]):
                    kan = range(karo * NB, min(S.KATMANLAR[0]["cin"], karo * NB + NB))
                    T.kelime_yaz("AKT0", b, karo, r, x, [AKT0[b][c][r][x] for c in kan], 0)
    for li, k in enumerate(S.KATMANLAR):
        for o in range(k["cout"]):
            for c in range(k["cin"]):
                T.agr_yaz(li + 1, o, c, PE.duzlestir(W0[li][o][c]))
    return T


# ----------------------------------------------------------------------------
# 1) Komut listesi (FSM'in davranışı, D85)
#    Komut = [op, faz, katman, b, x, y, z, a1, a2, a3]
# ----------------------------------------------------------------------------
def hedef_genislik(faz):
    return S.M_U if faz == FAZ_WG else S.HEDEF_AKT


def is_komutlari(K, faz, l):
    k = S.KATMANLAR[l - 1]
    K.append([OP_IS_BASLA, faz, l, 0, hedef_genislik(faz), 0, 0, 0, 0, 0])
    # D94: toplanan kanal döngüsü (FP'de c, BP'de o) en içte; Psum FIFO yalnızca bir geçişin çıkışlarını tutar
    # (derinlik T, batch'ten bağımsız). Eski sıra (kanal b ve karonun dışında) B × karo × T kayıt istiyordu.
    if faz == FAZ_FP:                              # o-karo -> b -> r-karo -> c
        for k0 in range(tavan(k["cout"], NB)):
            for b in range(S.BATCH):
                for z in range(tavan(k["ho"], NB)):
                    for c in range(k["cin"]):
                        K.append([OP_DIZI, faz, l, b, k0, c, z, int(c == 0), int(c == k["cin"] - 1), 0])
    elif faz == FAZ_BP:                            # c-karo -> b -> m/p-karo -> o
        n = k["h"] if k["s"] == 1 else S.bp_gecis_sayisi(k)
        for k0 in range(tavan(k["cin"], NB)):
            for b in range(S.BATCH):
                for z in range(tavan(n, NB)):
                    for o in range(k["cout"]):
                        K.append([OP_DIZI, faz, l, b, k0, o, z, int(o == 0), int(o == k["cout"] - 1), 0])
    else:                                          # c-karo -> o-karo -> b -> r
        for k0 in range(tavan(k["cin"], NB)):
            for k1 in range(tavan(k["cout"], NB)):
                for b in range(S.BATCH):
                    for r in range(k["ho"]):
                        ilk = int(b == 0 and r == 0)
                        son = int(b == S.BATCH - 1 and r == k["ho"] - 1)
                        K.append([OP_DIZI, faz, l, b, k0, k1, r, ilk, son, 0])
    K.append([OP_OLCEK, faz, l, 0, 0, 0, 0, 0, 0, 0])


def komut_sablonu():
    K = []
    L = S.L
    for l in range(1, L + 1):
        is_komutlari(K, FAZ_FP, l)
        K.append([OP_SA, 0, l, 0, None, 0, 0, 0, 0, 0])
    for b in range(S.BATCH):
        K.append([OP_CLU, 0, L, b, None, 0, 0, 0, 0, 0])
    for l in range(L, 0, -1):
        k = S.KATMANLAR[l - 1]
        if l > 1:
            is_komutlari(K, FAZ_BP, l)
        is_komutlari(K, FAZ_WG, l)
        for k0 in range(tavan(k["cout"], NB)):
            for c in range(k["cin"]):
                K.append([OP_WU, FAZ_WG, l, 0, k0, c, 0, 0, 0, 0])
    K.append([OP_BITTI, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    return K


# ----------------------------------------------------------------------------
# 2) (III'') Komut yorumlayıcı, tampon modeliyle
# ----------------------------------------------------------------------------
class Is:
    """Bir PE işinin durumu: PE başına Psum FIFO ve akümülatörler, paylaşılan B_max (G toplayıcı)."""
    def __init__(self, faz, l, hedef):
        self.faz, self.l, self.hedef = faz, l, hedef
        self.fifo = {}
        self.akum = {}
        self.B_max = 0
        self.olay = {}              # grup anahtarı -> (M, l)  (dizi_golden ile karşılaştırma için)

    def fifo_yaz(self, ij, anahtar, v):
        self.fifo.setdefault(ij, []).append((anahtar, v))
        global FIFO_EN_COK                         # D94: PE başına en çok bekleyen geçiş sayısı
        FIFO_EN_COK = max(FIFO_EN_COK, len(self.fifo[ij]))

    def fifo_oku(self, ij, anahtar):
        a, v = self.fifo[ij].pop(0)
        assert a == anahtar, (ij, a, anahtar)
        return v


def lms_yaz(T, J, ad, b, karo, r, x, grup, anahtar, islem=None):
    """Satır sonu: LMS -> (ReLU / ReLU-geri) -> kelime + l tampona; B -> paylaşılan toplayıcı."""
    c8, _, M, B, l = FE.lms_hedefli(grup, J.hedef)
    if islem is not None:
        c8 = islem(c8)
    T.kelime_yaz(ad, b, karo, r, x, c8, l)
    J.B_max = max(J.B_max, B)
    J.olay[anahtar] = (M, l)


FIFO_EN_COK = 0    # D94: ölçüm (Is.fifo_yaz)
IZ = None          # liste verilirse her DİZİ komutunun ön-getirme izi buraya eklenir (onget_izi.txt)


def alanlar(mod, g):
    """pe_golden'ın çevrim girişi -> (akis1[3], akis2[3], akis3[3]) — sistem_golden.pe_izi_yaz ile aynı eşleme.
    WG'de hata dizide sütun hattından gelir (D73): satır akışının o alanı 0."""
    a1, a2, a3 = [0] * 3, [0] * 3, [0] * 3
    if mod in (0, 2):
        a1 = g[0:3]
    elif mod == 1:
        a1 = [g[0], g[2], g[4]]; a2 = [g[1], g[3], g[5]]
    elif mod == 3:
        a1 = g[0:3]
    elif mod == 4:
        a1 = [g[0], g[2], g[4]]
    else:
        a1 = [g[0], g[3], g[6]]; a2 = [g[1], g[4], g[7]]
    return list(a1) + list(a2) + list(a3)


def hata_alani(mod, g):
    """WG'de PE'nin hata akışı (satır 0'ın değeri; üç iç satırda aynı)."""
    return g[1] if mod == 4 else g[2]


def iz_kaydet(kom_no, mod, satir_cev, sutun):
    if IZ is None:
        return
    T_ = len(next(iter(satir_cev.values())))
    IZ.append((kom_no, mod, T_, {i: [alanlar(mod, g) for (g, _, _) in c] for i, c in satir_cev.items()},
               {j: (v if mod < 4 else [hata_alani(mod, g) for (g, _, _) in v]) for j, v in sutun.items()}))


def dizi_gecisi(T, J, kom, AKT_relu, kom_no=0):
    """Bir DİZİ komutu: ön-getirme (GMS'li okuma) + 16x16 PE + Psum FIFO + son'da grup/LMS/yazma."""
    _, faz, l, b, k0, k1, z, ilk, son, _ = kom
    k = S.KATMANLAR[l - 1]
    satir_cev, sutun = {}, {}
    if faz == FAZ_FP:
        o0, c, r0 = k0 * NB, k1, z * NB
        no, nr = min(NB, k["cout"] - o0), min(NB, k["ho"] - r0)
        Xp = PE.dolgu_ekle(T.harita(f"AKT{l - 1}", b, c), k["p"])
        cikis = {}
        for i in range(nr):
            X = [Xp[k["s"] * (r0 + i) + q] for q in range(3)]
            for j in range(no):
                psum = [0] * k["wo"] if ilk else J.fifo_oku((i, j), (b, r0))
                Wk = T.agr_oku(l, o0 + j, c)
                if k["s"] == 1:
                    cev, cik = PE.pe_gecis_s1(X, Wk, PE.ps_akisi_s(psum, len(X[0])))
                else:
                    cift, tek = zip(*[PE.cift_tek_ayir(s_) for s_ in X])
                    cev, cik = PE.pe_gecis_s2(list(cift), list(tek), Wk, PE.ps_akisi_s(psum, len(cift[0])))
                cikis[(i, j)] = [d[0] for (_, d) in cik]
                satir_cev.setdefault(i, cev)
                sutun.setdefault(j, PE.duzlestir(Wk))
        iz_kaydet(kom_no, k["s"] - 1, satir_cev, sutun)
        for (i, j), v in cikis.items():
            if not son:
                J.fifo_yaz((i, j), (b, r0), v)
        if son:
            relu = (lambda g: [FE.relu_ileri(v) for v in g]) if k["relu"] else None
            for i in range(nr):
                for x in range(k["wo"]):
                    lms_yaz(T, J, f"AKT{l}", b, k0, r0 + i, x, [cikis[(i, j)][x] for j in range(no)],
                            (o0, b, r0 + i, x), relu)
        return
    if faz == FAZ_BP:
        c0, o = k0 * NB, k1
        nc = min(NB, k["cin"] - c0)
        E = T.harita(f"HATA{l}", b, o)

        def geri(R, C):                                  # D86: maske GMS'li AKT[l-1] (harita GMS'li)
            if not AKT_relu:
                return None
            maske = [T.kelime_oku_gms(f"AKT{l - 1}", b, k0, R, C)[jj] for jj in range(nc)]
            return lambda g: [FE.relu_geri(e, a) for e, a in zip(g, maske)]
        if k["s"] == 1:
            m0 = z * NB
            nm = min(NB, k["h"] - m0)
            Ep = PE.dolgu_ekle(E, 2 - k["p"])
            cikis = {}
            for i in range(nm):
                X = [Ep[m0 + i + q] for q in range(3)]
                T_ = len(X[0])
                for j in range(nc):
                    psum = [0] * k["w"] if ilk else J.fifo_oku((i, j), (b, m0))
                    Wr = PE.dondur_180(T.agr_oku(l, o, c0 + j))
                    cev, cik = PE.pe_gecis_s1(X, Wr, PE.ps_akisi_s(psum, T_))
                    cikis[(i, j)] = [d[0] for (_, d) in cik]
                    satir_cev.setdefault(i, cev)
                    sutun.setdefault(j, PE.duzlestir(Wr))
            iz_kaydet(kom_no, 2, satir_cev, sutun)
            if not son:
                for ij, v in cikis.items():
                    J.fifo_yaz(ij, (b, m0), v)
                return
            for i in range(nm):
                for x in range(k["w"]):
                    lms_yaz(T, J, f"HATA{l - 1}", b, k0, m0 + i, x, [cikis[(i, j)][x] for j in range(nc)],
                            (c0, b, m0 + i, x), geri(m0 + i, x))
            return
        He, We = k["ho"], k["wo"]
        n = We + 1
        sifir = [0] * We
        p0 = z * NB
        np_ = min(NB, S.bp_gecis_sayisi(k) - p0)
        serit = {}
        for i in range(np_):
            p = p0 + i
            e_p = E[p] if p < He else sifir
            e_once = E[p - 1] if p >= 1 else sifir
            akislar = [PE.bp_s2_akisi(e_p), PE.bp_s2_akisi(e_p), PE.bp_s2_akisi(e_once)]
            T_ = len(akislar[0])
            for j in range(nc):
                Wk = T.agr_oku(l, o, c0 + j)
                w_yuklu = [[Wk[q][2], Wk[q][0], Wk[q][1]] for q in range(3)]
                psum4 = [[0] * n for _ in range(4)] if ilk else J.fifo_oku((i, j), (b, p0))
                cev, cik = PE.pe_gecis_bp_s2(akislar, w_yuklu, PE.ps_akisi_bp_s2(psum4, T_))
                serit[(i, j)] = [[d[s_] for (_, d) in cik] for s_ in range(4)]
                satir_cev.setdefault(i, cev)
                sutun.setdefault(j, PE.duzlestir(w_yuklu))
        iz_kaydet(kom_no, 3, satir_cev, sutun)
        if not son:
            for ij, v in serit.items():
                J.fifo_yaz(ij, (b, p0), v)
            return
        for q in range(n):
            for s_ in range(4):
                for i in range(np_):
                    R = 2 * (p0 + i) + s_ // 2 - k["p"]
                    C = 2 * q + s_ % 2 - k["p"]
                    if 0 <= R < k["h"] and 0 <= C < k["w"]:            # D52
                        lms_yaz(T, J, f"HATA{l - 1}", b, k0, R, C, [serit[(i, j)][s_][q] for j in range(nc)],
                                (c0, b, R, C), geri(R, C))
        return
    # WG (D73): satır i = giriş kanalı c0 + i, sütun j = çıkış kanalı o0 + j
    c0, o0, r = k0 * NB, k1 * NB, z
    nc, no = min(NB, k["cin"] - c0), min(NB, k["cout"] - o0)
    if ilk:
        for i in range(nc):
            for j in range(no):
                J.akum[(i, j)] = PE.sifir_matris(3, 3)
    for i in range(nc):
        Ap = PE.dolgu_ekle(T.harita(f"AKT{l - 1}", b, c0 + i), k["p"])
        a_sat = [Ap[k["s"] * r + q] for q in range(3)]
        for j in range(no):
            e_sat = T.harita(f"HATA{l}", b, o0 + j)[r]
            if k["s"] == 1:
                T_ = len(a_sat[0])
                cev, _ = PE.pe_gecis_wg_s1(a_sat, [e_sat + [0] * (T_ - len(e_sat))] * 3, J.akum[(i, j)])
            else:
                cift, tek = zip(*[PE.cift_tek_ayir(s_) for s_ in a_sat])
                T_ = len(cift[0])
                cev, _ = PE.pe_gecis_wg_s2(list(cift), list(tek), [e_sat + [0] * (T_ - len(e_sat))] * 3,
                                           J.akum[(i, j)])
            satir_cev.setdefault(i, cev)
            sutun.setdefault(j, cev)
    iz_kaydet(kom_no, 3 + k["s"], satir_cev, sutun)
    if son:
        for i in range(nc):
            for q in range(9):
                lms_yaz(T, J, f"GRAD{l}", 0, k1, c0 + i, q,
                        [PE.duzlestir(J.akum[(i, j)])[q] for j in range(no)], (o0, c0 + i, q // 3, q % 3))


def yorumla(sablon, T, etiket):
    L = S.L
    s_a = S.S_A0
    s_a_list = [s_a]
    lfsr = S.CY.kanal_tohumlari(S.N_SINIF)
    komutlar, isler = [], []
    J = None
    for kom_no, kom in enumerate(sablon):
        kom = list(kom)
        op, faz, l = kom[0], kom[1], kom[2]
        if op == OP_IS_BASLA:
            J = Is(faz, l, kom[4])
        elif op == OP_DIZI:
            dizi_gecisi(T, J, kom, l > 1 and S.KATMANLAR[l - 2]["relu"], kom_no)
        elif op == OP_OLCEK:
            assert all(not f for f in J.fifo.values()), "iş sonunda Psum FIFO boş olmalı"
            G = max(0, J.B_max - J.hedef)
            ad = {FAZ_FP: f"AKT{l}", FAZ_BP: f"HATA{l - 1}", FAZ_WG: f"GRAD{l}"}[faz]
            T.G[ad] = G
            isler.append((faz, l, G, {a: (M, l_, G - l_) for a, (M, l_) in J.olay.items()}))
        elif op == OP_SA:
            s_a = s_a + S.KATMANLAR[l - 1]["sw"] + T.G[f"AKT{l}"]
            s_a_list.append(s_a)
            kom[4] = s_a
        elif op == OP_CLU:
            b = kom[3]
            kom[4] = s_a
            a = T.kelime_oku_gms(f"AKT{L}", b, 0, 0, 0)[:S.N_SINIF]
            e = S.clu_yer_tutucu(a, s_a, etiket[b], lfsr)
            T.kelime_yaz(f"HATA{L}", b, 0, 0, 0, e, 0)           # CLU çıkışı SRU'dan geçmez: l = 0, G = 0
        elif op == OP_WU:
            k0, c = kom[4], kom[5]
            k = S.KATMANLAR[l - 1]
            no = min(NB, k["cout"] - k0 * NB)
            g9 = [T.kelime_oku_gms(f"GRAD{l}", 0, k0, c, q)[:no] for q in range(9)]
            for j in range(no):
                o = k0 * NB + j
                w = PE.duzlestir(T.agr_oku(l, o, c))
                T.agr_yaz(l, o, c, [FE.agirlik_guncelle(w[q], g9[q][j]) for q in range(9)])
        komutlar.append(kom)
    assert all(v is not None for kom in komutlar for v in kom)
    return komutlar, s_a_list, isler


def coz(T):
    """Tamponun son hâlinden tensörler (GMS'li değerler) ve ağırlıklar."""
    K = S.KATMANLAR
    def harita_hepsi(ad, B, C):
        return [[T.harita(ad, b, c) for c in range(C)] for b in range(B)]
    AKT = [None] + [harita_hepsi(f"AKT{l}", S.BATCH, K[l - 1]["cout"]) for l in range(1, S.L + 1)]
    HATA = [None] + [None] * S.L
    for l in range(1, S.L + 1):
        HATA[l] = harita_hepsi(f"HATA{l}", S.BATCH, K[l - 1]["cout"])
    W = [[[T.agr_oku(li + 1, o, c) for c in range(k["cin"])] for o in range(k["cout"])] for li, k in enumerate(K)]
    return AKT, HATA, W


# ----------------------------------------------------------------------------
# 4) Dosyalar
# ----------------------------------------------------------------------------
def yaz_komutlar(yol, komutlar):
    with open(yol, "w") as f:
        f.write(f"{len(komutlar)}\n")
        for kom in komutlar:
            f.write(" ".join(str(v) for v in kom) + "\n")


def yaz_bolgeler(yol, T):
    """bolgeler.txt: satır başına 'ad taban B C H W n_karo G' (G: son hâlde bölgenin G'si);
    sonra 'AGR l taban' satırları."""
    with open(yol, "w") as f:
        f.write(f"{len(T.bolge)} {S.L}\n")
        for ad, bg in T.bolge.items():
            f.write(f"{ad} {bg['taban']} {bg['B']} {bg['C']} {bg['H']} {bg['W']} {bg['n_karo']} {T.G[ad]}\n")
        for l, t in T.agr_taban.items():
            f.write(f"AGR {l} {t}\n")


def yaz_veri(yol, T):
    """veri_*.txt: ilk satır kelime sayısı; her satır 'bank adr l v0 .. v15' (yazılmış kelimeler)."""
    satir = []
    for bank in range(NB):
        for adr in sorted(T.veri[bank]):
            w, l = T.veri[bank][adr]
            satir.append(f"{bank} {adr} {l} " + " ".join(str(v) for v in w))
    with open(yol, "w") as f:
        f.write(f"{len(satir)}\n" + "\n".join(satir) + "\n")


def yaz_agirlik(yol, T):
    """agirlik_*.txt: ilk satır kelime sayısı; her satır 'bank adr w0 .. w8'."""
    satir = []
    for bank in range(NB):
        for adr in sorted(T.agr[bank]):
            satir.append(f"{bank} {adr} " + " ".join(str(v) for v in T.agr[bank][adr]))
    with open(yol, "w") as f:
        f.write(f"{len(satir)}\n" + "\n".join(satir) + "\n")


def yaz_onget_izi(yol, iz):
    """onget_izi.txt — tb_on_getirme için: her DİZİ komutunda ön-getirmenin diziye verdiği akışlar.
      1. satır: kayıt sayısı
      Her kayıt: K kom_no mod T nr nc
        nr*T satır (satır i, çevrim t sırasıyla): akis1[0..2] akis2[0..2] akis3[0..2] (int8; WG'de hata alanı 0)
        nc satır: mod < 4 ise sütun j'nin 9 ağırlığı (PE'ye yüklenen hâli: BP s1 döndürülmüş, BP s2 Fig. 4b);
                  WG'de sütun j'nin T çevrimlik hata akışı
      Kayıtta olmayan satırlar/sütunlar (nr, nc dışı) 0 olmalı."""
    with open(yol, "w") as f:
        f.write(f"{len(iz)}\n")
        for kom_no, mod, T_, satirlar, sutunlar in iz:
            nr, nc = 1 + max(satirlar), 1 + max(sutunlar)
            f.write(f"K {kom_no} {mod} {T_} {nr} {nc}\n")
            for i in range(nr):
                for t in range(T_):
                    f.write(" ".join(str(v) for v in satirlar[i][t]) + "\n")
            for j in range(nc):
                f.write(" ".join(str(v) for v in sutunlar[j]) + "\n")


# ----------------------------------------------------------------------------
# Ana program
# ----------------------------------------------------------------------------
def calistir(ag, klasor):
    S.ag_kur(ag)
    ad = ag["ad"]
    AKT0, W0, etiket = S.baslangic_verisi()
    t = DG.tensor_adimi_dizi(AKT0, W0, etiket)            # (II')
    T = tampon_kur(AKT0, W0)
    os.makedirs(klasor, exist_ok=True)
    yaz_veri(os.path.join(klasor, "veri_baslangic.txt"), T)
    yaz_agirlik(os.path.join(klasor, "agirlik_baslangic.txt"), T)
    sablon = komut_sablonu()
    global IZ
    IZ = []
    komutlar, s_a, isler = yorumla(sablon, T, etiket)      # (III'')
    iz, IZ = IZ, None
    AKT, HATA, W = coz(T)
    for l in range(1, S.L + 1):
        assert S.esit_mi(AKT[l], t["AKT"][l]), f"{ad}: AKT {l} farklı"
        assert S.esit_mi(HATA[l], t["HATA"][l]), f"{ad}: HATA {l} farklı"
    assert S.esit_mi(W, t["W"]), f"{ad}: son ağırlıklar farklı"
    assert s_a == t["s_a"], f"{ad}: s_a farklı"
    assert isler == t["isler"], f"{ad}: iş başına G ya da grup olayları (M, l, Δ) farklı"
    sayac = {}
    for kom in komutlar:
        sayac[OP_ADI[kom[0]]] = sayac.get(OP_ADI[kom[0]], 0) + 1
    n_kelime = sum(len(b) for b in T.veri)
    print(f"[{ad}] (III'') tampon modelli komut yorumlayıcı = (II') bit bit: {len(komutlar)} komut {sayac}; "
          f"veri tamponu {n_kelime} kelime ({sum(bg['B'] * bg['n_karo'] * tavan(bg['H'], NB) * bg['W'] for bg in T.bolge.values())} "
          f"adres/bank ayrıldı), ağırlık {sum(len(b) for b in T.agr)} kelime; s_a = {s_a}")
    yaz_komutlar(os.path.join(klasor, "komutlar_dizi.txt"), komutlar)
    yaz_bolgeler(os.path.join(klasor, "bolgeler.txt"), T)
    yaz_veri(os.path.join(klasor, "veri_beklenen.txt"), T)
    yaz_agirlik(os.path.join(klasor, "agirlik_beklenen.txt"), T)
    yaz_onget_izi(os.path.join(klasor, "onget_izi.txt"), iz)
    S.yaz_ag(os.path.join(klasor, "ag_yapilandirma.txt"))
    with open(os.path.join(klasor, "etiket.txt"), "w") as f:      # CLU'nun doğru sınıfları (örnek sırasıyla)
        f.write(" ".join(str(y) for y in etiket) + "\n")
    print(f"[{ad}] Vektörler yazıldı: {klasor}/ (PE başına en çok bekleyen Psum geçişi: {FIFO_EN_COK})")
    return komutlar, T


# AG3 (5b-3c): 16x16 giriş; 1. katmanda 16 PE satırının hepsi dolu, 2. katman BP s2'de 9 geçiş (> 8: satır i ve
# i + 8 aynı banka yazar, iki yarıda yazma yolu, D83), FP s2 dolgulu ve dolgusuz.
AG3 = dict(ad="ag3", batch=2, tohum=77, katmanlar=[
    dict(cin=2, cout=3,  h=16, w=16, s=1, p=1, relu=1, sw=-8),
    dict(cin=3, cout=4,  h=16, w=16, s=2, p=1, relu=1, sw=-8),
    dict(cin=4, cout=5,  h=8,  w=8,  s=2, p=0, relu=1, sw=-8),
    dict(cin=5, cout=10, h=3,  w=3,  s=1, p=0, relu=0, sw=-9),
])


# AG4 (5b-3d): 16'dan fazla kanal -> birden çok karo: FP'de 2 o-karosu, BP'de 2 c-karosu, WG'de 2 x 2 karo,
# WU'da 2 o-karosu (D85'in karo döngüleri RTL'de ilk kez).
AG4 = dict(ad="ag4", batch=2, tohum=99, katmanlar=[
    dict(cin=3,  cout=20, h=7, w=7, s=1, p=1, relu=1, sw=-8),
    dict(cin=20, cout=18, h=7, w=7, s=2, p=0, relu=1, sw=-9),
    dict(cin=18, cout=10, h=3, w=3, s=1, p=0, relu=0, sw=-9),
])


# AG5 (5c-c, D97): 32x32 giriş, H, W <= 32 (line buffer). 1. ve 2. katmanda FP/BP s1'de iki satır karosu (z = 1),
# 3. katmanda FP s2'nin 33 satırlık penceresi ve BP s2'de 17 geçiş (z = 1: dX satırı 2z - 1 bloğu -> -W payı;
# 16 <= e: +W payı), WG'de satır payı 1. Veri tamponu (AW = 9) için batch 1, 6 katman (LMAX >= 6).
AG5 = dict(ad="ag5", batch=1, tohum=55, katmanlar=[
    dict(cin=2, cout=3,  h=32, w=32, s=1, p=1, relu=1, sw=-8),
    dict(cin=3, cout=4,  h=32, w=32, s=1, p=1, relu=1, sw=-8),
    dict(cin=4, cout=4,  h=32, w=32, s=2, p=1, relu=1, sw=-8),
    dict(cin=4, cout=5,  h=16, w=16, s=2, p=0, relu=1, sw=-8),
    dict(cin=5, cout=6,  h=7,  w=7,  s=2, p=0, relu=1, sw=-8),
    dict(cin=6, cout=10, h=3,  w=3,  s=1, p=0, relu=0, sw=-9),
])


def main(klasor="adim5_vektorleri"):
    calistir(S.AG1, klasor)
    calistir(S.AG2, os.path.join(klasor, "ag2"))
    calistir(AG3, os.path.join(klasor, "ag3"))
    calistir(AG4, os.path.join(klasor, "ag4"))
    calistir(AG5, os.path.join(klasor, "ag5"))
    S.ag_kur(S.AG1)


if __name__ == "__main__":
    main()
