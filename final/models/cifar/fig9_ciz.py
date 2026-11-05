# =============================================================================
#  fig9_ciz.py — Shao Fig. 9'un karşılığı: epoch'a göre test hatası (%)
# -----------------------------------------------------------------------------
#  Shao Fig. 9: x = epoch (1-200), y = top-1 test hatası (%), VGG16 ve VGG16-like eğrileri.
#  Girdi: egit.py'nin egri.csv dosyaları. Kullanım:
#    python fig9_ciz.py --cikti sonuc/fig9.png sonuc/vgg16like_int:"VGG16-like (int8, bu çalışma)" \
#        sonuc/vgg16_int:"VGG16 (int8)" sonuc/vgg16like_float:"VGG16-like (float32)"
#  Hazırlayan: Claude, 05.11.2026 (final/, Adım 6, Faz 1)
# =============================================================================
import argparse
import csv
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt   # noqa: E402


def oku(klasor):
    with open(os.path.join(klasor, "egri.csv"), newline="") as f:
        satirlar = list(csv.DictReader(f))
    return [int(s["epoch"]) for s in satirlar], [float(s["test_hata"]) for s in satirlar]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kosular", nargs="+", help="klasör:etiket")
    ap.add_argument("--cikti", default="sonuc/fig9.png")
    a = ap.parse_args()
    plt.figure(figsize=(6, 4))
    for k in a.kosular:
        klasor, _, etiket = k.partition(":")
        x, y = oku(klasor)
        plt.plot(x, y, label=etiket or klasor)
        print(f"{etiket or klasor}: {len(x)} epoch, son test hatası {y[-1]:.2f}%, en düşük {min(y):.2f}%")
    plt.xlabel("Epoch")
    plt.ylabel("Test hatası (%)")
    plt.xlim(1, 200)
    plt.ylim(0, 80)
    plt.grid(alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(a.cikti, dpi=200)
    print("Kaydedildi:", a.cikti)


if __name__ == "__main__":
    main()
