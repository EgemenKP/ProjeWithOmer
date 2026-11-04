# =============================================================================
#  performans_modeli.py — Dizili sistemin çevrim modeli ve GOPS tahmini (Adım 5b-3f)
# -----------------------------------------------------------------------------
#  1) Çevrim modeli: komut başına çevrim sayısı, RTL'in (sistem_dizi.v) simülasyonunda ölçülen sürelerden
#     çıkarıldı (tb_sistem_dizi'nin ölçüm kopyası, komut_sure.txt). Model, 4 test ağının ölçülen eğitim adımı
#     sürelerini (2448, 3608, 5614, 9450 çevrim) birebir vermeli (kontrol aşağıda).
#       DİZİ FP : ceil(H/16)·W (harita yükleme) + T + 10
#       DİZİ BP : 16 (ağırlık yükleme) + ceil(Ho/16)·Wo + T + 9; son = 1 ve s2 ise + 4·(T−1)·(2 if satır > 8 else 1)
#       DİZİ WG : W + Wo + T + 9 (+1 ilk = 1, +9 son = 1)
#       CLU 84, WU 14, diğerleri 3; komutlar arası 1 çevrim
#     T: FP s1 W+2p, FP s2 (W+2p+1)//2+1, BP s1 Wo+2(2−p), BP s2 Wo+2, WG s1 W+2p, WG s2 (W+2p+1)//2+1.
#  2) VGG16 benzeri ağ (D87), CIFAR-10, batch 256: bir eğitim adımının çevrimi, 200 MHz'te süre, GOPS
#     (2 × faydalı MAC / süre; dolguya ve sıfır eklemeye düşen işlemler sayılmaz), tepe 2304 MAC × 2 × 200 MHz
#     = 921,6 GOPS'a oran. RTL'in bugünkü sınırı (H, W ≤ 16, D90) aşılarak aynı zamanlama formülleriyle
#     DIŞ DEĞERLENDİRME; FC (512 -> 10) ve max-pool ihmal edildi (işlem payı < %0,01).
#  3) Aynı ağ için yüklemenin akışla örtüştüğü varsayımıyla (geçiş = T + sabit) üst sınır.
#  Hazırlayan: Claude, 04.11.2026 (final/, Adım 5b-3f)
# =============================================================================

import math

F_SAAT = 200e6
PE_MAC = 256 * 9


def T_akis(faz, s, p, W, Wo):
    if faz == "FP" or faz == "WG":
        return W + 2 * p if s == 1 else (W + 2 * p + 1) // 2 + 1
    return Wo + 2 * (2 - p) if s == 1 else Wo + 2


def katman_boyut(k):
    ho = (k["h"] + 2 * k["p"] - 3) // k["s"] + 1
    wo = (k["w"] + 2 * k["p"] - 3) // k["s"] + 1
    return ho, wo


def adim_cevrim(katmanlar, B, ortusme=False):
    """Bir eğitim adımının çevrim sayısı ve faydalı MAC sayısı. ortusme=True: yükleme akışla örtüşür."""
    c = 0
    n_kom = 0
    mac = 0
    L = len(katmanlar)
    karo = lambda n: math.ceil(n / 16)

    def ekle(d):
        nonlocal c, n_kom
        c += d + 1
        n_kom += 1

    for k in katmanlar:                                   # İLERİ
        ho, wo = katman_boyut(k)
        ekle(3)
        T = T_akis("FP", k["s"], k["p"], k["w"], wo)
        yuk = 0 if ortusme else karo(k["h"]) * k["w"]
        for _ in range(karo(k["cout"]) * k["cin"] * B * karo(ho)):
            ekle(yuk + T + 10)
        ekle(3); ekle(3)                                   # ÖLÇEK, SA
        mac += B * k["cout"] * k["cin"] * 9 * ho * wo
    for _ in range(B):
        ekle(84)                                           # CLU
    for li in reversed(range(L)):                         # GERİ
        k = katmanlar[li]
        ho, wo = katman_boyut(k)
        if li > 0:
            ekle(3)
            T = T_akis("BP", k["s"], k["p"], k["w"], wo)
            n = k["h"] if k["s"] == 1 else (k["h"] + k["p"] + 1) // 2
            yuk = 0 if ortusme else 16 + karo(ho) * wo
            for c0 in range(karo(k["cin"])):
                for o in range(k["cout"]):
                    for b in range(B):
                        for z in range(karo(n)):
                            d = yuk + T + 9
                            if o == k["cout"] - 1 and k["s"] == 2:
                                nr = min(16, n - 16 * z)
                                d += 4 * (T - 1) * (2 if nr > 8 else 1)
                            ekle(d)
            ekle(3)
            mac += B * k["cout"] * k["cin"] * 9 * ho * wo
        ekle(3)
        T = T_akis("WG", k["s"], k["p"], k["w"], wo)
        yuk = 0 if ortusme else k["w"] + wo
        for c0 in range(karo(k["cin"])):
            for o0 in range(karo(k["cout"])):
                for b in range(B):
                    for r in range(ho):
                        ilk = (b == 0 and r == 0)
                        son = (b == B - 1 and r == ho - 1)
                        ekle(yuk + T + 9 + int(ilk) + 9 * int(son))
        ekle(3)
        for _ in range(karo(k["cout"]) * k["cin"]):
            ekle(14)                                       # WU
        mac += B * k["cout"] * k["cin"] * 9 * ho * wo
    ekle(3)                                                # BİTTİ
    return c, mac, n_kom


