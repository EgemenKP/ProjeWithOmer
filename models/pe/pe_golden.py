# =============================================================================
#  pe_golden.py  —  PE (Processing Element) için Python golden model
# -----------------------------------------------------------------------------
#  Kaynak     : Shao vd., "An FPGA-Based Reconfigurable Accelerator for Low-Bit
#               DNN Training", ISVLSI 2021, Bölüm III-A ve Fig. 2-5 (s. 256-257)
#  Hazırlayan : Claude (Ömer'in isteğiyle; Egemen'in PE RTL'ini test etmek için)
#  Tarih      : 28.10.2026
#
#  Bu dosya dört iş yapar:
#    1) MATEMATİK REFERANSI  : FP, BP ve WG konvolüsyonlarını düz döngülerle hesaplar.
#    2) PE ÇEVRİM MODELİ     : Fig. 3-5'teki veri akışını saat çevrimi saat çevrimi
#                              taklit eder (D register'ları, kısmi toplam zincirleri).
#    3) KENDİNİ KONTROL      : (2)'nin sonucu her test durumunda (1) ile karşılaştırılır.
#    4) TEST VEKTÖRLERİ      : pe_vektorleri/ klasörüne testbench dosyaları yazar.
#                              Biçim README_PE_GOLDEN.md'de anlatılıyor.
#
#  Çalıştırma : python3 pe_golden.py
#  Kütüphane  : yok; yalnızca Python'un kendi 'os' ve 'random' modülleri.
#
#  Modelin varsaydığı ama makalenin yazmadığı noktalar (D adayları, README'de ayrıntı):
#    PE-a2 : Psum FIFO'dan gelen kısmi toplam, zincirin başındaki mux'tan girer.
#    PE-a3 : Zamanlama Fig. 3-5'teki D register'larıyla birebir; satırları toplayan
#            sağdaki toplayıcılar kombinasyonel (register'sız) kabul edildi.
#    PE-a6 : BP stride 2'de satır 0 ve 1'e e[p], satır 2'ye e[p-1] akışı gider.
#    PE-a7 : WG'de her PE satırına aynı hata satırı E[i], r. satıra A[s*i + r] gider.
# =============================================================================

import os        # os.makedirs(yol, exist_ok=True): klasör oluşturur (varsa hata vermez)
                 # os.path.join(a, b): klasör ve dosya adını doğru ayraçla birleştirir
import random    # random.seed(n): rastgele üreteci sabitler -> her çalıştırmada AYNI vektörler
                 # random.randint(a, b): a ile b arasında (ikisi dahil) rastgele tamsayı
                 # random.choice(liste): listeden rastgele bir eleman

# ----------------------------------------------------------------------------
# Sabitler
# ----------------------------------------------------------------------------
INT8_MIN, INT8_MAX = -127, 127            # D9: simetrik int8 aralığı
INT32_MIN, INT32_MAX = -2**31, 2**31 - 1  # PE'nin içindeki toplamlar int32'ye sığmalı

# Testbench'in $fscanf ile okuyabilmesi için modlar sayıyla kodlanıyor
MOD_KODLARI = {"FP_S1": 0, "FP_S2": 1, "BP_S1": 2, "BP_S2": 3, "WG_S1": 4, "WG_S2": 5}
N_CIKIS = {"FP_S1": 1, "FP_S2": 1, "BP_S1": 1, "BP_S2": 4, "WG_S1": 0, "WG_S2": 0}

KLASOR = "pe_vektorleri"                  # vektör dosyalarının yazılacağı klasör


# ----------------------------------------------------------------------------
# Küçük yardımcılar
# ----------------------------------------------------------------------------
def sifir_matris(satir, sutun):
    """satir x sutun boyutunda, her elemanı 0 olan matris (liste listesi)."""
    matris = []
    for _ in range(satir):            # _ : döngü değişkenini kullanmayacağımızı gösterir
        matris.append([0] * sutun)    # [0] * sutun -> sutun tane sıfırdan oluşan liste
    return matris


def matris_topla(A, B):
    """Aynı boyuttaki iki matrisi eleman eleman toplar."""
    C = sifir_matris(len(A), len(A[0]))
    for i in range(len(A)):
        for j in range(len(A[0])):
            C[i][j] = A[i][j] + B[i][j]
    return C


def dolgu_ekle(X, p):
    """X'in dört kenarına p kat sıfır ekler (zero padding)."""
    genislik = len(X[0]) + 2 * p
    Xp = []
    for _ in range(p):                         # üstteki p sıfır satırı
        Xp.append([0] * genislik)
    for satir in X:                            # her satırın soluna ve sağına p sıfır
        Xp.append([0] * p + satir + [0] * p)   # listeleri + ile uç uca ekleriz
    for _ in range(p):                         # alttaki p sıfır satırı
        Xp.append([0] * genislik)
    return Xp


def dondur_180(W):
    """3x3 çekirdeği 180 derece döndürür: yeni[r][c] = W[2-r][2-c] (Fig. 4a)."""
    yeni = sifir_matris(3, 3)
    for r in range(3):
        for c in range(3):
            yeni[r][c] = W[2 - r][2 - c]
    return yeni


def int32_mi(x):
    """x int32 aralığında değilse programı durdurur (donanımdaki taşmayı yakalamak için)."""
    assert INT32_MIN <= x <= INT32_MAX, f"int32 taşması: {x}"
    return x


def rastgele_matris(satir, sutun, alt=INT8_MIN, ust=INT8_MAX):
    """Elemanları [alt, ust] aralığında rastgele tamsayı olan matris."""
    M = sifir_matris(satir, sutun)
    for i in range(satir):
        for j in range(sutun):
            M[i][j] = random.randint(alt, ust)
    return M


def duzlestir(M):
    """Matrisi satır satır tek listeye çevirir: [[1,2],[3,4]] -> [1,2,3,4]."""
    liste = []
    for satir in M:
        liste += satir
    return liste


# ----------------------------------------------------------------------------
# 1) MATEMATİK REFERANSI (katman düzeyi; donanımdan bağımsız)
# ----------------------------------------------------------------------------
def ref_fp(X, W, stride, pad):
    """İleri yayılım (FP): Y[i][j] = toplam_{r,c} W[r][c] * Xp[stride*i + r][stride*j + c]."""
    Xp = dolgu_ekle(X, pad)
    Ho = (len(Xp) - 3) // stride + 1           # // : tamsayı bölme (aşağı yuvarlar)
    Wo = (len(Xp[0]) - 3) // stride + 1
    Y = sifir_matris(Ho, Wo)
    for i in range(Ho):
        for j in range(Wo):
            toplam = 0
            for r in range(3):
                for c in range(3):
                    toplam += W[r][c] * Xp[stride * i + r][stride * j + c]
            Y[i][j] = toplam
    return Y


