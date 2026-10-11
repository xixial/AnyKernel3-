import zipfile, struct, hashlib, zlib, shutil, os, sys

sys.stdout.reconfigure(encoding="utf-8")

# ============================================================
# K70 boot 组装（2512 铁律版 · 2026-10-12 定稿）
# 段内布局 = [2512 字节零][内核 Image 从 +2512 开始][余量补零]
# 底料 = D 盘官方原件（永远不回写 D；产物唯一落 G:\ak3\boot\boot.img）
# ============================================================

ZIP      = r"G:\ak3\2\SukiSU_kernel-android13-5.15-178-AnyKernel3_22.zip"
OFFICIAL = r"D:\Tools\K70\1\vermeer_images_OS3.0.9.0.WNKCNXM_16.0\images\boot.img"
CUR      = r"G:\ak3\boot\boot.img"
OUT      = r"G:\ak3\boot\boot.img"
SHIFT    = 2512

img = zipfile.ZipFile(ZIP).read("Image")
print(f"[1] 新内核: {len(img)} B  md5={hashlib.md5(img).hexdigest()}")

boot = bytearray(open(OFFICIAL, "rb").read())
hdr = hashlib.md5(boot[:1584]).hexdigest()
ks  = struct.unpack("<I", boot[8:12])[0]
hs  = struct.unpack("<I", boot[20:24])[0]
print(f"[2] 官方底料: {len(boot)} B | header_size={hs} kernel_size={ks} | 头md5={hdr[:12]}")

assert len(img) + SHIFT <= ks, "Image 超容量"

# 旧 boot 存档（按 md5 前缀命名，与历史备份同规则）
old = open(CUR, "rb").read()
old_md5 = hashlib.md5(old).hexdigest().upper()
bak = CUR + ".bak-" + old_md5[:8]
if not os.path.exists(bak):
    shutil.copy2(CUR, bak)
print(f"[3] 旧件存档: {bak}  (md5={old_md5[:8]}…)")

# 段内重组装
new_seg = b"\x00" * SHIFT + img + b"\x00" * (ks - SHIFT - len(img))
boot[hs:hs+ks] = new_seg
data = bytes(boot)
open(OUT, "wb").write(data)
print(f"[4] 输出: {OUT}")

# ============ 验证电池 ============
seg = data[hs:hs+ks]
ok1 = seg[SHIFT:SHIFT+2] == b"MZ"
ok2 = hashlib.md5(seg[SHIFT:SHIFT+len(img)]).hexdigest() == hashlib.md5(img).hexdigest()
ok3 = data[:hs] == open(OFFICIAL, "rb").read()[:hs]
ok4 = data[hs+ks:] == open(OFFICIAL, "rb").read()[hs+ks:]
ok5 = all(x == 0 for x in seg[:SHIFT])
ok6 = all(x == 0 for x in seg[SHIFT+len(img):])
print(f"[5] MZ@+2512: {ok1} | 段内Image一致: {ok2} | 头逐字节同官方: {ok3} | 段后逐字节同官方: {ok4} | 前2512全零: {ok5} | 尾部补零: {ok6}")
assert all([ok1, ok2, ok3, ok4, ok5, ok6]), "验证失败!!"

md5 = hashlib.md5(data).hexdigest()
crc = zlib.crc32(data) & 0xFFFFFFFF
print(f"[6] 定稿: {len(data)} B | md5={md5} | crc32=0x{crc:08x}")
