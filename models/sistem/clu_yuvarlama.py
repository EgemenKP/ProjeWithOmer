# =============================================================================
#  clu_yuvarlama.py — CLU çıkışındaki >>4 kaydırması için stokastik yuvarlama (D8)
# -----------------------------------------------------------------------------
#  Karar D8 (Ömer, 02.11.2026): (c) LFSR ile stokastik yuvarlama.
#
#  Dayanak (NITI): ti_loss.py satır 35 -> StoShift(out_grad, 4); ti_torch.py satır 33-46.
#    NITI'nin ortamı PyTorch 1.7 (Dockerfile). Bu sürümde tensör '//' işlemi sıfıra doğru
#    keser; yani StoShift işaret-büyüklükle çalışır:
#      q = |x| >> 4,  f = |x| mod 16,  r = 0..15 arası rastgele sayı
#      f > r ise q = q + 1        (yukarı yuvarlama olasılığı f/16, beklenen değer x/16)
#      sonuç = işaret(x) * q,  sonra int8_clip ile ±127'ye kırpılır (D9)
#
#  Rastgele sayı üreteci iki kaynakta da tanımlı değil (NITI torch.randint kullanıyor).
#  Donanım için seçilen alternatif:
#    - 16 bitlik Fibonacci LFSR, polinom x^16 + x^14 + x^13 + x^11 + 1 (periyot 65535)
#    - r = durumun alttaki 4 biti; her kullanımdan sonra LFSR 4 adım ilerler, böylece
#      ardışık r'ler örtüşmez
#    - her sınıf kanalının kendi LFSR'i var (Fig. 7'de CLU yolu kanal başına çizili, D3);
#      kanal tohumları aynı dizide eşit aralıklı: kanal i, ana tohumdan i * 6553 adım sonra
#
#  Bu dosya üç iş yapar: model, öz kontroller, RTL testbench'i için vektörler (vektorler/).
#  Hazırlayan: Claude (Ömer'in isteğiyle), 02.11.2026
#  Çalıştırma: python3 clu_yuvarlama.py   (ek kütüphane gerekmez)
# =============================================================================

import math      # math.trunc(x): x'i sıfıra doğru keser (NITI'nin yeniden yazımında)
import os        # os.makedirs: klasör oluşturur; os.path.join: yol birleştirir
import random    # random.seed(n): her çalıştırmada aynı vektörler; random.randint(a, b)

KAYDIRMA = 4                 # D5: CLU çıkışında >>4 (rastgele sayı da 4 bit)
N_KANAL = 10                 # D6: sınıf sayısı
ANA_TOHUM = 0xACE1           # kanal 0'ın LFSR tohumu (sıfır olmamalı)
ARALIK = 65535 // N_KANAL    # kanal tohumları arasındaki uzaklık (LFSR adımı): 6553
KLASOR = "vektorler"


# ----------------------------------------------------------------------------
# 1) MODEL
# ----------------------------------------------------------------------------
def lfsr_adim(s):
    """LFSR'in tek adımı: yeni bit = s[15] ^ s[13] ^ s[12] ^ s[10]; durum sola kayar,
    yeni bit en alta girer. (s >> k) & 1 : s'nin k. biti."""
    bit = ((s >> 15) ^ (s >> 13) ^ (s >> 12) ^ (s >> 10)) & 1
    return ((s << 1) & 0xFFFF) | bit            # & 0xFFFF: 16 bitte tut


def lfsr_ilerle(s, n):
    """LFSR'i n adım ilerletir."""
    for _ in range(n):
        s = lfsr_adim(s)
    return s


def kanal_tohumlari(n=N_KANAL):
    """Kanal i'nin tohumu: ana tohumdan i * ARALIK adım sonraki durum."""
    tohumlar = []
    s = ANA_TOHUM
    for _ in range(n):
        tohumlar.append(s)
        s = lfsr_ilerle(s, ARALIK)
    return tohumlar