def ref_bp(E, W, stride, pad, H_in, W_in):
    """Geri yayılım (BP): her E[i][j] hatası, ileri geçişte katkı verdiği girişlere dağıtılır.
    dX[m][n] += W[r][c] * E[i][j],  m = stride*i + r - pad,  n = stride*j + c - pad."""
    dX = sifir_matris(H_in, W_in)
    for i in range(len(E)):
        for j in range(len(E[0])):
            for r in range(3):
                for c in range(3):
                    m = stride * i + r - pad
                    n = stride * j + c - pad
                    if 0 <= m < H_in and 0 <= n < W_in:   # dolgu bölgesine düşenler atılır
                        dX[m][n] += W[r][c] * E[i][j]
    return dX


def ref_wg(A, E, stride, pad):
    """Ağırlık gradyanı (WG): G[r][c] = toplam_{i,j} Ap[stride*i + r][stride*j + c] * E[i][j]."""
    Ap = dolgu_ekle(A, pad)
    G = sifir_matris(3, 3)
    for r in range(3):
        for c in range(3):
            for i in range(len(E)):
                for j in range(len(E[0])):
                    G[r][c] += Ap[stride * i + r][stride * j + c] * E[i][j]
    return G


def ic_carpim(A, B):
    """İki matrisin eleman eleman çarpımlarının toplamı."""
    toplam = 0
    for i in range(len(A)):
        for j in range(len(A[0])):
            toplam += A[i][j] * B[i][j]
    return toplam


def referans_ozdeslik_testi(adet=300):
    """Üç referans fonksiyonun birbiriyle tutarlı olduğunu kontrol eder.
    Kullanılan matematiksel özdeşlikler (eşlenik / adjoint):
      <FP(X, W), E> = <X, BP(E, W)>   ve   <FP(X, W), E> = <W, WG(X, E)>
    Bu ikisi tutuyorsa BP'deki döndürme/dolgu ve WG'deki indisler doğrudur."""
    for _ in range(adet):
        stride = random.choice([1, 2])
        pad = random.choice([0, 1])
        H = random.randint(3, 8)
        Wd = random.randint(3, 8)
        X = rastgele_matris(H, Wd)
        W = rastgele_matris(3, 3)
        Y = ref_fp(X, W, stride, pad)
        E = rastgele_matris(len(Y), len(Y[0]))
        sol = ic_carpim(Y, E)
        assert sol == ic_carpim(X, ref_bp(E, W, stride, pad, H, Wd)), "ref_bp hatalı"
        assert sol == ic_carpim(W, ref_wg(X, E, stride, pad)), "ref_wg hatalı"


# ----------------------------------------------------------------------------
# 2) PE ÇEVRİM MODELİ (Fig. 3-5)
#
#  Zamanlama tanımı: t. çevrimde girişler uygulanır, çevrimin sonundaki saat
#  kenarında D register'ları güncellenir. Kaydedilen çıkış, bu kenardan SONRAKİ
#  değerdir ("figür çevrimi" = t).
# ----------------------------------------------------------------------------
def zincir_adimi(regler, agirliklar, girisler, zincir_girisi):
    """Bir kısmi toplam zincirini (Fig. 3: mux -> + -> D -> + -> D -> + -> D) bir çevrim ilerletir.
      regler        : zincirdeki D register'larının şu anki değerleri (soldan sağa)
      agirliklar    : her basamağın MAC'ine yüklenmiş ağırlık
      girisler      : her basamağın çarpıcısına bu çevrimde gelen veri
      zincir_girisi : ilk toplayıcının sol girişi (mux'tan: Psum FIFO değeri ya da 0)
    Dönüş: saat kenarından sonraki register değerleri."""
    yeni = []
    for k in range(len(regler)):
        if k == 0:
            onceki = zincir_girisi           # ilk basamak mux'tan beslenir
        else:
            onceki = regler[k - 1]           # bir önceki basamağın ESKİ (kenar öncesi) değeri
        yeni.append(int32_mi(onceki + agirliklar[k] * girisler[k]))
    return yeni


def pe_gecis_s1(akislar, w, ps_akisi):
    """FP stride 1 (Fig. 3a) ve BP stride 1 (Fig. 4a): aynı donanım deseni.
      akislar[r][t] : t. çevrimde PE'nin r. satırındaki 3 MAC'e yayınlanan değer
      w[r][c]       : MAC[r][c]'ye yüklenen ağırlık
      ps_akisi[t]   : t. çevrimde satır 0'ın başındaki mux'a gelen kısmi toplam
    Dönüş: (cevrimler, ciktilar)
      cevrimler : her çevrim için (giriş şeritleri, çıkış şeritleri, geçerli mi)
      ciktilar  : geçerli çıktılar, üretildikleri sırayla: [(figür çevrimi, [değer]), ...]"""
    T = len(akislar[0])
    regler = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]      # 3 satır x 3 D register
    cevrimler = []
    ciktilar = []
    for t in range(T):
        for r in range(3):
            x = akislar[r][t]                       # aynı değer satırdaki 3 MAC'e yayınlanır
            if r == 0:
                zincir_girisi = ps_akisi[t]         # yalnız satır 0'da mux var (PE-a2)
            else:
                zincir_girisi = 0
            regler[r] = zincir_adimi(regler[r], w[r], [x, x, x], zincir_girisi)
        cikis = int32_mi(regler[0][2] + regler[1][2] + regler[2][2])   # sağdaki toplayıcı
        gecerli = t >= 2                            # ilk 2 çevrimde pencere henüz dolmadı
        girisler = [akislar[0][t], akislar[1][t], akislar[2][t], ps_akisi[t]]
        cevrimler.append((girisler, [cikis], gecerli))
        if gecerli:
            ciktilar.append((t, [cikis]))
    return cevrimler, ciktilar


