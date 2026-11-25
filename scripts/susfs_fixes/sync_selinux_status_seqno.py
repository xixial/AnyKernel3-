#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# file: scripts/susfs_fixes/sync_selinux_status_seqno.py
#
# 背景（2026-11-25 实测）：
#   SUSFS 在 security/selinux/status.c 的 selinux_status_update_policyload() 里
#   加入 KSU 域分支，只写 status->policyload = seqno 后直接 return，
#   跳过了原生路径上的 status->sequence++。
#   结果：status.sequence 恒为 0，而 policyload 持续增长（实测 0 / 7）。
#   春秋 Native check 的「access seqno」规则正是比对这两个字段，
#   sequence 与 policyload 不同步即被判为策略异常。
#
# 本脚本在 SUSFS 主补丁应用之后运行，把 sequence 与 seqno 同步，
# 恢复真机语义（sequence 与 policyload 一致）。幂等。
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "security/selinux/status.c"

try:
    with open(PATH, encoding="utf-8", errors="surrogateescape") as f:
        src = f.read()
except FileNotFoundError:
    print("[seqno] %s 不存在，跳过" % PATH)
    sys.exit(0)

if "status->sequence = seqno;" in src:
    print("[seqno] sequence 已同步，跳过")
    sys.exit(0)

MARK = "susfs_is_current_ksu_domain"
# SUSFS 分支内的缩进是 3 个 tab；原生路径是 2 个 tab，可据此精确区分
OLD = "\t\t\tstatus->policyload = seqno;"
NEW = "\t\t\tstatus->policyload = seqno;\n\t\t\tstatus->sequence = seqno;"

idx = src.find(MARK)
changed = False
while idx >= 0:
    pos = src.find(OLD, idx)
    if pos >= 0 and pos - idx < 600:
        src = src[:pos] + NEW + src[pos + len(OLD):]
        changed = True
        break
    idx = src.find(MARK, idx + 1)

if changed:
    with open(PATH, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(src)
    print("[seqno] 已同步 selinux status sequence 与 policyload（修复 access seqno 不一致）")
else:
    print("[seqno] 未找到 SUSFS policyload 分支，跳过（上游可能已自行修复）")
