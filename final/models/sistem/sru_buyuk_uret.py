# =============================================================================
#  sru_buyuk_uret.py — Adım 4 (D63): 64 gruplu SRU tamponu için test vektörleri
# -----------------------------------------------------------------------------
#  sru_golden.py'nin katman() fonksiyonuyla (LMS + GMS, 03.11 kararları: doyma yok)
#  çok gruplu katmanlar üretir. Biçim sru_katman.txt ile aynı:
#    1. satır ayar kodu, 2. satır CASE_SAYISI
#    her case : CASE_NO GRUP_SAYISI G B_global
#    her grup : GRUP_NO N M B l Δ
#    N satır  : q32 lms8 lms_tasma gms8 gms_tasma
#  Case'ler: 64 grup (tam dolu), 60 (ag2'nin en çoğu), 56 (ag1'in en çoğu), 17 (eski
#  16 sınırını aşan en küçük), 1 grup, ve grup boyu 1..16 karışık 64 grup.
#  Çalıştırma: python3 sru_buyuk_uret.py   (sru_golden.py aynı klasörde)
#  Çıktı: adim4_vektorleri/sru_buyuk.txt
#  Yazan: Claude, 03.11.2026
# =============================================================================
import os
import random
import sru_golden as SRU


def main():
    random.seed(6464)
    vakalar = []
    for n_grup in (64, 60, 56, 17, 1):
        vakalar.append(SRU.rastgele_gruplar(n_grup, 16))
    karisik = []
    for _ in range(64):                         # grup boyu 1..16 karışık
        karisik.append(SRU.rastgele_gruplar(1, random.randint(1, 16))[0])
    vakalar.append(karisik)

    os.makedirs("adim4_vektorleri", exist_ok=True)
    with open(os.path.join("adim4_vektorleri", "sru_buyuk.txt"), "w") as f:
        f.write(" ".join(map(str, SRU.ayar_kodu())) + "\n")
        f.write(f"{len(vakalar)}\n")
        for case_no, gruplar in enumerate(vakalar):
            G, Bg, sonuclar = SRU.katman(gruplar)
            SRU.katman_kontrol(gruplar, G, Bg, sonuclar)       # bağımsız referansla kontrol
            f.write(f"{case_no} {len(gruplar)} {G} {Bg}\n")
            for grup_no, (g, s) in enumerate(zip(gruplar, sonuclar)):
                f.write(f"{grup_no} {len(g)} {s['M']} {s['B']} {s['l']} {s['delta']}\n")
                for i in range(len(g)):
                    f.write(f"{g[i]} {s['lms8'][i]} {s['lms_tasma'][i]} "
                            f"{s['gms8'][i]} {s['gms_tasma'][i]}\n")
    print(f"{len(vakalar)} case yazıldı: grup sayıları {[len(v) for v in vakalar]}")


if __name__ == "__main__":
    main()
