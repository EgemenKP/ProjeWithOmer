# =============================================================================
#  egit.py — CIFAR-10 eğitimi: Shao Fig. 9'un karşılığı (Adım 6)
# -----------------------------------------------------------------------------
#  Modlar:
#    int   : hizli_model (golden'la bit bit aynı aritmetik; RTL golden'la bit bit aynı)
#    float : aynı ağın float32 karşılığı (NITI'nin fp32 referansı gibi: SGD, momentum 0.9)
#  Ağlar (ag_tanimi): vgg16like (Shao IV: max-pool + ardından gelen s1 conv yerine s2 conv), vgg16
#    (aynı ağ, max-pool'lu; Fig. 9'daki "VGG16" eğrisinin karşılığı), vggsmall7 (NITI Table 5).
#  NITI'den alınanlar (Shao sessiz; NITI hakem, [NITI GitHub]): veri çoğaltma (pad 4 rastgele kırpma +
#    yatay çevirme + normalizasyon, data.py), ağırlık başlatma (xavier uniform -> weight_quant, ti_torch.py),
#    giriş TiFloatToInt8, batch 256, 200 epoch, m_u 5 -> 4 -> 3 (100. ve 150. epoch; ti_vgg.py regime),
#    fp32 referansında lr 0.01 -> 0.001 -> 0.0001 (NITI makalesi §4.3).
#  Hazırlayan: Claude, 04.11.2026 (final/, Adım 6)
#  Kullanım: python egit.py --ag vgg16like --mod int --epoch 200 --cikti sonuc/vgg16like_int
# =============================================================================
import argparse
import csv
import math
import os
import time

import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision
import torchvision.transforms as TR

import hizli_model as H

VERI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "veri")
ORT = [0.49139968, 0.48215827, 0.44653124]
STD = [0.24703233, 0.24348505, 0.26158768]


def ag_tanimi(ad):
    """Katman listesi: ('conv', cout, s) | ('M',) | ('fc', cout). ReLU her conv'dan sonra, fc'den sonra yok."""
    if ad == "vggsmall7":
        cfg = [128, 128, "M", 256, 256, "M", 512, 512, "M"]
        return [("conv", c, 1) if c != "M" else ("M",) for c in cfg] + [("fc", 10)]
    vgg16 = [64, 64, "M", 128, 128, "M", 256, 256, 256, "M", 512, 512, 512, "M", 512, 512, 512, "M"]
    if ad == "vgg16":
        return [("conv", c, 1) if c != "M" else ("M",) for c in vgg16] + [("fc", 10)]
    if ad == "vgg16like":
        # Shao IV: "replace the max-pooling layer and its subsequent convolutional layer (stride=1)
        # with a convolutional layer (stride=2)". Son max-pool'un ardından conv yok: o max-pool kalır
        # (Fig. 8'in fonksiyon motorunda Pooling birimi var). [Çıkarım]
        L, i = [], 0
        while i < len(vgg16):
            c = vgg16[i]
            if c == "M" and i + 1 < len(vgg16):
                L.append(("conv", vgg16[i + 1], 2))
                i += 2
                continue
            L.append(("M",) if c == "M" else ("conv", c, 1))
            i += 1
        return L + [("fc", 10)]
    raise ValueError(ad)


# ----------------------------------------------------------------------------
# int: ağırlık başlatma ve giriş (NITI)
# ----------------------------------------------------------------------------
def weight_quant(Wf):
    r = Wf.abs().max()
    bw = math.ceil(math.log2(r.item()))
    return torch.round(Wf / r * 127).long(), bw - 7


def float_to_int8(x):
    r = x.abs().max().item()
    bw = math.ceil(math.log2(r))
    return torch.round(x * 2.0 ** (7 - bw)).clamp(-128, 127).long(), bw - 7