def pe_gecis_s2(cift, tek, w, ps_akisi):
    """FP stride 2 (Fig. 3b).
      cift[r][t] : r. satırın çift akışı (x0, x2, x4, ..., 0)   -> w[r][0]'a doğrudan
      tek[r][t]  : r. satırın tek akışı  (0, x1, x3, ...)       -> w[r][1]'e
      w[r][2]'nin önünde çift akışı 1 çevrim geciktiren bir D register'ı var (mavi D)."""
    T = len(cift[0])
    regler = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
    gecikmeli = [0, 0, 0]                           # her satırın mavi D register'ı
    cevrimler = []
    ciktilar = []
    for t in range(T):
        girisler = []
        for r in range(3):
            c_t = cift[r][t]
            k_t = tek[r][t]
            mac_girisleri = [c_t, k_t, gecikmeli[r]]  # gecikmeli[r] = bir önceki çevrimin çifti
            if r == 0:
                zincir_girisi = ps_akisi[t]
            else:
                zincir_girisi = 0
            regler[r] = zincir_adimi(regler[r], w[r], mac_girisleri, zincir_girisi)
            gecikmeli[r] = c_t                         # saat kenarı: mavi D güncellenir
            girisler += [c_t, k_t]
        girisler.append(ps_akisi[t])
        cikis = int32_mi(regler[0][2] + regler[1][2] + regler[2][2])
        gecerli = t >= 2
        cevrimler.append((girisler, [cikis], gecerli))
        if gecerli:
            ciktilar.append((t, [cikis]))
    return cevrimler, ciktilar


def pe_gecis_bp_s2(akislar, w, ps_akisi):
    """BP stride 2 (Fig. 4b). Her satırda iki zincir var:
      A zinciri: 2 MAC (w[r][0], w[r][1]),  B zinciri: 1 MAC (w[r][2])
      Fig. 4(b) yüklemesi: satır0 = [w02, w00, w01], satır1 = [w12, w10, w11], satır2 = [w22, w20, w21]
      ps_akisi[t] = [psA0, psB0, psA1, psB1]: satır 0 ve 1'in A/B zincirlerinin başındaki mux'lara
    Çıkış şeritleri (her geçerli çevrimde 4 değer = Psum FIFO'ya 4 paralel kısmi toplam):
      out0 = A0 + A2,  out1 = B0 + B2,  out2 = A1,  out3 = B1"""
    T = len(akislar[0])
    regA = [[0, 0], [0, 0], [0, 0]]
    regB = [[0], [0], [0]]
    cevrimler = []
    ciktilar = []
    for t in range(T):
        psA0, psB0, psA1, psB1 = ps_akisi[t]           # listeyi 4 değişkene açar
        A_girisi = [psA0, psA1, 0]                      # satır 2'nin zincirlerine psum girmez
        B_girisi = [psB0, psB1, 0]
        for r in range(3):
            s = akislar[r][t]
            regA[r] = zincir_adimi(regA[r], [w[r][0], w[r][1]], [s, s], A_girisi[r])
            regB[r] = zincir_adimi(regB[r], [w[r][2]], [s], B_girisi[r])
        out0 = int32_mi(regA[0][1] + regA[2][1])
        out1 = int32_mi(regB[0][0] + regB[2][0])
        out2 = regA[1][1]
        out3 = regB[1][0]
        gecerli = t >= 1                                 # ilk çevrimde baştaki 0 işleniyor
        girisler = [akislar[0][t], akislar[1][t], akislar[2][t], psA0, psB0, psA1, psB1]
        cevrimler.append((girisler, [out0, out1, out2, out3], gecerli))
        if gecerli:
            ciktilar.append((t, [out0, out1, out2, out3]))
    return cevrimler, ciktilar


def pe_gecis_wg_s1(a, e, akum):
    """WG stride 1 (Fig. 5a). Çıktı-durağan: akum[r][c] MAC[r][c]'nin akümülatörüdür,
    geçişler boyunca birikir (case başında sıfırlanır).
      a[r][t] : r. satırın 3 MAC'ine yayınlanan aktivasyon
      e[r][t] : r. satırın hata akışı; MAC0 doğrudan, MAC1 1 çevrim, MAC2 2 çevrim gecikmeli görür"""
    T = len(a[0])
    e_d1 = [0, 0, 0]                                # her satırın hata zincirindeki 1. D
    e_d2 = [0, 0, 0]                                # 2. D
    cevrimler = []
    for t in range(T):
        girisler = []
        for r in range(3):
            a_t = a[r][t]
            e_t = e[r][t]
            e_mac = [e_t, e_d1[r], e_d2[r]]
            for c in range(3):
                akum[r][c] = int32_mi(akum[r][c] + a_t * e_mac[c])
            e_d2[r] = e_d1[r]                        # saat kenarı: hata zinciri bir adım kayar
            e_d1[r] = e_t
            girisler += [a_t, e_t]
        cevrimler.append((girisler, [], False))
    # Akışın sonundaki sıfırlar zinciri boşaltmış olmalı; yoksa sonraki geçiş kirlenir.
    assert e_d1 == [0, 0, 0] and e_d2 == [0, 0, 0], "WG hata zinciri boşalmadı"
    return cevrimler, []


def pe_gecis_wg_s2(cift, tek, e, akum):
    """WG stride 2 (Fig. 5b): aktivasyon Fig. 3(b)'deki gibi çift/tek akışlı,
    MAC2'nin önünde çift akışı geciktiren D var; hata zinciri WG s1 ile aynı."""
    T = len(cift[0])
    e_d1 = [0, 0, 0]
    e_d2 = [0, 0, 0]
    gecikmeli = [0, 0, 0]
    cevrimler = []
    for t in range(T):
        girisler = []
        for r in range(3):
            c_t = cift[r][t]
            k_t = tek[r][t]
            e_t = e[r][t]
            a_mac = [c_t, k_t, gecikmeli[r]]
            e_mac = [e_t, e_d1[r], e_d2[r]]
            for c in range(3):
                akum[r][c] = int32_mi(akum[r][c] + a_mac[c] * e_mac[c])
            gecikmeli[r] = c_t
            e_d2[r] = e_d1[r]
            e_d1[r] = e_t
            girisler += [c_t, k_t, e_t]
        cevrimler.append((girisler, [], False))
    assert e_d1 == [0, 0, 0] and e_d2 == [0, 0, 0] and gecikmeli == [0, 0, 0], \
        "WG s2 zinciri boşalmadı"
    return cevrimler, []


# ----------------------------------------------------------------------------
# Ön-getirme (prefetch) modülünün işi: satırlardan PE akışlarını hazırlamak
# ----------------------------------------------------------------------------
def cift_tek_ayir(satir):
    """Fig. 3(b)/5(b): satırı çift ve tek akışa ayırır.
      cift = x0, x2, x4, ... + [0]   (sondaki 0: son çıktı için 1 boşaltma çevrimi)
      tek  = 0, x1, x3, ...          (baştaki 0; çift akışla aynı uzunluğa 0 ile tamamlanır)"""
    cift = satir[0::2] + [0]           # satir[0::2]: 0., 2., 4., ... elemanlar
    tek = [0] + satir[1::2]            # satir[1::2]: 1., 3., 5., ... elemanlar
    while len(tek) < len(cift):
        tek.append(0)
    return cift, tek


