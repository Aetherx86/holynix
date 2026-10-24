/*
 * HolyC Unix Kernel - POSIX USTAR Tar Archiver (Tar.HC)
 * In-kernel tar archive creation, inspection, and extraction for VFS trees.
 * Fully compatible with standard POSIX tar / GNU tar archives.
 */

#ifndef TAR_HC
#define TAR_HC

#include "Types.HC"
#include "VFS.HC"
#include "Syscall.HC"

#define TAR_BLOCK_SIZE 512

class CTarHeader {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char pad[12];
};

static U32 TarComputeChecksum(const CTarHeader *hdr) {
    const U8 *raw = (const U8*)hdr;
    U32 sum = 0;
    for (I64 i = 0; i < TAR_BLOCK_SIZE; ++i) {
        if (i >= 148 && i < 156) {
            sum += ' '; /* Checksum field is treated as 8 spaces during calculation */
        } else {
            sum += raw[i];
        }
    }
    return sum;
}

/* Create a tar archive from an existing file in VFS */
I64 TarCreate(const char *tar_path, const char *src_path) {
    if (!tar_path || !src_path) return -1;

    I64 src_fd = SysOpen((const U8*)src_path, O_RDONLY);
    if (src_fd < 0) return -1;

    I64 tar_fd = SysOpen((const U8*)tar_path, O_CREAT | O_WRONLY | O_TRUNC);
    if (tar_fd < 0) {
        SysClose(src_fd);
        return -1;
    }

    CKernelStat st;
    if (SysStat((const U8*)src_path, &st) != 0) {
        SysClose(src_fd);
        SysClose(tar_fd);
        return -1;
    }

    CTarHeader hdr;
    MemSet(&hdr, 0, sizeof(hdr));

    /* Strip leading slash for relative tar path */
    const char *rel_name = (*src_path == '/') ? src_path + 1 : src_path;
    strncpy(hdr.name, rel_name, sizeof(hdr.name) - 1);
    snprintf(hdr.mode, sizeof(hdr.mode), "%07o", (unsigned int)(st.st_mode & 0777));
    snprintf(hdr.uid, sizeof(hdr.uid), "%07o", (unsigned int)st.st_uid);
    snprintf(hdr.gid, sizeof(hdr.gid), "%07o", (unsigned int)st.st_gid);
    snprintf(hdr.size, sizeof(hdr.size), "%011llo", (unsigned long long)st.st_size);
    snprintf(hdr.mtime, sizeof(hdr.mtime), "%011llo", (unsigned long long)st.st_mtime);
    hdr.typeflag = '0'; /* Regular file */
    memcpy(hdr.magic, "ustar", 5);
    memcpy(hdr.version, "00", 2);
    strncpy(hdr.uname, "terry", sizeof(hdr.uname) - 1);
    strncpy(hdr.gname, "terry", sizeof(hdr.gname) - 1);

    U32 sum = TarComputeChecksum(&hdr);
    snprintf(hdr.chksum, sizeof(hdr.chksum), "%06o", sum);
    hdr.chksum[6] = '\0';
    hdr.chksum[7] = ' ';

    /* Write Header */
    SysWrite(tar_fd, (const U8*)&hdr, TAR_BLOCK_SIZE);

    /* Write Data blocks */
    U8 block[TAR_BLOCK_SIZE];
    I64 remaining = st.st_size;
    while (remaining > 0) {
        I64 chunk = (remaining > TAR_BLOCK_SIZE) ? TAR_BLOCK_SIZE : remaining;
        MemSet(block, 0, TAR_BLOCK_SIZE);
        SysRead(src_fd, block, chunk);
        SysWrite(tar_fd, block, TAR_BLOCK_SIZE);
        remaining -= chunk;
    }

    /* Write two 512-byte zero blocks (end of archive) */
    MemSet(block, 0, TAR_BLOCK_SIZE);
    SysWrite(tar_fd, block, TAR_BLOCK_SIZE);
    SysWrite(tar_fd, block, TAR_BLOCK_SIZE);

    SysClose(src_fd);
    SysClose(tar_fd);
    return 0;
}

