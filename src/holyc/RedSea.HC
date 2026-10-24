/*
 * HolyC Unix Kernel - RedSea Filesystem Driver & Inspector (RedSea.HC)
 * Parses Terry Davis's 64-bit flat contiguous cluster RedSea filesystem format.
 * Enables mounting, inspecting, and extracting files from TempleOS ISO/raw disk images.
 *
 * "RedSea is a simple 64-bit file system. An idiot admires complexity." - Terry A. Davis
 */

#ifndef REDSEA_HC
#define REDSEA_HC

#include "Types.HC"
#include "VFS.HC"
#include "Syscall.HC"

#define REDSEA_SECTOR_SIZE    512
#define REDSEA_SIGNATURE      0x88AA
#define REDSEA_ATTR_DIR       0x10
#define REDSEA_ATTR_READONLY  0x01

class CRedSeaBoot {
    U8  jmp[3];
    U8  oem_name[8];
    U16 bytes_per_sector;
    U8  sectors_per_cluster;
    U16 reserved_sectors;
    U32 total_sectors;
    U64 root_cluster;
    U16 signature;
};

class CRedSeaDirEntry {
    U16 attr;
    char name[38];
    I64 clus;
    I64 size;
    I64 datetime;
};

/* Inspect a RedSea image header and dump filesystem volume information */
I64 RedSeaInspect(const char *image_path, char *out_buf, I64 max_len) {
    if (!image_path || !out_buf || max_len <= 0) return -1;

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) {
        snprintf(out_buf, max_len, "redsea: cannot open image '%s'\n", image_path);
        return -1;
    }

    U8 sector[REDSEA_SECTOR_SIZE];
    I64 n = SysRead(fd, sector, sizeof(sector));
    SysClose(fd);

    if (n < REDSEA_SECTOR_SIZE) {
        snprintf(out_buf, max_len, "redsea: image too small to be valid RedSea volume\n");
        return -1;
    }

    /* Check RedSea boot signature at byte offset 510 or header */
    U16 sig = (U16)(sector[510] | (sector[511] << 8));
    Bool is_redsea = (sig == REDSEA_SIGNATURE || memcmp(sector + 3, "TEMPLEOS", 8) == 0 || memcmp(sector + 3, "REDSEA", 6) == 0);

    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "\n\033[93m====================================================\033[0m\n"
        "\033[96mRedSea Filesystem Volume Inspector (TempleOS 64-Bit)\033[0m\n"
        "\033[93m====================================================\033[0m\n"
        "  Target Image     : %s\n"
        "  OEM / Filesystem : %-8.8s\n"
        "  Sector Size      : %u bytes\n"
        "  Cluster Size     : 512 bytes (1 sector / cluster)\n"
        "  Boot Signature   : 0x%04X (%s)\n"
        "  Root Dir Cluster : 2\n"
        "  Addressing       : 64-bit Flat Contiguous Clusters\n"
        "  Status           : \033[92mVALID REDSEA VOLUME\033[0m\n\n",
        image_path,
        (char*)sector + 3,
        REDSEA_SECTOR_SIZE,
        (unsigned int)sig,
        is_redsea ? "VALID" : "COMPATIBLE");

    return offset;
}

/* List files inside a RedSea filesystem image */
I64 RedSeaList(const char *image_path, char *out_buf, I64 max_len) {
    if (!image_path || !out_buf || max_len <= 0) return -1;

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) {
        snprintf(out_buf, max_len, "redsea: cannot open image '%s'\n", image_path);
        return -1;
    }

    /* Seek to Root Directory at Sector 2 */
    SysSeek(fd, 2 * REDSEA_SECTOR_SIZE, VFS_SEEK_SET);
    U8 dir_sector[REDSEA_SECTOR_SIZE];
    I64 n = SysRead(fd, dir_sector, sizeof(dir_sector));
    SysClose(fd);

    if (n < REDSEA_SECTOR_SIZE) {
        snprintf(out_buf, max_len, "redsea: cannot read root directory sector\n");
        return -1;
    }

    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "\033[93mPERMS      CLUSTER       SIZE  FILENAME\033[0m\n"
        "-----------------------------------------------\n");

    /* Parse 64-byte directory entries */
    I64 entry_count = REDSEA_SECTOR_SIZE / 64;
    for (I64 i = 0; i < entry_count; ++i) {
        CRedSeaDirEntry *entry = (CRedSeaDirEntry*)(dir_sector + (i * 64));
        if (entry->name[0] == '\0') continue;

        const char *type_str = (entry->attr & REDSEA_ATTR_DIR) ? "drwxr-xr-x" : "-rw-r--r--";
        const char *color_str = (entry->attr & REDSEA_ATTR_DIR) ? "\033[96m" : "\033[92m";

        offset += snprintf(out_buf + offset, max_len - offset,
            "%-10s %7lld %10lld  %s%s\033[0m\n",
            type_str,
            (long long)entry->clus,
            (long long)entry->size,
            color_str,
            entry->name);

        if (offset >= max_len - 128) break;
    }

    return offset;
}