def bp_s2_akisi(e_satiri):
    """Fig. 4(b): başta sınır sıfırı ("..., e11, e10, 0"), sonda 1 boşaltma sıfırı."""
    return [0] + e_satiri + [0]


def ps_akisi_s(psum, T):
    """s1/s2 geçişleri: j. çıktının kısmi toplamı j. çevrimde satır 0'ın mux'una verilir.
    (j. pencerenin ilk çarpımı j. çevrimde yapılır; psum oradan zincire girer.)"""
    akis = []
    for t in range(T):
        if t < T - 2:
            akis.append(psum[t])
        else:
            akis.append(0)                 # bu çevrimlerde başlayan geçerli pencere yok
    return akis


def ps_akisi_bp_s2(psum4, T):
    """BP s2: q. sütun çiftinin kısmi toplamı A zincirlerine q. çevrimde,
    B zincirlerine (q+1). çevrimde girer (B zinciri tek basamaklı olduğu için)."""
    n = T - 1                              # sütun çifti sayısı
    akis = []
    for t in range(T):
        psA0 = psum4[0][t] if t < n else 0
        psB0 = psum4[1][t - 1] if 1 <= t <= n else 0
        psA1 = psum4[2][t] if t < n else 0
        psB1 = psum4[3][t - 1] if 1 <= t <= n else 0
        akis.append([psA0, psB0, psA1, psB1])
    return akis


# ----------------------------------------------------------------------------
# 3) KATMAN DÜZEYİNDE TEST DURUMLARI (her biri PE sonucunu referansla karşılaştırır)
# ----------------------------------------------------------------------------
def case_fp(stride, pad, X_list, W_list, aciklama):
    """Tek çıkış kanalı için FP. X_list[k], W_list[k]: k. giriş kanalı.
    Sıra: kanal dışta, çıktı satırı içte (ağırlıklar kanal bitene kadar sabit, III-A-1).
    Kanallar arasındaki kısmi toplamları Psum FIFO taşır."""
    Y_ref = ref_fp(X_list[0], W_list[0], stride, pad)
    for k in range(1, len(X_list)):
        Y_ref = matris_topla(Y_ref, ref_fp(X_list[k], W_list[k], stride, pad))
    Ho = len(Y_ref)
    Wo = len(Y_ref[0])
    fifo = []                                    # Psum FIFO: kısmi toplam satırları
    Y_pe = sifir_matris(Ho, Wo)
    gecisler = []
    for k in range(len(X_list)):
        Xp = dolgu_ekle(X_list[k], pad)          # dolguyu ön-getirme modülü ekler
        for i in range(Ho):
            satirlar = [Xp[stride * i], Xp[stride * i + 1], Xp[stride * i + 2]]
            if k == 0:
                psum = [0] * Wo                  # ilk kanal: FIFO boş
            else:
                psum = fifo.pop(0)               # pop(0): FIFO'nun başındaki satırı al
            if stride == 1:
                T = len(satirlar[0])
                cevrimler, ciktilar = pe_gecis_s1(satirlar, W_list[k], ps_akisi_s(psum, T))
            else:
                cift = []
                tek = []
                for s in satirlar:
                    c_akis, t_akis = cift_tek_ayir(s)
                    cift.append(c_akis)
                    tek.append(t_akis)
                T = len(cift[0])
                cevrimler, ciktilar = pe_gecis_s2(cift, tek, W_list[k], ps_akisi_s(psum, T))
            degerler = [deger[0] for (_, deger) in ciktilar]
            assert len(degerler) == Wo
            if k < len(X_list) - 1:
                fifo.append(degerler)            # sonraki kanal için FIFO'ya yaz
            else:
                Y_pe[i] = degerler               # son kanal: nihai çıktı satırı
            gecisler.append({"w": W_list[k], "w_orijinal": W_list[k],
                             "cevrimler": cevrimler, "ciktilar": ciktilar})
    assert Y_pe == Y_ref, f"FP s{stride}: PE modeli referansla uyuşmuyor ({aciklama})"
    return {"aciklama": aciklama, "kanal": len(X_list), "gecisler": gecisler,
            "katman_sonucu": Y_ref}


def case_bp_s1(pad, E_list, W_list, aciklama):
    """BP stride 1 (Fig. 4a): hata haritası (2 - pad) kat sıfırla dolgulanır, çekirdek
    180 derece döndürülmüş yüklenir; geri kalanı FP s1 ile aynı donanım.
    E_list[k], W_list[k]: dX'e katkı veren k. çıkış kanalı (Psum FIFO'da toplanır)."""
    He = len(E_list[0])
    We = len(E_list[0][0])
    H_in = He + 2 - 2 * pad                  # ileri geçişteki giriş boyutu (stride 1)
    W_in = We + 2 - 2 * pad
    dX_ref = ref_bp(E_list[0], W_list[0], 1, pad, H_in, W_in)
    for k in range(1, len(E_list)):
        dX_ref = matris_topla(dX_ref, ref_bp(E_list[k], W_list[k], 1, pad, H_in, W_in))
    fifo = []
    dX_pe = sifir_matris(H_in, W_in)
    gecisler = []
    for k in range(len(E_list)):
        Ep = dolgu_ekle(E_list[k], 2 - pad)
        w_yuklu = dondur_180(W_list[k])
        for m in range(H_in):
            satirlar = [Ep[m], Ep[m + 1], Ep[m + 2]]
            psum = [0] * W_in if k == 0 else fifo.pop(0)
            T = len(satirlar[0])
            cevrimler, ciktilar = pe_gecis_s1(satirlar, w_yuklu, ps_akisi_s(psum, T))
            degerler = [deger[0] for (_, deger) in ciktilar]
            assert len(degerler) == W_in
            if k < len(E_list) - 1:
                fifo.append(degerler)
            else:
                dX_pe[m] = degerler
            gecisler.append({"w": w_yuklu, "w_orijinal": W_list[k],
                             "cevrimler": cevrimler, "ciktilar": ciktilar})
    assert dX_pe == dX_ref, f"BP s1: PE modeli referansla uyuşmuyor ({aciklama})"
    return {"aciklama": aciklama, "kanal": len(E_list), "gecisler": gecisler,
            "katman_sonucu": dX_ref}