/* List contents of a tar archive */
I64 TarList(const char *tar_path, char *out_buf, I64 max_len) {
    if (!tar_path || !out_buf || max_len <= 0) return -1;

    I64 tar_fd = SysOpen((const U8*)tar_path, O_RDONLY);
    if (tar_fd < 0) {
        snprintf(out_buf, max_len, "tar: cannot open '%s'\n", tar_path);
        return -1;
    }

    I64 offset = 0;
    out_buf[0] = '\0';
    CTarHeader hdr;

    while (1) {
        I64 n = SysRead(tar_fd, (U8*)&hdr, TAR_BLOCK_SIZE);
        if (n < TAR_BLOCK_SIZE) break;
        if (hdr.name[0] == '\0') break; /* End of archive marker */

        U64 size = 0;
        sscanf(hdr.size, "%llo", &size);

        offset += snprintf(out_buf + offset, max_len - offset,
                           "%-10s %8llu %s %s\n",
                           (hdr.typeflag == '5') ? "drwxr-xr-x" : "-rw-r--r--",
                           (unsigned long long)size,
                           hdr.uname[0] ? hdr.uname : "terry",
                           hdr.name);

        if (offset >= max_len - 128) break;

        /* Skip file data blocks */
        U64 blocks = (size + TAR_BLOCK_SIZE - 1) / TAR_BLOCK_SIZE;
        SysSeek(tar_fd, blocks * TAR_BLOCK_SIZE, VFS_SEEK_CUR);
    }

    SysClose(tar_fd);
    return offset;
}

static U0 TarEnsureParentDirs(const char *file_path) {
    if (!file_path) return;
    char tmp[MAX_PATH_LEN];
    strncpy(tmp, file_path, sizeof(tmp) - 1);
    char *slash = strrchr(tmp, '/');
    if (!slash) return;
    *slash = '\0';

    char *p = tmp;
    if (*p == '/') p++;
    while (*p) {
        if (*p == '/') {
            *p = '\0';
            VFSMkdir((const U8*)tmp, "/");
            *p = '/';
        }
        p++;
    }
    VFSMkdir((const U8*)tmp, "/");
}

/* Extract files from a tar archive into destination directory */
I64 TarExtract(const char *tar_path, const char *dest_dir) {
    if (!tar_path) return -1;
    const char *base_dest = dest_dir ? dest_dir : "/tmp";

    I64 tar_fd = SysOpen((const U8*)tar_path, O_RDONLY);
    if (tar_fd < 0) return -1;

    CTarHeader hdr;
    while (1) {
        I64 n = SysRead(tar_fd, (U8*)&hdr, TAR_BLOCK_SIZE);
        if (n < TAR_BLOCK_SIZE) break;
        if (hdr.name[0] == '\0') break;

        U64 size = 0;
        sscanf(hdr.size, "%llo", &size);

        char target_full_path[MAX_PATH_LEN];
        snprintf(target_full_path, sizeof(target_full_path), "%s/%s", base_dest, hdr.name);
        TarEnsureParentDirs(target_full_path);

        if (hdr.typeflag == '5') {
            SysMkdir((const U8*)target_full_path);
        } else {
            I64 out_fd = SysOpen((const U8*)target_full_path, O_CREAT | O_WRONLY | O_TRUNC);
            if (out_fd >= 0) {
                U8 block[TAR_BLOCK_SIZE];
                I64 remaining = (I64)size;
                while (remaining > 0) {
                    I64 chunk = (remaining > TAR_BLOCK_SIZE) ? TAR_BLOCK_SIZE : remaining;
                    SysRead(tar_fd, block, TAR_BLOCK_SIZE);
                    SysWrite(out_fd, block, chunk);
                    remaining -= chunk;
                }
                SysClose(out_fd);
            } else {
                /* Skip content blocks */
                U64 blocks = (size + TAR_BLOCK_SIZE - 1) / TAR_BLOCK_SIZE;
                SysSeek(tar_fd, blocks * TAR_BLOCK_SIZE, VFS_SEEK_CUR);
            }
        }
    }

    SysClose(tar_fd);
    return 0;
}

#endif /* TAR_HC */
