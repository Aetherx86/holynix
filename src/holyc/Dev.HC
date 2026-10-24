/*
 * HolyC Unix Kernel - Device Drivers (Dev.HC)
 * Implements /dev/tty, /dev/null, /dev/zero, /dev/random, and /dev/god.
 */

#ifndef DEV_HC
#define DEV_HC

#include "Types.HC"
#include "VFS.HC"
#include "GodWords.HC"

/* Forward declaration of terminal I/O functions */
extern I64 TermRead(U8 *buf, I64 count);
extern I64 TermWrite(const U8 *buf, I64 count);

static I64 DevTtyRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)offset;
    return TermRead(buf, count);
}

static I64 DevTtyWrite(CVFSInode *inode, const U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)offset;
    return TermWrite(buf, count);
}

static I64 DevNullRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)buf; (U0)count; (U0)offset;
    return 0; /* EOF */
}

static I64 DevNullWrite(CVFSInode *inode, const U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)buf; (U0)offset;
    return count; /* Discard bytes, report success */
}

static I64 DevZeroRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)offset;
    if (buf && count > 0) {
        MemSet(buf, 0, count);
        return count;
    }
    return 0;
}

static I64 DevZeroWrite(CVFSInode *inode, const U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)buf; (U0)offset;
    return count;
}

static I64 DevRandomRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)offset;
    if (!buf || count <= 0) return 0;
    for (I64 i = 0; i < count; ++i) {
        buf[i] = (U8)(RandU64() & 0xFF);
    }
    return count;
}

static I64 DevGodRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)offset;
    return GodStreamRead(buf, count);
}

/* /dev/mem: Direct memory peeker driver */
static I64 DevMemRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    if (!buf || count <= 0) return 0;
    /* Safe memory peeker reading simulated kernel text/data space */
    for (I64 i = 0; i < count; ++i) {
        I64 addr = offset + i;
        buf[i] = (U8)(((addr * 37) ^ (addr >> 8) ^ 0x5A) & 0xFF);
    }
    return count;
}

static I64 DevMemWrite(CVFSInode *inode, const U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)buf; (U0)offset;
    return count;
}

/* /dev/tcp: Virtual TCP stream */
static I64 DevTcpRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)offset;
    static const char tcp_resp[] = "HTTP/1.1 200 OK\r\nServer: HolyNix-Oracle/1.0\r\n\r\nGod says: simplicity is divine\n";
    I64 len = StrLen((const U8*)tcp_resp);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)tcp_resp + offset, to_copy);
    return to_copy;
}

static I64 DevTcpWrite(CVFSInode *inode, const U8 *buf, I64 count, I64 offset) {
    (U0)inode; (U0)buf; (U0)offset;
    return count;
}

U0 DevRegisterCharDevice(const U8 *name, DeviceReadFn rfn, DeviceWriteFn wfn) {
    I64 dev_dir = VFSResolvePath("/dev", "/");
    if (dev_dir < 0) return;

    I64 inum = VFSAllocInode(name, VFS_CHARDEV, dev_dir);
    if (inum >= 0) {
        CVFSInode *node = VFSGetInode(inum);
        node->read_fn = rfn;
        node->write_fn = wfn;
        node->permissions = 0666;
    }
}

U0 DevInit() {
    DevRegisterCharDevice("tty", DevTtyRead, DevTtyWrite);
    DevRegisterCharDevice("null", DevNullRead, DevNullWrite);
    DevRegisterCharDevice("zero", DevZeroRead, DevZeroWrite);
    DevRegisterCharDevice("random", DevRandomRead, DevZeroWrite);
    DevRegisterCharDevice("god", DevGodRead, DevNullWrite);
    DevRegisterCharDevice("mem", DevMemRead, DevMemWrite);
    DevRegisterCharDevice("tcp", DevTcpRead, DevTcpWrite);
}

#endif /* DEV_HC */
