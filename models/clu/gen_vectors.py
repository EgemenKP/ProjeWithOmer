"""
CLU icin test vektoru uretici.
golden_model.py'deki clu_golden() fonksiyonunu kullanarak, Verilog
testbench'in okuyacagi duz metin dosyasi uretir.

Format (her satir bir test durumu, bosluklarla ayrilmis ondalik sayilar):
  a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 sa y_idx e0 e1 e2 e3 e4 e5 e6 e7 e8 e9

y_idx: dogru sinifin indeksi (0-9) -- testbench bunu one-hot'a kendi cevirecek
e0..e9: golden_model'in urettigi BEKLENEN cikis (RTL ile karsilastirilacak)
"""
import sys, random
sys.path.insert(0, "/home/claude/clu")
from golden_model import clu_golden

N = 10
vectors = []  # (a, sa, y_idx)

def add(a, sa, y_idx, note=""):
    vectors.append((list(a), sa, y_idx, note))

# --- Daha once elle inceledigimiz / anlamli durumlar ---
add([20,5,3,0,-10,2,1,4,0,-5], 0, 0, "Test1: baskin dogru sinif")
add([20,5,3,0,-10,2,1,4,0,-5], 0, 1, "Test2: yanlis tahmin, dogru sinif dusuk")
add([1,-1,2,0,-2,1,0,-1,1,0], -8, 2, "Test3: TEU dali")
add([5]*N, 0, 0, "UcDurum1: tam belirsizlik")
add([3,1,0,-1,2,0,1,-2,0,1], -7, 1, "UcDurum2a: sa=-7 siniri (TEU'ya dusuyor)")
add([3,1,0,-1,2,0,1,-2,0,1], -6, 1, "UcDurum2b: sa=-6 (EPU)")
add([127]*N, 7, 0, "UcDurum3: int8 ust sinirda, dogru sinif")
add([-127]*N, 0, 3, "UcDurum4: int8 alt sinirda (simetrik -127)")
add([100,-100,0,0,0,0,0,0,0,0], 0, 0, "UcDurum6: genis aralik, dogru sinif baskin")
add([100,-100,0,0,0,0,0,0,0,0], 0, 1, "UcDurum6b: genis aralik, dogru sinif zayif")

# --- Rastgele kapsama (sabit seed, tekrar uretilebilir) ---
random.seed(42)
for i in range(30):
    a = [random.randint(-127, 127) for _ in range(N)]
    # NOT: sa araligi [-10,10] ile sinirlandi. Daha genisi (ornegin -15)
    # TEU'nun 2^(1-2sa) teriminde 32-bit tasmaya yol aciyor (davranissal
    # modelin 'integer' tipinde) -- bu, TEU'nun gercek donanimda kac bit
    # olmasi gerektiginin makalede belirtilmedigini gosteren ayri bir
    # acik nokta. Simdilik gerceve yakin bir aralikla sinirliyoruz.
    sa = random.randint(-10, 10)
    y_idx = random.randint(0, N-1)
    add(a, sa, y_idx, f"Rastgele #{i+1}")

# --- Golden model ile beklenen ciktilari hesapla, dosyaya yaz ---
out_path = "/home/claude/clu/vectors.txt"
skipped = 0
with open(out_path, "w") as f:
    for a, sa, y_idx, note in vectors:
        y = [1 if i == y_idx else 0 for i in range(N)]
        try:
            e = clu_golden(a, sa, y, N=N)
        except AssertionError as ex:
            skipped += 1
            print(f"ATLANDI ({note}): {ex}  a={a} sa={sa}")
            continue
        line = " ".join(map(str, a)) + f" {sa} {y_idx} " + " ".join(map(str, e))
        f.write(line + "\n")

n_written = len(vectors) - skipped
print(f"\n{n_written} test vektoru yazildi -> {out_path}")
print(f"({skipped} tanesi gecersiz kombinasyon oldugu icin atlandi)")
