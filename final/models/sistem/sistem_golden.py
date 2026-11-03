# =============================================================================
#  sistem_golden.py — Adım 4 sistem golden modeli: küçük ağın BİR eğitim adımı
# -----------------------------------------------------------------------------
#  Ne üretir:
#    1) komutlar.txt  : Master controller'ın (FSM) üretmesi gereken komut sırası.
#                       FSM RTL'inin çıktısı bununla satır satır karşılaştırılıyor.
#    2) maksreg.txt   : Max Regs bloğunun olay kaydı: her grubun yerel maksimumu (M) ve
#                       LMS kaydırması (l), her işin G'si, her KOPYA/WU'nun Δ'sı.
#                       Sahte PE M değerlerini buradan okur; testbench maks_reg
#                       çıkışlarını bununla karşılaştırır.
#    3) ag_yapilandirma.txt : FSM'e verilecek katman tablosu.
#    4) baslangic.txt / beklenen_sonuc.txt : 4.5 entegrasyonu için başlangıç belleği
#                       ve beklenen sonuçlar (ağırlıklar, aktivasyonlar, hatalar, s_a).
#    5) OKUNUR.txt    : Özet ve kontrol sonuçları.
#
#  Doğrulama (üç bağımsız yol):
#    (I)  KOMUT YORUMLAYICI: komut listesini adım adım yürütür; PE çevrim modeli
#         (pe_golden), ön-getirme (akış hazırlama), SRU, ReLU, ağırlık güncelleme.
#    (II) TENSÖR DÜZEYİ: aynı eğitim adımını katman fonksiyonlarıyla (ref_fp/bp/wg)
#         ve iki aşamalı SRU ile hesaplar. (I) ve (II) bit bit aynı olmalı.
#    (III) FLOAT: aynı ağ numpy ile ondalıklı; int sonuçların yönü/büyüklüğü tutmalı.
#
#  Güncelleme (03.11.2026): SRU'da doyma yok (D59, sru_golden.DOYMA = False); CLU'nun son
#  >>4'ü en yakına (D60, D8_YUVARLAMA = "a"); (III)'ün sıkı eşikleri doymalı referans
#  çalıştırmada (D65).
#
#  Kararlar: K4+K5 (1 PE, son katman 3x3 conv), K6a (kopyalama geçişi), K6b (doğrudan
#  ağırlık yazma), K9 (grup = bir PE satırının bir geçişi), K7 ve m_u kural gereği NITI.
#  Revizyon (02.11.2026, Ömer'in kuralı: önce Shao; Shao sessizse NITI; ikisi de
#  sessizse uygun bir alternatif. Ayrıntı: TASARIM_FSM.md Bölüm 9):
#    T1  Örnek (batch) döngüsü kanal çiftinin içinde: FP o→c→b→r, BP c→o→b→p,
#        WG o→c→b→r (Shao III-D: örnekler PE satırlarına, çıkış kanalları sütunlara açılır).
#    T4  Max Regs ayrı bir blok ve grubun yerel maksimumunu (M, 32 bit) saklar
#        (Shao III-B, Fig. 6).
#    T8  KOPYA'da önce ReLU, sonra GMS (Fig. 8: fonksiyon motoru çıkış tamponunda;
#        Fig. 6: GMS tampondan PE'ye giden yolda). Sonuç bit bit aynı; kontrol ediliyor.
#    Yeni komut İŞ_BAŞLA: her PE işinden önce gelir; tamponları ve Max Regs'i sıfırlar,
#    SRU hedef genişliğini (7 ya da m_u) bildirir.
#  CLU: YER TUTUCU (Shao Alg. 2 + DEVIATIONS D1-D9'dan yazıldı). D8 (03.11, D60): (a) en
#  yakına yuvarlama; Egemen'in golden_model.py'siyle 1940 vektörde birebir aynı.
#  D8_YUVARLAMA = "c" yapılırsa LFSR'li stokastik (D57, clu_yuvarlama.py). Gerçek CLU golden
#  modeliniz gelince clu_yer_tutucu() değiştirilecek. FSM komut sırası CLU'ya bağlı
#  değil; yalnızca veriye bağlı alanlar (s_a, M, G, Δ) değişir, dosyalar yeniden üretilir.
#
#  Hazırlayan: Claude (Ömer'in isteğiyle), 02.11.2026
#  Çalıştırma: python3 sistem_golden.py  (pe_golden.py, sru_golden.py, fe_golden.py
#              aynı klasörde; float kontrol için numpy gerekir)
# =============================================================================

import os
import random
import numpy as np            # yalnızca (III) float kontrolünde kullanılıyor

import pe_golden as PE
import sru_golden as SRU
import fe_golden as FE
import clu_yuvarlama as CY     # D8 = c seçilirse: CLU çıkışındaki >>4'ün stokastik yuvarlaması

D8_YUVARLAMA = "a"            # D60 (Ömer, 03.11): "a" = (e + 8) >> 4, en yakına (Egemen'in CLU'su)
                              #   | "c" = LFSR'li stokastik (D57, askıda)

# ----------------------------------------------------------------------------
# 4.1 TEST AĞLARI
#   AG1: ana test ağı (K4 + K5). 4.5 entegrasyonu bunu kullanacak.
#   AG2: yalnızca FSM testini güçlendirmek için ikinci yapılandırma. Her katmanda
#        Cin ≠ Cout, s_w'ler farklı, batch 3, dolgulu stride 2 (BP'de T6 atlaması var).
#        AG1'de son iki katmanda s_w + G = 0 olduğu için s_a değişmiyor; AG2 bu
#        durumda gizli kalabilecek hataları da görünür kılıyor.
# ----------------------------------------------------------------------------
M_U = 5                 # NITI takviminin ilk değeri (5 -> 4 -> 3); burada sabit
S_A0 = -7               # giriş verisinin ölçek üssü
N_SINIF = 10            # D6
HEDEF_AKT = 7           # a ve e için SRU hedef genişliği
MAKS_REG_DERINLIK = 64  # RTL'deki maks_reg derinliği (AD = 6); bir işteki grup sayısı aşamaz
AG1 = dict(ad="ag1", batch=2, tohum=4242, katmanlar=[
    # cin: giriş kanalı, cout: çıkış kanalı, h/w: giriş boyutu, s: stride, p: dolgu,
    # relu: çıkışta ReLU var mı, sw: ağırlık ölçek üssü (s_w, eğitimde değişmez)
    dict(cin=2, cout=4,  h=7, w=7, s=1, p=1, relu=1, sw=-8),   # FP s1, WG s1 (BP yok: 1. katman)
    dict(cin=4, cout=4,  h=7, w=7, s=2, p=0, relu=1, sw=-8),   # FP s2, BP s2, WG s2
    dict(cin=4, cout=10, h=3, w=3, s=1, p=0, relu=0, sw=-8),   # FP s1, BP s1, WG s1 (FC eşdeğeri)
])
AG2 = dict(ad="ag2", batch=3, tohum=2026, katmanlar=[
    dict(cin=3, cout=4,  h=5, w=5, s=1, p=1, relu=1, sw=-8),
    dict(cin=4, cout=6,  h=5, w=5, s=2, p=1, relu=1, sw=-7),   # BP s2 dolgulu: 3 geçiş (He + 1 = 4 değil)
    dict(cin=6, cout=10, h=3, w=3, s=1, p=0, relu=0, sw=-9),
])