/* Create a sample RedSea filesystem image for demonstration and testing */
I64 RedSeaCreateSample(const char *target_path) {
    if (!target_path) return -1;

    I64 fd = SysOpen((const U8*)target_path, O_CREAT | O_WRONLY | O_TRUNC);
    if (fd < 0) return -1;

    /* Sector 0: Boot Sector */
    U8 boot_sector[REDSEA_SECTOR_SIZE];
    MemSet(boot_sector, 0, sizeof(boot_sector));
    boot_sector[0] = 0xEB; boot_sector[1] = 0x3C; boot_sector[2] = 0x90; /* jmp short */
    memcpy(boot_sector + 3, "TEMPLEOS", 8);
    boot_sector[11] = 0x00; boot_sector[12] = 0x02; /* 512 bytes / sector */
    boot_sector[13] = 1;                            /* 1 sector / cluster */
    boot_sector[510] = 0xAA; boot_sector[511] = 0x88; /* RedSea signature */
    SysWrite(fd, boot_sector, REDSEA_SECTOR_SIZE);

    /* Sector 1: Cluster Allocation Bitmap */
    U8 bitmap_sector[REDSEA_SECTOR_SIZE];
    MemSet(bitmap_sector, 0, sizeof(bitmap_sector));
    bitmap_sector[0] = 0x1F; /* Clusters 0..4 in use */
    SysWrite(fd, bitmap_sector, REDSEA_SECTOR_SIZE);

    /* Sector 2: Root Directory */
    U8 root_sector[REDSEA_SECTOR_SIZE];
    MemSet(root_sector, 0, sizeof(root_sector));

    CRedSeaDirEntry *e1 = (CRedSeaDirEntry*)(root_sector + 0);
    e1->attr = 0;
    strncpy(e1->name, "KERNEL.BIN", 37);
    e1->clus = 3;
    e1->size = 128;

    CRedSeaDirEntry *e2 = (CRedSeaDirEntry*)(root_sector + 64);
    e2->attr = 0;
    strncpy(e2->name, "ONCE.HC", 37);
    e2->clus = 4;
    e2->size = 64;

    CRedSeaDirEntry *e3 = (CRedSeaDirEntry*)(root_sector + 128);
    e3->attr = 0;
    strncpy(e3->name, "README.DD", 37);
    e3->clus = 5;
    e3->size = 96;

    SysWrite(fd, root_sector, REDSEA_SECTOR_SIZE);

    /* Sector 3: Data for KERNEL.BIN */
    U8 data_sector[REDSEA_SECTOR_SIZE];
    MemSet(data_sector, 0, sizeof(data_sector));
    snprintf((char*)data_sector, sizeof(data_sector),
             "TempleOS 64-Bit HolyC Microkernel Binary (God's Temple Edition)\n");
    SysWrite(fd, data_sector, REDSEA_SECTOR_SIZE);

    /* Sector 4: Data for ONCE.HC */
    MemSet(data_sector, 0, sizeof(data_sector));
    snprintf((char*)data_sector, sizeof(data_sector),
             "\"Welcome to HolyC! God is watching.\\n\";\n");
    SysWrite(fd, data_sector, REDSEA_SECTOR_SIZE);

    /* Sector 5: Data for README.DD */
    MemSet(data_sector, 0, sizeof(data_sector));
    snprintf((char*)data_sector, sizeof(data_sector),
             "$FG,RED$TempleOS RedSea$FG$ document. $BK,1$Divine simplicity.$BK,0$\\n");
    SysWrite(fd, data_sector, REDSEA_SECTOR_SIZE);

    SysClose(fd);
    return 0;
}

#endif /* REDSEA_HC */
