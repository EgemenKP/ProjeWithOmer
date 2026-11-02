"""16-kanal testi icin: sru_katman.txt'den 2-gruplu 6 case'i (0,2,4,5,6,7)
secip 6 farkli SRU kanaline atiyoruz. Hepsi ayni cevrimde (lockstep)
calisir, ama PAYLASILAN G = max(tum 6 case'in B_global'i) olur --
her case'in kendi G'si DEGIL. GMS sonuclari bu paylasilan G ile
YENIDEN hesaplanir (LMS/B/l degismez, yalnizca GMS/delta degisir).
"""
import sys

def alg1(q32, bp):
    """SRU-a1=shao (h+1 bit alt yari), SRU-a3=doyma yok (8-bit sarma)."""
    s = -1 if q32 < 0 else 1
    a = abs(q32)
    q = (a >> bp) & 0xFF
    f = a & ((1 << bp) - 1)
    if bp % 2 == 1:
        f >>= 1
        bp -= 1
    h = bp // 2
    if bp > 0:
        top = f >> h
        bot = f & ((1 << (h+1)) - 1)
        if top > bot:
            q += 1
    qs = -q if s < 0 else q
    return ((qs + 128) % 256) - 128   # 8-bit sarma, doyma yok

# sru_katman.txt'yi parse et
with open("/home/claude/clu/sru_katman.txt") as f:
    toks = f.read().split()
idx = 0
def rd():
    global idx
    v = int(toks[idx]); idx += 1; return v

cfg = [rd() for _ in range(4)]
n_cases = rd()
cases = []
for c in range(n_cases):
    case_no, n_groups, G, Bglob = rd(), rd(), rd(), rd()
    groups = []
    for g in range(n_groups):
        grp_no, n, M, B, l, delta = rd(),rd(),rd(),rd(),rd(),rd()
        vals = []
        for j in range(n):
            x, lms, lmst, gms, gmst = rd(),rd(),rd(),rd(),rd()
            vals.append((x, lms, l))
        groups.append((n, B, l, vals))
    cases.append((case_no, n_groups, G, Bglob, groups))

# case0,2,4,5,6,7 -- hepsi 2 gruplu (CASE_LISTESI'nden biliniyor)
chosen = [0, 2, 4, 5, 6, 7]
sel = [c for c in cases if c[0] in chosen]

B_max = max(c[3] for c in sel)   # Bglob'larin en buyugu
G_shared = max(0, B_max - 7)
print(f"Secilen case'ler: {chosen}")
print(f"Her birinin kendi B_global'i: {[c[3] for c in sel]}")
print(f"Paylasilan B_max={B_max}, G_shared={G_shared}")

# her case bir kanala (0..5) gidiyor; yeni GMS = alg1(lms_degeri, G_shared-l)
with open("/home/claude/clu/sru_array_test.txt", "w") as out:
    out.write(f"{len(sel)} {G_shared}\n")
    for ch_idx, c in enumerate(sel):
        case_no, n_groups, G, Bglob, groups = c
        out.write(f"{ch_idx} {n_groups}\n")
        for (n, B, l, vals) in groups:
            delta = G_shared - l
            out.write(f"{n} {l}\n")
            for (x, lms, _l) in vals:
                new_gms = alg1(lms, delta)
                out.write(f"{x} {lms} {new_gms}\n")
        print(f"  kanal{ch_idx} (case{case_no}): G_shared={G_shared} ile yeniden hesaplandi")

print("\nsru_array_test.txt yazildi.")
