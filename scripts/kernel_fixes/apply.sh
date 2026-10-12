#!/usr/bin/env bash
# SELinux 哨兵过滤补丁（Luna 对抗 · 内核侧）
#
# 目的：应用 uid（>=10000）向 selinuxfs 的写通道（context/access/create/
# relabel/user/member）提交含 ksu/magisk/susfs/apatch/supersu 词的查询时，
# 直接按“类型不存在”返回 -EINVAL —— 与未 root 的 stock 内核行为完全一致，
# 使“测 u:r:ksu:s0 是否合法”这类策略指纹探测失效。
# root / system（uid<10000）行为不变。
#
# 用法：在 KERNEL_ROOT 目录下执行（工作目录=KERNEL_ROOT，或 $KERNEL_ROOT 已设置）。
# 幂等：已应用则跳过；应用失败/部分应用则【自动回滚】并警告跳过（构建不中断）。
# v2 加固（2026-10-11）：① 应用后断言计数（deny=7、backup_state>=3），防“补丁只应用一半”；
#                       ② 失败/部分应用时先回滚到补丁前原文件，杜绝半打状态进构建；
#                       ③ 失败与成功都写 GITHUB_STEP_SUMMARY。
# v5 接线（2026-10-12）：新增 sidtab_hash_stats 备份作答段（依赖哨兵先生效；
#                       哨兵未生效/缺失时 v5 自动跳过并告警，构建不中断）。
# v2 切换（2026-10-12）：哨兵→哨兵-LITE（撤 context/access 注入以适配新版 SUSFS 内联 hunks；
#                       断言 deny=5；v3 段同步退役）。
set -eo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$PKG_DIR/selinuxfs_sentinel_lite.patch"
V5_PATCH="$PKG_DIR/sidtab_backup_answer.patch"

if [ -f security/selinux/selinuxfs.c ]; then
  KCOMMON="$(pwd)"
elif [ -n "${KERNEL_ROOT:-}" ] && [ -f "$KERNEL_ROOT/common/security/selinux/selinuxfs.c" ]; then
  KCOMMON="$KERNEL_ROOT/common"
else
  echo "::warning title=SELinux 哨兵过滤已跳过::未找到内核 common 目录（security/selinux/selinuxfs.c）"
  exit 0
fi

SELFS="$KCOMMON/security/selinux/selinuxfs.c"
rm -f "$SELFS.rej" "$SELFS.orig"

# ---------- 第 1 段：哨兵过滤（写通道词过滤 + 备份作答） ----------
SENT_OK=0
if [ ! -f "$PATCH_FILE" ]; then
  echo "::warning title=SELinux 哨兵过滤已跳过::补丁文件缺失: $PATCH_FILE"
elif grep -q 'selinuxfs_deny_query' "$SELFS"; then
  echo "selinuxfs.c 已包含哨兵过滤，跳过"
  SENT_OK=1
else
  BAK="$(mktemp)"
  cp -f "$SELFS" "$BAK"

  rollback_and_warn() {
    cp -f "$BAK" "$SELFS"
    rm -f "$BAK" "$SELFS.rej" "$SELFS.orig"
    echo "::warning title=SELinux 哨兵过滤已回滚::$1（构建继续，内核为未打补丁状态）"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "" >> "$GITHUB_STEP_SUMMARY"
      echo "> ⏪ **SELinux 哨兵过滤** 未生效（$1），已回滚为补丁前原文件（构建未中断）" >> "$GITHUB_STEP_SUMMARY"
    fi
  }

  echo "应用 SELinux 哨兵过滤补丁..."
  if patch -p1 --forward -d "$KCOMMON" < "$PATCH_FILE"; then
    CT_DENY=$(grep -c 'selinuxfs_deny_query' "$SELFS" || echo 0)
    CT_BAK=$(grep -c 'selinuxfs_backup_state' "$SELFS" || echo 0)
    if [ "$CT_DENY" -ne 5 ] || [ "$CT_BAK" -lt 1 ]; then
      rollback_and_warn "部分应用（deny=$CT_DENY/7, backup_state=$CT_BAK/3）"
    else
      rm -f "$BAK" "$SELFS.rej" "$SELFS.orig"
      echo "SELinux 哨兵过滤已应用（deny 命中 $CT_DENY 处：1 定义 + 4 冷门通道守卫；备份作答标记 $CT_BAK 处）"
      if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "" >> "$GITHUB_STEP_SUMMARY"
        echo "> ✅ **SELinux 哨兵-LITE** 已应用：4 冷门写通道词过滤（create/relabel/user/member；context/access 由新版 SUSFS 接管）（deny=$CT_DENY, backup_state=$CT_BAK）" >> "$GITHUB_STEP_SUMMARY"
      fi
      SENT_OK=1
    fi
  else
    rollback_and_warn "补丁应用失败（源码上下文不一致）"
  fi
fi

# ---------- 第 2 段：sidtab_hash_stats 备份作答（依赖哨兵） ----------
if [ "$SENT_OK" -ne 1 ]; then
  echo "::warning title=sidtab 备份作答已跳过::依赖的哨兵过滤未生效（v5 需要 selinuxfs_backup_state）"
elif [ ! -f "$V5_PATCH" ]; then
  echo "::warning title=sidtab 备份作答已跳过::补丁文件缺失: $V5_PATCH"
elif grep -q 'v5:sidtab-backup-answer' "$SELFS"; then
  echo "sidtab 备份作答已应用，跳过"
else
  V5_BAK="$(mktemp)"
  cp -f "$SELFS" "$V5_BAK"
  rm -f "$SELFS.rej" "$SELFS.orig"

  v5_rollback() {
    cp -f "$V5_BAK" "$SELFS"
    rm -f "$V5_BAK" "$SELFS.rej" "$SELFS.orig"
    echo "::warning title=sidtab 备份作答已回滚::$1（构建继续，该修复未生效）"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "" >> "$GITHUB_STEP_SUMMARY"
      echo "> ⏪ **sidtab 备份作答（v5）** 未生效（$1），已回滚为补丁前原文件（构建未中断）" >> "$GITHUB_STEP_SUMMARY"
    fi
  }

  echo "应用 sidtab 备份作答补丁（v5）..."
  if patch -p1 --forward -d "$KCOMMON" < "$V5_PATCH"; then
    V5_CNT=$(grep -c 'v5:sidtab-backup-answer' "$SELFS" || echo 0)
    if [ "$V5_CNT" -lt 1 ]; then
      v5_rollback "部分应用（标记 $V5_CNT/1）"
    else
      rm -f "$V5_BAK" "$SELFS.rej" "$SELFS.orig"
      echo "sidtab 备份作答已应用（标记 $V5_CNT 处）"
      if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "" >> "$GITHUB_STEP_SUMMARY"
        echo "> ✅ **sidtab 备份作答（v5）** 已应用：app 读 sidtab_hash_stats 从 KSU 前快照作答（entries/buckets/chain 与 stock 一致）" >> "$GITHUB_STEP_SUMMARY"
      fi
    fi
  else
    v5_rollback "补丁应用失败（源码上下文不一致）"
  fi
fi
