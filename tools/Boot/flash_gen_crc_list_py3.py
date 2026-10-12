#!/usr/bin/env python3
# flash_gen_crc_list.py 的 Python 3 移植版（原版是 py2，本机跑不了）
# 关键修正：chunk.bksz/chunk.data_sz -> // 整数除法
from __future__ import print_function
import os, copy, struct, binascii

sparse_file_list = {
    "super": "super.img",
    "userdata": "userdata.img",
    "metadata": "metadata.img",
    "vm-bootsys_ab": "vm-bootsys.img",
    "rescue": "rescue.img",
}

unsparse_file_list = {
    "xbl_ab": "xbl_s.melf", "xbl_config_ab": "xbl_config.elf", "shrm_ab": "shrm.elf",
    "uefi_ab": "uefi.elf", "uefisecapp_ab": "uefi_sec.elf", "xbl_ramdump_ab": "XblRamdump.elf",
    "aop_ab": "aop.mbn", "aop_config_ab": "aop_devcfg.mbn", "abl_ab": "abl.elf",
    "tz_ab": "tz.mbn", "featenabler_ab": "featenabler.mbn", "devcfg_ab": "devcfg.mbn",
    "hyp_ab": "hypvmperformance.mbn", "keymaster_ab": "keymint.mbn", "modem_ab": "NON-HLOS.bin",
    "bluetooth_ab": "BTFM.bin", "dsp_ab": "dspso.bin", "qupfw_ab": "qupv3fw.elf",
    "imagefv_ab": "imagefv.elf", "multiimgoem_ab": "multi_image.mbn", "cpucp_ab": "cpucp.elf",
    "logfs": "logfs_ufs_8mb.bin", "storsec": "storsec.mbn", "vendor_boot_ab": "vendor_boot.img",
    "dtbo_ab": "dtbo.img", "vbmeta_ab": "vbmeta.img", "vbmeta_system_ab": "vbmeta_system.img",
    "recovery_ab": "recovery.img", "boot_ab": "boot.img", "vm-bootsys_ab": "vm-bootsys.img",
    "multiimgqti_ab": "multi_image_qti.mbn", "toolsfv": "tools.fv", "init_boot_ab": "init_boot.img",
    "misc": "misc.img",
}

MAX_DOWNLOAD_SIZE = 768 * 1024 * 1024
MAX_SPARSE_PARTS = 20
SPARSE_IMAGE_HEAD_SZ = 28
SPARSE_CHUNK_HEAD_SZ = 12
SPARSE_OVER_HEAD_SZ = SPARSE_IMAGE_HEAD_SZ + 2 * SPARSE_CHUNK_HEAD_SZ + 4

file_list = dict(unsparse_file_list, **sparse_file_list)


class SparseChunk:
    def __init__(self):
        self.type = 0
        self.size = 0
        self.total_sz = 0
        self.data_sz = 0
        self.bksz = 0
        self.data = b''


