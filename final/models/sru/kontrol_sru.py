# kontrol_sru.py — GOLDEN MODEL DEĞİLDİR.
# PE_SRU_BASLANGIC.md Bölüm 3 ve 6'daki [Ölçüldü] sayılarını üreten tek seferlik kontrol betiği.
# Çalıştırma: python3 kontrol_sru.py   (yalnızca standart Python; torch gerekmez)
# NITI kodu içe aktarılmıyor; PstoShift/RoundShift mantığı ti_torch.py (commit d097335)
# okunarak elle yeniden yazıldı. trunc_div = PyTorch<1.13 '//', floor_div = PyTorch>=1.13 '//'.
import math, random

random.seed(1)

def B_paper(m):            # NITI makalesi: max değeri temsil için gereken en az bit
    return m.bit_length()

def B_code(m):             # NITI kodu: ceil(log2(max)), max==0 -> 0
    return 0 if m == 0 else math.ceil(math.log2(m))

# 1) Bitwidth tanımları nerede ayrışıyor?
diff = [m for m in range(1, 1 << 20) if B_paper(m) != B_code(m)]
print("1) B_paper != B_code sayisi:", len(diff), "| hepsi 2'nin kuvveti mi:",
      all(d & (d - 1) == 0 for d in diff), "| ilkler:", diff[:6])
print("   m=128: B_paper", B_paper(128), "-> shift", max(0, B_paper(128) - 7),
      "| B_code", B_code(128), "-> shift", max(0, B_code(128) - 7))

def alg1(q32, bp, bottom="niti", clip=True):
    """Shao Alg.1 / NITI Alg.3, işaret-büyüklük. bottom='niti' -> f[bp/2-1,0];
       bottom='shao_literal' -> f[bp/2,0] (Shao'daki yazım)."""
    s = -1 if q32 < 0 else 1
    a = abs(q32)
    q = (a >> bp) & 0xFF                 # |q32|[bp+7, bp]
    f = a & ((1 << bp) - 1)              # |q32|[bp-1, 0]
    if bp % 2 == 1:
        f >>= 1; bp -= 1
    h = bp // 2
    top = f >> h                          # f[bp-1, bp/2]
    if bottom == "niti":
        bot = f & ((1 << h) - 1)          # f[bp/2-1, 0]
    else:
        bot = f & ((1 << (h + 1)) - 1)    # f[bp/2, 0]  (literal)
    if bp > 0 and top > bot:
        q += 1
    q *= s
    if clip:
        q = max(-127, min(127, q))
    return q