def case_bp_s2(pad, H_in, W_in, E_list, W_list, aciklama):
    """BP stride 2 (Fig. 4b). p. geçiş: satır 0 ve 1 <- e[p], satır 2 <- e[p-1] (PE-a6).
    Her çevrim 2x2'lik bir çıktı bloğu üretir. Dolgusuz koordinatlarda:
      out0 -> dx0[2p][2q], out1 -> dx0[2p][2q+1], out2 -> dx0[2p+1][2q], out3 -> dx0[2p+1][2q+1]
    İleri geçişte dolgu varsa: dX[m][n] = dx0[m + pad][n + pad]."""
    He = len(E_list[0])
    We = len(E_list[0][0])
    n = We + 1                                   # bir geçişteki sütun çifti sayısı
    dX_ref = ref_bp(E_list[0], W_list[0], 2, pad, H_in, W_in)
    for k in range(1, len(E_list)):
        dX_ref = matris_topla(dX_ref, ref_bp(E_list[k], W_list[k], 2, pad, H_in, W_in))
    fifo = []
    dx0 = sifir_matris(2 * He + 2, 2 * We + 2)
    gecisler = []
    sifir_satir = [0] * We
    for k in range(len(E_list)):
        W = W_list[k]
        w_yuklu = [[W[0][2], W[0][0], W[0][1]],      # Fig. 4(b)'deki MAC sırası
                   [W[1][2], W[1][0], W[1][1]],
                   [W[2][2], W[2][0], W[2][1]]]
        E = E_list[k]
        for p in range(He + 1):
            e_p = E[p] if p < He else sifir_satir
            e_once = E[p - 1] if p >= 1 else sifir_satir
            akislar = [bp_s2_akisi(e_p), bp_s2_akisi(e_p), bp_s2_akisi(e_once)]
            T = len(akislar[0])
            if k == 0:
                psum4 = [[0] * n, [0] * n, [0] * n, [0] * n]
            else:
                psum4 = fifo.pop(0)
            cevrimler, ciktilar = pe_gecis_bp_s2(akislar, w_yuklu, ps_akisi_bp_s2(psum4, T))
            seritler = [[], [], [], []]              # 4 çıkış şeridini ayrı listelere topla
            for (_, degerler) in ciktilar:
                for s in range(4):
                    seritler[s].append(degerler[s])
            assert len(seritler[0]) == n
            if k < len(E_list) - 1:
                fifo.append(seritler)
            else:
                for q in range(n):
                    dx0[2 * p][2 * q] = seritler[0][q]
                    dx0[2 * p][2 * q + 1] = seritler[1][q]
                    dx0[2 * p + 1][2 * q] = seritler[2][q]
                    dx0[2 * p + 1][2 * q + 1] = seritler[3][q]
            gecisler.append({"w": w_yuklu, "w_orijinal": W,
                             "cevrimler": cevrimler, "ciktilar": ciktilar})
    dX_pe = sifir_matris(H_in, W_in)
    for m in range(H_in):
        for nn in range(W_in):
            if m + pad < len(dx0) and nn + pad < len(dx0[0]):
                dX_pe[m][nn] = dx0[m + pad][nn + pad]
    assert dX_pe == dX_ref, f"BP s2: PE modeli referansla uyuşmuyor ({aciklama})"
    return {"aciklama": aciklama, "kanal": len(E_list), "gecisler": gecisler,
            "katman_sonucu": dX_ref}


def case_wg(stride, pad, A_list, E_list, aciklama):
    """WG (Fig. 5). A_list[b], E_list[b]: batch'in b. örneği (aynı kanal çifti).
    i. geçiş: r. PE satırına A[stride*i + r] satırı, üç satırın hepsine E[i] satırı (PE-a7).
    9 akümülatör tüm geçişler boyunca birikir; sonuç = G[r][c]."""
    G_ref = ref_wg(A_list[0], E_list[0], stride, pad)
    for b in range(1, len(A_list)):
        G_ref = matris_topla(G_ref, ref_wg(A_list[b], E_list[b], stride, pad))
    akum = sifir_matris(3, 3)
    gecisler = []
    for b in range(len(A_list)):
        Ap = dolgu_ekle(A_list[b], pad)
        E = E_list[b]
        for i in range(len(E)):
            a_satirlari = [Ap[stride * i], Ap[stride * i + 1], Ap[stride * i + 2]]
            if stride == 1:
                T = len(a_satirlari[0])
                e_akis = []
                for _ in range(3):
                    e_akis.append(E[i] + [0] * (T - len(E[i])))   # sonu sıfır: zincir boşalır
                cevrimler, _ = pe_gecis_wg_s1(a_satirlari, e_akis, akum)
            else:
                cift = []
                tek = []
                for s in a_satirlari:
                    c_akis, t_akis = cift_tek_ayir(s)
                    cift.append(c_akis)
                    tek.append(t_akis)
                T = len(cift[0])
                e_akis = []
                for _ in range(3):
                    e_akis.append(E[i] + [0] * (T - len(E[i])))
                cevrimler, _ = pe_gecis_wg_s2(cift, tek, e_akis, akum)
            gecisler.append({"w": sifir_matris(3, 3), "w_orijinal": sifir_matris(3, 3),
                             "cevrimler": cevrimler, "ciktilar": []})
    assert akum == G_ref, f"WG s{stride}: PE modeli referansla uyuşmuyor ({aciklama})"
    return {"aciklama": aciklama, "kanal": len(A_list), "gecisler": gecisler,
            "katman_sonucu": G_ref, "beklenen_akum": G_ref}


# ----------------------------------------------------------------------------
# Rastgele durum üreticileri (boyutları ileri geçişle tutarlı seçer)
# ----------------------------------------------------------------------------
def cikis_boyu(n, pad, stride):
    """İleri geçişte n uzunluklu girişin çıktı uzunluğu."""
    return (n + 2 * pad - 3) // stride + 1


def rastgele_fp(stride, pad, kanal, H, W, alt=INT8_MIN, aciklama=""):
    X_list = [rastgele_matris(H, W, alt=alt) for _ in range(kanal)]
    W_list = [rastgele_matris(3, 3) for _ in range(kanal)]
    return case_fp(stride, pad, X_list, W_list, aciklama)


def rastgele_bp_s1(pad, kanal, He, We, aciklama=""):
    E_list = [rastgele_matris(He, We) for _ in range(kanal)]
    W_list = [rastgele_matris(3, 3) for _ in range(kanal)]
    return case_bp_s1(pad, E_list, W_list, aciklama)


