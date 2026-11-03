# =============================================================================
#  kontrol_hizli.py — hizli_model.py, dizi golden'ının tensör düzeyiyle (II') bit bit aynı mı?
#  ag1, ag2 ve 16'dan fazla kanallı (birden çok karo) rastgele ağlarda bir eğitim adımı karşılaştırılır:
#  her katmanın aktivasyonu ve hatası, son ağırlıklar, s_a, iş başına G.
#  Hazırlayan: Claude, 04.11.2026 (final/, Adım 6)
# =============================================================================
import os
import sys
import random
import torch

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sistem"))
import sistem_golden as S          # noqa: E402
import dizi_golden as DG           # noqa: E402
import hizli_model as H            # noqa: E402


def t(x):
    return torch.tensor(x, dtype=torch.int64, device=H.DEV)


def karsilastir(ag):
    S.ag_kur(ag)
    AKT0, W0, etiket = S.baslangic_verisi()
    g = DG.tensor_adimi_dizi(AKT0, W0, etiket)
    katmanlar = []
    for li, k in enumerate(S.KATMANLAR):
        kk = H.Katman("conv", k["cin"], k["cout"], k["s"], k["p"], bool(k["relu"]), k["sw"])
        kk.W = t(W0[li])
        katmanlar.append(kk)
    h = H.egitim_adimi(katmanlar, t(AKT0), S.S_A0, t(etiket), S.M_U)
    hata = []
    for l in range(1, S.L + 1):
        if h["A"][l].tolist() != g["AKT"][l]:
            hata.append(f"AKT{l}")
        if h["E"][l].tolist() != g["HATA"][l]:
            hata.append(f"HATA{l}")
    if [k.W.tolist() for k in katmanlar] != g["W"]:
        hata.append("W")
    if h["s_a"] != g["s_a"]:
        hata.append(f"s_a {h['s_a']} != {g['s_a']}")
    G_golden = [G for (_, _, G, _) in g["isler"]]
    G_hizli = list(h["G_ileri"])
    for l in range(S.L, 0, -1):
        if l > 1:
            G_hizli.append(h["G_geri"][("BP", l)])
        G_hizli.append(h["G_geri"][("WG", l)])
    if G_hizli != G_golden:
        hata.append(f"G {G_hizli} != {G_golden}")
    return hata


def rastgele_ag(tohum):
    r = random.Random(tohum)
    h = r.choice([5, 7, 9])
    c1, c2 = r.choice([3, 17, 20]), r.choice([16, 18, 33])
    s2 = r.choice([1, 2])
    p2 = r.choice([0, 1])
    k1 = dict(cin=c1, cout=c2, h=h, w=h, s=1, p=1, relu=1, sw=-8)
    h2o = (h + 2 * p2 - 3) // s2 + 1
    k2 = dict(cin=c2, cout=r.choice([17, 20]), h=h, w=h, s=s2, p=p2, relu=1, sw=-8)
    katmanlar = [k1, k2]
    hh = h2o
    while hh > 3:                                    # 3x3'e inene kadar dolgusuz s1
        katmanlar.append(dict(cin=katmanlar[-1]["cout"], cout=r.choice([12, 18]), h=hh, w=hh, s=1, p=0, relu=1, sw=-8))
        hh -= 2
    katmanlar.append(dict(cin=katmanlar[-1]["cout"], cout=10, h=hh, w=hh, s=1, p=0, relu=0, sw=-9))
    if hh != 3:
        return None
    return dict(ad=f"rastgele{tohum}", batch=r.choice([2, 3]), tohum=tohum, katmanlar=katmanlar)


def main():
    aglar = [S.AG1, S.AG2]
    tohum = 1
    while len(aglar) < 6:
        a = rastgele_ag(tohum)
        tohum += 1
        if a:
            aglar.append(a)
    hepsi = True
    for ag in aglar:
        h = karsilastir(ag)
        kanal = [k["cout"] for k in ag["katmanlar"]]
        print(f"[{ag['ad']}] kanallar {kanal}, batch {ag['batch']}: " + ("BIT BIT AYNI" if not h else "FARK: " + ", ".join(h)))
        hepsi = hepsi and not h
    S.ag_kur(S.AG1)
    print("SONUC kontrol_hizli:", "PASS" if hepsi else "FAIL")


if __name__ == "__main__":
    main()
