#!/usr/bin/env bash
# 应用 SUSFS 补丁及各内核版本所需的上下文修复
#
# 依赖环境变量：
#   ANDROID_VERSION KERNEL_VERSION KSU_VARIANT OS_PATCH_LEVEL SUB_LEVEL
#   KERNEL_ROOT SUSFS4KSU KERNEL_PATCHES LEGACY_SUKISU_CONFIG
# 调用前必须将工作目录设为 $KERNEL_ROOT
set -eo pipefail

echo "应用 SUSFS 补丁..."

SUSFS_PATCH="50_add_susfs_in_gki-$ANDROID_VERSION-$KERNEL_VERSION.patch"
cp "$SUSFS4KSU/kernel_patches/$SUSFS_PATCH" ./common/
cp "$SUSFS4KSU"/kernel_patches/fs/* ./common/fs/
cp "$SUSFS4KSU"/kernel_patches/include/linux/* ./common/include/linux/

case "$KSU_VARIANT" in
  "SukiSU"|"BakaSU")
    echo "SukiSU/BakaSU 使用内置 SUSFS 支持"
    ;;
esac

cd "$KERNEL_ROOT/common"
CURRENT_SUB="$SUB_LEVEL"
if [[ ! "$CURRENT_SUB" =~ ^[0-9]+$ ]]; then
  CURRENT_SUB=99999
fi

# 兼容缺少 VMA padding 接口的 5.10.66～209、5.15.74～144 和 6.1.25～68
if grep -qF 'VMA_PAD_START(vma)' "$SUSFS_PATCH" \
  && ! grep -Rqs 'VMA_PAD_START' ./include/linux; then
  echo "目标内核未提供 VMA_PAD_START，使用 vma->vm_end 兼容 SUSFS OPEN_REDIRECT"
  sed -i 's/VMA_PAD_START(vma)/vma->vm_end/g' "$SUSFS_PATCH"
fi

adjust_legacy_fdinfo_context() {
  sed -i '/^[[:space:]]*\/\*$/,/^[[:space:]]*u32 mask = mark->mask & IN_ALL_EVENTS;$/d' fs/notify/fdinfo.c
  perl -i -pe 's/\bmask,\s*mark->ignored_mask/inotify_mark_user_mask(mark)/g' fs/notify/fdinfo.c
  perl -i -pe 's/ignored_mask:%x/ignored_mask:0/g' fs/notify/fdinfo.c
}

restore_legacy_fdinfo_context() {
  perl -i -pe 's/^(\s+if \(inode\) \{)/$1\n\t\t\/\*\n\t\t * IN_ALL_EVENTS represents all of the mask bits\n\t\t * that we expose to userspace.  There is at\n\t\t * least one bit (FS_EVENT_ON_CHILD) which is\n\t\t * used only internally to the kernel.\n\t\t *\/\n\t\tu32 mask = mark->mask & IN_ALL_EVENTS;/m' fs/notify/fdinfo.c
  perl -i -pe 's/\binotify_mark_user_mask\(mark\)/mask, mark->ignored_mask/g' fs/notify/fdinfo.c
  perl -i -pe 's/ignored_mask:0/ignored_mask:%x/g' fs/notify/fdinfo.c
}

# 临时调整旧内核源码上下文，使 SUSFS 主补丁可以匹配
if [[ "$ANDROID_VERSION" == "android12" && "$KERNEL_VERSION" == "5.10" ]]; then
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -le 43 ]]; then
    echo "临时调整 Android 12 5.10 base.c 上下文"
    perl -i -pe 's/(int|size_t)\s+this_len\s*=\s*min_t\s*\(\s*\1\s*,/size_t this_len = min_t(size_t,/;' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 117 ]]; then
    echo "临时调整 Android 12 5.10 fdinfo.c 上下文"
    adjust_legacy_fdinfo_context
  fi
fi

if [[ "$ANDROID_VERSION" == "android13" && "$KERNEL_VERSION" == "5.15" ]]; then
  if [[ "$CURRENT_SUB" -le 41 ]]; then
    echo "临时调整 Android 13 5.15 namespace.c/open.c/fdinfo.c 上下文"
    if ! grep -qF '#include <linux/mnt_idmapping.h>' fs/namespace.c; then
      sed -i '/^#include <linux\/shmem_fs.h>$/a #include <linux/mnt_idmapping.h>' fs/namespace.c
    fi
    if ! grep -qF '#include <linux/mnt_idmapping.h>' fs/open.c; then
      sed -i '/^#include <linux\/compat.h>$/a #include <linux/mnt_idmapping.h>' fs/open.c
    fi
    adjust_legacy_fdinfo_context
  fi
  if [[ "$OS_PATCH_LEVEL" == "lts" ]]; then
    echo "临时调整 Android 13 5.15 LTS 头文件上下文"
    sed -i '/^#include <trace\/hooks\/blk.h>$/d' fs/namespace.c
    sed -i '/^#include <trace\/hooks\/mm.h>$/d' fs/proc/task_mmu.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" ]]; then
  if [[ "$CURRENT_SUB" -le 25 ]] && ! grep -qF '#include <trace/hooks/sched.h>' fs/proc/base.c; then
    echo "临时调整 Android 14 6.1 sched.h 上下文"
    sed -i '/^#include <trace\/events\/oom.h>$/a #include <trace/hooks/sched.h>' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 141 ]] && ! grep -qF '#include <linux/dma-buf.h>' fs/proc/base.c; then
    echo "临时调整 Android 14 6.1 dma-buf.h 上下文"
    sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -ge 157 ]]; then
    echo "临时调整 Android 14 6.1 namespace.c 上下文"
    sed -i '/^#include <trace\/hooks\/blk.h>$/d' fs/namespace.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
  if [[ "$CURRENT_SUB" -le 92 ]] && ! grep -qF '#include <linux/dma-buf.h>' fs/proc/base.c; then
    echo "临时调整 Android 15 6.6 base.c 上下文"
    sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 57 ]] && ! grep -qF '#include <linux/zswap.h>' mm/memory.c; then
    echo "临时调整 Android 15 6.6 memory.c 上下文"
    sed -i '/^#include <linux\/sched\/sysctl.h>$/a #include <linux/zswap.h>' mm/memory.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android16" && "$KERNEL_VERSION" == "6.12" ]]; then
  if [[ "$CURRENT_SUB" -ge 58 ]]; then
    echo "临时调整 Android 16 6.12 exec.c 上下文"
    sed -i '/^#include <linux\/dma-buf.h>$/d' fs/exec.c
  fi
fi

# 新版内核在 super.c 的 internal.h 之后新增了 trace/hooks/fs.h，
# 旧版 SUSFS 主补丁以 thaw_super_locked 为上下文插入 extern 声明，会整段被拒绝；
# 上游 2026-09-15 起已把声明挪到 unnamed_dev_ida 之后，不再依赖这段上下文，
# 但 ShirkNeko fork 尚未同步（固定提交的旧版补丁不改 super.c），只对旧版补丁做临时调整
SUPER_FS_H_REMOVED=""
if grep -q '^ static int thaw_super_locked' "$SUSFS_PATCH" \
  && grep -qF '#include <trace/hooks/fs.h>' fs/super.c; then
  echo "临时调整 super.c 上下文"
  sed -i '/^#include <trace\/hooks\/fs.h>$/,+1d' fs/super.c
  SUPER_FS_H_REMOVED=1
fi

patch -p1 < "$SUSFS_PATCH" || true

# ---- 预期冲突处理：上游已包含同款修改的 .rej 剔除，真实缺失的手工补齐 ----

# 1) fs/unicode：ASB 内核已包含上游 "unicode: don't special case ignorable code
#    points" 提交，主补丁删除 ignore_init / 重生成 utf8data 的 hunk 已天然满足
if [[ -f fs/unicode/mkutf8data.c.rej ]] && ! grep -q 'ignore_init' fs/unicode/mkutf8data.c; then
  echo "fs/unicode .rej 为上游已包含同款修改，剔除预期冲突文件"
  rm -f fs/unicode/*.rej
fi

# 2) mm/rmap.c：6.6.127+ 已包含 huge_pmd_unshare 的 tlb 化改造
if [[ -f mm/rmap.c.rej ]] && grep -q 'tlb_gather_mmu_vma' mm/rmap.c; then
  echo "mm/rmap.c .rej 为上游已包含同款修改，剔除预期冲突文件"
  rm -f mm/rmap.c.rej
fi

# 3) fs/proc/task_mmu.c（6.12.69+）：show_smap 重构（vma_pages → vma_data_pages）
#    导致 SUS_MAP 检查 hunk 上下文失配被拒，属于真实缺失，手工补回
if [[ -f fs/proc/task_mmu.c.rej ]] \
  && grep -qF 'static int show_smap(struct seq_file *m, void *v)' fs/proc/task_mmu.c; then
  SHOW_SMAP_BODY="$(sed -n '/^static int show_smap(struct seq_file \*m, void \*v)/,/^}/p' fs/proc/task_mmu.c)"
  if [[ -n "$SHOW_SMAP_BODY" ]] && ! grep -qF 'SUSFS_IS_INODE_SUS_MAP' <<< "$SHOW_SMAP_BODY"; then
    echo "为 show_smap 手工补入 SUS_MAP 检查（6.12.69+ 上下文漂移）"
    perl -0pi -e 's/(static int show_smap\(struct seq_file \*m, void \*v\)\n\{\n\tstruct vm_area_struct \*vma = v;\n\tstruct mem_size_stats mss = \{\};\n)/$1\n#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tif (vma->vm_file) {\n\t\tif (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\n\t\t\treturn 0;\n\t}\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n/' fs/proc/task_mmu.c
    if ! grep -qF 'SUSFS_IS_INODE_SUS_MAP' fs/proc/task_mmu.c; then
      echo "::error::show_smap SUS_MAP 检查手工补丁失败，请人工核对 fs/proc/task_mmu.c"
      exit 1
    fi
    rm -f fs/proc/task_mmu.c.rej
  fi
fi

# 为尚未提供 SU 会话 FD 接口的 SukiSU/BakaSU 恢复旧版 exec hook 行为
EXEC_HELPER=""
if [[ "$KSU_VARIANT" == SukiSU* || "$KSU_VARIANT" == "BakaSU" ]]; then
  if grep -qF 'ksu_install_su_fd();' fs/exec.c; then
    EXEC_HELPER="ksu_install_su_fd"
  elif grep -qF 'ksu_handle_post_execveat_sucompat(' fs/exec.c; then
    EXEC_HELPER="ksu_handle_post_execveat_sucompat"
  fi
fi
if [[ -n "$EXEC_HELPER" ]] \
  && ! grep -RqsE --include='*.c' "^[[:space:]]*int[[:space:]]+${EXEC_HELPER}[[:space:]]*\(" "$KERNEL_ROOT/KernelSU/kernel"; then
  echo "$KSU_VARIANT 尚未提供 $EXEC_HELPER，恢复旧版 exec hook"
  sed -i '/^extern int ksu_install_su_fd(void);$/d' fs/exec.c
  sed -i '/^extern int ksu_handle_post_execveat_sucompat(/,+1d' fs/exec.c
  sed -i 's/is_su_session = !\(ksu_handle_execveat[^;]*;\)/\1/' fs/exec.c
  sed -i '/^[[:space:]]*bool is_su_session = false;$/d' fs/exec.c
  sed -i '/^[[:space:]]*if (unlikely(is_su_session && retval >= 0))$/,+1d' fs/exec.c
  sed -i '/^[[:space:]]*if (unlikely(is_su_session))$/,+1d' fs/exec.c
  sed -i '/^#ifdef CONFIG_KSU_SUSFS$/N;/^#ifdef CONFIG_KSU_SUSFS\n#endif \/\/ #ifdef CONFIG_KSU_SUSFS$/d' fs/exec.c
  if grep -qE 'ksu_install_su_fd|ksu_handle_post_execveat_sucompat|is_su_session' fs/exec.c; then
    echo "::error::$KSU_VARIANT exec hook 结构已变化，无法完成兼容修复"
    exit 1
  fi
fi

# 上游 5.10 主补丁把 susfs_sus_kstat_spoof_vfs_statfs 的 extern 声明放在了
# fs/statfs.c 的使用点之后（vfs_statfs 之前），clang -Werror 报隐式声明；
# 声明属于 SUSFS 接口，直接补进公共头 include/linux/susfs_def.h：
# 不依赖 statfs.c 内锚点与行号比较，声明重复合法，上游后续自行修复也不冲突
SUSFS_DEF_H="$KERNEL_ROOT/common/include/linux/susfs_def.h"
if [[ -f fs/statfs.c ]] && grep -qF 'susfs_sus_kstat_spoof_vfs_statfs(' fs/statfs.c \
  && [[ -f "$SUSFS_DEF_H" ]] \
  && ! grep -qF 'susfs_sus_kstat_spoof_vfs_statfs(' "$SUSFS_DEF_H"; then
  echo "将 susfs_sus_kstat_spoof_vfs_statfs 声明补入 include/linux/susfs_def.h"
  sed -i '/^#endif \/\/ #ifndef KSU_SUSFS_DEF_H$/i extern int susfs_sus_kstat_spoof_vfs_statfs(struct inode *inode, struct kstatfs *buf, bool *is_fuse);' "$SUSFS_DEF_H"
fi

# 上游 susfs.c 直接调用 security_sb_statfs 却没有包含 linux/security.h，
# 5.15+ 靠其他头文件间接带入，5.10 没有这条路径，clang -Werror 报隐式声明；缺失时补上
if [[ -f fs/susfs.c ]] && grep -qF 'security_sb_statfs(' fs/susfs.c \
  && ! grep -qF '#include <linux/security.h>' fs/susfs.c; then
  echo "为 susfs.c 补充 linux/security.h 头文件"
  sed -i '0,/^#include <linux\/fs.h>$/s//#include <linux\/fs.h>\n#include <linux\/security.h>/' fs/susfs.c
fi

# 在编译前报告 SUSFS 主补丁产生的冲突文件
SUSFS_REJ_COUNT=$(find . -name '*.rej' | wc -l)
if [ "$SUSFS_REJ_COUNT" -gt 0 ]; then
  echo "::warning title=SUSFS 补丁冲突::SUSFS 主补丁产生了 ${SUSFS_REJ_COUNT} 个 .rej 冲突文件，可能导致后续编译失败（详见 Rejects 产物）"
  find . -name '*.rej' -print
fi

# 还原仅用于补丁匹配的临时源码调整
if [[ "$ANDROID_VERSION" == "android12" && "$KERNEL_VERSION" == "5.10" ]]; then
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -le 43 ]]; then
    echo "还原 Android 12 5.10 base.c 临时调整"
    sed -i 's/^size_t this_len = min_t(size_t, count, PAGE_SIZE);$/int this_len = min_t(int, count, PAGE_SIZE);/' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 117 ]]; then
    echo "还原 Android 12 5.10 fdinfo.c 临时调整"
    restore_legacy_fdinfo_context
  fi
fi

if [[ "$ANDROID_VERSION" == "android13" && "$KERNEL_VERSION" == "5.15" ]]; then
  if [[ "$CURRENT_SUB" -le 41 ]]; then
    echo "还原 Android 13 5.15 临时调整"
    sed -i '/#include <linux\/mnt_idmapping.h>$/d' fs/namespace.c
    sed -i '/#include <linux\/mnt_idmapping.h>$/d' fs/open.c
    restore_legacy_fdinfo_context
    sed -i 's|i_uid_into_mnt(i_user_ns(&fi->inode), &fi->inode).val|i_uid_into_mnt(\&init_user_ns, \&fi->inode).val|g' fs/susfs.c
    sed -i 's|i_uid_into_mnt(i_user_ns(inode), inode).val|i_uid_into_mnt(\&init_user_ns, inode).val|g' fs/susfs.c
  fi
  if [[ "$OS_PATCH_LEVEL" == "lts" ]]; then
    echo "还原 Android 13 5.15 LTS 头文件上下文"
    if ! grep -qF '#include <trace/hooks/blk.h>' fs/namespace.c; then
      sed -i '/^#include "internal.h"$/a #include <trace/hooks/blk.h>' fs/namespace.c
    fi
    if ! grep -qF '#include <trace/hooks/mm.h>' fs/proc/task_mmu.c; then
      sed -i '/^#include <linux\/pkeys.h>$/a #include <trace/hooks/mm.h>' fs/proc/task_mmu.c
    fi
  fi
fi

if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" ]]; then
  if [[ "$CURRENT_SUB" -le 25 ]]; then
    sed -i '/^#include <trace\/hooks\/sched.h>$/d' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 141 ]]; then
    echo "还原 Android 14 6.1 base.c 临时调整"
    sed -i '/^#include <linux\/dma-buf.h>$/d' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -ge 157 ]] && ! grep -qF '#include <trace/hooks/blk.h>' fs/namespace.c; then
    echo "还原 Android 14 6.1 namespace.c 临时调整"
    sed -i '/^#include "internal.h"$/a #include <trace/hooks/blk.h>' fs/namespace.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
  if [[ "$CURRENT_SUB" -le 92 ]]; then
    echo "还原 Android 15 6.6 base.c 临时调整"
    sed -i '/^#include <linux\/dma-buf.h>$/d' fs/proc/base.c
  fi
  if [[ "$CURRENT_SUB" -le 57 ]]; then
    echo "还原 Android 15 6.6 memory.c 临时调整"
    sed -i '/^#include <linux\/zswap.h>$/d' mm/memory.c
  fi
fi

if [[ "$ANDROID_VERSION" == "android16" && "$KERNEL_VERSION" == "6.12" ]]; then
  if [[ "$CURRENT_SUB" -ge 58 ]] && ! grep -qF '#include <linux/dma-buf.h>' fs/exec.c; then
    echo "还原 Android 16 6.12 exec.c 临时调整"
    sed -i '0,/^#include /s//#include <linux\/dma-buf.h>\n&/' fs/exec.c
  fi
fi

if [[ -n "$SUPER_FS_H_REMOVED" ]] \
  && ! grep -qF '#include <trace/hooks/fs.h>' fs/super.c; then
  echo "还原 super.c 临时调整"
  sed -i '/^#include "internal.h"$/a #include <trace/hooks/fs.h>' fs/super.c
fi

fix_missing_vm_flags_clear() {
  if [[ "$OS_PATCH_LEVEL" == "2024-11" ]] && grep -qF 'vm_flags_clear(new_vma, VM_PAD_MASK);' ./mm/mmap.c; then
    sed -i 's/vm_flags_clear(new_vma, VM_PAD_MASK);/new_vma->vm_flags \&= ~VM_PAD_MASK;/' ./mm/mmap.c
  fi
}

fix_task_mmu_show_pad() {
  local max_sub="$1"
  local excluded_patch_level="${2:-}"

  # 仅固定旧版 SUSFS 补丁会引入 goto show_pad，最新版已不再包含该代码
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -le "$max_sub" ]] \
    && { [[ -z "$excluded_patch_level" ]] || [[ "$OS_PATCH_LEVEL" != "$excluded_patch_level" ]]; }; then
    sed -i -e 's/goto show_pad;/return 0;/' ./fs/proc/task_mmu.c
  fi
}

# Android 12 - 5.10 修复
if [[ "$ANDROID_VERSION" == "android12" && "$KERNEL_VERSION" == "5.10" ]]; then
  # 修复 2024-11 分支: mmap.c 调用了 vm_flags_clear()，但同分支 mm.h 未提供 helper
  fix_missing_vm_flags_clear
  fix_task_mmu_show_pad 209
fi

# Android 13 - 5.15 修复
  if [[ "$ANDROID_VERSION" == "android13" && "$KERNEL_VERSION" == "5.15" ]]; then
  # 修复 2024-11 分支: mmap.c 调用了 vm_flags_clear()，但同分支 mm.h 未提供 helper
  fix_missing_vm_flags_clear
  fix_task_mmu_show_pad 148 "2024-05"
fi

# Android 14 - 6.1 修复
if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" ]]; then
  fix_task_mmu_show_pad 75 "2024-05"
fi

# Android 15 - 6.6 修复
if [[ "$ANDROID_VERSION" == "android15" && "$KERNEL_VERSION" == "6.6" ]]; then
  # 修复老版 SukiSU 6.6.50~6.6.58: task_mmu.c 打入 SUSFS 后使用 vma，但旧源码没有对应声明
  if [[ -n "$LEGACY_SUKISU_CONFIG" && "$CURRENT_SUB" -ge 50 && "$CURRENT_SUB" -le 58 ]] \
    && grep -qF 'vma = find_vma(mm, start_vaddr);' ./fs/proc/task_mmu.c; then
    TASK_MMU_PATCH="$KERNEL_PATCHES/wild/archived/susfs_fix_patches/v2.1.0/a15-6.6/task_mmu.c.patch"
    if [ ! -f "$TASK_MMU_PATCH" ]; then
      echo "::error::补丁不存在: $TASK_MMU_PATCH"
      exit 1
    fi
    cp "$TASK_MMU_PATCH" ./
    if patch -p1 --dry-run < task_mmu.c.patch >/dev/null 2>&1; then
      patch -p1 --no-backup-if-mismatch < task_mmu.c.patch
      echo "已应用 Android 15 6.6.50~6.6.58 task_mmu.c 归档修复补丁"
    else
      echo "Android 15 6.6.50~6.6.58 task_mmu.c 归档修复补丁已应用或当前上下文不匹配，跳过"
    fi
  fi
fi

# Android 16 - 6.12 修复
if [[ "$ANDROID_VERSION" == "android16" && "$KERNEL_VERSION" == "6.12" ]]; then
  # 固定旧版 SukiSU 在 6.12 上会重复定义 setresuid hook
  SETUID_HOOK="$KERNEL_ROOT/common/drivers/kernelsu/setuid_hook.c"
  if [[ -n "$LEGACY_SUKISU_CONFIG" && -f "$SETUID_HOOK" ]] \
    && grep -qF 'defined(CONFIG_KSU_MANUAL_HOOK))' "$SETUID_HOOK"; then
    sed -i 's/defined(CONFIG_KSU_MANUAL_HOOK))/!defined(CONFIG_KSU_SUSFS) \&\& defined(CONFIG_KSU_MANUAL_HOOK))/' "$SETUID_HOOK"
    echo "已修复 setuid_hook.c 重复定义问题"
  fi
fi

# ============================================================
# v3: my_setprocattr 的 AVC 计数行为对齐（Luna 对抗 · 内核侧）
# 背景：SUSFS 的 my_setprocattr 对"空/纯换行载荷"会继续进入 stock 处理器，
# 导致被拒写入的 PROCESS__SETCURRENT avc 查询次数偏离 stock（2 次 vs 1 次），
# 该计数指纹可被"AVC lookup 计数实验"识别为"带隐藏的 KernelSU"。
# 本段把该跳步路径改为直接 no-op 返回，使计数与 stock 一致（权限语义不变）。
# 幂等：已应用（唯一标记 v3:setprocattr-avc-align）则跳过；
# 应用失败/部分应用：【自动回滚】并警告跳过（构建不中断）；成功/失败均写 summary。
# ============================================================
V3_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../kernel_fixes/setprocattr_avc_align.patch"
HOOKS=security/selinux/hooks.c
if [ ! -f "$HOOKS" ]; then
  echo "::warning title=setprocattr AVC 对齐已跳过::未找到 $HOOKS"
elif [ ! -f "$V3_PATCH" ]; then
  echo "::warning title=setprocattr AVC 对齐已跳过::补丁文件缺失: $V3_PATCH"
elif grep -q 'v3:setprocattr-avc-align' "$HOOKS"; then
  echo "setprocattr AVC 对齐已应用，跳过"
else
  V3_BAK="$(mktemp)"
  cp -f "$HOOKS" "$V3_BAK"
  rm -f "$HOOKS.rej" "$HOOKS.orig"
  v3_rollback() {
    cp -f "$V3_BAK" "$HOOKS"
    rm -f "$V3_BAK" "$HOOKS.rej" "$HOOKS.orig"
    echo "::warning title=setprocattr AVC 对齐已回滚::$1（构建继续，该修复未生效）"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "" >> "$GITHUB_STEP_SUMMARY"
      echo "> ⏪ **setprocattr AVC 对齐** 未生效（$1），已回滚为补丁前原文件（构建未中断）" >> "$GITHUB_STEP_SUMMARY"
    fi
  }
  echo "应用 setprocattr AVC 计数对齐补丁..."
  if ! patch -p1 --forward < "$V3_PATCH"; then
    v3_rollback "补丁应用失败（源码上下文不一致）"
  else
    V3_CNT=$(grep -c 'v3:setprocattr-avc-align' "$HOOKS" || echo 0)
    if [ "$V3_CNT" -lt 1 ]; then
      v3_rollback "部分应用（标记计数 $V3_CNT/1）"
    else
      rm -f "$V3_BAK" "$HOOKS.rej" "$HOOKS.orig"
      echo "setprocattr AVC 计数对齐已应用（标记 $V3_CNT 处）"
      if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "" >> "$GITHUB_STEP_SUMMARY"
        echo "> ✅ **setprocattr AVC 计数对齐（v3）** 已应用：skip-path 写入的 avc 查询计数与 stock 一致（1/1）" >> "$GITHUB_STEP_SUMMARY"
      fi
    fi
  fi
fi

# ============================================================
# v4: mountinfo 的 /adb/modules 条目对 app 读者过滤（Luna 对抗 · 内核侧）
# 背景：GGAT_10007 等模块的 bind mount（root 字段含 adb/modules）可从系统进程的
# 挂载表被 app（app_zygote carrier）读到 → 命中"挂载异常 / Mount token"检测。
# 本段在 fs/proc_namespace.c 的两个 mountinfo 输出函数中，对 uid≥10000 的读者
# 跳过 root 含 "adb/modules" 的条目（root/system 读者不受影响）。
# 幂等：已应用（标记 [v4:mountinfo-adb-filter] x2）则跳过；失败自动回滚并写 summary。
# ============================================================
V4_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../kernel_fixes/mountinfo_adb_filter.patch"
PNS=fs/proc_namespace.c
if [ ! -f "$PNS" ]; then
  echo "::warning title=mountinfo /adb 过滤已跳过::未找到 $PNS"
elif [ ! -f "$V4_PATCH" ]; then
  echo "::warning title=mountinfo /adb 过滤已跳过::补丁文件缺失: $V4_PATCH"
elif grep -q 'v4:mountinfo-adb-filter' "$PNS"; then
  echo "mountinfo /adb 过滤已应用，跳过"
else
  V4_BAK="$(mktemp)"
  cp -f "$PNS" "$V4_BAK"
  rm -f "$PNS.rej" "$PNS.orig"
  v4_rollback() {
    cp -f "$V4_BAK" "$PNS"
    rm -f "$V4_BAK" "$PNS.rej" "$PNS.orig"
    echo "::warning title=mountinfo /adb 过滤已回滚::$1（构建继续，该修复未生效）"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      echo "" >> "$GITHUB_STEP_SUMMARY"
      echo "> ⏪ **mountinfo /adb 过滤（v4）** 未生效（$1），已回滚为补丁前原文件（构建未中断）" >> "$GITHUB_STEP_SUMMARY"
    fi
  }
  echo "应用 mountinfo /adb 过滤补丁..."
  if ! patch -p1 --forward < "$V4_PATCH"; then
    v4_rollback "补丁应用失败（源码上下文不一致）"
  else
    V4_CNT=$(grep -c 'v4:mountinfo-adb-filter' "$PNS" || echo 0)
    if [ "$V4_CNT" -lt 2 ]; then
      v4_rollback "部分应用（标记计数 $V4_CNT/2）"
    else
      rm -f "$V4_BAK" "$PNS.rej" "$PNS.orig"
      echo "mountinfo /adb 过滤已应用（标记 $V4_CNT 处）"
      if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "" >> "$GITHUB_STEP_SUMMARY"
        echo "> ✅ **mountinfo /adb 过滤（v4）** 已应用：app 读者看不到 root 含 adb/modules 的挂载条目" >> "$GITHUB_STEP_SUMMARY"
      fi
    fi
  fi
fi