def ag_kur(ag):
    """Modül düzeyindeki ağ değişkenlerini (BATCH, TOHUM, KATMANLAR, L) verilen ağa göre kurar.
    Fonksiyonlar bu değişkenleri her çağrıda okuduğu için başka bir değişiklik gerekmez."""
    global BATCH, TOHUM, KATMANLAR, L
    BATCH = ag["batch"]
    TOHUM = ag["tohum"]
    KATMANLAR = [dict(k) for k in ag["katmanlar"]]     # dict(k): katmanın kopyası
    L = len(KATMANLAR)
    for k in KATMANLAR:
        k["ho"] = (k["h"] + 2 * k["p"] - 3) // k["s"] + 1   # çıkış yüksekliği
        k["wo"] = (k["w"] + 2 * k["p"] - 3) // k["s"] + 1   # çıkış genişliği
    assert KATMANLAR[-1]["ho"] == 1 and KATMANLAR[-1]["wo"] == 1 and KATMANLAR[-1]["cout"] == N_SINIF


ag_kur(AG1)

# Komut kodları (op)
OP_PE, OP_OLCEK, OP_KOPYA, OP_SA, OP_CLU, OP_WU, OP_BITTI, OP_IS_BASLA = 1, 2, 3, 4, 5, 6, 7, 8
FAZ_FP, FAZ_BP, FAZ_WG = 0, 1, 2
ISLEM_YOK, ISLEM_RELU_ILERI, ISLEM_RELU_GERI = 0, 1, 2
OP_ADI = {1: "PE", 2: "OLCEK", 3: "KOPYA", 4: "SA", 5: "CLU", 6: "WU", 7: "BITTI", 8: "IS_BASLA"}
FAZ_ADI = {0: "FP", 1: "BP", 2: "WG"}
# maksreg.txt olay türleri (her satır 4 tamsayı: tür, grup, değer1, değer2)
OLAY_YEREL = 1          # 1 grup M l : grubun yerel maksimumu ve LMS kaydırması
OLAY_G = 2              # 2 0 G 0    : ÖLÇEK'te katmanın toplam kaydırması
OLAY_DELTA = 3          # 3 grup Δ 0 : KOPYA/WU'da grubun GMS kaydırması


def bp_gecis_sayisi(k):
    """BP'de bir (örnek, kanal) için geçiş sayısı.
    stride 1: her dX satırı bir geçiş (h). stride 2: her geçiş 2 dX satırı üretir;
    hiç geçerli satır üretmeyecek geçişler atlanır: ceil((h + p) / 2)."""
    if k["s"] == 1:
        return k["h"]
    return (k["h"] + k["p"] + 1) // 2


def bp_s2_satirlari(k, p):
    """BP s2'de p. geçişin ürettiği geçerli dX satırları (dolgu kırpıldıktan sonra)."""
    return [R for R in (2 * p - k["p"], 2 * p + 1 - k["p"]) if 0 <= R < k["h"]]


def dongu_sinirlari(faz, k):
    """PE işinin 4 döngü sayacının sınırları (n0 en dış, n3 en iç). T1:
       FP: o -> c -> b -> r    BP: c -> o -> b -> p    WG: o -> c -> b -> r"""
    if faz == FAZ_FP:
        return k["cout"], k["cin"], BATCH, k["ho"]
    if faz == FAZ_BP:
        return k["cin"], k["cout"], BATCH, bp_gecis_sayisi(k)
    return k["cout"], k["cin"], BATCH, k["ho"]


def hedef_genislik(faz):
    """SRU'nun hedef genişliği: a ve e için 7, g için m_u (K2a)."""
    return M_U if faz == FAZ_WG else HEDEF_AKT


# ----------------------------------------------------------------------------
# Veri üretimi
# ----------------------------------------------------------------------------
def rastgele_harita(h, w, alt=-127, ust=127):
    return [[random.randint(alt, ust) for _ in range(w)] for _ in range(h)]


def baslangic_verisi(tohum=None):
    random.seed(TOHUM if tohum is None else tohum)
    AKT0 = [[rastgele_harita(KATMANLAR[0]["h"], KATMANLAR[0]["w"], -128, 127)
             for _ in range(KATMANLAR[0]["cin"])] for _ in range(BATCH)]
    W = []
    for k in KATMANLAR:
        W.append([[rastgele_harita(3, 3) for _ in range(k["cin"])] for _ in range(k["cout"])])
    etiket = [random.randint(0, N_SINIF - 1) for _ in range(BATCH)]
    return AKT0, W, etiket


def kopya(x):
    """İç içe listelerin derin kopyası."""
    if isinstance(x, list):
        return [kopya(e) for e in x]
    return x


