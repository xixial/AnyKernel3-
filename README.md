# AnyKernel3- · Redmi K70 内核构建线（私有）

> 本仓库 fork 自 [LingLuo17/AnyKernel3](https://github.com/LingLuo17/AnyKernel3)（已与上游脱钩、独立维护）。
> 承载 Redmi K70（vermeer / 23113RKC6C）的定制内核构建线：
> **SukiSU + SUSFS + 自研 SELinux 防护补丁（哨兵 / v3 / v4 / v5）**。
> 构建走 GitHub Actions（手动触发）；**设备刷入与一切决策由机主本人执行**。

---

## 一、构建方法（手动触发）

**入口**：Actions → 「Android 内核构建-自定义」（`kernel-custom.yml`）
直达：`https://github.com/xixial/AnyKernel3-/actions/workflows/kernel-custom.yml` → 右上 **Run workflow**

**表单标准值（K70）：**

| 字段 | 值 |
|---|---|
| 内核版本 | **5.15** |
| 5.15 子版本 | **`178 (2025-03)`**（勿选 auto） |
| KernelSU 变体 | **SukiSU** |
| 自定义版本名 / 构建时间 | 留空 |
| use_kpm | disabled (关闭) |
| droidspaces / droidspaces_ntsync | off / false |
| artifact_upload_mode | 建议「上传全部」（排错时可直接拿到日志） |
| use_zram / use_bbg / use_net_enhance / use_rekernel | 按需（默认即可，与防护线无关） |
| **cancel_susfs** | **必须保持 false**（红线：勾选=整条 SUSFS 防线摘除） |
| supp_op / skip_incompatible | 默认 |

**成功标志**（run 页 Summary，v2 现役三行 + 无 v3 行）：
```
✅ SELinux 哨兵-LITE（deny=5, backup_state=1）
✅ sidtab 快照作答（v5）
✅ mountinfo /adb 过滤（v4）
（不应出现 v3 行——v3 已随 v2 退役）
日志应现：切换 SUSFS 到自定义提交: 138a6641…（钉版生效证据）
```

**产物**：`SukiSU_kernel-android13-5.15-178-AnyKernel3`（zip，约 23MB）＝ 内含 `Image` 的刷机包。

---

## 二、内核侧补丁体系

| 执行段 | 补丁 | 作用 |
|---|---|---|
| `kernel_fixes`（SUSFS **前**） | `selinuxfs_sentinel_lite.patch` | **哨兵-LITE**：4 冷门写通道（create/relabel/user/member）词过滤 + 备份状态访问器（context/access 由新版 SUSFS 假账本原生接管） |
| `kernel_fixes` | `sidtab_backup_answer.patch`（v5） | app 读 `sidtab_hash_stats` 走 KSU 前快照（**Luna 最后泄漏通道·实锤封堵**） |
| `susfs_fixes`（SUSFS **后**） | `mountinfo_adb_filter.patch`（v4） | app 读者看不到 root 含 adb/modules 的 mountinfo 条目 |
| （已退役） | ~~`setprocattr_avc_align.patch`（v3）~~ | 2026-10-12 v2 起退役：新版 SUSFS 以「内联假校验」原生消解该计数问题（旧件保留在仓库供回退） |

- 各段脚本特性：**幂等标记 / 应用后断言 / 失败自动回滚（构建不中断）/ 写 GITHUB_STEP_SUMMARY**。
- **SUSFS 版本钉定**：`config/config` → `custom=true` + `gki-android13-5.15=687d2d18d94cb2e3e72d1074778d58384d58e379`
  （上游分支 HEAD 曾于 2026-10-12 推入与哨兵撞车的提交 → `-Werror` 构建失败；钉版为事故前最后干净提交）。
- **fusion v2**（新版 SUSFS 适配：哨兵-LITE + v3 退役 + v5 保留）＝ 已备料，独立仓库 **susfs-fusion** 管理，切换时改本仓 `config` 值 + 两段脚本。

---

## 三、boot.img 组装方法（完整 · 2512 铁律版）★

### 0. 原料
| 项 | 说明 |
|---|---|
| **底料（模板）** | 官方完整刷机包内 `boot.img`：`D:\Tools\K70\1\vermeer_images_OS3.0.9.0.WNKCNXM_16.0\images\boot.img`（**永不回写**；md5 `6626b33239149a3abcbd8f887108472a`；内核版本 `5.15.178-android13-8-00021-g6f2f96be86b9-ab13729987`，未修改原件） |
| **新内核** | 构建产物 zip 内的 `Image`（AnyKernel3 zip 根目录） |
| 环境 | Windows + Python3 标准库（无第三方依赖） |

### 1. 铁律布局（★★★ 违反必卡米）
内核段（boot.img 内 `[header_size, header_size+kernel_size)` 区间）必须为：
```
[ 2512 字节 0x00 ][ 新 Image（MZ 从 +2512 开始）][ 余量补 0 ]
                          └─ 设备引导链要求内核 MZ 魔数位于「段内偏移 2512」
```
> **历史事故**：任何把 Image 放在段内 `+0` 的组装（早期 build-boot2.py）→ **卡米（bootloop）**。
> 同款坑历史上出现过两次（史称「移位 2512」），本布局为唯一正确解。

### 2. 组装步骤
1. 从产物 zip 取 `Image`，记录长度 + md5；
2. 读官方 boot.img 为字节数组，解析头部两个字段（小端 u32）：
   - `kernel_size` == 偏移 **8** 处 4 字节
   - `header_size` == 偏移 **20** 处 4 字节
3. **容量检查**：`len(Image) + 2512 <= kernel_size`（不满足=内核体积超标，先停下排查）；
4. **旧件存档**：把当前 `boot.img` 复制为 `boot.img.bak-<旧md5前8位>`（已存在则跳过）；
5. **段内重组装**：`new_seg = 零×2512 + Image + 零×(kernel_size − 2512 − len(Image))`；
6. **写回段区**：`boot[header_size : header_size+kernel_size] = new_seg`（**头部区与段后区一字不动**）；
7. 写出**唯一产物** `G:\ak3\boot\boot.img`（一个文件一个名字）。

### 3. 验证电池（6 项，全过才可交付）
| # | 检查项 |
|---|---|
| 1 | 段内偏移 2512 处两字节 == `MZ` |
| 2 | 段内 `[2512, 2512+len(Image))` 的 md5 == 新 Image 的 md5 |
| 3 | 头部 `[0, header_size)` 与官方**逐字节一致** |
| 4 | 段后 `[header_size+kernel_size, 末)` 与官方**逐字节一致** |
| 5 | 段内前 2512 字节**全零** |
| 6 | 段内尾部补零区**全零** |

最后记录产物 `md5 + crc32`，登记至 `G:\ak3\boot\boot.img.md5.txt`（含坏件注记，如 `3d3c32c9 = MZ@0 坏件勿用`）。

### 4. 完整脚本（定稿版，可直接运行）
```python
import zipfile, struct, hashlib, zlib, shutil, os, sys

sys.stdout.reconfigure(encoding="utf-8")

# ============================================================
# K70 boot 组装（2512 铁律版 · 定稿）
# 段内布局 = [2512 字节零][内核 Image 从 +2512 开始][余量补零]
# 底料 = D 盘官方原件（永远不回写 D；产物唯一落 G:\ak3\boot\boot.img）
# ============================================================

ZIP      = r"G:\ak3\2\SukiSU_kernel-android13-5.15-178-AnyKernel3_22.zip"   # ← 换成新产物
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
```

**头部字段速查**（Android boot image）：`kernel_size` = LE u32 @8；`header_size` = LE u32 @20（本机官方件实测 `header_size=1584`）。

### 5. 刷入与回退
- **刷入**（机主执行）：`fastboot flash boot <组装的 boot.img>`；**切勿**使用任何 `flash_all_lock` 类回锁命令；
- **回退**：直接刷任一 `boot.img.bak-*` 备份或官方原件（实测有效）；兜底 = KernelSU 安全模式（开机按住音量下 = 禁用全部模块）；
- 组装 ≠ 刷入：本仓库流程只负责产出**经 6 项验证**的 boot.img，刷与不刷、哪一版，全部由机主拍板。

---

## 四、组装件并入线刷包（MiFlash 整包刷入用）★

> 场景：让**重新组装的 boot.img** 跟完整线刷包（如 `G:\大肥鱼\K70_debloat_root_OS3.0.9.0\`）一起，用 MiFlash 整包刷入。
> **核心原理：包内 `images\crclist.txt` 是设备 bootloader 的完整性校验表（由刷机脚本 `fastboot flash crclist` 刷入设备）——
> 换了 boot.img 就必须同步重算其 CRC32，否则设备拒绝引导。**

### 包内关键件速览
| 件 | 作用 |
|---|---|
| `images\boot.img` | 目标：我们要替换的内核分区映像（当前替换件尺寸必须保持 **100,663,296 B**） |
| `images\crclist.txt` | 校验表：`<分区名> 0x<crc32>` 逐行（含 `boot_ab 0x……` 行） |
| `images\sparsecrclist.txt` | 稀疏块校验表（super/userdata 等） |
| `flash_gen_crc_list_py3.py` | **校验表生成器**（读取 images 全部映像 → 重写上述两表） |
| `校验清单_md5.txt` | 人读用整体清单（md5） |
| `flash_all.bat` / `刷机-带日志.bat` | 刷机脚本（循环含 `flash crclist` / `flash boot_ab` 等） |

> ★ 上述各步骤所用脚本已收入本仓库 **`tools/`** 目录——逐个工具的详细说明见 **`tools/README.md`**。

### 并入七步
1. **组装**新 boot.img（第三章 · 2512 铁律 + 六项验证电池全过）；
2. **原件备份**（回退用）：把 `images\boot.img`、`images\crclist.txt`、`images\sparsecrclist.txt`、`校验清单_md5.txt` 四件复制到他处存档；
3. **替换**：`images\boot.img` ← 新组装件（尺寸同为 100,663,296 B——inplace 组装天然保持）；
4. **重算校验表**：在包根目录执行
   ```
   python flash_gen_crc_list_py3.py
   ```
   （自动读 images 全部映像 → 重写 `crclist.txt` + `sparsecrclist.txt`）；
5. **核对**：`crclist.txt` 中 `boot_ab 0x????????` 新值 == 新 boot.img 的 CRC32（小写 8 位；示例：旧件 b7358e33 对应 `boot_ab 0x86b453ed`）；同步更新 `校验清单_md5.txt` 中 boot.img 行；
6. **刷入（机主操作）**：MiFlash 或包内 `刷机-带日志.bat`；**绝不使用任何带 `lock` 的刷机模式/脚本**（`flash_all_lock.*` 会回锁 BL）；
7. **回退**：把第 2 步备份的四件放回原位（或用官方原包重刷）。

### 红线与原理备注
- **crclist 必须同步**：`boot_ab` 的 CRC 与实际 boot 分区不符 → 设备拒绝引导（最易漏的一步）；
- `vbmeta.img` / `vbmeta_system.img` 保持官方原版不动 → verity 判定与 `ro.boot.veritymode` 不受影响；
- A/B 双槽：`boot_ab` 目标一次覆盖两槽，仅需替换一次；
- 内容变、尺寸不变 → 包内其余引用（分区表、脚本行）零改动。

---

## 五、血泪教训（构建与组装）

1. **2512 铁律**：MZ@+0 = 卡米。任何新组装脚本必须先跑「验证电池」全绿再交付；
2. **唯一产物**：一个文件一个名字（曾因同一字节双命名（boot_v3.img / boot.img）引发混乱）；
3. **上游不稳**：SUSFS 拉分支 HEAD 曾引入与自家哨兵 patches 撞车的提交 → 已用 **config 钉版 + 独立仓库整份收编**双保险；
4. **补丁链 e2e**：`git apply` 为原子（一 hunk 失败=整补丁拒绝）；`patch` 后端才有部分应用——断言设计需区分；
5. **构建红线**：`cancel_susfs` 永远保持 false；构建失败先看 run 页 Summary 与日志 artifact。

---

*本仓库为私有基础设施：K70 内核构建线 + SELinux 防护补丁 + boot.img 组装方法的唯一权威记录。*

---

## 六、v2 收官报告（2026-10-12 · 全项满分验收）

### 6.1 这版做了什么（功能清单）
| 件 | 功能 | 状态 |
|---|---|---|
| **新版 SUSFS**（上游 138a6641） | 假账本四门（context/access/状态页/属性写入的 app 侧作答）+ AVC 审计日志伪装 | ✅ 现役 |
| **哨兵-LITE** | 4 冷门写通道词过滤 + KSU 前快照访问器（其余交给新版 SUSFS） | ✅ 现役 |
| **v5（sidtab 快照作答）** | 让 app 读 `sidtab_hash_stats` 得到「KSU 之前」的数字（Luna 最后的泄漏通道） | ✅ 现役·**首秀满贯** |
| **v4（mountinfo 过滤）** | app 读者看不到含 adb/modules 的挂载条目 | ✅ 现役 |
| **v3（计数对齐）** | 历史使命完成 | ⌛ 已退役（新版原生消解） |
| **@Seele 签标** | 内核版本串/管理器显示/构建脚本品牌常量（源头 base64 常量已改签） | ✅ 现役（往后构建自动继承） |

### 6.2 效果（实机验收 · 2026-10-12 上午）
| 检测器 | 改前 | **v2 实况（刷入 165ef002 后）** |
|---|---|---|
| **Luna** | 5/8「高危风险·发现KernelSU」 | **8/8「可信环境」全项满分**（09:23 实况截图为准） |
| **春秋 NativeCheck** | 6 项异常 | **1 项**（attestation(31)＝文档明示误报族） |
| **Duck Detector** | 1 危险 + 4 警告 | **0 危险 + 1 警告**（Shared storage baseline＝零权限探针设计噪声） |

### 6.3 战斗工序（值得留档的工程史）
1. **抓包解剖 Luna**（内核 uprobe 实录）：它经 `app_zygote` 域扫描 selinuxfs——三通道：context/access（SUSFS 假账本挡）+ setprocattr 计数（v3 挡）+ **sidtab_hash_stats（无人管）**；
2. **造 v5**：app 读统计时改从「KSU 前快照」作答；
3. **上游撞车事故**（2026-10-12 凌晨）：新版 SUSFS 把假账本逻辑内联进函数，与旧哨兵注入位置重叠 → 构建失败 → **钉版 687d2d18** 保绿 → 哨兵瘦身为 **LITE** 完成适配（本地 e2e 四场景全过含「撞车复现对照」）；
4. **v2 构建**（#20）→ 六项验证电池组装（`tools/assemble_boot_2512.py`）→ 刷入 → 全表复测；
5. **@LingLuo → @Seele**：二进制洗标（同长原位替换）+ 源头改签（`scripts/ksu_post_setup.sh` 品牌常量）→ 全仓残留=0。

### 6.4 产物与回退
- **现役 boot**：`165ef002c3ad26336b0f6fb3f6b957e0`（crc32 0x89bd3a22，100,663,296 B，@Seele 版）；
- 台账：`G:\ak3\boot\boot.img.md5.txt`（全版本链 + 收官记）；
- 回退：任一历史 bak（含 Luna 通行版 DD2B88A9）可直接刷回；仓库侧改动=单提交可 revert。
