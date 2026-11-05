# =============================================================================
#  kontrol_maxpool_fc.py — hizli_model'in max-pool ve FC yolları bağımsız (döngülü) referansa karşı
# -----------------------------------------------------------------------------
#  Bu iki yol yalnızca Fig. 9'un VGG16 referans eğrisinde (max-pool'lu ağ) kullanılıyor; RTL golden'ında
#  karşılıkları yok (D101'de VGG16-like tamamen konvolüsyonel). Burada denetlenen:
#    - max-pool ileri (2x2, s2) ve geri (hata, penceredeki ilk en büyüğün konumuna; satır öncelikli)
#    - FC ileri / geri (dX) / gradyan, int32 sarmalı toplam (PE'nin MAC'i gibi)
#  SRU ve CLU burada denetlenmez (kontrol_hizli.py golden'la bit bit denetliyor).
#  Hazırlayan: Claude, 05.11.2026 (final/, Adım 6, Faz 1)
# =============================================================================
import random
import torch
import torch.nn.functional as F

import hizli_model as H


def sar32(v):
    return ((v + 2 ** 31) % 2 ** 32) - 2 ** 31


def maxpool_ref(X):
    N, C, Hh, W = len(X), len(X[0]), len(X[0][0]), len(X[0][0][0])
    Y = [[[[0] * (W // 2) for _ in range(Hh // 2)] for _ in range(C)] for _ in range(N)]
    konum = {}
    for n in range(N):
        for c in range(C):
            for i in range(Hh // 2):
                for j in range(W // 2):
                    eniyi, yer = None, None
                    for di in range(2):
                        for dj in range(2):
                            v = X[n][c][2 * i + di][2 * j + dj]
                            if eniyi is None or v > eniyi:
                                eniyi, yer = v, (2 * i + di, 2 * j + dj)
                    Y[n][c][i][j] = eniyi
                    konum[(n, c, i, j)] = yer
    return Y, konum


def unpool_ref(E, konum, Hh, W):
    N, C = len(E), len(E[0])
    D = [[[[0] * W for _ in range(Hh)] for _ in range(C)] for _ in range(N)]
    for (n, c, i, j), (a, b) in konum.items():
        D[n][c][a][b] += E[n][c][i][j]
    return D


def matmul_ref(A, B):
    return [[sar32(sum(A[i][k] * B[k][j] for k in range(len(B)))) for j in range(len(B[0]))] for i in range(len(A))]


def main():
    r = random.Random(7)
    hata = []
    # ---- max-pool (eşitlikli değerler bilerek dar aralıktan) ----
    N, C, Hh, W = 2, 3, 6, 4
    X = [[[[r.randint(-3, 3) for _ in range(W)] for _ in range(Hh)] for _ in range(C)] for _ in range(N)]
    E = [[[[r.randint(-127, 127) for _ in range(W // 2)] for _ in range(Hh // 2)] for _ in range(C)] for _ in range(N)]
    Xt = torch.tensor(X, dtype=torch.int64, device=H.DEV)
    Y, ix = F.max_pool2d(Xt.double(), 2, 2, return_indices=True)
    Yr, konum = maxpool_ref(X)
    if Y.long().tolist() != Yr:
        hata.append("maxpool ileri")
    D = F.max_unpool2d(torch.tensor(E, dtype=torch.float64, device=H.DEV), ix, 2, 2, output_size=(Hh, W)).long()
    if D.tolist() != unpool_ref(E, konum, Hh, W):
        hata.append("maxpool geri (konum)")
    # ---- FC: ileri, dX, gradyan (int8 değerler, int32 sarmalı; taşmayı zorlamak için büyük K) ----
    Nb, K, O = 3, 70000, 5
    A = [[r.choice([-128, 127, r.randint(-128, 127)]) for _ in range(K)] for _ in range(Nb)]
    Wm = [[r.choice([-128, 127, r.randint(-127, 127)]) for _ in range(K)] for _ in range(O)]
    Ef = [[r.randint(-127, 127) for _ in range(O)] for _ in range(Nb)]
    At, Wt, Et = (torch.tensor(v, dtype=torch.int64, device=H.DEV) for v in (A, Wm, Ef))
    WT = [list(c) for c in zip(*Wm)]
    if H.int_mm(At, Wt.t()).tolist() != matmul_ref(A, WT):
        hata.append("fc ileri")
    if H.int_mm(Et, Wt).tolist() != matmul_ref(Ef, Wm):
        hata.append("fc geri dX")
    ET = [list(c) for c in zip(*Ef)]
    if H.int_mm(Et.t().contiguous(), At).tolist() != matmul_ref(ET, A):
        hata.append("fc gradyan")
    tasma = any(abs(sum(A[0][k] * WT[k][0] for k in range(K))) >= 2 ** 31 for _ in [0])
    print(f"FC'de int32 taşması denendi mi: {'evet' if tasma else 'hayır (yalnızca sarmasız aralık)'}")
    print("SONUC kontrol_maxpool_fc:", "PASS" if not hata else "FAIL " + ", ".join(hata))


if __name__ == "__main__":
    main()
