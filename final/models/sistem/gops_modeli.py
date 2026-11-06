# =============================================================================
#  gops_modeli.py — Faz 5: Table II'nin GOPS'u için RTL'in çevrim modeli (D108)
# -----------------------------------------------------------------------------
#  Shao (ISVLSI 2021) GOPS'u nasıl hesapladığını yazmıyor (yalnızca Table II: 200 MHz'de 771 GOPS). Burada:
#    tepe  = 2304 MAC × 2 işlem × 200 MHz = 921,6 GOPS (256 PE × 9 MAC, Fig. 2 / Fig. 8)
#    etkin = bir eğitim adımının yararlı işlem sayısı (2 × MAC; FP + BP + WG) / adımın süresi (çevrim / 200 MHz)
#  Adımın çevrimi: FSM'in komut listesi (dizi_sistem_golden.komut_sablonu ile aynı döngüler, burada analitik
#  sayılır) × komut başına çevrim formülü. Formül RTL'den (on_getirme.v / dizi_motoru.v / sistem_dizi.v'nin
#  durum sırası) çıkarıldı ve tb_sistem_dizi'nin komut izine (komut_cevrim.txt, ag1–ag6, 8082 komut) karşı
#  komut komut doğrulanır: sapma 0 olmalı (--iz ile).
#  Varsayım (sınırlama): bütün veri çip üstü tamponlarda (harici bellek / DDR yok, Shao da anlatmıyor);
#  VGG16-like batch 256'nın verisi gerçekte 824 RAMB36'ya sığmaz. Sayı yalnızca hesap + çip üstü yükleme süresi.
#  Yazan: Claude, 06.11.2026 (final/, Faz 5)
#  Çalıştırma: python gops_modeli.py [--iz <komut_cevrim.txt>]
# =============================================================================
import argparse, os

NB = 16
F_HZ = 200e6
MAC_SAYISI = 256 * 9
V = os.path.join(os.path.dirname(os.path.abspath(__file__)), "adim5_vektorleri")
ALT = ["", "ag2", "ag3", "ag4", "ag5", "ag6"]