def stok_yuvarla(x, r):
    """x: işaretli tamsayı (CLU'nun e_i'si), r: 0..15 rastgele sayı -> int8 (-127..127)."""
    isaret = -1 if x < 0 else 1
    m = abs(x)                                  # işaret-büyüklük: önce büyüklükle çalış
    q = m >> KAYDIRMA                           # tam kısım
    f = m & ((1 << KAYDIRMA) - 1)               # kesir: alttaki 4 bit
    if f > r:                                   # olasılık f/16
        q = q + 1
    q = min(q, 127)                             # D9: ±127
    return isaret * q


def kanal_yuvarla(durumlar, kanal, x):
    """Kanalın LFSR'inden r'yi alır, x'i yuvarlar, sonra o kanalın LFSR'ini 4 adım
    ilerletir. durumlar: kanal başına LFSR durumu listesi (yerinde güncellenir)."""
    r = durumlar[kanal] & ((1 << KAYDIRMA) - 1)
    y = stok_yuvarla(x, r)
    durumlar[kanal] = lfsr_ilerle(durumlar[kanal], KAYDIRMA)
    return y


# ----------------------------------------------------------------------------
# 2) ÖZ KONTROLLER
# ----------------------------------------------------------------------------
def niti_stoshift(x, r):
    """NITI StoShift'in (ti_torch.py 33-46) PyTorch 1.7 davranışıyla bağımsız yeniden
    yazımı; torch.randint'in ürettiği sayı yerine r verilir."""
    round_temp = math.trunc(x / 2 ** KAYDIRMA)              # 1.7'de '//' sıfıra doğru keser
    prob = abs(x - round_temp * 2 ** KAYDIRMA)
    karar = 0 if prob <= r else 1
    karar = karar * (1 if x > 0 else (-1 if x < 0 else 0))  # torch.sign
    return max(-127, min(127, round_temp + karar))          # int8_clip


def oz_kontrol():
    """Dönüş: yukarı yuvarlama olasılığının f/16'dan en büyük sapması."""
    # a) LFSR en uzun periyotlu: sıfır dışındaki 65535 durumun hepsi bir kez görülür
    gorulen = set()
    s = ANA_TOHUM
    for _ in range(65535):
        gorulen.add(s)
        s = lfsr_adim(s)
    assert s == ANA_TOHUM and len(gorulen) == 65535 and 0 not in gorulen
    # b) 4'er adımlık ilerleme de bütün durumları dolaşır; r'nin dağılımı
    sayac = [0] * 16
    gorulen = set()
    s = ANA_TOHUM
    for _ in range(65535):
        gorulen.add(s)
        sayac[s & 15] += 1
        s = lfsr_ilerle(s, KAYDIRMA)
    assert s == ANA_TOHUM and len(gorulen) == 65535
    assert sayac[0] == 4095 and all(c == 4096 for c in sayac[1:])
    sapma = max(abs(sum(sayac[:f]) / 65535 - f / 16) for f in range(16))
    # c) NITI StoShift ile birebir aynı: tüm x (-40000..40000) ve tüm r için
    for x in range(-40000, 40001):
        for r in range(16):
            assert stok_yuvarla(x, r) == niti_stoshift(x, r), (x, r)
    # d) kanal tohumları farklı ve sıfır değil
    t = kanal_tohumlari()
    assert len(set(t)) == N_KANAL and 0 not in t
    return sapma


# ----------------------------------------------------------------------------
# 3) TEST VEKTÖRLERİ
#   Satır = bir CLU işlemi: her kanal bir kez kullanılır, sonra LFSR'ler ilerler.
#   Dosya: 1. satır "N T KAYDIRMA", 2. satır N tohum (ondalık),
#          sonra T satır: x_0 y_0 x_1 y_1 ... x_(N-1) y_(N-1)
# ----------------------------------------------------------------------------
OZEL = [0, 1, -1, 15, -15, 16, -16, 17, -17, 31, -31, 2047, -2047, 2048, -2048,
        2032, -2032, 2033, -2033, 4095, -4095, 32767, -32768]


