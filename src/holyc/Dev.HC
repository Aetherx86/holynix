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
}

#endif /* DEV_HC */