def tavan(a, b):
    return -(-a // b)


def katman(cin, cout, h, w, s, p, relu=1):
    ho = (h + 2 * p - 3) // s + 1
    wo = (w + 2 * p - 3) // s + 1
    return dict(cin=cin, cout=cout, h=h, w=w, s=s, p=p, relu=relu, ho=ho, wo=wo)


def T_fw(k):            # on_getirme.v g_Tfw (FP / WG akış boyu)
    w2p = k["w"] + 2 * k["p"]
    return (w2p + 1) // 2 + 1 if k["s"] == 2 else w2p


def T_b(k):             # on_getirme.v g_Tb (BP akış boyu)
    return k["wo"] + 2 if k["s"] == 2 else k["wo"] + 4 - 2 * k["p"]


def n_bp(k):            # BP geçiş sayısı (sistem_golden.bp_gecis_sayisi, on_getirme.v g_np)
    return k["h"] if k["s"] == 1 else (k["h"] + k["p"] + 1) // 2


# ---- komut başına çevrim (önceki komutun kom_bitti'sinden bu komutunkine) ----
# DİZİ: motor M_BOS→M_ONGET + ön-getirme yükleme (AGR, SATIR, [HATA], BEKLE) + akış T + motorun sonu
# (M_SON1 / M_BEK / M_SON) + yürütücünün Y_DIZI → Y_BITTI → Y_BEKLE + FSM'in komut geçişi.
#   FP: 12 + w·⌈h/16⌉ + T_fw              (AGR 1 okuma; SATIR: kanalın bütün haritası, banklar paralel)
#   BP: 27 + wo·⌈ho/16⌉ + T_b             (AGR 16 ardışık okuma); s2'nin son geçişinde (o = cout−1) M_BP2:
#       4·(T_b − 1) çevrim, etkin satır > 8 ise ×2 (iki yarı)
#   WG: 11 + w + wo + T_fw                (SATIR 1 tur + HATA 1 tur); ilk'te +1 (M_WGRST), son'da +9 (M_WG)
# Diğerleri sabit: ÖLÇEK, SA, İŞ_BAŞLA, BİTTİ 4; CLU 85 (10 sınıf); WU 15.
SABIT = {2: 4, 4: 4, 5: 85, 6: 15, 7: 4, 8: 4}


def dizi_cevrimi(faz, k, z, ilk, son):
    if faz == 0:
        return 12 + k["w"] * tavan(k["h"], NB) + T_fw(k)
    if faz == 1:
        c = 27 + k["wo"] * tavan(k["ho"], NB) + T_b(k)
        if son and k["s"] == 2:
            nr = min(NB, n_bp(k) - NB * z)
            c += 4 * (T_b(k) - 1) * (2 if nr > 8 else 1)
        return c
    return 11 + k["w"] + k["wo"] + T_fw(k) + (1 if ilk else 0) + (9 if son else 0)


def adim(K, B):
    """Bir eğitim adımı: komut listesi analitik (dizi_sistem_golden.is_komutlari / komut_sablonu döngüleri).
    Döner: toplam çevrim, döküm (akış / yükleme+ek / sabit komutlar), MAC sayısı."""
    L = len(K)
    top = akis = sabit = 0
    mac = 0
    n_kom = 0

    def is_(faz, l):
        nonlocal top, akis, sabit, n_kom
        k = K[l - 1]
        top += SABIT[8] + SABIT[2]; sabit += SABIT[8] + SABIT[2]; n_kom += 2      # İŞ_BAŞLA + ÖLÇEK
        if faz == 0:
            n = tavan(k["cout"], NB) * B * tavan(k["ho"], NB) * k["cin"]
            top += n * dizi_cevrimi(0, k, 0, 0, 0); akis += n * T_fw(k); n_kom += n
        elif faz == 1:
            for z in range(tavan(n_bp(k), NB)):
                n = tavan(k["cin"], NB) * B
                top += n * ((k["cout"] - 1) * dizi_cevrimi(1, k, z, 0, 0) + dizi_cevrimi(1, k, z, 0, 1))
                akis += n * k["cout"] * T_b(k); n_kom += n * k["cout"]
        else:
            kk = tavan(k["cin"], NB) * tavan(k["cout"], NB)
            n = B * k["ho"]                                    # (k0, k1) başına; ilk ve son birer kez
            top += kk * (n * dizi_cevrimi(2, k, 0, 0, 0) + 1 + 9)
            akis += kk * n * T_fw(k); n_kom += kk * n

    for l in range(1, L + 1):
        is_(0, l)
        top += SABIT[4]; sabit += SABIT[4]; n_kom += 1                               # SA
    top += B * SABIT[5]; sabit += B * SABIT[5]; n_kom += B                           # CLU
    for l in range(L, 0, -1):
        k = K[l - 1]
        if l > 1:
            is_(1, l)
        is_(2, l)
        n = tavan(k["cout"], NB) * k["cin"]
        top += n * SABIT[6]; sabit += n * SABIT[6]; n_kom += n                       # WU
    top += SABIT[7]; sabit += SABIT[7]; n_kom += 1                                   # BİTTİ
    for l, k in enumerate(K, 1):
        m = B * k["ho"] * k["wo"] * k["cout"] * k["cin"] * 9
        mac += m * (3 if l > 1 else 2)                     # FP + WG (+ BP, ilk katmanda yok)
    return dict(cevrim=top, akis=akis, sabit=sabit, yukleme_ek=top - akis - sabit, mac=mac, n_kom=n_kom)


def yapilandirma(alt):
    s = open(os.path.join(V, alt, "ag_yapilandirma.txt")).read().split("\n")
    L, B = map(int, s[0].split()[:2])
    K = []
    for i in range(L):
        cin, cout, h, w, st, p, relu, _ = map(int, s[1 + i].split())
        K.append(katman(cin, cout, h, w, st, p, relu))
    return B, K


def vgg16like():
    """D101: VGG16-like, tamamen konvolüsyonel (egit.py ag_tanimi('vgg16like') ile aynı sıra), CIFAR-10 32×32."""
    cfg = [(64, 1), (64, 1), (128, 2), (128, 1), (256, 2), (256, 1), (256, 1), (512, 2), (512, 1), (512, 1),
           (512, 2), (512, 1), (512, 1), (10, 2)]
    K, cin, h = [], 3, 32
    for i, (cout, s) in enumerate(cfg):
        k = katman(cin, cout, h, h, s, 1, 0 if i == len(cfg) - 1 else 1)
        K.append(k)
        cin, h = cout, k["ho"]
    assert len(K) == 14 and K[-1]["ho"] == 1
    return K


def iz_dogrula(yol):
    AG = [yapilandirma(a) for a in ALT]
    hata = n = 0
    top = [0] * len(ALT)
    for sat in open(yol):
        v = list(map(int, sat.split()))
        if len(v) != 12:
            continue
        ag, op, faz, l, b, x, y, z, a1, a2, a3, cev = v
        B, K = AG[ag]
        bek = dizi_cevrimi(faz, K[l - 1], z, a1, a2) if op == 1 else SABIT[op]
        n += 1; top[ag] += cev
        if bek != cev:
            hata += 1
            if hata <= 5:
                print("  SAPMA:", v, "model", bek)
    for i, a in enumerate(ALT):
        B, K = AG[i]
        m = adim(K, B)["cevrim"]
        print(f"  {a or 'ag1'}: iz {top[i]} çevrim, analitik model {m}" + ("" if m == top[i] else "  <-- FARK"))
        hata += (m != top[i])
    print(f"IZ: {n} komut, {hata} sapma")
    return hata


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iz", help="tb_sistem_dizi'nin komut_cevrim.txt'si (ag1–ag6)")
    ap.add_argument("--batch", type=int, default=256)
    a = ap.parse_args()
    if a.iz:
        iz_dogrula(a.iz)
    K = vgg16like()
    r = adim(K, a.batch)
    t = r["cevrim"] / F_HZ
    tepe = MAC_SAYISI * 2 * F_HZ / 1e9
    etkin = 2 * r["mac"] / t / 1e9
    print(f"\nVGG16-like (D101), batch {a.batch}, bir eğitim adımı (FP + CLU + BP + WG + WU):")
    print(f"  komut {r['n_kom']:,}, çevrim {r['cevrim']:,} -> {t * 1e3:.1f} ms @ 200 MHz"
          f" (epoch = 196 adım -> {196 * t:.0f} s)")
    print(f"  döküm: akış {100 * r['akis'] / r['cevrim']:.1f}%, yükleme + komut başı/sonu "
          f"{100 * r['yukleme_ek'] / r['cevrim']:.1f}%, sabit komutlar {100 * r['sabit'] / r['cevrim']:.1f}%")
    print(f"  MAC {r['mac']:,} -> {2 * r['mac'] / 1e9:.2f} GOP")
    print(f"  tepe {tepe:.1f} GOPS, etkin {etkin:.1f} GOPS ({100 * etkin / tepe:.1f}% tepe); Shao 771 GOPS")
    print(f"  akış çevrimlerinde MAC kullanımı: {100 * r['mac'] / (MAC_SAYISI * r['akis']):.1f}%")
    # Neden analizi (tasarım değişikliği değil): yükleme akışla tam örtüşseydi (D50'de yok) süre ≈ akış çevrimleri
    print(f"  üst sınır, yükleme tam örtüşseydi: {2 * r['mac'] / (r['akis'] / F_HZ) / 1e9:.1f} GOPS")
    fp1 = sum(k["ho"] * k["wo"] * k["cout"] * k["cin"] * 9 for k in K)
    print(f"  (kontrol: bir görüntünün FP MAC'i {fp1 / 1e6:.1f} M)")


if __name__ == "__main__":
    main()
