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
# 幂等：已应用则跳过；应用失败则警告并跳过（构建不中断）。
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

if grep -q 'selinuxfs_deny_query' "$SELFS"; then
  echo "selinuxfs.c 已包含哨兵过滤，跳过"
  exit 0
fi

echo "应用 SELinux 哨兵过滤补丁..."
if ! patch -p1 --forward -d "$KCOMMON" < "$PATCH_FILE"; then
  echo "::warning title=SELinux 哨兵过滤已跳过::补丁应用失败（内核源码上下文不一致），构建继续"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo "> ⏭️ **SELinux 哨兵过滤** 已自动跳过：补丁应用失败（构建未中断）" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

if ! grep -q 'selinuxfs_deny_query' "$SELFS"; then
  echo "::warning title=SELinux 哨兵过滤校验失败::应用后未检出过滤代码，构建继续"
  exit 0
fi

CNT=$(grep -c 'selinuxfs_deny_query' "$SELFS")
echo "SELinux 哨兵过滤已应用（命中 $CNT 处：1 定义 + 6 写通道守卫）"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "> ✅ **SELinux 哨兵过滤** 已应用：app 侧 ksu/magisk 词探测按 stock 行为返回 EINVAL" >> "$GITHUB_STEP_SUMMARY"
fi
