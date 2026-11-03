# =============================================================================
#  veriyolu_vektor_uret.py — Paket 2 testbench'i (tb_veriyolu) için bellek dosyaları
# -----------------------------------------------------------------------------
#  sistem_golden.py'nin yazdığı ag_yapilandirma.txt, baslangic.txt ve beklenen_sonuc.txt
#  dosyalarını okur; bellek düzenini (ARAYUZ_SOZLESMESI.md Bölüm 4) kurar ve iki dosya yazar:
#
#    veriyolu_duzen.txt  : satır 1: L BATCH N (N = kullanılan bayt sayısı)
#                          sonra L satır: cin cout h w s p
#                          sonra 4 satır: AKT[0..L], HATA[0..L], AGR[0..L] taban adresleri
#                          (HATA[0] ve AGR[0] kullanılmaz, 0) ve ETIKET tabanı
#    veriyolu_bellek.txt : satır 1: N; sonra N satır, her adres için
#                          "başlangıç beklenen bölge" (bölge: 100+l AKT[l], 200+l HATA[l],
#                          300+l AGR[l], 400 ETIKET, 0 ara boşluk)
#
#  Bölgeler arasında 16 baytlık ara boşluk var. Ara boşluklar ve çıkış bölgeleri (AKT[1..L],
#  HATA[1..L]) başlangıçta sıfır değil, sabit bir sözde-rastgele desenle dolu: bir satırın
#  dışını okuyan ya da yazılmadan okunan bir bölge varsa sonuç bozulur ve görünür olur.
#  Testbench ayrıca her baytın kaç kez yazıldığını sayar: çıkış bölgeleri ve AGR tam bir kez,
#  diğerleri hiç.
#
#  Kullanım: python3 veriyolu_vektor_uret.py [klasör ...]
#            (varsayılan: adim4_vektorleri ve adim4_vektorleri/ag2)
#  Yazan: Claude, 03.11.2026
# =============================================================================

import os
import sys

ARA = 16          # bölgeler arası boşluk (bayt)


def ag_oku(klasor):
    """ag_yapilandirma.txt: 1. satır L BATCH M_U S_A0 N_SINIF; sonra katman başına
    cin cout h w s p relu sw."""
    with open(os.path.join(klasor, "ag_yapilandirma.txt")) as f:
        satirlar = [s.split() for s in f if s.strip()]
    L, batch = int(satirlar[0][0]), int(satirlar[0][1])
    katmanlar = []
    for s in satirlar[1:1 + L]:
        cin, cout, h, w, st, p = (int(v) for v in s[:6])
        ho = (h + 2 * p - 3) // st + 1          # // : tamsayı bölmesi
        wo = (w + 2 * p - 3) // st + 1
        katmanlar.append(dict(cin=cin, cout=cout, h=h, w=w, s=st, p=p, ho=ho, wo=wo))
    return L, batch, katmanlar


def tensor_oku(yol):
    """'AD l b c r değerler' satırlarını sözlüğe alır: (AD, l, b, c, r) -> değer listesi.
    '#' ile başlayan satırlar atlanır. ETIKET satırı: ('ETIKET', b) -> [sınıf]."""
    t = {}
    with open(yol, encoding="utf-8") as f:
        for s in f:
            p = s.split()
            if not p or p[0].startswith("#"):
                continue
            if p[0] == "ETIKET":
                t[("ETIKET", int(p[1]))] = [int(p[2])]
            elif p[0] in ("AKT", "HATA", "W"):
                anahtar = (p[0], int(p[1]), int(p[2]), int(p[3]), int(p[4]))
                t[anahtar] = [int(v) for v in p[5:]]
    return t


def duzen_kur(L, batch, K):
    """Bölgelerin boyutları ve taban adresleri. AKT/HATA[l]: (b, kanal, satır, sütun);
    AGR[l]: (o, c, 3, 3)."""
    boyut_akt = [(K[0]["cin"], K[0]["h"], K[0]["w"])] + [(k["cout"], k["ho"], k["wo"]) for k in K]
    bolgeler = []                          # (ad, l, taban, uzunluk)
    adr = 0
    for l in range(L + 1):
        c, h, w = boyut_akt[l]
        bolgeler.append(("AKT", l, adr, batch * c * h * w))
        adr += batch * c * h * w + ARA
    for l in range(1, L + 1):
        c, h, w = boyut_akt[l]
        bolgeler.append(("HATA", l, adr, batch * c * h * w))
        adr += batch * c * h * w + ARA
    for l in range(1, L + 1):
        k = K[l - 1]
        bolgeler.append(("W", l, adr, k["cout"] * k["cin"] * 9))
        adr += k["cout"] * k["cin"] * 9 + ARA
    bolgeler.append(("ETIKET", 0, adr, batch))
    adr += batch
    return boyut_akt, bolgeler, adr


