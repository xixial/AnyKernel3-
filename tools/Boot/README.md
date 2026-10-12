# tools/ —— 工具集说明书（逐个详细）

> 本目录存放「内核构建线 + 线刷包维护」用到的全部独立脚本。
> **这些脚本均不被 GitHub Actions 构建流程引用**（构建只执行 `.github/workflows` 与 `scripts/` 下被显式引用的文件），
> 放进仓库 = **纯存档 + 取用，零影响**。

---

## 1. `assemble_boot_2512.py` —— boot.img 组装器（2512 铁律版）★

**干什么**
把构建产物里的内核 `Image`，按设备引导链要求的布局组装进官方 `boot.img` 模板：
```
内核段内布局 = [ 2512 字节零 ][ 新 Image（MZ 从 +2512 开始）][ 余量补零 ]
```

**输入**
| 项 | 来源 |
|---|---|
| 新内核 `Image` | 构建产物 zip（AnyKernel3 zip 根目录） |
| 官方 `boot.img` 模板 | 官方完整线刷包 `images/boot.img`（脚本顶部 `OFFICIAL` 变量指定） |

**输出**
- `boot.img`（唯一产物，脚本顶部 `OUT` 指定；示例 `G:\ak3\boot\boot.img`）；
- 旧产物自动存档为 `boot.img.bak-<旧md5前8位>`（不存在才存）。

**内置验证电池（6 项，任一不过直接报错退出）**
1. 段内偏移 2512 处 == `MZ`；2. 段内 Image md5 一致；3. 头部与官方逐字节一致；
4. 段后与官方逐字节一致；5. 前 2512 字节全零；6. 尾部补零区全零。

**用法**
```bash
# 1) 改脚本顶部三个路径：ZIP / OFFICIAL / OUT
# 2) 运行
python assemble_boot_2512.py
# 3) 输出定稿 md5 + crc32，登记到 boot.img.md5.txt
```
**依据**：主 README 第三章「boot.img 组装方法（完整 · 2512 铁律版）」。

---

## 2. `flash_gen_crc_list_py3.py` —— 线刷包校验表生成器 ★★（MiFlash 并入必备）

**干什么**
扫描线刷包 `images/` 全部映像，**重写**两张设备校验表：
| 输出 | 内容 |
|---|---|
| `images/crclist.txt` | `CRC-LIST` + 每个**直刷映像**的 CRC32（含 `boot_ab`、`xbl_ab`、`vendor_boot_ab` …） |
| `images/sparsecrclist.txt` | `SPARSECRC-LIST` + **稀疏映像**（super/userdata/metadata 等）分块 CRC 表 |

**为什么必须有它**
刷机脚本会把 `crclist.txt` 用 `fastboot flash crclist` 写进设备——**bootloader 按它校验各分区**。
换过 `boot.img` 却不重算 → `boot_ab` 的 CRC 对不上 → **设备拒绝引导**。

**输入 / 输出**
- 输入：脚本**同级目录**下的 `images/`（即：把本脚本放进线刷包根目录）；
- 输出：原地重写 `images/crclist.txt` + `images/sparsecrclist.txt`，并逐个打印分区 CRC。

**用法**
```bash
# 放进线刷包根目录后：
python flash_gen_crc_list_py3.py
# 随后核对：crclist.txt 中 boot_ab 的值 == 新 boot.img 的 crc32（小写 8 位 hex）
```
**备注**：本文件 = 官方 py2 原版的 **Python 3 移植**（修正了 sparse chunk 的整除运算；py2 原版在普通环境跑不了）。

**依据**：主 README 第四章「组装件并入线刷包（MiFlash 整包刷入用）」。

---

## 3. `flash_gen_crc_list.py` —— 校验表生成器（官方 py2 原版 · 参考）

与 #2 **同逻辑**的原始版本（`#!/usr/bin/env python`，Python 2 时代产物）。
保留原因：对照参考 / 溯源。**日常一律使用 #2（py3 版）**。

---

## 4. `flash_gen_md5_list.py` —— md5 清单生成器（官方体系工具）

**干什么**
生成 `md5sum.xml`：对 `images/` 逐文件登记 md5 + 写入安全补丁级别（从 `$ANDROID_BUILD_TOP/build/core/version_defaults.mk` 读取）。

**备注（如实）**
它源自官方线刷包工具链，**依赖 Android 完整构建环境变量**；在普通 Windows 环境效果有限。
本仓库线刷包里的 `校验清单_md5.txt` 属另一套人工/自建清单，不依赖此脚本。
保留原因：官方原件存档 + 完整性。

---

## 关联流程一览（脚本在流程中的位置）

```
[构建产物 zip]
      │  assemble_boot_2512.py
      ▼
[新 boot.img（2512 布局+六项验证）]
      │  替换进线刷包 images/boot.img（尺寸不变）
      ▼
[线刷包目录]
      │  flash_gen_crc_list_py3.py   ← ★不可跳过
      ▼
[crclist.txt / sparsecrclist.txt 已重算]
      │  MiFlash 或 刷机-带日志.bat（勿用 lock 模式）
      ▼
[设备整包刷入]
      │  出问题？把备份的 boot.img/crclist/sparsecrclist/校验清单 放回原位 → 重刷
      ▼
[回退]
```

**辅助脚本一览**
| 文件 | 状态 | 说明 |
|---|---|---|
| `assemble_boot_2512.py` | 自研（2026-10-12 定稿） | boot 组装，六项验证电池 |
| `flash_gen_crc_list_py3.py` | 官方 py2 版移植 | 校验表重算（日常用这个） |
| `flash_gen_crc_list.py` | 官方原件（py2） | 参考 / 溯源 |
| `flash_gen_md5_list.py` | 官方原件 | md5 清单（依赖 Android 构建环境） |
