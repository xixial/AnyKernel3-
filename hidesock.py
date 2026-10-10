#!/usr/bin/env python3
"""[HIDESOCK] 从 /proc/net/unix 隐藏 zn_/lsp_/lspbridge 命名的 socket。"""
import sys

P = sys.argv[1] if len(sys.argv) > 1 else "common/net/unix/af_unix.c"
src = open(P, "r", encoding="utf-8", errors="surrogateescape").read()

if "[HIDESOCK]" in src:
    print("[HIDESOCK] already patched, skip.")
    sys.exit(0)

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
