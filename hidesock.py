#!/usr/bin/env python3
"""[HIDESOCK] 从 /proc/net/unix 与 sock_diag(ss -x) 隐藏 zn_/lsp_/lspbridge 命名的 socket。

v2（2026-10-11）：除 af_unix.c（/proc/net/unix 的 seq 打印路径）外，
自动在同一目录给 diag.c（sock_diag / ss -x 的 dump 路径）打同规则隐藏——
堵上审计发现的「ss -x 可枚举同名 socket」盲区。
diag 端为“软失败”：锚点不匹配时警告并继续（exit 0），不影响构建；
af_unix 端保持原行为（锚点不匹配即报错退出）。
"""
import os
import sys

P = sys.argv[1] if len(sys.argv) > 1 else "common/net/unix/af_unix.c"

# ---------- af_unix.c：/proc/net/unix seq 打印机 ----------
src = open(P, "r", encoding="utf-8", errors="surrogateescape").read()

if "[HIDESOCK]" in src:
    print("[HIDESOCK] already patched, skip.")
else:
    ANCHOR = (
        "\t\tunix_state_lock(s);\n"
        "\n"
        '\t\tseq_printf(seq, "%pK: %08X %08X %08X %04X %02X %5lu",'
    )

    n = src.count(ANCHOR)
    if n != 1:
        print(f"[HIDESOCK] ERROR: anchor count = {n} (expect exactly 1); abort.", file=sys.stderr)
        sys.exit(1)

    PATCH = (
        "\t\tunix_state_lock(s);\n"
        "\n"
        "\t\t/* [HIDESOCK] hide named sockets (zn_ / lsp_ / lspbridge) */\n"
        "\t\tif (u->addr) {\n"
        "\t\t\tint _h_i = 0, _h_len = u->addr->len - sizeof(short);\n"
        "\t\t\tconst char *_h_nm;\n"
        "\n"
        "\t\t\tif (!UNIX_ABSTRACT(s))\n"
        "\t\t\t\t_h_len--;\n"
        "\t\t\telse\n"
        "\t\t\t\t_h_i++;\n"
        "\n"
        "\t\t\t_h_nm = &u->addr->name->sun_path[_h_i];\n"
        "\t\t\tif ((_h_len - _h_i >= 3 && !memcmp(_h_nm, \"zn_\", 3)) ||\n"
        "\t\t\t    (_h_len - _h_i >= 4 && !memcmp(_h_nm, \"lsp_\", 4)) ||\n"
        "\t\t\t    (_h_len - _h_i >= 9 && !memcmp(_h_nm, \"lspbridge\", 9))) {\n"
        "\t\t\t\tunix_state_unlock(s);\n"
        "\t\t\t\treturn 0;\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\t\t/* [HIDESOCK] end */\n"
        "\n"
        '\t\tseq_printf(seq, "%pK: %08X %08X %08X %04X %02X %5lu",'
    )

    out = src.replace(ANCHOR, PATCH)
    open(P, "w", encoding="utf-8", errors="surrogateescape").write(out)
    print("[HIDESOCK] patch applied OK")

# ---------- diag.c：sock_diag（ss -x / netlink diag）dump 路径 ----------
D = os.path.join(os.path.dirname(P) or ".", "diag.c")
if not os.path.exists(D):
    print(f"[HIDESOCK] WARN: diag.c not found at '{D}'; sock_diag 盲区未覆盖（继续）")
    sys.exit(0)

dsrc = open(D, "r", encoding="utf-8", errors="surrogateescape").read()

if "[HIDESOCK-DIAG]" in dsrc:
    print("[HIDESOCK] diag.c already patched, skip.")
    sys.exit(0)

DANCHOR = (
    "\t\t\tif (!(req->udiag_states & (1 << READ_ONCE(sk->sk_state))))\n"
    "\t\t\t\tgoto next;\n"
)

dn = dsrc.count(DANCHOR)
if dn != 1:
    print(f"[HIDESOCK] WARN: diag.c anchor count = {dn} (expect exactly 1); sock_diag 盲区未覆盖（继续）", file=sys.stderr)
    sys.exit(0)

DPATCH = (
    DANCHOR
    + "\n"
    + "\t\t\t/* [HIDESOCK-DIAG] hide named sockets (zn_ / lsp_ / lspbridge) */\n"
    + "\t\t\t{\n"
    + "\t\t\t\tstruct unix_sock *_hd_u = unix_sk(sk);\n"
    + "\n"
    + "\t\t\t\tif (_hd_u->addr) {\n"
    + "\t\t\t\t\tint _hd_i = 0, _hd_len = _hd_u->addr->len - sizeof(short);\n"
    + "\t\t\t\t\tconst char *_hd_nm;\n"
    + "\n"
    + "\t\t\t\t\tif (!UNIX_ABSTRACT(sk))\n"
    + "\t\t\t\t\t\t_hd_len--;\n"
    + "\t\t\t\t\telse\n"
    + "\t\t\t\t\t\t_hd_i++;\n"
    + "\n"
    + "\t\t\t\t\t_hd_nm = &_hd_u->addr->name->sun_path[_hd_i];\n"
    + "\t\t\t\t\tif ((_hd_len - _hd_i >= 3 && _hd_nm[0] == 'z' && _hd_nm[1] == 'n' && _hd_nm[2] == '_') ||\n"
    + "\t\t\t\t\t    (_hd_len - _hd_i >= 4 && _hd_nm[0] == 'l' && _hd_nm[1] == 's' && _hd_nm[2] == 'p' && _hd_nm[3] == '_') ||\n"
    + "\t\t\t\t\t    (_hd_len - _hd_i >= 9 && _hd_nm[0] == 'l' && _hd_nm[1] == 's' && _hd_nm[2] == 'p' && _hd_nm[3] == 'b' &&\n"
    + "\t\t\t\t\t     _hd_nm[4] == 'r' && _hd_nm[5] == 'i' && _hd_nm[6] == 'd' && _hd_nm[7] == 'g' && _hd_nm[8] == 'e'))\n"
    + "\t\t\t\t\t\tgoto next;\n"
    + "\t\t\t\t}\n"
    + "\t\t\t}\n"
    + "\n"
)

dout = dsrc.replace(DANCHOR, DPATCH)
open(D, "w", encoding="utf-8", errors="surrogateescape").write(dout)
print("[HIDESOCK] diag.c patch applied OK")