def ag(katmanlar):
    return [dict(cin=a, cout=b, h=h, w=h, s=s, p=p) for (a, b, h, s, p) in katmanlar]


TEST = {
    "ag1": (ag([(2, 4, 7, 1, 1), (4, 4, 7, 2, 0), (4, 10, 3, 1, 0)]), 2, 2448),
    "ag2": (ag([(3, 4, 5, 1, 1), (4, 6, 5, 2, 1), (6, 10, 3, 1, 0)]), 3, 3608),
    "ag3": (ag([(2, 3, 16, 1, 1), (3, 4, 16, 2, 1), (4, 5, 8, 2, 0), (5, 10, 3, 1, 0)]), 2, 5614),
    "ag4": (ag([(3, 20, 7, 1, 1), (20, 18, 7, 2, 0), (18, 10, 3, 1, 0)]), 2, 9450),
}

# D87: conv64, conv64, conv128/s2, conv128, conv256/s2, conv256, conv256, conv512/s2, conv512, conv512,
#      conv512/s2, conv512, conv512 (+ max-pool, FC 512->10 ihmal)
VGG16_BENZERI = ag([(3, 64, 32, 1, 1), (64, 64, 32, 1, 1), (64, 128, 32, 2, 1), (128, 128, 16, 1, 1),
                    (128, 256, 16, 2, 1), (256, 256, 8, 1, 1), (256, 256, 8, 1, 1), (256, 512, 8, 2, 1),
                    (512, 512, 4, 1, 1), (512, 512, 4, 1, 1), (512, 512, 4, 2, 1), (512, 512, 2, 1, 1),
                    (512, 512, 2, 1, 1)])


def main():
    print("1) Çevrim modeli, ölçülen RTL simülasyonuna karşı (+5 çevrim: basla -> ilk komut, testbench):")
    for ad, (k, B, olculen) in TEST.items():
        c, mac, n = adim_cevrim(k, B)
        print(f"   {ad}: model {c} (+ başlangıç) | ölçülen {olculen} | fark {olculen - c}; "
              f"{n} komut, {mac} MAC, kullanım {mac / (c * PE_MAC):.2%}")
    print("2) VGG16 benzeri, CIFAR-10, batch 256, 200 MHz (dış değerlendirme, D90 sınırı aşılarak):")
    for ortusme in (False, True):
        c, mac, n = adim_cevrim(VGG16_BENZERI, 256, ortusme)
        sure = c / F_SAAT
        gops = 2 * mac / sure / 1e9
        print(f"   {'yükleme örtüşmeli (üst sınır)' if ortusme else 'bugünkü RTL zamanlaması'}: "
              f"{c:,} çevrim, {sure * 1e3:.1f} ms/adım, {mac / 1e9:.2f} G MAC, {gops:.1f} GOPS "
              f"(tepe 921,6 GOPS'un %{100 * gops / 921.6:.1f}'i); Shao: 771 GOPS")


if __name__ == "__main__":
    main()