def vektor_uret(T=4096):
    random.seed(77)
    durumlar = kanal_tohumlari()
    satirlar = []
    for t in range(T):
        satir = []
        for k in range(N_KANAL):
            if t < len(OZEL):
                x = OZEL[(t + k) % len(OZEL)]     # her kanal özel değerleri farklı sırayla görür
            else:
                x = random.randint(-2048, 2048)   # CLU'nun e_i aralığı
            satir.append((x, kanal_yuvarla(durumlar, k, x)))
        satirlar.append(satir)
    return satirlar


def dosya_yaz(satirlar):
    os.makedirs(KLASOR, exist_ok=True)
    with open(os.path.join(KLASOR, "stok_yuvarla.txt"), "w") as f:
        f.write(f"{N_KANAL} {len(satirlar)} {KAYDIRMA}\n")
        f.write(" ".join(str(t) for t in kanal_tohumlari()) + "\n")
        for satir in satirlar:
            f.write(" ".join(f"{x} {y}" for x, y in satir) + "\n")


def dosya_geri_oku():
    """Dosyayı geri okuyup, değerleri modelle sıfırdan yeniden hesaplar."""
    sayilar = [int(v) for v in open(os.path.join(KLASOR, "stok_yuvarla.txt")).read().split()]
    n, T, k = sayilar[0:3]
    assert (n, k) == (N_KANAL, KAYDIRMA)
    tohumlar = sayilar[3:3 + n]
    assert tohumlar == kanal_tohumlari()
    durumlar = list(tohumlar)
    i = 3 + n
    for _ in range(T):
        for kanal in range(n):
            x, y = sayilar[i], sayilar[i + 1]
            i += 2
            assert kanal_yuvarla(durumlar, kanal, x) == y
    assert i == len(sayilar)
    return T * n


def okunur_yaz():
    p = ["CLU stokastik yuvarlama (D8 = c) — okunur döküm", "",
         f"LFSR: 16 bit, x^16 + x^14 + x^13 + x^11 + 1, kullanım başına {KAYDIRMA} adım; r = alt 4 bit",
         "Kanal tohumları (ondalık / hex):"]
    for i, t in enumerate(kanal_tohumlari()):
        p.append(f"  kanal {i}: {t:>5} / {t:04X}")
    p += ["", "Kanal 0'ın ilk 8 kullanımı, x = 40 (40/16 = 2,5) ile:",
          f"{'kullanım':>8} {'LFSR':>6} {'r':>3} {'f':>3} {'y':>3}"]
    durumlar = kanal_tohumlari()
    for u in range(8):
        s = durumlar[0]
        y = kanal_yuvarla(durumlar, 0, 40)
        p.append(f"{u:>8} {s:>6X} {s & 15:>3} {40 & 15:>3} {y:>3}   ({'yukarı' if y == 3 else 'aşağı'})")
    p += ["", "f = 8 olduğu için yukarı yuvarlama olasılığı 8/16; uzun vadede ortalama 2,5."]
    with open(os.path.join(KLASOR, "OKUNUR.txt"), "w") as f:
        f.write("\n".join(p) + "\n")


def main():
    sapma = oz_kontrol()
    print(f"1) Öz kontrol: LFSR periyodu 65535 (4'er adımda da), r dağılımı düzgün "
          f"(olasılık sapması en çok {sapma:.1e}), NITI StoShift ile 80001 x 16 durumda birebir aynı.")
    satirlar = vektor_uret()
    dosya_yaz(satirlar)
    n = dosya_geri_oku()
    okunur_yaz()
    print(f"2) Vektörler yazıldı ve geri okunup doğrulandı: {len(satirlar)} CLU işlemi x {N_KANAL} kanal = {n} değer.")
    print(f"   Kanal tohumları (hex): {' '.join(f'{t:04X}' for t in kanal_tohumlari())}")


if __name__ == "__main__":
    main()