def rastgele_bp_s2(pad, kanal, H_in, W_in, aciklama=""):
    He = cikis_boyu(H_in, pad, 2)
    We = cikis_boyu(W_in, pad, 2)
    E_list = [rastgele_matris(He, We) for _ in range(kanal)]
    W_list = [rastgele_matris(3, 3) for _ in range(kanal)]
    return case_bp_s2(pad, H_in, W_in, E_list, W_list, aciklama)


def rastgele_wg(stride, pad, batch, H, W, alt=INT8_MIN, aciklama=""):
    A_list = [rastgele_matris(H, W, alt=alt) for _ in range(batch)]
    He = cikis_boyu(H, pad, stride)
    We = cikis_boyu(W, pad, stride)
    E_list = [rastgele_matris(He, We) for _ in range(batch)]
    return case_wg(stride, pad, A_list, E_list, aciklama)


def isaretli_desen(H, W, deger):
    """+deger ve -deger'in dama tahtası gibi dizildiği matris (uç değer testi)."""
    M = sifir_matris(H, W)
    for i in range(H):
        for j in range(W):
            M[i][j] = deger if (i + j) % 2 == 0 else -deger
    return M


def ornek_caseler():
    """Vektör dosyalarına yazılacak deterministik test durumları."""
    random.seed(2026)                               # her çalıştırmada aynı vektörler
    W_el = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]        # el ile izlenebilir çekirdek
    C = {}                                          # mod adı -> case listesi

    C["FP_S1"] = [
        case_fp(1, 0, [[[0, 1, 2, 3, 4], [1, 2, 3, 4, 0], [2, 3, 4, 0, 1]]], [W_el],
                "El kontrolü: 3x5 giriş, 1 kanal, dolgu 0 -> tek geçiş, 3 çıktı"),
        case_fp(1, 0, [isaretli_desen(3, 6, 127)], [[[127] * 3, [127] * 3, [127] * 3]],
                "Uç değer: ±127 giriş, tüm ağırlıklar 127"),
        case_fp(1, 0, [[[-128] * 5, [-128] * 5, [-128] * 5]], [[[-127] * 3, [-127] * 3, [-127] * 3]],
                "−128 giriş (ilk katman, D9 notu), ağırlıklar −127"),
        rastgele_fp(1, 1, 1, 3, 4, aciklama="Dolgu 1: 3x4 giriş -> 3 geçiş"),
        rastgele_fp(1, 0, 3, 4, 6, aciklama="3 kanal: Psum FIFO birikimi"),
        rastgele_fp(1, 1, 2, 5, 7, aciklama="Rastgele: 2 kanal, dolgu 1"),
        rastgele_fp(1, 0, 1, 6, 8, aciklama="Rastgele: 1 kanal, dolgu 0"),
        rastgele_fp(1, 1, 3, 4, 3, aciklama="Rastgele: 3 kanal, en dar giriş (3 sütun)"),
    ]
    C["FP_S2"] = [
        case_fp(2, 0, [[[0, 1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6, 0], [2, 3, 4, 5, 6, 0, 1]]], [W_el],
                "El kontrolü: 3x7 giriş, 1 kanal, dolgu 0 -> tek geçiş, 3 çıktı"),
        case_fp(2, 0, [isaretli_desen(3, 7, 127)], [isaretli_desen(3, 3, 127)],
                "Uç değer: ±127 giriş ve ağırlık"),
        case_fp(2, 0, [[[-128] * 6, [-128] * 6, [-128] * 6]], [[[127] * 3, [127] * 3, [127] * 3]],
                "−128 giriş, çift genişlik (6 sütun)"),
        rastgele_fp(2, 1, 1, 4, 4, aciklama="Dolgu 1, çift genişlik"),
        rastgele_fp(2, 1, 3, 5, 7, aciklama="3 kanal: Psum FIFO birikimi"),
        rastgele_fp(2, 0, 2, 7, 9, aciklama="Rastgele: 2 kanal, dolgu 0"),
        rastgele_fp(2, 1, 1, 6, 8, aciklama="Rastgele: 1 kanal, dolgu 1"),
        rastgele_fp(2, 0, 1, 3, 3, aciklama="En küçük: 3x3 giriş -> 1 çıktı"),
    ]
    C["BP_S1"] = [
        case_bp_s1(0, [[[1, 2, 3]]], [W_el],
                   "El kontrolü: 1x3 hata, dolgu 0 -> dX 3x5 (3 geçiş)"),
        case_bp_s1(1, [isaretli_desen(3, 4, 127)], [isaretli_desen(3, 3, 127)],
                   "Uç değer: ±127 hata ve ağırlık, dolgu 1"),
        rastgele_bp_s1(1, 1, 3, 3, aciklama="Dolgu 1: 3x3 hata"),
        rastgele_bp_s1(0, 2, 2, 4, aciklama="2 kanal: Psum FIFO birikimi, dolgu 0"),
        rastgele_bp_s1(1, 3, 4, 5, aciklama="Rastgele: 3 kanal, dolgu 1"),
        rastgele_bp_s1(0, 1, 3, 6, aciklama="Rastgele: 1 kanal, dolgu 0"),
    ]
    C["BP_S2"] = [
        case_bp_s2(0, 3, 3, [[[1]]], [W_el],
                   "El kontrolü: 1x1 hata, dolgu 0 -> dX 3x3 (2 geçiş)"),
        case_bp_s2(0, 5, 5, [isaretli_desen(2, 2, 127)], [isaretli_desen(3, 3, 127)],
                   "Uç değer: ±127 hata ve ağırlık, dolgu 0"),
        rastgele_bp_s2(1, 1, 4, 4, aciklama="Dolgu 1: dX 4x4 (VGG tipi)"),
        rastgele_bp_s2(1, 2, 6, 6, aciklama="2 kanal: Psum FIFO birikimi (4 şerit)"),
        rastgele_bp_s2(0, 1, 7, 9, aciklama="Rastgele: dolgu 0, tek genişlik"),
        rastgele_bp_s2(1, 3, 5, 8, aciklama="Rastgele: 3 kanal, dolgu 1"),
    ]
    C["WG_S1"] = [
        case_wg(1, 0, [[[0, 1, 2, 3, 4], [1, 2, 3, 4, 0], [2, 3, 4, 0, 1]]], [[[1, 2, 3]]],
                "El kontrolü: 3x5 aktivasyon, 1x3 hata -> tek geçiş"),
        case_wg(1, 0, [isaretli_desen(4, 6, 127)], [isaretli_desen(2, 4, 127)],
                "Uç değer: ±127"),
        rastgele_wg(1, 0, 1, 3, 5, alt=-128, aciklama="−128 içeren aktivasyon (ilk katman)"),
        rastgele_wg(1, 1, 2, 4, 4, aciklama="Batch 2, dolgu 1"),
        rastgele_wg(1, 0, 3, 5, 6, aciklama="Rastgele: batch 3, dolgu 0"),
    ]
    C["WG_S2"] = [
        case_wg(2, 0, [[[0, 1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6, 0], [2, 3, 4, 5, 6, 0, 1]]],
                [[[1, 2, 3]]], "El kontrolü: 3x7 aktivasyon, 1x3 hata -> tek geçiş"),
        case_wg(2, 0, [isaretli_desen(5, 7, 127)], [isaretli_desen(2, 3, 127)],
                "Uç değer: ±127"),
        rastgele_wg(2, 1, 1, 4, 4, aciklama="Dolgu 1, çift genişlik"),
        rastgele_wg(2, 1, 2, 6, 8, aciklama="Batch 2, dolgu 1"),
        rastgele_wg(2, 0, 2, 7, 9, alt=-128, aciklama="Batch 2, −128 içeren aktivasyon"),
    ]
    return C


