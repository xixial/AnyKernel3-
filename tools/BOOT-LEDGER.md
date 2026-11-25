# 本地烧机台账（K70 / vermeer）

> 采集时间：2026-11-25 · 全部为实测（HEAD 解析 + 段哈希），非回忆。
> 所有 boot 均为 boot header **v4 / header_size=1584 / kernel_size=47,442,432 / 页对齐 pad=2512**。
> `seg` = kernel 段 `[4096, 4096+47442432)` 的 MD5 前 10 位，用来区分不同代的组装件。
> 本文件只解决一个问题：**哪个文件是哪一版**。换机、回退、复测时查这里，不要去猜文件名。

## 台账

| 文件 | boot MD5 | seg 指纹 | 说明 |
|---|---|---|---|
| `boot.img` | `84354cda975034b65e3eaa6222bd831b` | `5e1c5eef75` | **现役**。段内前 43,036,032B = `de075adc`，即 `SukiSU_kernel-android13-5.15-178-AnyKernel3_2-1.zip` 包内的 Image，CI 直出 |
| `boot.img.bak-0BBCF5D0` | `0bbcf5d0…` | `b6c2f44d0a` | KPM 完全体（本地 kptools 修补）。段内前 43,036,032B = `512663ad`，与 commit `72b6078` 记录的"本地实测产物与官方 Android 版逐字节一致 512663ad"对应 |
| `boot.img.bak-DA53A923` | `da53a923…` | `09079f8c7e` | KPM 首次打通的版本（正版 kpimg 重打，+295,808B） |
| `boot.img.bak-6A5A9C59` | `6a5a9c59…` | `404a5aedfe` | v3 KPM-off。段内前 42,740,224B = `b65a47ff`，即 `…_2.zip` 的 Image |
| `boot.img.bak-165EF002` | `165ef002…` | `58956773bb` | run#20 产物（KPM-off，Luna 8/8 检测基线）；= `K70boot/boot20版.img` |
| `boot.img.bak-DD2B88A9` | `dd2b88a9…` | `e94eab9f47` | run#19 产物；= `K70boot/boot19版.img` |
| `boot.img.bak-49b46f94` | `49b46f94…` | `76683377d4` | wild 同款 inplace 首次实机全绿 |
| `boot.img.bak-7e65fa20` | `7e65fa20…` | `232bb3a38b` | config.gz 官方化版 |
| `boot.img.bak-7ded226d` | `7ded226d…` | `f814f2e6e4` | 哨兵 v1 首测 |
| `boot.img.bak-5f39b718` | `5f39b718…` | `396d84489a` | 哨兵 v1 + config 官方化 |
| `boot.img.bak-DA082C72` | `da082c72…` | `5c4f786934` | 哨兵 v2 |
| `boot.img.bak-A25501A0` | `a25501a0…` | `1be0e42d86` | 哨兵 v3（刷入后春秋「kernelsu detected / 第三方内核」双双消失） |
| `boot.img.bak-38DB98B6` | `38db98b6…` | `d5fe14a15d` | 2512 重装首测（六项电池全绿） |
| `boot.img.bak-5A2447BB` | `5a2447bb…` | `744aa18ad3` | 台账未标注用途，保留件 |
| `boot.img.bak-B66AA83C` | `b66aa83c…` | `f2cfb23437` | 台账未标注用途，保留件 |

## 回退顺序

| 顺序 | 命令 | 何时用 |
|---|---|---|
| 1 | `fastboot flash boot boot.img.bak-6A5A9C59` | 新件有问题，退回 KPM-off 的稳定态 |
| 2 | `fastboot flash boot boot.img.bak-0BBCF5D0` | 退回 KPM 完全体验收版 |
| 3 | `fastboot flash boot boot.img.bak-DA53A923` | 退回 KPM 首成功版 |
| 4 | 线刷包 `K70_debloat_root_OS3.0.9.0/images/boot.img` | 彻底回底（wild 内核，实测完全可用） |

## 组装规则（2512 铁律）

```
boot.img = header(1584B，逐字节复制官方)
         + 2512B 填充（1584 + 2512 = 4096，页对齐）
         + Image
         + 段内余下部分（保持原样）
```

NOP 化头部、或把 Image 整体移位 2512（而不是填在 +4096）会直接黑砖——两次事故都是这么来的。

## 相关工具

- `tools/assemble_boot_2512.py` —— 组装脚本（独立文件，不进构建链）
- 校验：`python tools/assemble_boot_2512.py --inspect <boot.img>`
