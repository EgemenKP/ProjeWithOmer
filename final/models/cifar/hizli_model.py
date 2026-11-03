# =============================================================================
#  hizli_model.py — Dizi golden'ının (dizi_golden.py, tensör düzeyi II') GPU'daki bit bit kopyası
# -----------------------------------------------------------------------------
#  Amaç: Shao Fig. 9'un karşılığı (CIFAR-10 eğitimi) için golden'ın aritmetiğini hızlı koşturmak.
#  Golden (Python listeleri) ile RTL bit bit aynı; bu dosya golden'la bit bit aynı olmalı
#  (tests: kontrol_et() ag1, ag2 ve rastgele ağlarda dizi_golden.tensor_adimi_dizi ile karşılaştırır).
#
#  Aritmetik (DEVIATIONS'taki kararlarla):
#    - Konvolüsyonlar im2col + torch._int_mm: int8 x int8 -> int32 birikim (PE'nin MAC'i, taşmada sarar).
#      BP'nin col2im toplamı float64'te (tam).
#    - SRU: grup = bir konumdaki 16 kanal (D76); LMS (Alg. 1, SRU-a1/a2, doymasız D59) -> paylaşılan G ->
#      GMS (Δ = G − l, SRU-a8). FP'de ReLU, BP'de ReLU-geri (maske nihai aktivasyon, D86).
#    - WG: gradyan grupları aynı (c, ki, kj)deki 16 çıkış kanalı, hedef m_u (D40, D76); w − g ±127 (D41).
#    - CLU: sistem_golden.clu_yer_tutucu'nun vektör hâli (D1–D9, D60).
#    - s_a(l) = s_a(l−1) + s_w + G (D32).
#  Hazırlayan: Claude, 04.11.2026 (final/, Adım 6)
# =============================================================================

import torch
import torch.nn.functional as F

DEV = "cuda" if torch.cuda.is_available() else "cpu"
DOYMA = False              # D59: SRU doymasız (True: ±127, D38 — yalnızca ablasyon için)
GRUP = 16                  # D76: grup = 16 kanal (0: bütün tensör tek grup — NITI tarzı ablasyon)
YUVARLAMA_AE = "alg1"      # D33: a ve e için Alg. 1 | "round": NITI'nin RoundShift'i (ablasyon)

_IKI_KUVVET = None


def B(m):
    """D28: bit_length (m >= 0, int64)."""
    global _IKI_KUVVET
    if _IKI_KUVVET is None or _IKI_KUVVET.device != m.device:
        _IKI_KUVVET = (2 ** torch.arange(0, 62, device=m.device, dtype=torch.int64))
    return (m.unsqueeze(-1) >= _IKI_KUVVET).sum(-1)


def sarma8(q):
    return torch.remainder(q + 128, 256) - 128


def sru_yuvarla(q32, bp):
    """sru_golden.sru_yuvarla'nın vektör hâli (Alg. 1, ALT_YARI = shao, TEK_BP = makale)."""
    bp = bp.expand_as(q32) if torch.is_tensor(bp) else torch.full_like(q32, bp)
    isaret = torch.where(q32 < 0, -1, 1)
    m = q32.abs()
    q = (m >> bp) & 0xFF
    f = m & ((torch.ones_like(bp) << bp) - 1)
    tek = (bp % 2) == 1
    f = torch.where(tek, f >> 1, f)
    bp2 = torch.where(tek, bp - 1, bp)
    h = bp2 // 2
    ust = f >> h
    alt = f & ((torch.ones_like(h) << (h + 1)) - 1)
    q = q + ((bp2 > 0) & (ust > alt)).long()
    q = q * isaret
    if DOYMA:
        q = q.clamp(-127, 127)
    return sarma8(q)


def round_shift(q32, bp):
    """NITI RoundShift (ablasyon): en yakına, atılan en üst bit 1 ise yukarı (işaret-büyüklük)."""
    bp = bp.expand_as(q32) if torch.is_tensor(bp) else torch.full_like(q32, bp)
    isaret = torch.where(q32 < 0, -1, 1)
    m = q32.abs()
    q = (m >> bp) + torch.where(bp > 0, (m >> (bp - 1).clamp(min=0)) & 1, 0)
    return (q * isaret).clamp(-127, 127)


