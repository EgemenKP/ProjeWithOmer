# kontrol_pe.py — GOLDEN MODEL DEĞİLDİR.
# PE_SRU_BASLANGIC.md Bölüm 5.3'teki şekil okumalarını (Shao Fig. 3-5) çevrim düzeyinde
# simüle edip referans hesapla karşılaştıran tek seferlik kontrol betiği.
# Çalıştırma: python3 kontrol_pe.py   (numpy gerekir)
import random
import numpy as np

random.seed(2)
r8 = lambda: random.randint(-127, 127)

def corr1d(x, w, s):                 # referans: y[j] = sum_k w[k] x[s*j + k]
    n = (len(x) - 3) // s + 1
    return [sum(w[k] * x[s * j + k] for k in range(3)) for j in range(n)]

def fp_row_s1(x, w):                 # Fig.3(a): yayın girişi + D'li kısmi toplam zinciri
    p1 = p2 = p3 = 0; out = []
    for t, xt in enumerate(x):
        p1, p2, p3 = 0 + w[0] * xt, p1 + w[1] * xt, p2 + w[2] * xt
        if t >= 2: out.append(p3)
    return out

def fp_row_s2(x, w):                 # Fig.3(b): çift akış w0'a, tek akış w1'e, gecikmeli çift akış w2'ye
    E = x[0::2] + [0]; O = [0] + x[1::2]      # +1 boşaltma (flush) çevrimi
    T = len(E)
    p1 = p2 = p3 = 0; d = 0; out = []
    for t in range(T):
        e_t = E[t]; o_t = O[t] if t < len(O) else 0
        p1, p2, p3 = 0 + w[0] * e_t, p1 + w[1] * o_t, p2 + w[2] * d
        d = e_t
        if t >= 2: out.append(p3)
    return out

def wg_row(a, e, s):                 # Fig.5: çıktı-durağan; e bir D zinciriyle kayıyor
    acc = [0, 0, 0]
    if s == 1:
        A = [[a[t]] * 3 for t in range(len(a))]          # yayın
    else:
        E = a[0::2]; O = [0] + a[1::2]
        A = []; d = 0
        for t in range(max(len(E), len(O)) + 1):   # +1 boşaltma çevrimi
            et = E[t] if t < len(E) else 0; ot = O[t] if t < len(O) else 0
            A.append([et, ot, d]); d = et
    ez = e + [0, 0, 0]
    for t in range(len(A)):
        for c in range(3):
            ec = ez[t - c] if 0 <= t - c < len(ez) else 0
            acc[c] += A[t][c] * ec
    return acc

def wg_ref(a, e, s):                 # g[c] = sum_tau a[s*tau + c] e[tau]
    return [sum(a[s * tau + c] * e[tau] for tau in range(len(e))) for c in range(3)]

ok = {"FP s1": 0, "FP s2": 0, "WG s1": 0, "WG s2": 0}
for _ in range(300):
    L = random.randint(5, 20); x = [r8() for _ in range(L)]; w = [r8() for _ in range(3)]
    ok["FP s1"] += fp_row_s1(x, w) == corr1d(x, w, 1)
    x2 = x if len(x) % 2 == 1 else x + [r8()]
    ok["FP s2"] += fp_row_s2(x2, w) == corr1d(x2, w, 2)
    for s in (1, 2):
        n = (len(x2) - 3) // s + 1
        e = [r8() for _ in range(n)]
        ok[f"WG s{s}"] += wg_row(x2, e, s) == wg_ref(x2, e, s)
print("1-B satır modelleri (300 rastgele deneme):", ok)

# 2-B FP s1: üç satır + dikey toplayıcı == 2-B korelasyon
def corr2d(X, W, s=1):
    H, Wd = X.shape; Ho = (H - 3) // s + 1; Wo = (Wd - 3) // s + 1
    Y = np.zeros((Ho, Wo), dtype=np.int64)
    for i in range(Ho):
        for j in range(Wo):
            Y[i, j] = int((W * X[s * i:s * i + 3, s * j:s * j + 3]).sum())
    return Y