def split_sparse_chunk(backed_sz, bck, sck):
    split_max_len = MAX_DOWNLOAD_SIZE - SPARSE_OVER_HEAD_SZ
    backed_real_sz = backed_sz[0] - SPARSE_CHUNK_HEAD_SZ - 4

    if backed_real_sz + bck.data_sz <= split_max_len:
        backed_sz[0] += bck.total_sz
        return 0, 0
    elif backed_real_sz >= (split_max_len * 7) // 8:
        if bck.total_sz <= split_max_len:
            backed_sz[0] = bck.total_sz + SPARSE_IMAGE_HEAD_SZ + SPARSE_CHUNK_HEAD_SZ
            return 0, 1
        else:
            over_flag = 1
            backed_real_sz = 0
    else:
        over_flag = 0

    split_sz = bck.bksz * ((split_max_len - backed_real_sz) // bck.bksz)

    sck.type = bck.type
    sck.bksz = bck.bksz
    sck.data_sz = bck.data_sz - split_sz
    sck.total_sz = sck.data_sz + SPARSE_CHUNK_HEAD_SZ
    sck.data = bck.data[split_sz:]
    sck.size = (sck.total_sz - SPARSE_CHUNK_HEAD_SZ) // sck.bksz

    bck.data_sz = split_sz
    bck.total_sz = bck.data_sz + SPARSE_CHUNK_HEAD_SZ
    bck.data = bck.data[:bck.data_sz]
    bck.size = (bck.total_sz - SPARSE_CHUNK_HEAD_SZ) // bck.bksz

    if over_flag == 1:
        backed_sz[0] = bck.total_sz
        return 1, 1
    else:
        backed_sz[0] = SPARSE_CHUNK_HEAD_SZ + SPARSE_IMAGE_HEAD_SZ
        return 1, 2


def read_chunk_from_file(FH, blk_sz):
    chunk = SparseChunk()
    header_bin = FH.read(12)
    header = struct.unpack("<2H2I", header_bin)
    chunk.type = header[0]
    chunk.size = header[2]
    chunk.total_sz = header[3]
    chunk.bksz = blk_sz
    chunk.data_sz = chunk.total_sz - SPARSE_CHUNK_HEAD_SZ
    if chunk.type == 0xCAC1:
        if chunk.data_sz != (chunk.size * blk_sz):
            raise Exception("Raw chunk size mismatch: %u vs %u" % (chunk.data_sz, chunk.size * blk_sz))
        chunk.data = FH.read(chunk.data_sz)
    elif chunk.type == 0xCAC2:
        if chunk.data_sz != 4:
            raise Exception("Fill chunk data size must be 4, got %u" % chunk.data_sz)
        chunk.data = FH.read(chunk.data_sz)
    elif chunk.type == 0xCAC3:
        chunk.data = b''
    else:
        raise Exception("Unknown chunk type 0x%04X" % chunk.type)
    return chunk


def calulate_sparse_chunk_crc(chunk, crc):
    if chunk.type == 0xCAC1:
        crc = binascii.crc32(chunk.data, crc)
    elif chunk.type == 0xCAC2:
        fill_buf = chunk.data * (chunk.bksz // chunk.data_sz)   # py3 整数除法
        for j in range(0, chunk.size):
            crc = binascii.crc32(fill_buf, crc)
    return crc


def gen_sparse_crc(path):
    sparse_parts = 0
    crc_result_list = [0 for i in range(MAX_SPARSE_PARTS)]
    backedsize = [SPARSE_IMAGE_HEAD_SZ]

    FH = open(path, 'rb')
    header_bin = FH.read(SPARSE_IMAGE_HEAD_SZ)
    header = struct.unpack("<I4H4I", header_bin)
    magic, major_version, minor_version, file_hdr_sz, chunk_hdr_sz, blk_sz, total_blks, total_chunks, image_checksum = header
    if magic != 0xED26FF3A:
        raise Exception("%s: bad magic" % path)
    print("%s: %u blocks, %u chunks" % (os.path.basename(path), total_blks, total_chunks))

    for i in range(0, total_chunks):
        rchunk = read_chunk_from_file(FH, blk_sz)
        split_flag = 1
        sck = SparseChunk()
        while split_flag == 1:
            split_flag, sparse_part = split_sparse_chunk(backedsize, rchunk, sck)
            if sparse_part == 1:
                sparse_parts += 1
            if sparse_parts >= MAX_SPARSE_PARTS:
                raise Exception("too many parts")
            crc_result_list[sparse_parts] = calulate_sparse_chunk_crc(rchunk, crc_result_list[sparse_parts])
            if sparse_part == 2:
                sparse_parts += 1
            rchunk = copy.deepcopy(sck)
    FH.close()
    return sparse_parts + 1, crc_result_list


def gen_crc(file_path):
    f = open(file_path, "rb")
    crc = binascii.crc32(f.read())
    f.close()
    return crc


if __name__ == "__main__":
    thispath = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(thispath, 'images')
    crclist = os.path.join(path, 'crclist.txt')
    sparsecrclist = os.path.join(path, 'sparsecrclist.txt')
    crc = 0
    fs = open(sparsecrclist, 'w')
    f = open(crclist, 'w')
    fs.write("SPARSECRC-LIST\n")
    f.write("CRC-LIST\n")
    for ptn in file_list:
        filepath = os.path.join(path, file_list[ptn])
        if not os.path.isfile(filepath):
            print(filepath + " missing, skip")
            continue
        if ptn in unsparse_file_list:
            crc = gen_crc(filepath)
            if crc:
                f.write(ptn + ' ' + hex(crc & (2**32 - 1)) + '\n')
                print("  CRC %s = %s" % (ptn, hex(crc & (2**32 - 1))))
        else:
            parts, crclist_out = gen_sparse_crc(filepath)
            if parts == 0:
                raise Exception("sparse file error")
            fs.write(ptn + ' ' + str(parts))
            for i in range(1, parts + 1):
                fs.write(' ' + hex(crclist_out[i - 1] & (2**32 - 1)))
            fs.write('\n')
            print("  SPARSE %s: %d parts" % (ptn, parts))
    fs.close()
    f.close()
    print("done")