# ----------------------------------------------------------------------------
# CLU — YER TUTUCU (Shao Alg. 2 + D1-D9). Gerçek modeliniz gelince değiştirin.
# ----------------------------------------------------------------------------
def clu_yer_tutucu(a, s_a, y, lfsr):
    """a: N int8 aktivasyon, s_a: ölçek üssü, y: doğru sınıf -> e: N int8 hata.
    lfsr: kanal başına LFSR durumları (CY.kanal_tohumlari ile başlar, yerinde güncellenir)."""
    if s_a > -7:
        x = []
        for ai in a:                               # EPU (Fig. 7): a*184 >> 7 (D4), sonra Shift Unit (D2)
            t = (ai * 184) >> 7                    # [varsayım] aritmetik kaydırma (aşağı)
            t = t << s_a if s_a >= 0 else t >> (-s_a)
            x.append(t)
        ofset = max(x) - 10
        g = [(1 << max(0, xi - ofset)) - 1 for xi in x]                     # D1: 2^a - 1
    else:                                          # TEU: 2^(1-2s) + a*2^(1-s) + a*a
        g = [(1 << (1 - 2 * s_a)) + ai * (1 << (1 - s_a)) + ai * ai for ai in a]
    toplam = sum(g)
    g2 = [(gi << 11) // toplam for gi in g]        # D7: kesmeli bölme
    toplam2 = sum(g2)
    e = [g2[i] - toplam2 if i == y else g2[i] for i in range(len(a))]
    cikis = []
    for i, ei in enumerate(e):                     # D5 + D8 + D9: >>4, sonra ±127
        if D8_YUVARLAMA == "a":
            cikis.append(max(-127, min(127, (ei + 8) >> 4)))   # D60: en yakına (Egemen: (e + 8) >>> 4)
        else:
            cikis.append(CY.kanal_yuvarla(lfsr, i, ei))        # D57: LFSR'li stokastik
    return cikis


# ----------------------------------------------------------------------------
# (FSM'İN DAVRANIŞI) Komut şablonları — veriye bağlı alanlar (s_a) None
#   Komut = 10 tamsayı: [op, faz, katman, b, x, y, z, a1, a2, a3]  (tablo: TASARIM_FSM.md)
# ----------------------------------------------------------------------------
def pe_isi(K, faz, l):
    """Bir PE işi: İŞ_BAŞLA + 4 sayaçlı döngü + ÖLÇEK. Dönüş: grup sayısı.
    PE komut alanları: b = k2 (örnek), x = k0, y = k1, z = k3 (her fazda aynı eşleme)."""
    k = KATMANLAR[l - 1]
    n0, n1, n2, n3 = dongu_sinirlari(faz, k)
    K.append([OP_IS_BASLA, faz, l, 0, hedef_genislik(faz), 0, 0, 0, 0, 0])
    grup = 0
    for k0 in range(n0):
        for k1 in range(n1):
            for k2 in range(n2):
                for k3 in range(n3):
                    if faz == FAZ_WG:      # çıktı-durağan: akümülatör (b, satır) boyunca toplar
                        ilk = int(k2 == 0 and k3 == 0)
                        son = int(k2 == n2 - 1 and k3 == n3 - 1)
                    else:                  # FIFO, k1 (FP'de c, BP'de o) boyunca toplar
                        ilk = int(k1 == 0)
                        son = int(k1 == n1 - 1)
                    K.append([OP_PE, faz, l, k2, k0, k1, k3, ilk, son, grup if son else -1])
                    grup += son
    K.append([OP_OLCEK, faz, l, 0, 0, 0, 0, grup, 0, 0])
    return grup


def komut_sablonlari():
    K = []
    # ---- İleri yayılım: her katman, tüm örnekler ----
    for li, k in enumerate(KATMANLAR):
        l = li + 1
        pe_isi(K, FAZ_FP, l)
        K.append([OP_SA, 0, l, 0, None, 0, 0, 0, 0, 0])
        islem = ISLEM_RELU_ILERI if k["relu"] else ISLEM_YOK
        g = 0
        for o in range(k["cout"]):              # grupların üretildiği sıra: o, b, r
            for b in range(BATCH):
                for r in range(k["ho"]):
                    K.append([OP_KOPYA, FAZ_FP, l, b, o, r, islem, g, 0, 0])
                    g += 1
    # ---- CLU: her örnek ----
    for b in range(BATCH):
        K.append([OP_CLU, 0, L, b, None, 0, 0, 0, 0, 0])
    # ---- Geri yayılım: son katmandan ilke ----
    for li in reversed(range(L)):
        k = KATMANLAR[li]
        l = li + 1
        if l > 1:                                # 1. katmanda BP yok (K7, NITI)
            pe_isi(K, FAZ_BP, l)
            islem = ISLEM_RELU_GERI if KATMANLAR[l - 2]["relu"] else ISLEM_YOK
            g = 0
            for c in range(k["cin"]):            # grupların üretildiği sıra: c, b, p
                for b in range(BATCH):
                    for p in range(bp_gecis_sayisi(k)):
                        K.append([OP_KOPYA, FAZ_BP, l, b, c, p, islem, g, 0, 0])
                        g += 1
        pe_isi(K, FAZ_WG, l)
        g = 0
        for o in range(k["cout"]):               # grupların üretildiği sıra: o, c
            for c in range(k["cin"]):
                K.append([OP_WU, FAZ_WG, l, 0, o, c, 0, g, 0, 0])
                g += 1
    K.append([OP_BITTI, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    return K


def grup_koordinati(kom):
    """Bir grubun koordinatı; üretici ('son' PE komutu) ile tüketici (KOPYA/WU) aynı
    grup için aynı koordinatı vermeli."""
    op, faz = kom[0], kom[1]
    if op == OP_PE:
        if faz == FAZ_WG:
            return (kom[4], kom[5])            # (o, c)
        return (kom[4], kom[3], kom[6])        # FP (o, b, r) · BP (c, b, p)
    if op == OP_KOPYA:
        return (kom[4], kom[3], kom[5])        # (kanal, b, satır ya da p)
    return (kom[4], kom[5])                    # WU (o, c)


def sablon_kontrol(K):
    """Komut sırasının yapısal kuralları (veriden bağımsız). Her PE işi için:
      a) Hemen önünde aynı faz ve katmanla İŞ_BAŞLA var; hedef doğru.
      b) Kanal çifti (x, y) yalnızca Cin*Cout kez değişiyor: FP ve BP'de ağırlıklar,
         WG'de akümülatörler bir kanal çifti boyunca sabit (T1, Shao III-A-1).
      c) Toplama doğru: aynı grubun geçişlerinin ilki 'ilk', sonuncusu 'son';
         geçiş sayısı FP/BP'de n1, WG'de n2*n3.
      d) 'son' sayısı = ÖLÇEK'teki grup sayısı = KOPYA/WU sayısı; grup numaraları 0, 1, 2...
      e) Tüketici, grupları üretildikleri sırayla ve aynı koordinatla işliyor."""
    i = 0
    n_is = 0
    while i < len(K):
        if K[i][0] != OP_PE:
            i += 1
            continue
        j = i
        while K[j][0] == OP_PE:
            j += 1
        isk = K[i:j]
        faz, l = isk[0][1], isk[0][2]
        k = KATMANLAR[l - 1]
        n0, n1, n2, n3 = dongu_sinirlari(faz, k)
        ad = f"{FAZ_ADI[faz]} {l}"
        # a)
        assert K[i - 1][:3] == [OP_IS_BASLA, faz, l] and K[i - 1][4] == hedef_genislik(faz), ad
        assert all(kom[1] == faz and kom[2] == l for kom in isk), ad
        # b)
        anahtar = [(kom[4], kom[5]) for kom in isk]
        degisim = 1 + sum(1 for a, b in zip(anahtar, anahtar[1:]) if a != b)
        assert degisim == k["cin"] * k["cout"], f"{ad}: kanal çifti {degisim} kez değişiyor"
        # c)
        gecisler = {}
        for kom in isk:
            gecisler.setdefault(grup_koordinati(kom), []).append(kom)
        beklenen = n2 * n3 if faz == FAZ_WG else n1
        for koord, liste in gecisler.items():
            assert len(liste) == beklenen, (ad, koord, len(liste))
            assert [kom[7] for kom in liste] == [1] + [0] * (beklenen - 1), (ad, koord, "ilk")
            assert [kom[8] for kom in liste] == [0] * (beklenen - 1) + [1], (ad, koord, "son")
        # d)
        sonlar = [kom for kom in isk if kom[8]]
        assert [kom[9] for kom in sonlar] == list(range(len(sonlar))), ad
        assert all(kom[9] == -1 for kom in isk if not kom[8]), ad
        assert K[j][:3] == [OP_OLCEK, faz, l] and K[j][7] == len(sonlar), ad
        m = j + 1
        if faz == FAZ_FP:
            assert K[m][:3] == [OP_SA, 0, l], ad
            m += 1
        tuketici = []
        while m < len(K) and K[m][0] in (OP_KOPYA, OP_WU):
            tuketici.append(K[m])
            m += 1
        assert len(tuketici) == len(sonlar), f"{ad}: {len(sonlar)} grup, {len(tuketici)} KOPYA/WU"
        # e)
        for s_, t_ in zip(sonlar, tuketici):
            assert t_[1] == faz and t_[2] == l and t_[7] == s_[9], (ad, s_, t_)
            assert grup_koordinati(s_) == grup_koordinati(t_), (ad, s_, t_)
        n_is += 1
        i = j
    assert n_is == L + (L - 1) + L          # FP her katman, BP 2..L, WG her katman
    return n_is


def relu_gms_degisme_kontrolu():
    """T8: KOPYA'da ReLU ile GMS'in sırası sonucu değiştiriyor mu? Tüm int8 değerleri ve
    0..31 kaydırma için denenir: ileri ReLU ve maskeli geri ReLU (maskenin üç işaret sınıfı)."""
    n = 0
    for d in range(32):
        for v in range(-128, 128):
            gv = SRU.sru_yuvarla(v, d)[0]                      # önce GMS
            assert FE.relu_ileri(gv) == SRU.sru_yuvarla(FE.relu_ileri(v), d)[0], (v, d)
            n += 1
            for a in (-128, -1, 0, 1, 127):                    # maske: negatif, sıfır, pozitif
                assert FE.relu_geri(gv, a) == SRU.sru_yuvarla(FE.relu_geri(v, a), d)[0], (v, a, d)
                n += 1
    return n


# ----------------------------------------------------------------------------
# (I) KOMUT YORUMLAYICI — ön-getirme + PE çevrim modeli + SRU + fonksiyon motoru
# ----------------------------------------------------------------------------
def fifo_al(FIFO, anahtar):
    """Psum FIFO'nun başındaki kaydı alır. Anahtar yalnızca kontrol için: döngü sırası
    doğruysa FIFO'nun başında her zaman beklenen (örnek, satır) kısmi toplamı durur."""
    a, deger = FIFO.pop(0)                     # pop(0): listenin ilk elemanını çıkarır
    assert a == anahtar, f"Psum FIFO sırası bozuk: başta {a}, beklenen {anahtar}"
    return deger


def int32_sayisi(x):
    """İç içe listedeki sayı adedi (FIFO doluluğunu int32 cinsinden ölçmek için)."""
    if isinstance(x, list):
        return sum(int32_sayisi(e) for e in x)
    return 1


def gms(degerler, d, tasma):
    """SRU 2. aşama: tampondaki int8 değerleri d bit kaydırıp yuvarlar."""
    cikis = []
    for v in degerler:
        c8, t8 = SRU.sru_yuvarla(v, d)
        cikis.append(c8)
        tasma["GMS"] += t8
    return cikis


def yorumla(sablon, AKT0, W0, etiket):
    """Komutları sırayla yürütür; veriye bağlı alanları (s_a) doldurur.
    Dönüş: (komutlar, durum)."""
    AKT = [kopya(AKT0)] + [None] * L              # AKT[l][b][c]: l. katmanın çıkışı (l=0 giriş)
    HATA = [None] * (L + 1)                        # HATA[l][b][o]: δ_l
    W = kopya(W0)                                  # W[l-1][o][c]
    s_a = S_A0
    s_a_list = [S_A0]
    CIK = []                                       # çıkış tamponu: LMS çıktıları, grup sırasıyla
    MAKS = []                                      # Max Regs: grup başına yerel maksimum M (T4)
    FIFO = []                                      # Psum FIFO: (anahtar, kısmi toplam)
    akum = None                                    # WG akümülatörleri (PE içinde)
    hedef = None                                   # İŞ_BAŞLA ile gelir
    G = None                                       # ÖLÇEK'te hesaplanır
    tasma = {"LMS": 0, "GMS": 0}                   # SRU'da 128'e ulaşan değer sayısı
    olaylar = []                                   # maksreg.txt
    isler = []                                     # iş başına özet
    fifo_en_cok = 0                                # FIFO'nun en büyük doluluğu (int32)
    clu_lfsr = CY.kanal_tohumlari(N_SINIF)         # CLU'nun kanal LFSR'leri (D8)
    cik_en_cok = 0                                 # çıkış tamponunun en büyük doluluğu (bayt)
    komutlar = []
    iz = []                                        # Paket 2: PE iz kaydı (pe_izi.txt); hesabı değiştirmez

    for kom_no, kom in enumerate(sablon):
        kom = list(kom)
        op, faz, l, b = kom[0], kom[1], kom[2], kom[3]
        if op == OP_IS_BASLA:                      # yeni iş: tampon, Max Regs, FIFO sıfırlanır
            CIK, MAKS, FIFO = [], [], []
            hedef = kom[4]
            G = None
            isler.append(dict(faz=faz, l=l, hedef=hedef, n_pe=0, M=MAKS, G=None))
        elif op == OP_PE:
            k = KATMANLAR[l - 1]
            x, y, z, ilk, son, grup = kom[4:10]
            isler[-1]["n_pe"] += 1
            if faz == FAZ_FP:
                o, c, r = x, y, z
                Xp = PE.dolgu_ekle(AKT[l - 1][b][c], k["p"])
                satirlar = [Xp[k["s"] * r + i] for i in range(3)]
                psum = [0] * k["wo"] if ilk else fifo_al(FIFO, (b, r))
                if k["s"] == 1:
                    T = len(satirlar[0])
                    cev, cik = PE.pe_gecis_s1(satirlar, W[l - 1][o][c], PE.ps_akisi_s(psum, T))
                    iz_kayit = (0, PE.duzlestir(W[l - 1][o][c]), cev)
                else:
                    cift, tek = [], []
                    for s_ in satirlar:
                        ct, tt = PE.cift_tek_ayir(s_)
                        cift.append(ct)
                        tek.append(tt)
                    T = len(cift[0])
                    cev, cik = PE.pe_gecis_s2(cift, tek, W[l - 1][o][c], PE.ps_akisi_s(psum, T))
                    iz_kayit = (1, PE.duzlestir(W[l - 1][o][c]), cev)
                degerler = [d[0] for (_, d) in cik]
                assert len(degerler) == k["wo"]
                if son:
                    grup_degerleri = degerler
                else:
                    FIFO.append(((b, r), degerler))
            elif faz == FAZ_BP:
                c, o, p = x, y, z
                E = HATA[l][b][o]
                if k["s"] == 1:
                    Ep = PE.dolgu_ekle(E, 2 - k["p"])
                    satirlar = [Ep[p + i] for i in range(3)]
                    psum = [0] * k["w"] if ilk else fifo_al(FIFO, (b, p))
                    T = len(satirlar[0])
                    cev, cik = PE.pe_gecis_s1(satirlar, PE.dondur_180(W[l - 1][o][c]), PE.ps_akisi_s(psum, T))
                    iz_kayit = (2, PE.duzlestir(PE.dondur_180(W[l - 1][o][c])), cev)
                    degerler = [d[0] for (_, d) in cik]
                    assert len(degerler) == k["w"]
                    if son:
                        grup_degerleri = degerler
                    else:
                        FIFO.append(((b, p), degerler))
                else:
                    He, We = k["ho"], k["wo"]
                    n = We + 1
                    sifir = [0] * We
                    e_p = E[p] if p < He else sifir
                    e_once = E[p - 1] if p >= 1 else sifir
                    akislar = [PE.bp_s2_akisi(e_p), PE.bp_s2_akisi(e_p), PE.bp_s2_akisi(e_once)]
                    Wk = W[l - 1][o][c]
                    w_yuklu = [[Wk[i][2], Wk[i][0], Wk[i][1]] for i in range(3)]   # Fig. 4(b)
                    psum4 = [[0] * n for _ in range(4)] if ilk else fifo_al(FIFO, (b, p))
                    T = len(akislar[0])
                    cev, cik = PE.pe_gecis_bp_s2(akislar, w_yuklu, PE.ps_akisi_bp_s2(psum4, T))
                    iz_kayit = (3, PE.duzlestir(w_yuklu), cev)
                    seritler = [[d[s_] for (_, d) in cik] for s_ in range(4)]
                    if son:
                        # Çıkış adres üreteci: şeritleri dX koordinatlarına yerleştir, dolguyu kırp
                        grup_degerleri = []
                        for R in bp_s2_satirlari(k, p):
                            satir_dx0 = R + k["p"]                 # 2p ya da 2p+1
                            for C in range(k["w"]):
                                C0 = C + k["p"]
                                serit = (0 if satir_dx0 == 2 * p else 2) + (C0 % 2)
                                grup_degerleri.append(seritler[serit][C0 // 2])
                        assert len(grup_degerleri) > 0
                    else:
                        FIFO.append(((b, p), seritler))
            else:  # FAZ_WG
                o, c, r = x, y, z
                if ilk:
                    akum = PE.sifir_matris(3, 3)
                Ap = PE.dolgu_ekle(AKT[l - 1][b][c], k["p"])
                a_sat = [Ap[k["s"] * r + i] for i in range(3)]
                e_sat = HATA[l][b][o][r]
                if k["s"] == 1:
                    T = len(a_sat[0])
                    e_akis = [e_sat + [0] * (T - len(e_sat)) for _ in range(3)]
                    cev, _ = PE.pe_gecis_wg_s1(a_sat, e_akis, akum)
                    iz_kayit = (4, [0] * 9, cev)
                else:
                    cift, tek = [], []
                    for s_ in a_sat:
                        ct, tt = PE.cift_tek_ayir(s_)
                        cift.append(ct)
                        tek.append(tt)
                    T = len(cift[0])
                    e_akis = [e_sat + [0] * (T - len(e_sat)) for _ in range(3)]
                    cev, _ = PE.pe_gecis_wg_s2(cift, tek, e_akis, akum)
                    iz_kayit = (5, [0] * 9, cev)
                if son:
                    grup_degerleri = PE.duzlestir(akum)
            iz.append((kom_no, iz_kayit[0], iz_kayit[1], iz_kayit[2],
                       list(grup_degerleri) if son else []))
            fifo_en_cok = max(fifo_en_cok, sum(int32_sayisi(v) for (_, v) in FIFO))
            if son:                                      # SRU 1. aşama (LMS) -> çıkış tamponu
                lms8, lms_t, M, _, l_kay = FE.lms_hedefli(grup_degerleri, hedef)
                tasma["LMS"] += sum(lms_t)
                assert grup == len(MAKS)
                CIK.append(lms8)
                cik_en_cok = max(cik_en_cok, sum(len(c) for c in CIK))
                MAKS.append(M)                           # T4: yerel maksimumun kendisi saklanır
                olaylar.append((OLAY_YEREL, grup, M, l_kay))
        elif op == OP_OLCEK:
            assert kom[7] == len(MAKS)
            assert not FIFO, "iş bittiğinde FIFO boş olmalı"
            G = max(0, SRU.B(max(MAKS)) - hedef)         # global maks = yerel maksların en büyüğü
            isler[-1]["G"] = G
            olaylar.append((OLAY_G, 0, G, 0))
        elif op == OP_SA:
            s_a = s_a + KATMANLAR[l - 1]["sw"] + G       # s_a(l) = s_a(l-1) + s_w + G
            s_a_list.append(s_a)
            kom[4] = s_a
        elif op == OP_KOPYA:                             # T8: ReLU -> GMS -> depo
            k = KATMANLAR[l - 1]
            ch, satir, islem, grup = kom[4], kom[5], kom[6], kom[7]
            d = G - max(0, SRU.B(MAKS[grup]) - hedef)    # Δ = G - l_g (SRU-a8)
            olaylar.append((OLAY_DELTA, grup, d, 0))
            y8 = list(CIK[grup])
            if faz == FAZ_FP:
                if AKT[l] is None:
                    AKT[l] = [[PE.sifir_matris(k["ho"], k["wo"]) for _ in range(k["cout"])] for _ in range(BATCH)]
                if islem == ISLEM_RELU_ILERI:
                    y8 = [FE.relu_ileri(v) for v in y8]
                AKT[l][b][ch][satir] = gms(y8, d, tasma)
            else:                                        # BP: δ_{l-1} = ReLU-geri(e, a_{l-1})
                if HATA[l - 1] is None:
                    HATA[l - 1] = [[PE.sifir_matris(k["h"], k["w"]) for _ in range(k["cin"])] for _ in range(BATCH)]
                satirlar = [satir] if k["s"] == 1 else bp_s2_satirlari(k, satir)
                if islem == ISLEM_RELU_GERI:
                    maske = [a for R in satirlar for a in AKT[l - 1][b][ch][R]]
                    y8 = [FE.relu_geri(e, a) for e, a in zip(y8, maske)]
                y8 = gms(y8, d, tasma)
                for i, R in enumerate(satirlar):
                    HATA[l - 1][b][ch][R] = y8[i * k["w"]:(i + 1) * k["w"]]
        elif op == OP_CLU:
            if HATA[L] is None:
                HATA[L] = [[[[0]] for _ in range(N_SINIF)] for _ in range(BATCH)]
            kom[4] = s_a
            a_vek = [AKT[L][b][o][0][0] for o in range(N_SINIF)]
            e = clu_yer_tutucu(a_vek, s_a, etiket[b], clu_lfsr)
            for o in range(N_SINIF):
                HATA[L][b][o] = [[e[o]]]
        elif op == OP_WU:                                # GMS + w - g -> ağırlık tamponu
            o, c, grup = kom[4], kom[5], kom[7]
            d = G - max(0, SRU.B(MAKS[grup]) - hedef)
            olaylar.append((OLAY_DELTA, grup, d, 0))
            g8 = gms(CIK[grup], d, tasma)
            w_eski = PE.duzlestir(W[l - 1][o][c])
            w_yeni = [FE.agirlik_guncelle(w, g) for w, g in zip(w_eski, g8)]
            W[l - 1][o][c] = [w_yeni[0:3], w_yeni[3:6], w_yeni[6:9]]
        komutlar.append(kom)
    assert all(v is not None for kom in komutlar for v in kom), "doldurulmamış alan kaldı"
    return komutlar, dict(AKT=AKT, HATA=HATA, W=W, s_a=s_a_list, isler=isler, olaylar=olaylar,
                          tasma=tasma, fifo_en_cok=fifo_en_cok, cik_en_cok=cik_en_cok, iz=iz)


# ----------------------------------------------------------------------------
# (II) TENSÖR DÜZEYİ — katman fonksiyonları + iki aşamalı SRU (komutlardan bağımsız)
#   Grupların sırası T1'e göre: FP (o, b, r), BP (c, b, p), WG (o, c).
#   KOPYA burada NITI sırasıyla yapılıyor (önce GMS, sonra ReLU); (I) ise Shao sırasıyla
#   (önce ReLU, sonra GMS). İkisinin bit bit aynı çıkması T8'in uçtan uca kontrolü.
# ----------------------------------------------------------------------------
def is_olaylari(olaylar, sonuclar, G):
    """Bir işin Max Regs olayları: önce gruplar (M, l), sonra G, sonra gruplar (Δ)."""
    for g, s_ in enumerate(sonuclar):
        olaylar.append((OLAY_YEREL, g, s_["M"], s_["l"]))
    olaylar.append((OLAY_G, 0, G, 0))
    for g, s_ in enumerate(sonuclar):
        olaylar.append((OLAY_DELTA, g, s_["delta"], 0))


def tensor_adimi(AKT0, W0, etiket):
    AKT = [kopya(AKT0)] + [None] * L
    HATA = [None] * (L + 1)
    W = kopya(W0)
    s_a = S_A0
    s_a_list = [S_A0]
    isler = []
    olaylar = []
    G32 = [None] * L                                 # float kontrolü için ham gradyanlar
    clu_lfsr = CY.kanal_tohumlari(N_SINIF)           # CLU'nun kanal LFSR'leri (D8)
    # İleri
    for li, k in enumerate(KATMANLAR):
        Y = {}
        for b in range(BATCH):
            for o in range(k["cout"]):
                for c in range(k["cin"]):
                    Yc = PE.ref_fp(AKT[li][b][c], W[li][o][c], k["s"], k["p"])
                    Y[(b, o)] = Yc if c == 0 else PE.matris_topla(Y[(b, o)], Yc)
        gruplar, kim = [], []
        for o in range(k["cout"]):
            for b in range(BATCH):
                for r in range(k["ho"]):
                    gruplar.append(Y[(b, o)][r])
                    kim.append((b, o, r))
        G, Bg, son = SRU.katman(gruplar)
        isler.append((FAZ_FP, li + 1, [s_["M"] for s_ in son], G))
        is_olaylari(olaylar, son, G)
        AKT[li + 1] = [[PE.sifir_matris(k["ho"], k["wo"]) for _ in range(k["cout"])] for _ in range(BATCH)]
        for (b, o, r), s_ in zip(kim, son):
            y8 = s_["gms8"]
            if k["relu"]:
                y8 = [FE.relu_ileri(v) for v in y8]
            AKT[li + 1][b][o][r] = y8
        s_a = s_a + k["sw"] + G
        s_a_list.append(s_a)
    # CLU
    HATA[L] = [[[[0]] for _ in range(N_SINIF)] for _ in range(BATCH)]
    for b in range(BATCH):
        e = clu_yer_tutucu([AKT[L][b][o][0][0] for o in range(N_SINIF)], s_a, etiket[b], clu_lfsr)
        for o in range(N_SINIF):
            HATA[L][b][o] = [[e[o]]]
    # Geri
    for li in reversed(range(L)):
        k = KATMANLAR[li]
        l = li + 1
        if l > 1:
            dX = {}
            for b in range(BATCH):
                for c in range(k["cin"]):
                    for o in range(k["cout"]):
                        d = PE.ref_bp(HATA[l][b][o], W[li][o][c], k["s"], k["p"], k["h"], k["w"])
                        dX[(b, c)] = d if o == 0 else PE.matris_topla(dX[(b, c)], d)
            gruplar, kim = [], []
            for c in range(k["cin"]):
                for b in range(BATCH):
                    if k["s"] == 1:
                        for m in range(k["h"]):
                            gruplar.append(dX[(b, c)][m])
                            kim.append((b, c, [m]))
                    else:
                        for p in range(bp_gecis_sayisi(k)):
                            satirlar = bp_s2_satirlari(k, p)
                            gruplar.append([v for R in satirlar for v in dX[(b, c)][R]])
                            kim.append((b, c, satirlar))
            G, Bg, son = SRU.katman(gruplar)
            isler.append((FAZ_BP, l, [s_["M"] for s_ in son], G))
            is_olaylari(olaylar, son, G)
            HATA[l - 1] = [[PE.sifir_matris(k["h"], k["w"]) for _ in range(k["cin"])] for _ in range(BATCH)]
            for (b, c, satirlar), s_ in zip(kim, son):
                for i, R in enumerate(satirlar):
                    parca = s_["gms8"][i * k["w"]:(i + 1) * k["w"]]
                    if KATMANLAR[li - 1]["relu"]:
                        parca = [FE.relu_geri(e, a) for e, a in zip(parca, AKT[l - 1][b][c][R])]
                    HATA[l - 1][b][c][R] = parca
        g_gruplar, w_gruplar, kim = [], [], []
        G32[li] = [[None] * k["cin"] for _ in range(k["cout"])]
        for o in range(k["cout"]):
            for c in range(k["cin"]):
                Gm = None
                for b in range(BATCH):
                    g = PE.ref_wg(AKT[li][b][c], HATA[l][b][o], k["s"], k["p"])
                    Gm = g if Gm is None else PE.matris_topla(Gm, g)
                G32[li][o][c] = Gm
                g_gruplar.append(PE.duzlestir(Gm))
                w_gruplar.append(PE.duzlestir(W[li][o][c]))
                kim.append((o, c))
        G, Bg, son = FE.wu_katman(g_gruplar, w_gruplar, M_U)
        isler.append((FAZ_WG, l, [s_["M"] for s_ in son], G))
        is_olaylari(olaylar, son, G)
        for (o, c), s_ in zip(kim, son):
            w = s_["w_yeni"]
            W[li][o][c] = [w[0:3], w[3:6], w[6:9]]
    return dict(AKT=AKT, HATA=HATA, W=W, s_a=s_a_list, isler=isler, olaylar=olaylar, G32=G32)


# ----------------------------------------------------------------------------
# (III) FLOAT KONTROLÜ — numpy ile, katman fonksiyonlarından bağımsız yazıldı
# ----------------------------------------------------------------------------
def f_ileri(X, Wt, s, p):
    """X: (Cin,H,W), Wt: (Cout,Cin,3,3) -> (Cout,Ho,Wo). Kaydır-topla yöntemiyle."""
    Xp = np.pad(X, ((0, 0), (p, p), (p, p)))
    Ho = (Xp.shape[1] - 3) // s + 1
    Wo = (Xp.shape[2] - 3) // s + 1
    Y = np.zeros((Wt.shape[0], Ho, Wo))
    for r in range(3):
        for c in range(3):
            parca = Xp[:, r:r + s * (Ho - 1) + 1:s, c:c + s * (Wo - 1) + 1:s]
            Y += np.einsum('oi,ihw->ohw', Wt[:, :, r, c], parca)
    return Y


def f_geri(dY, X, Wt, s, p):
    Xp = np.pad(X, ((0, 0), (p, p), (p, p)))
    dXp = np.zeros_like(Xp)
    dW = np.zeros_like(Wt)
    Ho, Wo = dY.shape[1], dY.shape[2]
    for r in range(3):
        for c in range(3):
            dilim = (slice(None), slice(r, r + s * (Ho - 1) + 1, s), slice(c, c + s * (Wo - 1) + 1, s))
            dW[:, :, r, c] = np.einsum('ohw,ihw->oi', dY, Xp[dilim])
            dXp[dilim] += np.einsum('oi,ohw->ihw', Wt[:, :, r, c], dY)
    H, Wd = X.shape[1], X.shape[2]
    return dXp[:, p:p + H, p:p + Wd], dW


def kosinus(a, b):
    a = np.asarray(a, dtype=float).ravel()
    b = np.asarray(b, dtype=float).ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def float_kontrol(AKT0, W0, etiket, t):
    """int sonuçlarının float ağla tutarlılığı. Dönüş: ölçümler sözlüğü."""
    s_a = t["s_a"]
    Wf = [np.array(W0[li], dtype=float) * 2.0 ** k["sw"] for li, k in enumerate(KATMANLAR)]
    olcum = {}
    dW_top = [np.zeros_like(w) for w in Wf]
    dz_hepsi = [[] for _ in range(L + 1)]
    a_hepsi = [[] for _ in range(L + 1)]
    for b in range(BATCH):
        a = [np.array(AKT0[b], dtype=float) * 2.0 ** S_A0]
        z = [None]
        for li, k in enumerate(KATMANLAR):
            zl = f_ileri(a[li], Wf[li], k["s"], k["p"])
            z.append(zl)
            a.append(np.maximum(zl, 0) if k["relu"] else zl)
        logit = z[L].ravel()
        pr = np.exp(logit - logit.max())
        pr /= pr.sum()
        dz = pr.copy()
        dz[etiket[b]] -= 1.0
        dz = [None] * L + [dz.reshape(N_SINIF, 1, 1)]
        for li in reversed(range(L)):
            k = KATMANLAR[li]
            dX, dW = f_geri(dz[li + 1], a[li], Wf[li], k["s"], k["p"])
            dW_top[li] += dW
            if li > 0:
                dz[li] = dX * (z[li] > 0) if KATMANLAR[li - 1]["relu"] else dX
        for l in range(1, L + 1):
            a_hepsi[l].append(a[l])
            dz_hepsi[l].append(dz[l])
    for l in range(1, L + 1):
        f = np.array(a_hepsi[l])
        i = np.array(t["AKT"][l], dtype=float) * 2.0 ** s_a[l]
        olcum[f"FP katman {l}: max |int - float| / max |float|"] = float(np.abs(i - f).max() / np.abs(f).max())
        olcum[f"BP δ_{l}: kosinüs(int, float)"] = kosinus(t["HATA"][l], dz_hepsi[l])
        olcum[f"WG katman {l}: kosinüs(int G32, float dW)"] = kosinus(t["G32"][l - 1], dW_top[l - 1])
    return olcum


# ----------------------------------------------------------------------------
# Dosyalar
# ----------------------------------------------------------------------------
def yaz_ag(yol):
    with open(yol, "w") as f:
        f.write(f"{L} {BATCH} {M_U} {S_A0} {N_SINIF}\n")
        for k in KATMANLAR:
            f.write(f"{k['cin']} {k['cout']} {k['h']} {k['w']} {k['s']} {k['p']} {k['relu']} {k['sw']}\n")


def harita_satirlari(t, ad, l):
    s = []
    for b, kanallar in enumerate(t):
        for c, M in enumerate(kanallar):
            for r, satir in enumerate(M):
                s.append(f"{ad} {l} {b} {c} {r} " + " ".join(str(v) for v in satir))
    return s


def yaz_veri(yol_bas, yol_son, AKT0, W0, etiket, t):
    with open(yol_bas, "w") as f:
        f.write("# Başlangıç belleği. Satır: AKT 0 b c satır değerler | W katman o c satır değerler | ETIKET b sınıf\n")
        f.write("\n".join(harita_satirlari(AKT0, "AKT", 0)) + "\n")
        for li in range(L):
            f.write("\n".join(harita_satirlari(W0[li], "W", li + 1)) + "\n")
        for b, y in enumerate(etiket):
            f.write(f"ETIKET {b} {y}\n")
    with open(yol_son, "w") as f:
        f.write("# Beklenen sonuç (bir eğitim adımından sonra). AKT/HATA/W: katman b(o) c satır değerler; SA: katman s_a\n")
        for l in range(1, L + 1):
            f.write("\n".join(harita_satirlari(t["AKT"][l], "AKT", l)) + "\n")
        for l in range(1, L + 1):
            f.write("\n".join(harita_satirlari(t["HATA"][l], "HATA", l)) + "\n")
        for li in range(L):
            f.write("\n".join(harita_satirlari(t["W"][li], "W", li + 1)) + "\n")
        for l, s in enumerate(t["s_a"]):
            f.write(f"SA {l} {s}\n")


def pe_izi_yaz(yol, iz):
    """pe_izi.txt (Paket 2): her PE komutunda PE'nin çevrim çevrim gördüğü girişler, çıkışlar ve grup.
    Biçim: 1. satır kayıt sayısı; her kayıt için
      KOMUT_NO MOD T SON N_GRUP      (KOMUT_NO: komutlar.txt'teki sıra, 0'dan; MOD: 0 FP s1, 1 FP s2,
                                      2 BP s1, 3 BP s2, 4 WG s1, 5 WG s2)
      9 ağırlık                      (PE'ye yüklenen hâli: BP s1'de 180° döndürülmüş, BP s2'de Fig. 4(b))
      T satır, her biri 13 sayı      (akis1 r0 r1 r2, akis2 r0 r1 r2, akis3 r0 r1 r2, ps0 ps1 ps2 ps3;
                                      pe_sarmalayici portlarıyla aynı anlamda, kullanılmayanlar 0)
      N_CIKIS, sonra N_CIKIS satır   (t c0 c1 c2 c3: figür çevrimi t'deki geçerli çıkış şeritleri)
      N_GRUP sayı (son = 1 ise)      (SRU'ya gidecek int32 grup)"""
    def alanlar(mod, g):
        a1, a2, a3, ps = [0] * 3, [0] * 3, [0] * 3, [0] * 4
        if mod in (0, 2):                      # s1: x0 x1 x2 ps
            a1 = g[0:3]; ps[0] = g[3]
        elif mod == 1:                         # FP s2: c0 t0 c1 t1 c2 t2 ps
            a1 = [g[0], g[2], g[4]]; a2 = [g[1], g[3], g[5]]; ps[0] = g[6]
        elif mod == 3:                         # BP s2: s0 s1 s2 psA0 psB0 psA1 psB1
            a1 = g[0:3]; ps = g[3:7]
        elif mod == 4:                         # WG s1: a0 e0 a1 e1 a2 e2
            a1 = [g[0], g[2], g[4]]; a2 = [g[1], g[3], g[5]]
        else:                                  # WG s2: c0 k0 e0 c1 k1 e1 c2 k2 e2
            a1 = [g[0], g[3], g[6]]; a2 = [g[1], g[4], g[7]]; a3 = [g[2], g[5], g[8]]
        return list(a1) + list(a2) + list(a3) + list(ps)
    with open(yol, "w") as f:
        f.write(f"{len(iz)}\n")
        for kom_no, mod, w9, cev, grup in iz:
            son = 1 if grup else 0
            f.write(f"{kom_no} {mod} {len(cev)} {son} {len(grup)}\n")
            f.write(" ".join(str(v) for v in w9) + "\n")
            for girisler, _, _ in cev:
                f.write(" ".join(str(v) for v in alanlar(mod, girisler)) + "\n")
            gecerli = [(t, c) for t, (_, c, g) in enumerate(cev) if g]
            f.write(f"{len(gecerli)}\n")
            for t, c in gecerli:
                c4 = list(c) + [0] * (4 - len(c))
                f.write(f"{t} " + " ".join(str(v) for v in c4) + "\n")
            if grup:
                f.write(" ".join(str(v) for v in grup) + "\n")


def yaz_maksreg(yol, olaylar):
    """maksreg.txt: ilk satır olay sayısı; sonra her olay 4 tamsayı (tür grup değer1 değer2)."""
    with open(yol, "w") as f:
        f.write(f"{len(olaylar)}\n")
        for o in olaylar:
            f.write(" ".join(str(v) for v in o) + "\n")


def okunur_yaz(yol, komutlar, y, olcum, olcum_ref, n_degisme):
    p = ["Sistem golden modeli — özet", "",
         f"Ağ: batch {BATCH}, m_u {M_U}, s_a0 {S_A0}, {L} katman, başlangıç tohumu {TOHUM}",
         f"{'katman':>6} {'cin':>4} {'cout':>4} {'giriş':>7} {'çıkış':>7} {'s':>2} {'p':>2} {'relu':>4} {'s_w':>4}"]
    for li, k in enumerate(KATMANLAR):
        p.append(f"{li + 1:>6} {k['cin']:>4} {k['cout']:>4} {k['h']}x{k['w']:<5} {k['ho']}x{k['wo']:<5} "
                 f"{k['s']:>2} {k['p']:>2} {k['relu']:>4} {k['sw']:>4}")
    p += ["", "İşler (sırasıyla): faz, katman, PE geçişi, grup sayısı, B_global, G, hedef"]
    for i in y["isler"]:
        p.append(f"  {FAZ_ADI[i['faz']]} katman {i['l']}: {i['n_pe']} PE geçişi, {len(i['M'])} grup, "
                 f"B_global {SRU.B(max(i['M']))}, G {i['G']} (hedef {i['hedef']})")
    sayac = {}
    for kom in komutlar:
        sayac[OP_ADI[kom[0]]] = sayac.get(OP_ADI[kom[0]], 0) + 1
    p += ["", f"Komut sayıları: {sayac}, toplam {len(komutlar)}",
          f"Max Regs derinliği (bir işteki en çok grup): {max(len(i['M']) for i in y['isler'])} x 32 bit",
          f"Psum FIFO en çok doluluk: {y['fifo_en_cok']} int32",
          f"Çıkış tamponu (CIK) en çok doluluk: {y['cik_en_cok']} bayt",
          f"maksreg.txt olay sayısı: {len(y['olaylar'])}",
          f"s_a: {y['s_a']}  (CLU s_a = {y['s_a'][-1]})", "",
          "İlk 6 komut (op faz katman b x y z a1 a2 a3):"]
    for kom in komutlar[:6]:
        p.append("  " + " ".join(f"{v:>3}" for v in kom) + f"   <- {OP_ADI[kom[0]]}")
    p += ["", f"T8 kontrolü: ReLU ile GMS'in sırası {n_degisme} durumun hepsinde aynı sonucu verdi.",
          "", "Float kontrolü (III): int sonuçlar, aynı başlangıçtaki ondalıklı ağla karşılaştırıldı.",
          f"{'ölçüm':<52} {'karar (D59)':>15} {'doymalı ref.':>15}"]
    for ad in olcum:
        p.append(f"  {ad:<50} {olcum[ad]:>15.4f} {olcum_ref[ad]:>15.4f}")
    p += [f"SRU'da 128'e ulaşan değer (bu adımda): {y['tasma']}"
          + (" — hepsi ±127'ye doyuruldu" if SRU.DOYMA else " — 8 bitte sarıldı (D59, makaledeki gibi)"),
          "'karar' sütunu yazılan vektörlerin (beklenen_sonuc.txt) değerleri; yalnızca raporlanır.",
          "'doymalı ref.' sütunu sıkı eşiklerle denetlenir (FP sapması < 0,1, kosinüs > 0,95); doyma",
          "yalnızca bu karşılaştırma için açıldı. Doyma olmazsa taşan değer grubun en büyük değeridir",
          "ve işaret değiştirir."]
    with open(yol, "w") as f:
        f.write("\n".join(p) + "\n")


# ----------------------------------------------------------------------------
# Ana program
# ----------------------------------------------------------------------------
def esit_mi(a, b):
    return kopya(a) == kopya(b)


def calistir(ag, klasor):
    """Bir ağ için bütün kontrolleri çalıştırır ve dosyaları klasöre yazar."""
    ag_kur(ag)
    ag_adi = ag["ad"]
    AKT0, W0, etiket = baslangic_verisi()
    sablon = komut_sablonlari()
    n_is = sablon_kontrol(sablon)
    n_degisme = relu_gms_degisme_kontrolu()
    komutlar, y = yorumla(sablon, AKT0, W0, etiket)
    t = tensor_adimi(AKT0, W0, etiket)
    en_cok_grup = max(len(i["M"]) for i in y["isler"])
    assert en_cok_grup <= MAKS_REG_DERINLIK, f"{ag_adi}: {en_cok_grup} grup, Max Regs derinliği yetmiyor"

    # (I) == (II): bit bit
    for l in range(1, L + 1):
        assert esit_mi(y["AKT"][l], t["AKT"][l]), f"AKT {l} farklı"
        assert esit_mi(y["HATA"][l], t["HATA"][l]), f"HATA {l} farklı"
    assert esit_mi(y["W"], t["W"]), "son ağırlıklar farklı"
    assert y["s_a"] == t["s_a"], "s_a farklı"
    assert [(i["faz"], i["l"], i["M"], i["G"]) for i in y["isler"]] == t["isler"], \
        "iş başına yerel maksimum listeleri ya da G farklı"
    assert y["olaylar"] == t["olaylar"], "Max Regs olayları farklı"
    assert not esit_mi(t["W"], W0), "ağırlıklar hiç değişmedi"
    print(f"[{ag_adi}] 1) Komut yorumlayıcı (I) ile tensör düzeyi (II) bit bit aynı: {len(komutlar)} komut, "
          f"{len(y['olaylar'])} Max Regs olayı; aktivasyonlar, hatalar, son ağırlıklar ve s_a = {t['s_a']}.")

    # (III) Float kontrolü (Ömer, 03.11: yapı aynen kalsın; vektörler Egemen'in sistemine ve
    #       makaleye göre, yani doymasız, D59).
    #  (III-a) Sıkı eşikler, doymalı REFERANS çalıştırmada: SRU-a3 dışındaki her şeyi (PE, LMS/GMS,
    #          ReLU, CLU, WU, ölçek üsleri) float ağa karşı denetler. Doyma yalnızca bu çalıştırmada
    #          geçici olarak açılır; yazılan vektörleri etkilemez.
    eski = SRU.DOYMA
    SRU.DOYMA = True
    t_ref = tensor_adimi(AKT0, W0, etiket)
    SRU.DOYMA = eski
    olcum_ref = float_kontrol(AKT0, W0, etiket, t_ref)
    for ad, v in olcum_ref.items():
        assert (v > 0.95) if "kosinüs" in ad else (v < 0.1), (ad, v)
    #  (III-b) Kararın kendisi (SRU.DOYMA dosyadaki değeriyle; D59: False): yalnızca raporlanır.
    #          Doymasızda taşan değer grubun en büyüğüdür ve işaret değiştirir (D38'deki ölçümler).
    olcum = float_kontrol(AKT0, W0, etiket, t)
    print(f"[{ag_adi}] 2) Float kontrolü (sıkı eşikler doymalı referansta): FP sapması <= "
          f"{max(v for a, v in olcum_ref.items() if 'kosinüs' not in a):.3f}, kosinüs >= "
          f"{min(v for a, v in olcum_ref.items() if 'kosinüs' in a):.3f}. "
          f"Kararla ({'doymalı' if SRU.DOYMA else 'doymasız'}, SRU'da 128'e ulaşan: {y['tasma']}) "
          f"FP sapması en çok {max(v for a, v in olcum.items() if 'kosinüs' not in a):.3f} (yalnızca rapor).")
    print(f"[{ag_adi}] 3) Yapısal kontroller {n_is} işte tamam; T8 (ReLU/GMS sırası) {n_degisme} durumda aynı.")

    os.makedirs(klasor, exist_ok=True)
    yaz_ag(os.path.join(klasor, "ag_yapilandirma.txt"))
    with open(os.path.join(klasor, "komutlar.txt"), "w") as f:
        f.write(f"{len(komutlar)}\n")
        for kom in komutlar:
            f.write(" ".join(str(v) for v in kom) + "\n")
    yaz_maksreg(os.path.join(klasor, "maksreg.txt"), y["olaylar"])
    pe_izi_yaz(os.path.join(klasor, "pe_izi.txt"), y["iz"])
    yaz_veri(os.path.join(klasor, "baslangic.txt"), os.path.join(klasor, "beklenen_sonuc.txt"),
             AKT0, W0, etiket, t)
    okunur_yaz(os.path.join(klasor, "OKUNUR.txt"), komutlar, y, olcum, olcum_ref, n_degisme)
    print(f"[{ag_adi}] 4) Dosyalar yazıldı: {klasor}/")
    return komutlar, y, t, olcum


def main(klasor="adim4_vektorleri"):
    sonuc = calistir(AG1, klasor)                       # ana test ağı
    calistir(AG2, os.path.join(klasor, "ag2"))          # FSM testi için ikinci yapılandırma
    ag_kur(AG1)                                         # modül durumu ana ağa dönsün
    return sonuc


if __name__ == "__main__":
    main()