X = np.random.randint(-127, 128, (7, 9)).astype(np.int64); W = np.random.randint(-127, 128, (3, 3)).astype(np.int64)
Y = np.array([[sum(fp_row_s1(list(X[i + r]), list(W[r]))[j] for r in range(3)) for j in range(9 - 2)] for i in range(7 - 2)])
print("2-B FP s1 (3 satır + toplayıcı) referansla aynı:", np.array_equal(Y, corr2d(X, W)))

# BP s1: 180° döndürülmüş çekirdek + sıfır dolgu (tam korelasyon) == dX (stride 1, dolgusuz ileri)
def conv_fwd(X, W, s, pad):
    Xp = np.pad(X, pad); return corr2d(Xp, W, s)
def bp_ref(E, W, s, pad, Hin, Win):   # dX[m,n] = sum_{i,j,kr,kc} W[kr,kc] E[i,j] [m = s*i+kr-pad, n = s*j+kc-pad]
    dX = np.zeros((Hin, Win), dtype=np.int64)
    for i in range(E.shape[0]):
        for j in range(E.shape[1]):
            for kr in range(3):
                for kc in range(3):
                    m, n = s * i + kr - pad, s * j + kc - pad
                    if 0 <= m < Hin and 0 <= n < Win:
                        dX[m, n] += W[kr, kc] * E[i, j]
    return dX
# (ileri geçişin adjoint'i olduğunu kontrol: <conv(X), E> == <X, bp(E)>)
for s, pad in [(1, 0), (1, 1), (2, 0), (2, 1)]:
    X = np.random.randint(-9, 10, (9, 9)).astype(np.int64)
    Yf = conv_fwd(X, W, s, pad); E = np.random.randint(-9, 10, Yf.shape).astype(np.int64)
    lhs = int((Yf * E).sum()); rhs = int((X * bp_ref(E, W, s, pad, 9, 9)).sum())
    assert lhs == rhs, (s, pad)
Wr = W[::-1, ::-1]
E = np.random.randint(-127, 128, (5, 6)).astype(np.int64)
dX_full = corr2d(np.pad(E, 2), Wr)          # stride 1, dolgusuz ileri geçişin geri yayılımı
print("BP s1 = döndürülmüş çekirdekle tam korelasyon:", np.array_equal(dX_full, bp_ref(E, W, 1, 0, 7, 8)))

# BP s2: dört çıktı grubu (satır/sütun paritesi) ve çekirdek alt kümeleri
def bp_s2_groups(E, W, pad):
    Hin = 2 * (E.shape[0] - 1) + 3 - 2 * pad; Win = 2 * (E.shape[1] - 1) + 3 - 2 * pad
    ref = bp_ref(E, W, 2, pad, Hin, Win)
    used = {}
    for pr in (0, 1):
        for pc in (0, 1):
            rows = [kr for kr in range(3) if (kr - pad) % 2 == pr]
            cols = [kc for kc in range(3) if (kc - pad) % 2 == pc]
            used[(pr, pc)] = (rows, cols)
            # yalnızca bu alt kümeyle hesapla
            Wm = np.zeros_like(W)
            for kr in rows:
                for kc in cols: Wm[kr, kc] = W[kr, kc]
            sub = bp_ref(E, Wm, 2, pad, Hin, Win)
            assert np.array_equal(sub[pr::2, pc::2], ref[pr::2, pc::2])
    return used
for pad in (0, 1):
    u = bp_s2_groups(np.random.randint(-127, 128, (4, 5)).astype(np.int64), W, pad)
    print(f"BP s2, ileri dolgu={pad}: (satır paritesi, sütun paritesi) -> (çekirdek satırları, sütunları):",
          {k: v for k, v in u.items()}, "| MAC sayıları:", {k: len(v[0]) * len(v[1]) for k, v in u.items()})

# int32 bit büyümesi
print("9*127^2 =", 9 * 127**2, "| x512 kanal =", 9 * 127**2 * 512, "< 2^31-1:", 9 * 127**2 * 512 < 2**31 - 1)
print("WG en kötü: 127^2 * 32*32 * B < 2^31-1 için B <=", (2**31 - 1) // (127**2 * 1024))