def trunc_div(x, d):        # PyTorch < 1.13 '//' davranışı (sıfıra doğru)
    return int(x / d) if abs(x) < 2**52 else (abs(x) // d) * (1 if x >= 0 else -1)

def floor_div(x, d):        # PyTorch >= 1.13 '//' davranışı
    return x // d

def psto_code(x, shift, div):   # ti_torch.py PstoShift, elle yeniden yazım
    rt = div(x, 2**shift)
    prob = abs(x - rt * 2**shift)
    qp = div(prob, 2**(shift // 2))
    pr = prob - qp * 2**(shift // 2)
    if shift % 2 == 1:
        pr *= 2
    dec = 0 if qp <= pr else 1
    sgn = (x > 0) - (x < 0)
    return max(-127, min(127, rt + dec * sgn))

def round_code(x, shift, div):  # ti_torch.py RoundShift
    rt = div(x, 2**shift)
    prob = x - rt * 2**shift
    dec = div(prob, 2**(shift - 1))
    return max(-127, min(127, rt + dec))

# 2) Alg.1 (NITI düzeltmeli) vs NITI kodu (trunc) — çift/tek kaydırma
print("2) Alg.1(niti alt yarı) vs NITI PstoShift (trunc):")
for bp in range(1, 12):
    xs = [random.randint(-(1 << (bp + 7)) + 1, (1 << (bp + 7)) - 1) for _ in range(20000)]
    mis = sum(alg1(x, bp) != psto_code(x, bp, trunc_div) for x in xs)
    print(f"   bp={bp:2d} ({'tek' if bp % 2 else 'çift'}): farklı {mis}/20000")

# 3) Shao'daki yazım f[bp/2,0] ile NITI f[bp/2-1,0]: yukarı yuvarlama oranı ve ortalama hata
print("3) alt yarı aralığı etkisi (pozitif sayılar, doyma dışı):")
for bp in [2, 4, 6, 8]:
    xs = [random.randint(0, (1 << (bp + 6)) - 1) for _ in range(40000)]
    for mode in ["niti", "shao_literal"]:
        ups = sum(alg1(x, bp, mode) != (x >> bp) for x in xs) / len(xs)
        bias = sum(alg1(x, bp, mode) - x / 2**bp for x in xs) / len(xs)
        print(f"   bp={bp} {mode:13s}: yukari orani {ups:.3f}, ort. hata {bias:+.4f}")

# 4) Modern PyTorch (floor) ile NITI kodu negatiflerde ne yapıyor?
print("4) NITI PstoShift: trunc vs floor (negatif girişler):")
for bp in [2, 5, 8]:
    xs = [random.randint(-(1 << (bp + 6)), -1) for _ in range(20000)]
    mis = sum(psto_code(x, bp, trunc_div) != psto_code(x, bp, floor_div) for x in xs)
    err_t = sum(psto_code(x, bp, trunc_div) - x / 2**bp for x in xs) / len(xs)
    err_f = sum(psto_code(x, bp, floor_div) - x / 2**bp for x in xs) / len(xs)
    mx_f = max(abs(psto_code(x, bp, floor_div) - x / 2**bp) for x in xs)
    print(f"   bp={bp}: farklı {mis}/20000 | ort.hata trunc {err_t:+.3f} floor {err_f:+.3f} | floor maks |hata| {mx_f:.2f}")

# 5) bp=1 davranışı
print("5) bp=1: x=3 (1.5) ->", "Alg1:", alg1(3, 1), "NITI kodu:", psto_code(3, 1, trunc_div),
      "| x=-3 ->", alg1(-3, 1), psto_code(-3, 1, trunc_div))

# 6) Doyma gerekiyor mu? |x| = 255 << bp ... örnek: B=14, bp=7, x = 2^14-1
x = (1 << 14) - 1; bp = max(0, B_paper(x) - 7)
print("6) x=16383, bp=", bp, "-> klipsiz:", alg1(x, bp, clip=False), "klipli:", alg1(x, bp))
cnt = 0; tot = 0
for _ in range(200000):
    x = random.randint(1, (1 << 20) - 1); bp = max(0, B_paper(x) - 7)
    tot += 1; cnt += alg1(x, bp, clip=False) == 128
print("   rastgele 200k değerde klipsiz 128 çıkma sayısı:", cnt)

# 7) İki aşamalı (LMS+GMS) vs tek aşamalı (global) ölçekleme
def lms_gms(groups, delta_mode="shift"):
    Ms = [max(abs(v) for v in g) for g in groups]
    Bg = [B_paper(m) for m in Ms]
    G = max(0, max(Bg) - 7)
    out = []
    for g, b in zip(groups, Bg):
        l = max(0, b - 7)
        z = [alg1(v, l) for v in g]                       # LMS
        d = (G - l) if delta_mode == "shift" else (max(Bg) - b)   # GMS kaydırma
        out.append([alg1(v, d) for v in z])               # GMS
    return out, G

def one_stage(groups):
    M = max(max(abs(v) for v in g) for g in groups)
    G = max(0, B_paper(M) - 7)
    return [[alg1(v, G) for v in g] for g in groups], G

print("7) iki aşamalı vs tek aşamalı:")
for trial, scales in enumerate([(12, 14, 16, 18), (5, 9, 13, 17), (16, 16, 16, 16)]):
    groups = []
    for sc in scales:
        groups.append([int(random.gauss(0, 1) * (1 << sc) / 3) for _ in range(4000)])
    a, G1 = one_stage(groups); b, G2 = lms_gms(groups)
    flat = [v for g in groups for v in g]
    fa = [v for g in a for v in g]; fb = [v for g in b for v in g]
    mis = sum(x != y for x, y in zip(fa, fb)); mx = max(abs(x - y) for x, y in zip(fa, fb))
    ea = sum(q - v / 2**G1 for q, v in zip(fa, flat)) / len(flat)
    eb = sum(q - v / 2**G2 for q, v in zip(fb, flat)) / len(flat)
    rms_a = (sum((q - v / 2**G1) ** 2 for q, v in zip(fa, flat)) / len(flat)) ** .5
    rms_b = (sum((q - v / 2**G2) ** 2 for q, v in zip(fb, flat)) / len(flat)) ** .5
    print(f"   ölçekler {scales}: G={G1}, farklı {mis}/{len(fa)} ({100*mis/len(fa):.1f}%), maks fark {mx}, "
          f"rms hata tek {rms_a:.3f} iki {rms_b:.3f}, ort. hata tek {ea:+.4f} iki {eb:+.4f}")

# 8) GMS kaydırması: (G - l) mi, B(M) - B(Mg) mi? Küçük grup (B<7) örneği
groups = [[31, -20, 17], [400, -300, 123]]          # küçük grup B=5, büyük grup B=9
o1, G = lms_gms(groups, "shift"); o2, _ = lms_gms(groups, "bitdiff")
ref = [[round(v / 2**G, 2) for v in g] for g in groups]
print("8) G =", G, "| gerçek değer/2^G:", ref, "| (G-l):", o1, "| B(M)-B(Mg):", o2)

# 9) El kontrolü için örnek vakalar (dokümandaki tablo)
for x in [1846, 3218, -3218, 253, 338, 2044]:
    bp = max(0, B_paper(abs(x)) - 7)
    print(f"9) x={x:6d} bp={bp} gerçek={x / 2**bp:9.4f} Alg1={alg1(x, bp):5d} "
          f"Shao-yazımı={alg1(x, bp, 'shao_literal'):5d} klipsiz={alg1(x, bp, clip=False):5d} "
          f"NITI-kodu={psto_code(x, bp, trunc_div):5d}")