def desen(i):
    """Sabit sözde-rastgele bayt (-128..127): doğrusal eşlik üreteci."""
    return ((i * 1103515245 + 12345) >> 16) % 256 - 128


def uret(klasor):
    L, batch, K = ag_oku(klasor)
    bas = tensor_oku(os.path.join(klasor, "baslangic.txt"))
    son = tensor_oku(os.path.join(klasor, "beklenen_sonuc.txt"))
    boyut_akt, bolgeler, N = duzen_kur(L, batch, K)

    baslangic = [desen(i) for i in range(N)]     # ara boşluklar ve çıkış bölgeleri: desen
    beklenen = list(baslangic)
    bolge = [0] * N
    taban = {}
    for ad, l, t0, n in bolgeler:
        taban[(ad, l)] = t0
        kod = {"AKT": 100, "HATA": 200, "W": 300, "ETIKET": 400}[ad] + (l if ad != "ETIKET" else 0)
        for i in range(n):
            bolge[t0 + i] = kod

    def yerlestir(hedef, ad, l, kaynak, zorunlu):
        """kaynak sözlüğündeki (ad, l, ...) satırlarını bölgeye yazar."""
        t0 = taban[(ad, l)]
        if ad == "W":
            k = K[l - 1]
            for o in range(k["cout"]):
                for c in range(k["cin"]):
                    for r in range(3):
                        v = kaynak[("W", l, o, c, r)]
                        for j in range(3):
                            hedef[t0 + ((o * k["cin"] + c) * 3 + r) * 3 + j] = v[j]
            return
        C, H, W_ = boyut_akt[l]
        say = 0
        for b in range(batch):
            for c in range(C):
                for r in range(H):
                    a = (ad, l, b, c, r)
                    if a not in kaynak:
                        assert not zorunlu, f"{klasor}: {a} yok"
                        continue
                    v = kaynak[a]
                    assert len(v) == W_, (a, len(v), W_)
                    for k_ in range(W_):
                        hedef[t0 + ((b * C + c) * H + r) * W_ + k_] = v[k_]
                    say += 1
        assert say == batch * C * H, f"{klasor}: {ad} {l} eksik satır"

    # Başlangıç: giriş, ağırlıklar, etiketler
    yerlestir(baslangic, "AKT", 0, bas, True)
    for l in range(1, L + 1):
        yerlestir(baslangic, "W", l, bas, True)
    for b in range(batch):
        baslangic[taban[("ETIKET", 0)] + b] = bas[("ETIKET", b)][0]
    # Beklenen: giriş ve etiketler değişmez; AKT[1..L], HATA[1..L] ve ağırlıklar golden'dan
    beklenen = list(baslangic)
    for l in range(1, L + 1):
        yerlestir(beklenen, "AKT", l, son, True)
        yerlestir(beklenen, "HATA", l, son, True)
        yerlestir(beklenen, "W", l, son, True)

    with open(os.path.join(klasor, "veriyolu_duzen.txt"), "w") as f:
        f.write(f"{L} {batch} {N}\n")
        for k in K:
            f.write(f"{k['cin']} {k['cout']} {k['h']} {k['w']} {k['s']} {k['p']}\n")
        f.write(" ".join(str(taban[("AKT", l)]) for l in range(L + 1)) + "\n")
        f.write(" ".join(["0"] + [str(taban[("HATA", l)]) for l in range(1, L + 1)]) + "\n")
        f.write(" ".join(["0"] + [str(taban[("W", l)]) for l in range(1, L + 1)]) + "\n")
        f.write(f"{taban[('ETIKET', 0)]}\n")
    with open(os.path.join(klasor, "veriyolu_bellek.txt"), "w") as f:
        f.write(f"{N}\n")
        for i in range(N):
            f.write(f"{baslangic[i]} {beklenen[i]} {bolge[i]}\n")
    degisen = sum(1 for i in range(N) if baslangic[i] != beklenen[i])
    print(f"{klasor}: L {L}, batch {batch}, {N} bayt; tabanlar "
          + ", ".join(f"{ad}{l}={t0}" for ad, l, t0, _ in bolgeler) + f"; {degisen} bayt değişmeli")


if __name__ == "__main__":
    klasorler = sys.argv[1:] or ["adim4_vektorleri", os.path.join("adim4_vektorleri", "ag2")]
    for k in klasorler:
        uret(k)