# ----------------------------------------------------------------------------
# int8 x int8 -> int32 çarpımlar (PE'nin MAC'leri)
# ----------------------------------------------------------------------------
def int_mm(a, b):
    """a (m, k), b (k, n) int8 değerli (herhangi tamsayı tipi) -> int64 (int32 birikim, taşmada sarar)."""
    m, k = a.shape
    n = b.shape[1]
    M_, K_, N_ = max(32, -(-m // 8) * 8), -(-k // 8) * 8, -(-n // 8) * 8
    A = torch.zeros((M_, K_), dtype=torch.int8, device=a.device)
    Bm = torch.zeros((K_, N_), dtype=torch.int8, device=a.device)
    A[:m, :k] = a.to(torch.int8)
    Bm[:k, :n] = b.to(torch.int8)
    return torch._int_mm(A, Bm)[:m, :n].long()


def im2col(X, s, p):
    """X (N, C, H, W) int8 değerli -> (N*Ho*Wo, C*9) int8, Ho, Wo. Sütun sırası (c, ki, kj)."""
    N, C, H, W = X.shape
    cols = F.unfold(X.to(torch.float16), kernel_size=3, stride=s, padding=p)   # int8 fp16'da tam
    Ho, Wo = (H + 2 * p - 3) // s + 1, (W + 2 * p - 3) // s + 1
    return cols.transpose(1, 2).reshape(N * Ho * Wo, C * 9).to(torch.int8), Ho, Wo


def conv_fp(X, Wt, s, p):
    """Y[n, o] = sum_c conv(X[n, c], W[o, c]) — int32."""
    N = X.shape[0]
    cols, Ho, Wo = im2col(X, s, p)
    Y = int_mm(cols, Wt.reshape(Wt.shape[0], -1).t())
    return Y.view(N, Ho, Wo, -1).permute(0, 3, 1, 2).contiguous()


def conv_bp(E, Wt, s, p, H, W):
    """dX: E (N, Cout, Ho, Wo), W (Cout, Cin, 3, 3) -> (N, Cin, H, W) (ref_bp)."""
    N, Co, Ho, Wo = E.shape
    Ecol = E.permute(0, 2, 3, 1).reshape(N * Ho * Wo, Co)
    cols = int_mm(Ecol, Wt.reshape(Co, -1))                              # (N*Ho*Wo, Cin*9)
    cols = cols.view(N, Ho * Wo, -1).transpose(1, 2).to(torch.float64)
    Hp, Wp = (Ho - 1) * s + 3, (Wo - 1) * s + 3
    dXp = F.fold(cols, output_size=(Hp, Wp), kernel_size=3, stride=s)
    dX = torch.zeros((N, Wt.shape[1], H + 2 * p, W + 2 * p), dtype=torch.float64, device=E.device)
    dX[:, :, :Hp, :Wp] = dXp[:, :, :H + 2 * p, :W + 2 * p]
    return dX[:, :, p:p + H, p:p + W].round().long()


def conv_wg(X, E, s, p):
    """G[o, c, ki, kj] = sum_{n, i, j} Xp[n, c, s*i+ki, s*j+kj] * E[n, o, i, j] (batch üzerinden de toplar)."""
    N, Co, Ho, Wo = E.shape
    cols, _, _ = im2col(X, s, p)
    Ecol = E.permute(0, 2, 3, 1).reshape(N * Ho * Wo, Co)
    G = int_mm(Ecol.t().contiguous(), cols)                              # (Cout, Cin*9)
    return G.view(Co, X.shape[1], 3, 3)


# ----------------------------------------------------------------------------
# SRU: LMS -> paylaşılan G -> GMS, grup = kanal ekseninde 16'lık parçalar (D76)
# ----------------------------------------------------------------------------
def sru_katman(Y, hedef):
    """Y (N, C, ...) int32. Dönüş: (GMS sonrası int8 değerler, G). Grup: aynı (n, konum)daki 16 kanal."""
    N, C = Y.shape[0], Y.shape[1]
    g = GRUP if GRUP else None
    if g is None:                                                         # NITI tarzı: tek grup
        M = Y.abs().max()
        l = (B(M.view(1)) - hedef).clamp(min=0)
        yuv = sru_yuvarla if YUVARLAMA_AE == "alg1" or hedef != 7 else round_shift
        return yuv(Y, l.view([1] * Y.dim())), int(l.item())
    T = -(-C // g)
    pad = T * g - C
    Yp = F.pad(Y, [0, 0] * (Y.dim() - 2) + [0, pad]) if pad else Y
    Yg = Yp.view(N, T, g, *Y.shape[2:])
    M = Yg.abs().amax(2, keepdim=True)
    Bv = B(M)
    l = (Bv - hedef).clamp(min=0)
    yuv = sru_yuvarla if YUVARLAMA_AE == "alg1" or hedef != 7 else round_shift
    c8 = yuv(Yg, l)
    G = max(0, int(Bv.max().item()) - hedef)
    out = sru_yuvarla(c8, G - l)
    return out.view(N, T * g, *Y.shape[2:])[:, :C].contiguous(), G


def sru_wg(Gw, m_u):
    """WG gradyanı (Cout, Cin, 3, 3): grup = aynı (c, ki, kj)deki 16 çıkış kanalı, hedef m_u."""
    g8, G = sru_katman(Gw.permute(1, 0, 2, 3).contiguous(), m_u)
    return g8.permute(1, 0, 2, 3).contiguous(), G


# ----------------------------------------------------------------------------
# CLU (sistem_golden.clu_yer_tutucu, D60 = a)
# ----------------------------------------------------------------------------
def clu(a, s_a, y):
    """a (N, 10) int8 değerli, s_a int, y (N,) -> e (N, 10)."""
    if s_a > -7:
        t = (a * 184) >> 7
        t = t << s_a if s_a >= 0 else t >> (-s_a)
        ofset = t.max(1, keepdim=True).values - 10
        g = (torch.ones_like(t) << (t - ofset).clamp(min=0)) - 1
    else:
        g = (1 << (1 - 2 * s_a)) + a * (1 << (1 - s_a)) + a * a
    toplam = g.sum(1, keepdim=True)
    g2 = torch.div(g << 11, toplam, rounding_mode="floor")
    toplam2 = g2.sum(1, keepdim=True)
    e = g2 - toplam2 * F.one_hot(y, a.shape[1]).long()
    return ((e + 8) >> 4).clamp(-127, 127)


# ----------------------------------------------------------------------------
# Ağ ve bir eğitim adımı (dizi_golden.tensor_adimi_dizi ile aynı sıra)
# ----------------------------------------------------------------------------
class Katman:
    """tur: 'conv' (3x3, s, p) | 'fc' | 'maxpool' (2x2). relu: çıkışta ReLU."""
    def __init__(self, tur, cin=0, cout=0, s=1, p=1, relu=True, sw=-8):
        self.tur, self.cin, self.cout, self.s, self.p, self.relu, self.sw = tur, cin, cout, s, p, relu, sw
        self.W = None


def ileri(katmanlar, A0, s_a0, kayit=None):
    """Dönüş: (aktivasyonlar listesi, s_a listesi, G listesi, maxpool indisleri)."""
    A, s_a, Gs, idx = [A0], [s_a0], [], {}
    for li, k in enumerate(katmanlar):
        X = A[-1]
        if k.tur == "maxpool":
            Y, ix = F.max_pool2d(X.double(), 2, 2, return_indices=True)
            idx[li] = (ix, X.shape)
            A.append(Y.long()); s_a.append(s_a[-1]); Gs.append(None)
            continue
        if k.tur == "fc":
            Y = int_mm(X.reshape(X.shape[0], -1), k.W.t())
        else:
            Y = conv_fp(X, k.W, k.s, k.p)
        Y8, G = sru_katman(Y, 7)
        if k.relu:
            Y8 = Y8.clamp(min=0)
        A.append(Y8); s_a.append(s_a[-1] + k.sw + G); Gs.append(G)
    return A, s_a, Gs, idx


def egitim_adimi(katmanlar, A0, s_a0, y, m_u):
    """Bir eğitim adımı; ağırlıkları yerinde günceller. Dönüş: dict(A, E, s_a, G)."""
    A, s_a, G_ileri, idx = ileri(katmanlar, A0, s_a0)
    L = len(katmanlar)
    son = A[-1].reshape(A[-1].shape[0], -1)
    E = {L: clu(son, s_a[-1], y).view(A[-1].shape)}
    G_geri = {}
    for li in reversed(range(L)):
        k = katmanlar[li]
        El = E[li + 1]
        X = A[li]
        if k.tur == "maxpool":
            ix, sh = idx[li]
            dX = F.max_unpool2d(El.double(), ix, 2, 2, output_size=sh[2:]).long()
            if li > 0 and katmanlar[li - 1].relu and katmanlar[li - 1].tur != "maxpool":
                dX = torch.where(A[li] > 0, dX, torch.zeros_like(dX))
            E[li] = dX
            continue
        if li > 0:                                               # 1. katmanda BP yok (D46)
            if k.tur == "fc":
                dX = int_mm(El.reshape(El.shape[0], -1), k.W).view(X.shape)
            else:
                dX = conv_bp(El, k.W, k.s, k.p, X.shape[2], X.shape[3])
            dX8, G = sru_katman(dX, 7)
            G_geri[("BP", li + 1)] = G
            if _relu_once(katmanlar, li - 1):                    # ReLU-geri, maske nihai aktivasyon (D86)
                dX8 = torch.where(X > 0, dX8, torch.zeros_like(dX8))
            E[li] = dX8
        if k.tur == "fc":
            Gw = int_mm(El.reshape(El.shape[0], -1).t().contiguous(), X.reshape(X.shape[0], -1))
            g8, G = sru_katman(Gw.t().contiguous().view(Gw.shape[1], Gw.shape[0]), m_u)
            g8 = g8.t()
        else:
            g8, G = sru_wg(conv_wg(X, El, k.s, k.p), m_u)
        G_geri[("WG", li + 1)] = G
        k.W = (k.W - g8).clamp(-127, 127)                       # D41
    return dict(A=A, E=E, s_a=s_a, G_ileri=G_ileri, G_geri=G_geri)


def _relu_once(katmanlar, li):
    """maxpool'un girişi ReLU'lu bir katmansa maske gerekir."""
    while li >= 0 and katmanlar[li].tur == "maxpool":
        li -= 1
    return li >= 0 and katmanlar[li].relu
