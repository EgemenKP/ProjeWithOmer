"""
Shao et al. (ISVLSI 2021) - Cross-Entropy Loss Unit (CLU) altin modeli
========================================================================
Bu dosya FPGA'ye GITMIYOR. Tek amaci: Verilog/XSIM'de yazilacak RTL'in
uretmesi gereken DOGRU cikisi hesaplamak, boylece testbench bu degerlerle
bit-bit karsilastirma yapabilsin.

Uyguladigimiz kararlar (onaylandi, bkz. proje hafizasi):
  D1) gi = 2^ai - 1   (NITI kodu + Shao Algoritma 2 satir 4 ile tutarli)
  D2) EPU'nun Shift Unit'i iki yonlu (sa>=0 -> sola, sa<0 -> saga)
  D3) TEU kanal basina ayri (ama matematiksel olarak TEU'nun N kere
      cagrilmasiyla ayni sonucu verir, bu yuzden fonksiyon seviyesinde
      tek bir teu() fonksiyonu N kere cagriliyor)
  D4) EPU donanim blogu icin log2(e) ~= 184/2^7 (Algoritma 2 metnindeki
      47274/2^15 DEGIL -- Fig.7'de cizilen donanima sadik kaliniyor)
  D5) CLU ciktisina Shao'nun cizmedigi bir son kaydirma (>>4) + int8'e
      kirpma ekleniyor (NITI StoShift esdegeri). ACIK NOKTA: Shao'ya
      mail atildi, cevap gelince bu adim degisebilir.
  D6) N = 10 (CIFAR-10), henuz parametrik degil
  D7) Divider (sum'a bolme) icin yuvarlama davranisi: su an TRUNCATE
      (tam bolme, asagi yuvarlama) varsayiliyor -- makalede bu bolme
      icin ayri bir yuvarlama semasi belirtilmiyor. ACIK NOKTA.
  D8) Son kaydirma (D5) icin NITI'nin pseudo-stokastik yuvarlamasi
      (Algoritma 1) HENUZ uygulanmadi -- su an duz (deterministik)
      round-to-nearest kullaniliyor. Bit-tam eslesme icin ileride
      Algoritma 1'in RTL'deki ayniyla degistirilmesi gerekecek.
"""

N_DEFAULT = 10          # D6
INT8_MIN, INT8_MAX = -127, 127


def clip_int8(x: int) -> int:
    """int8 araligina kirpma (saturation), -127..+127."""
    return max(INT8_MIN, min(INT8_MAX, x))


def epu(ai: int, sa: int) -> int:
    """
    Exponential Unit (Fig.7 sag-alt detay).
    ai * 0xB8 (=184) >> 7  ->  log2(e)*ai yaklasik degeri
    sonra sa'ya gore iki yonlu kaydirma (D2).
    Donen deger: log2(e) * ai * 2^sa yaklasik degeri (tam sayi).
    """
    base = (ai * 0xB8) >> 7          # 184/2^7 ~ log2(e)   (D4)
    if sa >= 0:
        return base << sa
    else:
        return base >> (-sa)


def teu(ai: int, sa: int) -> int:
    """
    Taylor Expansion Unit - Algoritma 2, satir 6 (sa <= -7 dalı).
    gi <- 2^(1-2sa) + ai*2^(1-sa) + ai*ai
    """
    return (1 << (1 - 2 * sa)) + ai * (1 << (1 - sa)) + ai * ai


def compute_gi(a: list[int], sa: int) -> list[int]:
    """
    Algoritma 2, satir 1-7: sa'nin isaretine gore EPU ya da TEU dali.
    sa TUM kanallar icin ORTAK oldugundan, dal secimi global (kanal
    basina degil).
    """
    if sa > -7:
        scaled = [epu(ai, sa) for ai in a]        # her kanal icin EPU
        a_max = max(scaled)
        offset = a_max - 10                        # satir 3
        gi = []
        for s in scaled:
            ai_clip = max(0, s - offset)            # satir 4 (max(0,x))
            gi.append((1 << ai_clip) - 1)           # satir 4 (D1: -1 dahil)
        return gi
    else:
        return [teu(ai, sa) for ai in a]            # satir 6


def clu_golden(a: list[int], sa: int, y: list[int], N: int = N_DEFAULT,
                final_shift: int = 4) -> list[int]:
    """
    Tam CLU hattinin altin modeli (Fig.7 + D1..D8).

    a  : N adet int8 aktivasyon
    sa : ortak int8 olcek ussu
    y  : N adet one-hot etiket (0/1)
    donus: N adet int8 e_i (hata/gradyan)
    """
    assert len(a) == N and len(y) == N

    gi = compute_gi(a, sa)                          # satir 1-7

    sum1 = sum(gi)                                   # satir 8
    assert sum1 > 0, "sum1 sifir olamaz (bolme hatasi)"

    # satir 9-10: <<11 sonra sum1'e bolme (D7: truncating division)
    gi2 = [(g << 11) // sum1 for g in gi]
    sum2 = sum(gi2)                                  # satir 10 (yeni sum)

    e_raw = []
    for i in range(N):
        if y[i] == 1:
            e_raw.append(gi2[i] - sum2)              # satir 12
        else:
            e_raw.append(gi2[i])                     # satir 14

    # D5: son kaydirma + int8'e kirpma (Shao'da cizilmemis, varsayim)
    e_final = []
    for v in e_raw:
        # round-to-nearest saga kaydirma (D8: stokastik degil, simdilik)
        shifted = (v + (1 << (final_shift - 1))) >> final_shift
        e_final.append(clip_int8(shifted))

    return e_final


if __name__ == "__main__":
    # --- Basit duzey testleri (bit-tam RTL karsilastirmasi degil,
    #     sadece fonksiyonun calistigini ve makul deger urettigini
    #     gormek icin) ---

    print("Test 1: tek bir sinif baskin, sa=0 (EPU dali)")
    a = [20, 5, 3, 0, -10, 2, 1, 4, 0, -5]
    sa = 0
    y = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]   # dogru sinif = 0 (en yuksek skor)
    e = clu_golden(a, sa, y)
    print("  a  =", a)
    print("  e  =", e)
    print("  (dogru sinifin e'si negatif olmali -> agirliklar o yone itilir)")
    print()

    print("Test 2: yanlis siniflandirma, sa=0")
    y2 = [0, 1, 0, 0, 0, 0, 0, 0, 0, 0]   # dogru sinif = 1 (dusuk skor)
    e2 = clu_golden(a, sa, y2)
    print("  a  =", a)
    print("  e  =", e2)
    print("  (dogru sinifin skoru dusukken e cok daha negatif olmali -> buyuk hata)")
    print()

    print("Test 3: sa <= -7 (TEU dali)")
    a3 = [1, -1, 2, 0, -2, 1, 0, -1, 1, 0]
    sa3 = -8
    y3 = [0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    e3 = clu_golden(a3, sa3, y3)
    print("  a  =", a3)
    print("  e  =", e3)
