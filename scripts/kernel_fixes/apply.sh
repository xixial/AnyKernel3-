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
set -eo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$PKG_DIR/selinuxfs_sentinel.patch"
[ -f "$PATCH_FILE" ] || { echo "::warning title=SELinux 哨兵过滤已跳过::补丁文件缺失: $PATCH_FILE"; exit 0; }

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

if grep -q 'selinuxfs_deny_query' "$SELFS"; then
  echo "selinuxfs.c 已包含哨兵过滤，跳过"
  exit 0
fi

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
  exit 0
}

echo "应用 SELinux 哨兵过滤补丁..."
patch -p1 --forward -d "$KCOMMON" < "$PATCH_FILE" || rollback_and_warn "补丁应用失败（源码上下文不一致）"

CT_DENY=$(grep -c 'selinuxfs_deny_query' "$SELFS" || echo 0)
CT_BAK=$(grep -c 'selinuxfs_backup_state' "$SELFS" || echo 0)
if [ "$CT_DENY" -ne 7 ] || [ "$CT_BAK" -lt 3 ]; then
  rollback_and_warn "部分应用（deny=$CT_DENY/7, backup_state=$CT_BAK/3）"
fi

rm -f "$BAK" "$SELFS.rej" "$SELFS.orig"
echo "SELinux 哨兵过滤已应用（deny 命中 $CT_DENY 处：1 定义 + 6 写通道守卫；备份作答标记 $CT_BAK 处）"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "> ✅ **SELinux 哨兵过滤** 已应用：app 侧 ksu/magisk 词探测按 stock 行为返回 EINVAL（deny=$CT_DENY, backup_state=$CT_BAK）" >> "$GITHUB_STEP_SUMMARY"
fi
