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

static char g_sysctl_osname[64] = "HolyNix";
static char g_sysctl_hostname[64] = "holy-unix";
static char g_sysctl_version[64] = "1.0.0-holyc";

static I64 ProcNetDevRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    static const char net_str[] =
        "Inter-|   Receive                                                |  Transmit\n"
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n"
        "    lo:    8192     128    0    0    0     0          0         0     8192     128    0    0    0     0       0          0\n"
        "  eth0:   65536    1024    0    0    0     0          0         0    49152     896    0    0    0     0       0          0\n";
    I64 len = StrLen((const U8*)net_str);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)net_str + offset, to_copy);
    return to_copy;
}

static I64 ProcNetTcpRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    static const char tcp_str[] =
        "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"
        "   0: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 1204 1 00000000 100 0 0 10 -1\n"
        "   1: 00000000:0050 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 1205 1 00000000 100 0 0 10 -1\n"
        "   2: 00000000:1E61 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 7777 1 00000000 100 0 0 10 -1\n";
    I64 len = StrLen((const U8*)tcp_str);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)tcp_str + offset, to_copy);
    return to_copy;
}

static I64 ProcSysOsnameRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    char tmp[128];
    snprintf(tmp, sizeof(tmp), "%s\n", g_sysctl_osname);
    I64 len = StrLen((const U8*)tmp);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)tmp + offset, to_copy);
    return to_copy;
}

static I64 ProcSysHostnameRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    char tmp[128];
    snprintf(tmp, sizeof(tmp), "%s\n", g_sysctl_hostname);
    I64 len = StrLen((const U8*)tmp);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)tmp + offset, to_copy);
    return to_copy;
}

static I64 ProcSysVersionRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    char tmp[128];
    snprintf(tmp, sizeof(tmp), "%s\n", g_sysctl_version);
    I64 len = StrLen((const U8*)tmp);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)tmp + offset, to_copy);
    return to_copy;
}

extern I64 ModuleFormatProc(char *out_buf, I64 max_len);

static I64 ProcModulesRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    char tmp[1024];
    I64 len = ModuleFormatProc(tmp, sizeof(tmp));
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)tmp + offset, to_copy);
    return to_copy;
}

static I64 ProcVmstatRead(CVFSInode *inode, U8 *buf, I64 count, I64 offset) {
    (U0)inode;
    static const char vm_str[] =
        "nr_free_pages 12288\n"
        "nr_alloc_batch 16\n"
        "nr_inactive_anon 2048\n"
        "nr_active_anon 4096\n"
        "nr_inactive_file 1024\n"
        "nr_active_file 2048\n"
        "nr_unevictable 0\n"
        "nr_mlock 0\n"
        "nr_anon_pages 4096\n"
        "nr_mapped 1024\n"
        "nr_file_pages 3072\n"
        "nr_dirty 0\n"
        "nr_writeback 0\n"
        "pgpgin 65536\n"
        "pgpgout 49152\n"
        "pswpin 0\n"
        "pswpout 0\n";
    I64 len = StrLen((const U8*)vm_str);
    if (offset >= len) return 0;
    I64 to_copy = Min(len - offset, count);
    MemCpy(buf, (const U8*)vm_str + offset, to_copy);
    return to_copy;
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
    ProcRegisterNode("modules", ProcModulesRead);
    ProcRegisterNode("vmstat", ProcVmstatRead);

    /* Create /proc/net and /proc/sys/kernel directories */
    VFSMkdir("net", "/proc");
    VFSMkdir("sys", "/proc");
    VFSMkdir("kernel", "/proc/sys");

    I64 net_dir = VFSResolvePath("/proc/net", "/");
    if (net_dir >= 0) {
        I64 inum_dev = VFSAllocInode("dev", VFS_PROC, net_dir);
        if (inum_dev >= 0) {
            CVFSInode *node = VFSGetInode(inum_dev);
            node->read_fn = ProcNetDevRead;
            node->permissions = 0444;
        }
        I64 inum_tcp = VFSAllocInode("tcp", VFS_PROC, net_dir);
        if (inum_tcp >= 0) {
            CVFSInode *node = VFSGetInode(inum_tcp);
            node->read_fn = ProcNetTcpRead;
            node->permissions = 0444;
        }
    }

    I64 sys_dir = VFSResolvePath("/proc/sys/kernel", "/");
    if (sys_dir >= 0) {
        I64 inum_os = VFSAllocInode("osname", VFS_PROC, sys_dir);
        if (inum_os >= 0) {
            CVFSInode *node = VFSGetInode(inum_os);
            node->read_fn = ProcSysOsnameRead;
            node->permissions = 0644;
        }
        I64 inum_host = VFSAllocInode("hostname", VFS_PROC, sys_dir);
        if (inum_host >= 0) {
            CVFSInode *node = VFSGetInode(inum_host);
            node->read_fn = ProcSysHostnameRead;
            node->permissions = 0644;
        }
        I64 inum_ver = VFSAllocInode("version", VFS_PROC, sys_dir);
        if (inum_ver >= 0) {
            CVFSInode *node = VFSGetInode(inum_ver);
            node->read_fn = ProcSysVersionRead;
            node->permissions = 0644;
        }
    }
}

#endif /* PROC_HC */