def int_ag_kur(ad, tohum):
    torch.manual_seed(tohum)
    katmanlar, cin, hw = [], 3, 32
    for t in ag_tanimi(ad):
        if t[0] == "M":
            katmanlar.append(H.Katman("maxpool", relu=False))
            hw //= 2
            continue
        if t[0] == "conv":
            Wf = torch.empty(t[1], cin, 3, 3)
            nn.init.xavier_uniform_(Wf)
            k = H.Katman("conv", cin, t[1], t[2], 1, True)
            cin = t[1]
            hw = (hw + 2 - 3) // t[2] + 1
        else:
            Wf = torch.empty(t[1], cin * hw * hw)
            nn.init.xavier_uniform_(Wf)
            k = H.Katman("fc", cin * hw * hw, t[1], relu=False)
        W8, sw = weight_quant(Wf)
        k.W, k.sw = W8.to(H.DEV), sw
        katmanlar.append(k)
    return katmanlar


# ----------------------------------------------------------------------------
# float referans
# ----------------------------------------------------------------------------
class FloatAg(nn.Module):
    def __init__(self, ad):
        super().__init__()
        L, cin, hw = [], 3, 32
        for t in ag_tanimi(ad):
            if t[0] == "M":
                L.append(nn.MaxPool2d(2, 2)); hw //= 2
            elif t[0] == "conv":
                L += [nn.Conv2d(cin, t[1], 3, t[2], 1, bias=False), nn.ReLU()]
                cin = t[1]; hw = (hw + 2 - 3) // t[2] + 1
            else:
                L += [nn.Flatten(), nn.Linear(cin * hw * hw, t[1], bias=False)]
        self.ag = nn.Sequential(*L)
        for m in self.modules():
            if isinstance(m, (nn.Conv2d, nn.Linear)):
                nn.init.xavier_uniform_(m.weight)

    def forward(self, x):
        return self.ag(x)


def veri(batch, isci=4):
    egit_tr = TR.Compose([TR.RandomCrop(32, padding=4), TR.RandomHorizontalFlip(), TR.ToTensor(), TR.Normalize(ORT, STD)])
    test_tr = TR.Compose([TR.ToTensor(), TR.Normalize(ORT, STD)])
    e = torchvision.datasets.CIFAR10(VERI, train=True, download=False, transform=egit_tr)
    t = torchvision.datasets.CIFAR10(VERI, train=False, download=False, transform=test_tr)
    return (torch.utils.data.DataLoader(e, batch, shuffle=True, num_workers=isci, pin_memory=True, drop_last=False,
                                        persistent_workers=isci > 0),
            torch.utils.data.DataLoader(t, 500, shuffle=False, num_workers=isci, pin_memory=True,
                                        persistent_workers=isci > 0))


def m_u_takvimi(epoch, toplam):
    """NITI: 5 bit, 100. epoch'ta 4, 150. epoch'ta 3 (200 epoch). Kısa koşularda aynı oranlar."""
    if epoch >= round(toplam * 0.75):
        return 3
    if epoch >= round(toplam * 0.5):
        return 4
    return 5