# ----------------------------------------------------------------------------
# 4) DOSYA YAZMA / GERİ OKUMA
# ----------------------------------------------------------------------------
def sayilari_yaz(liste):
    """[1, -2, 3] -> "1 -2 3" """
    return " ".join(str(x) for x in liste)    # str(x): sayıyı metne çevirir


def dosyaya_yaz(yol, mod, caseler):
    """Biçim (yalnız sayılar; boşluk ve satır sonu fark etmez, $fscanf("%d") ile okunur):
      MOD_KODU  CASE_SAYISI
      her case : CASE_NO  GECIS_SAYISI  KANAL_SAYISI
      her geçiş: GECIS_NO  T  N_CIKTI  N_GIRIS  N_CIKIS
                 9 yüklü ağırlık (MAC[0][0] ... MAC[2][2]; WG'de 9 sıfır)
                 T satır    : N_GIRIS sayı (giriş şeritleri, psum şeritleri dahil)
                 N_CIKTI satır: FIGUR_CEVRIMI + N_CIKIS sayı (beklenen çıkışlar)
      WG'de case sonunda: 9 beklenen akümülatör (G[0][0] ... G[2][2])"""
    satirlar = [f"{MOD_KODLARI[mod]} {len(caseler)}"]
    for case_no, case in enumerate(caseler):        # enumerate: (sıra no, eleman) verir
        satirlar.append(f"{case_no} {len(case['gecisler'])} {case['kanal']}")
        for gecis_no, g in enumerate(case["gecisler"]):
            T = len(g["cevrimler"])
            n_giris = len(g["cevrimler"][0][0])
            satirlar.append(f"{gecis_no} {T} {len(g['ciktilar'])} {n_giris} {N_CIKIS[mod]}")
            satirlar.append(sayilari_yaz(duzlestir(g["w"])))
            for (girisler, _, _) in g["cevrimler"]:
                satirlar.append(sayilari_yaz(girisler))
            for (t, degerler) in g["ciktilar"]:
                satirlar.append(sayilari_yaz([t] + degerler))
        if mod in ("WG_S1", "WG_S2"):
            satirlar.append(sayilari_yaz(duzlestir(case["beklenen_akum"])))
    with open(yol, "w") as f:                       # "w": yazmak için aç; with bitince kapanır
        f.write("\n".join(satirlar) + "\n")


def sutun(cevrim_satirlari, k):
    """Çevrim satırlarından k. şeridi (sütunu) liste olarak çeker."""
    return [satir[k] for satir in cevrim_satirlari]


def dosyadan_oku_ve_dogrula(yol, mod):
    """Yazılan dosyayı geri okur, PE modelini dosyadaki akışlarla YENİDEN çalıştırır ve
    dosyadaki beklenen çıkışlarla karşılaştırır. Biçim hatası ya da tutarsızlık varsa durur.
    Dönüş: (case sayısı, geçiş sayısı, karşılaştırılan çıkış değeri sayısı)"""
    with open(yol) as f:
        sayilar = [int(s) for s in f.read().split()]   # split(): boşluk/satır sonundan böler
    it = iter(sayilar)                     # iter(): listeyi sırayla tüketebileceğimiz akışa çevirir
    def al():
        return next(it)                    # next(): akıştaki bir sonraki sayıyı verir
    assert al() == MOD_KODLARI[mod]
    n_case = al()
    toplam_gecis = 0
    toplam_deger = 0
    for case_no in range(n_case):
        assert al() == case_no
        n_gecis = al()
        al()                               # kanal sayısı (yalnız bilgi amaçlı)
        akum = sifir_matris(3, 3)
        for gecis_no in range(n_gecis):
            assert al() == gecis_no
            T, n_cikti, n_giris, n_cikis = al(), al(), al(), al()
            w_duz = [al() for _ in range(9)]
            w = [w_duz[0:3], w_duz[3:6], w_duz[6:9]]
            girdi = [[al() for _ in range(n_giris)] for _ in range(T)]
            beklenen = [[al() for _ in range(1 + n_cikis)] for _ in range(n_cikti)]
            if mod in ("FP_S1", "BP_S1"):
                akislar = [sutun(girdi, 0), sutun(girdi, 1), sutun(girdi, 2)]
                _, ciktilar = pe_gecis_s1(akislar, w, sutun(girdi, 3))
            elif mod == "FP_S2":
                cift = [sutun(girdi, 0), sutun(girdi, 2), sutun(girdi, 4)]
                tek = [sutun(girdi, 1), sutun(girdi, 3), sutun(girdi, 5)]
                _, ciktilar = pe_gecis_s2(cift, tek, w, sutun(girdi, 6))
            elif mod == "BP_S2":
                akislar = [sutun(girdi, 0), sutun(girdi, 1), sutun(girdi, 2)]
                ps = [satir[3:7] for satir in girdi]
                _, ciktilar = pe_gecis_bp_s2(akislar, w, ps)
            elif mod == "WG_S1":
                a = [sutun(girdi, 0), sutun(girdi, 2), sutun(girdi, 4)]
                e = [sutun(girdi, 1), sutun(girdi, 3), sutun(girdi, 5)]
                _, ciktilar = pe_gecis_wg_s1(a, e, akum)
            else:  # WG_S2
                cift = [sutun(girdi, 0), sutun(girdi, 3), sutun(girdi, 6)]
                tek = [sutun(girdi, 1), sutun(girdi, 4), sutun(girdi, 7)]
                e = [sutun(girdi, 2), sutun(girdi, 5), sutun(girdi, 8)]
                _, ciktilar = pe_gecis_wg_s2(cift, tek, e, akum)
            yeniden = [[t] + degerler for (t, degerler) in ciktilar]
            assert yeniden == beklenen, f"{mod} case {case_no} geçiş {gecis_no}: uyuşmazlık"
            toplam_gecis += 1
            toplam_deger += n_cikti * n_cikis
        if mod in ("WG_S1", "WG_S2"):
            G_dosya = [al() for _ in range(9)]
            assert duzlestir(akum) == G_dosya, f"{mod} case {case_no}: akümülatör uyuşmazlığı"
            toplam_deger += 9
    assert next(it, None) is None, "Dosyanın sonunda fazladan sayı var"
    return n_case, toplam_gecis, toplam_deger


