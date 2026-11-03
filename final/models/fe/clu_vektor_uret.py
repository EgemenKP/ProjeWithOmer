# =============================================================================
#  clu_vektor_uret.py — Adım 3.4: fonksiyon motoru testi için CLU vektörleri
# -----------------------------------------------------------------------------
#  Model: sistem golden modelindeki CLU yer tutucusu, D8 = (a) en yakına yuvarlama
#         (Egemen'in clu_top.v'si ve golden_model.py'si böyle; 1500 vektörde birebir
#         aynı olduğu 03.11'de ölçüldü). D1-D9 Egemen'in DEVIATIONS.md'sinden.
#  Çıktı: fe_vektorleri/clu_vektorleri.txt — satır başına 22 sayı: a0..a9 s_a y e0..e9
#    1) 1500 vektör: 03.11 inceleme vektörleri (tohum 303), a ∈ [-127, 127]
#    2) 40 vektör: Egemen'in models/clu/vectors.txt'si (beklenenler burada yeniden hesaplanır
#       ve dosyadakiyle karşılaştırılır)
#    3) 400 vektör: a'da -128 olan durumlar (D59: doymasız SRU -128 üretebilir), tohum 2027
#  Çalıştırma (models/fe klasöründe): python3 clu_vektor_uret.py ../clu/vectors.txt
#  Ek kütüphane gerekmez.
#  Yazan: Claude, 03.11.2026
# =============================================================================
import random   # random.seed(n): her çalıştırmada aynı vektörler; random.randint(a, b): a..b arası
import sys      # sys.argv: komut satırı argümanları
import os       # os.path.join, os.makedirs


def clu_rtn(a, s_a, y):
    """CLU, Shao Alg. 2 + D1-D9, son >>4 en yakına yuvarlanır (D8 = a). y: doğru sınıfın indisi."""
    if s_a > -7:                                   # EPU dalı (Shao III-C: s_a > -7)
        x = []
        for ai in a:
            t = (ai * 184) >> 7                    # D4: log2(e) ≈ 184/2^7
            t = t << s_a if s_a >= 0 else t >> (-s_a)
            x.append(t)
        ofset = max(x) - 10                        # en büyük üs tam 10 olsun
        g = [(1 << max(0, xi - ofset)) - 1 for xi in x]   # D1: 2^x - 1
    else:                                          # TEU dalı: 2. dereceden Taylor
        g = [(1 << (1 - 2 * s_a)) + ai * (1 << (1 - s_a)) + ai * ai for ai in a]
    toplam = sum(g)
    g2 = [(gi << 11) // toplam for gi in g]        # D7: bölmede kesme
    toplam2 = sum(g2)
    e = [g2[i] - toplam2 if i == y else g2[i] for i in range(len(a))]
    return [max(-127, min(127, (ei + 8) >> 4)) for ei in e]   # D5 + D8 (a) + D9


def main():
    satirlar = []

    # 1) 03.11 inceleme vektörleri (aynı tohum ve aynı sıra)
    random.seed(303)
    for k in range(1500):
        if k < 20:
            a = [k * 6 - 60] * 10                  # hepsi eşit
        else:
            a = [random.randint(-127, 127) for _ in range(10)]
        s_a = random.randint(-12, 3)
        y = random.randint(0, 9)
        satirlar.append(a + [s_a, y] + clu_rtn(a, s_a, y))

    # 2) Egemen'in 40 vektörü: girişleri al, beklenenleri yeniden hesapla, dosyayla karşılaştır
    farkli = 0
    for s in open(sys.argv[1]):
        if not s.strip():
            continue
        v = list(map(int, s.split()))
        a, s_a, y, e_dosya = v[0:10], v[10], v[11], v[12:22]
        e = clu_rtn(a, s_a, y)
        if e != e_dosya:
            farkli += 1
        satirlar.append(a + [s_a, y] + e)
    assert farkli == 0, f"Egemen'in vektörlerinde {farkli} satır modelle uyuşmuyor"

    # 3) -128 içeren durumlar
    random.seed(2027)
    ozel = [[-128] * 10,                                   # hepsi -128
            [-128] * 9 + [127],                            # biri en büyük, kalanı -128
            [127] + [-128] * 9,
            [-128, 0, 0, 0, 0, 0, 0, 0, 0, 0]]
    for k in range(400):
        if k < 4 * 4:
            a = list(ozel[k % 4])
            s_a = [-12, -7, -6, 3][k // 4]                 # TEU ve EPU dallarının sınırları
        else:
            a = [random.choice([-128, -128, random.randint(-128, 127)]) for _ in range(10)]
            s_a = random.randint(-12, 3)
        y = random.randint(0, 9)
        satirlar.append(a + [s_a, y] + clu_rtn(a, s_a, y))

    os.makedirs("fe_vektorleri", exist_ok=True)
    with open(os.path.join("fe_vektorleri", "clu_vektorleri.txt"), "w") as f:
        for s in satirlar:
            f.write(" ".join(map(str, s)) + "\n")
    n128 = sum(1 for s in satirlar if -128 in s[0:10])
    print(f"{len(satirlar)} vektör yazıldı (a'da -128 olan: {n128}); Egemen'in 40 vektörü modelle aynı.")


if __name__ == "__main__":
    main()
