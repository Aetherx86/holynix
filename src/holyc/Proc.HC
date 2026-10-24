/*
 * HolyC Unix Kernel - ProcFS Driver (Proc.HC)
 * Virtual pseudo-filesystem exposing kernel runtime diagnostics and task metrics.
 */

#ifndef PROC_HC
#define PROC_HC

#include "Types.HC"
#include "VFS.HC"

/* Forward declarations */
extern I64 KernelGetUptimeSec();
extern I64 KernelGetTicks();
extern I64 KernelFormatProcTasks(U8 *buf, I64 max_len);

static I64 ProcVersionRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    static const char ver_str[] =
        "HolyC Unix Kernel (TerryDavis-Edition) version 1.0.0-holyc (x86_64/arm64)\n"
        "TempleOS-Compatible 64-Bit Micro-Kernel & Terminal OS\n"
        "God's Chosen Operating System. Compiled with HolyC on macOS Darwin.\n";
    I64 len = StrLen((const U8*)ver_str);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)ver_str + offset, to_copy);
    return to_copy;
}

static I64 ProcUptimeRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    U8 tmp[128];
    I64 sec = KernelGetUptimeSec();
    I64 ms = GetTimestampMs();
    I64 centi = (ms % 1000) / 10;
    snprintf((char*)tmp, sizeof(tmp), "%lld.%02lld %lld.%02lld\n",
             (long long)sec, (long long)centi, (long long)sec, (long long)centi);
    I64 len = StrLen(tmp);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, tmp + offset, to_copy);
    return to_copy;
}

static I64 ProcLoadavgRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    static const char load_str[] = "0.08 0.02 0.01 1/64 1\n";
    I64 len = StrLen((const U8*)load_str);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)load_str + offset, to_copy);
    return to_copy;
}

static I64 ProcMemInfoRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    U8 tmp[512];
    snprintf((char*)tmp, sizeof(tmp),
        "MemTotal:       65536 kB\n"
        "MemFree:        49152 kB\n"
        "MemAvailable:   53248 kB\n"
        "Buffers:         2048 kB\n"
        "Cached:          8192 kB\n"
        "KernelHeap:      4096 kB\n"
        "VFSInodes:       %lld\n"
        "TempleOS Ring:   64-bit Flat Memory (No paging tricks)\n",
        (long long)g_inode_count);
    I64 len = StrLen(tmp);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, tmp + offset, to_copy);
    return to_copy;
}

static I64 ProcCpuInfoRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    static const char cpu_str[] =
        "processor       : 0\n"
        "vendor_id       : TempleOS Divine Silicon\n"
        "model name      : 64-Bit HolyC Engine (God's Divine Core)\n"
        "cpu MHz         : 3200.000\n"
        "cache size      : 16384 KB\n"
        "flags           : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov holyc ring0\n"
        "bogomips        : 6400.00\n";
    I64 len = StrLen((const U8*)cpu_str);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)cpu_str + offset, to_copy);
    return to_copy;
}

static I64 ProcTasksRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    U8 *tasks_buf = (U8*)MAlloc(4096);
    I64 len = KernelFormatProcTasks(tasks_buf, 4096);
    I64 result = 0;
    if (offset < len) {
        I64 to_copy = Min(len - offset, count);
        MemCpy(buf, tasks_buf + offset, to_copy);
        result = to_copy;
    }
    Free(tasks_buf);
    return result;
}

U0 ProcRegisterNode(const U8 *name, DeviceReadFn rfn) {
    I64 proc_dir = VFSResolvePath("/proc", "/");
    if (proc_dir < 0) return;

    I64 inum = VFSAllocInode(name, VFS_PROC, proc_dir);
    if (inum >= 0) {
        CVFSInode *node = VFSGetInode(inum);
        node->read_fn = rfn;
        node->permissions = 0444;
    }
}

U0 ProcInit() {
    ProcRegisterNode("version", ProcVersionRead);
    ProcRegisterNode("uptime", ProcUptimeRead);
    ProcRegisterNode("loadavg", ProcLoadavgRead);
    ProcRegisterNode("meminfo", ProcMemInfoRead);
    ProcRegisterNode("cpuinfo", ProcCpuInfoRead);
    ProcRegisterNode("tasks", ProcTasksRead);
}

#endif /* PROC_HC */