def int_test(katmanlar, yukleyici):
    dogru = n = 0
    with torch.no_grad():
        for x, y in yukleyici:
            A0, s0 = float_to_int8(x.to(H.DEV))
            A, _, _, _ = H.ileri(katmanlar, A0, s0)
            dogru += (A[-1].reshape(len(y), -1).argmax(1).cpu() == y).sum().item()
            n += len(y)
    return 100.0 * dogru / n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ag", default="vgg16like")
    ap.add_argument("--mod", default="int", choices=["int", "float"])
    ap.add_argument("--epoch", type=int, default=200)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--tohum", type=int, default=1)
    ap.add_argument("--grup", type=int, default=16, help="SRU grup boyu (D76); 0 = tensör başına (NITI tarzı)")
    ap.add_argument("--doyma", action="store_true", help="SRU ±127 doyması (D38; ablasyon)")
    ap.add_argument("--ae", default="alg1", choices=["alg1", "round"], help="a/e yuvarlaması (D33; round = NITI)")
    ap.add_argument("--cikti", default="sonuc/deneme")
    ap.add_argument("--olcum", type=int, default=0, help=">0: yalnızca bu kadar adımın süresini ölç")
    a = ap.parse_args()
    H.GRUP, H.DOYMA, H.YUVARLAMA_AE = a.grup, a.doyma, a.ae
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cuda.matmul.allow_tf32 = False
    os.makedirs(a.cikti, exist_ok=True)

    if a.olcum:
        x = torch.randn(a.batch, 3, 32, 32, device=H.DEV)
        y = torch.randint(0, 10, (a.batch,), device=H.DEV)
        if a.mod == "int":
            K = int_ag_kur(a.ag, a.tohum)
            for i in range(a.olcum + 1):
                if i == 1:
                    torch.cuda.synchronize(); t0 = time.time()
                A0, s0 = float_to_int8(x)
                H.egitim_adimi(K, A0, s0, y, 5)
        else:
            m = FloatAg(a.ag).to(H.DEV); opt = torch.optim.SGD(m.parameters(), 0.01, momentum=0.9)
            for i in range(a.olcum + 1):
                if i == 1:
                    torch.cuda.synchronize(); t0 = time.time()
                opt.zero_grad(); F.cross_entropy(m(x), y).backward(); opt.step()
        torch.cuda.synchronize()
        s = (time.time() - t0) / a.olcum
        print(f"OLCUM {a.ag} {a.mod}: adım {s:.3f} s, epoch (196 adım) ~{s * 196 / 60:.1f} dk, "
              f"{a.epoch} epoch ~{s * 196 * a.epoch / 3600:.1f} saat")
        return

    egit_y, test_y = veri(a.batch)
    kayit = open(os.path.join(a.cikti, "egri.csv"), "w", newline="")
    yaz = csv.writer(kayit)
    yaz.writerow(["epoch", "egitim_dogruluk", "test_dogruluk", "test_hata", "sure_s", "m_u"])
    if a.mod == "int":
        K = int_ag_kur(a.ag, a.tohum)
    else:
        torch.manual_seed(a.tohum)
        m = FloatAg(a.ag).to(H.DEV)
        opt = torch.optim.SGD(m.parameters(), 0.01, momentum=0.9)
        sched = torch.optim.lr_scheduler.MultiStepLR(opt, [round(a.epoch * 0.5), round(a.epoch * 0.75)], 0.1)
    for ep in range(a.epoch):
        t0 = time.time()
        dogru = n = 0
        mu = m_u_takvimi(ep, a.epoch)
        for x, y in egit_y:
            x, y = x.to(H.DEV, non_blocking=True), y.to(H.DEV, non_blocking=True)
            if a.mod == "int":
                A0, s0 = float_to_int8(x)
                r = H.egitim_adimi(K, A0, s0, y, mu)
                tahmin = r["A"][-1].reshape(len(y), -1).argmax(1)
            else:
                m.train(); opt.zero_grad()
                out = m(x); F.cross_entropy(out, y).backward(); opt.step()
                tahmin = out.argmax(1)
            dogru += (tahmin == y).sum().item(); n += len(y)
        if a.mod == "int":
            td = int_test(K, test_y)
        else:
            sched.step(); m.eval(); td_d = td_n = 0
            with torch.no_grad():
                for x, y in test_y:
                    td_d += (m(x.to(H.DEV)).argmax(1).cpu() == y).sum().item(); td_n += len(y)
            td = 100.0 * td_d / td_n
        sure = time.time() - t0
        yaz.writerow([ep + 1, f"{100.0 * dogru / n:.2f}", f"{td:.2f}", f"{100 - td:.2f}", f"{sure:.0f}", mu])
        kayit.flush()
        print(f"epoch {ep + 1}/{a.epoch}: eğitim {100.0 * dogru / n:.2f}%, test {td:.2f}%, {sure:.0f} s, m_u {mu}", flush=True)
    kayit.close()


if __name__ == "__main__":
    main()