# ----------------------------------------------------------------------------
# Okunur döküm: her modun 0. case'i (el kontrolü), çevrim çevrim
# ----------------------------------------------------------------------------
GIRIS_ADLARI = {
    "FP_S1": ["x_r0", "x_r1", "x_r2", "psum"],
    "BP_S1": ["e_r0", "e_r1", "e_r2", "psum"],
    "FP_S2": ["cift_r0", "tek_r0", "cift_r1", "tek_r1", "cift_r2", "tek_r2", "psum"],
    "BP_S2": ["e_r0", "e_r1", "e_r2", "psA0", "psB0", "psA1", "psB1"],
    "WG_S1": ["a_r0", "e_r0", "a_r1", "e_r1", "a_r2", "e_r2"],
    "WG_S2": ["cift_r0", "tek_r0", "e_r0", "cift_r1", "tek_r1", "e_r1",
              "cift_r2", "tek_r2", "e_r2"],
}
CIKIS_ADLARI = {"FP_S1": ["out"], "FP_S2": ["out"], "BP_S1": ["out"],
                "BP_S2": ["out0", "out1", "out2", "out3"], "WG_S1": [], "WG_S2": []}


def matris_metni(M, girinti="    "):
    return "\n".join(girinti + " ".join(f"{x:7d}" for x in satir) for satir in M)


def okunur_dosya_yaz(yol, C):
    parcalar = []
    for mod in MOD_KODLARI:
        case = C[mod][0]
        parcalar.append("=" * 78)
        parcalar.append(f"{mod} — case 0: {case['aciklama']}")
        parcalar.append("=" * 78)
        g0 = case["gecisler"][0]
        if mod.startswith("BP"):
            parcalar.append("Orijinal çekirdek W[r][c]:")
            parcalar.append(matris_metni(g0["w_orijinal"]))
        if not mod.startswith("WG"):
            parcalar.append("MAC[r][c]'ye yüklenen ağırlıklar:")
            parcalar.append(matris_metni(g0["w"]))
        for gecis_no, g in enumerate(case["gecisler"]):
            parcalar.append(f"-- geçiş {gecis_no} --")
            basliklar = ["t"] + GIRIS_ADLARI[mod] + CIKIS_ADLARI[mod] + ["geçerli"]
            parcalar.append(" ".join(f"{b:>8}" for b in basliklar))
            for t, (girisler, cikislar, gecerli) in enumerate(g["cevrimler"]):
                hucreler = [t] + girisler + cikislar
                metin = " ".join(f"{x:>8}" for x in hucreler)
                parcalar.append(metin + f" {'evet' if gecerli else '-':>8}")
        if mod.startswith("WG"):
            parcalar.append("Beklenen akümülatörler G[r][c] (case sonunda):")
            parcalar.append(matris_metni(case["beklenen_akum"]))
        else:
            parcalar.append("Katman sonucu (referans):")
            parcalar.append(matris_metni(case["katman_sonucu"]))
        parcalar.append("")
    with open(yol, "w") as f:
        f.write("\n".join(parcalar) + "\n")


def case_listesi_yaz(yol, C):
    satirlar = []
    for mod in MOD_KODLARI:
        for case_no, case in enumerate(C[mod]):
            satirlar.append(f"{mod:6s} case {case_no}: {len(case['gecisler']):3d} geçiş, "
                            f"{case['kanal']} kanal/batch — {case['aciklama']}")
    with open(yol, "w") as f:
        f.write("\n".join(satirlar) + "\n")


# ----------------------------------------------------------------------------
# Stres testi: dosyaya yazılmayan çok sayıda rastgele durum
# ----------------------------------------------------------------------------
def stres_testi(adet):
    random.seed(7)
    for _ in range(adet):
        pad = random.choice([0, 1])
        kanal = random.randint(1, 3)
        rastgele_fp(1, pad, kanal, random.randint(3, 7), random.randint(3, 9))
        rastgele_fp(2, pad, kanal, random.randint(3, 8), random.randint(3, 10))
        rastgele_bp_s1(pad, kanal, random.randint(1, 5), random.randint(1, 6))
        H_in = random.randint(3, 9)
        W_in = random.randint(3, 9)
        if cikis_boyu(H_in, pad, 2) >= 1 and cikis_boyu(W_in, pad, 2) >= 1:
            rastgele_bp_s2(pad, kanal, H_in, W_in)
        rastgele_wg(1, pad, kanal, random.randint(3, 7), random.randint(3, 9))
        rastgele_wg(2, pad, kanal, random.randint(3, 8), random.randint(3, 10))


# ----------------------------------------------------------------------------
# Ana program
# ----------------------------------------------------------------------------
def main():
    random.seed(1)
    referans_ozdeslik_testi(300)
    print("1) Matematik referansı tutarlı (300 rastgele eşlenik testi).")

    C = ornek_caseler()
    print("2) Vektör case'leri üretildi; her birinde PE modeli = referans.")

    os.makedirs(KLASOR, exist_ok=True)
    for mod in MOD_KODLARI:
        yol = os.path.join(KLASOR, f"pe_{mod.lower()}.txt")   # lower(): küçük harfe çevirir
        dosyaya_yaz(yol, mod, C[mod])
        n_case, n_gecis, n_deger = dosyadan_oku_ve_dogrula(yol, mod)
        print(f"   {yol}: {n_case} case, {n_gecis} geçiş, {n_deger} beklenen değer "
              f"(geri okundu, yeniden hesaplandı, uyuştu)")
    okunur_dosya_yaz(os.path.join(KLASOR, "OKUNUR_case0.txt"), C)
    case_listesi_yaz(os.path.join(KLASOR, "CASE_LISTESI.txt"), C)

    stres_testi(200)
    print("3) Stres testi: her moddan 200 rastgele durum daha, hepsinde PE modeli = referans.")


if __name__ == "__main__":     # dosya doğrudan çalıştırılırsa main() çağrılır
    main()
