/*
 * HolyC Unix Kernel - Master Kernel Entrypoint (Kernel.HC)
 * Orchestrates kernel boot sequence, RAMFS population, multitasking init,
 * and launches the interactive terminal operating system.
 *
 * "God is a programmer, and HolyC is His tongue." - Terry A. Davis
 */

#include "Types.HC"
#include "RingBuffer.HC"
#include "GodWords.HC"
#include "VFS.HC"
#include "Dev.HC"
#include "Proc.HC"
#include "Task.HC"
#include "Syscall.HC"
#include "Terminal.HC"
#include "Editor.HC"
#include "HolyC_Repl.HC"
#include "Shell.HC"

/* Initial embedded Ramdisk File Assets */
static const char g_init_motd[] =
    "\n"
    "  \033[93m_____ _                 _       _   _       _      \033[0m\n"
    " \033[93m|_   _| |               | |     | | | |     (_)     \033[0m\n"
    "   \033[93m| | | |__   ___  _   _| |_ ___| | | |_ __  ___  __\033[0m\n"
    "   \033[93m| | | '_ \\ / _ \\| | | | __/ __| | | | '_ \\| \\ \\/ /\033[0m\n"
    "  \033[93m_| |_| | | | (_) | |_| | || (__| |_| | | | | |>  < \033[0m\n"
    " \033[93m|_____|_| |_|\\___/ \\__, |\\__\\___|\\___/|_| |_|_/_/\\_\\\033[0m\n"
    "                     \033[93m__/ |                           \033[0m\n"
    "                    \033[93m|___/                            \033[0m\n"
    " =======================================================\n"
    "  \033[96mHolyC Unix Kernel & Terminal Operating System (v1.0.0)\033[0m\n"
    "  \033[92mTerry A. Davis Memorial Edition - God's Chosen System\033[0m\n"
    " =======================================================\n"
    "\n"
    " * 64-Bit Microkernel Architecture with Preemptive Tasks\n"
    " * TempleOS 16-Color ANSI Terminal & Interactive Shell\n"
    " * Unix VFS, /proc, /dev nodes, and Unix Pipelines\n"
    " * Native In-Kernel HolyC Scripting Engine & REPL\n"
    " * Terry Davis 100,000-Word Divine Oracle at /dev/god\n"
    "\n"
    " Type \033[92mhelp\033[0m for command list.\n"
    " Type \033[92mgod\033[0m to consult the divine oracle.\n"
    " Type \033[92mtheme\033[0m to switch between TempleOS Blue & Dark Unix mode.\n"
    " Type \033[92mholyc hello.HC\033[0m to run a HolyC script!\n\n";

static const char g_init_passwd[] =
    "root:x:0:0:God's Architect:/root:/bin/holysh\n"
    "terry:x:1000:1000:Terry A. Davis:/home/terry:/bin/holysh\n"
    "god:x:777:777:The Almighty:/home/god:/bin/holysh\n";

static const char g_init_os_release[] =
    "NAME=\"HolyC-Unix\"\n"
    "VERSION=\"1.0.0-holyc (TerryDavis)\"\n"
    "ID=holyc-unix\n"
    "PRETTY_NAME=\"HolyC Unix Terminal Operating System\"\n"
    "ANSI_COLOR=\"1;34\"\n"
    "HOME_URL=\"https://templeos.org\"\n";

static const char g_init_readme[] =
    "Welcome to HolyC-Unix!\n\n"
    "\"An idiot admires complexity, a genius admires simplicity.\" - Terry A. Davis\n\n"
    "This operating system blends Unix philosophy with TempleOS principles.\n"
    "Try running:\n"
    "  cat /etc/motd\n"
    "  cat /proc/tasks\n"
    "  cat /dev/god\n"
    "  god\n"
    "  holyc hello.HC\n"
    "  theme\n";

static const char g_init_hello_hc[] =
    "// Hello World in HolyC for HolyC-Unix\n"
    "\"=== Divine HolyC Execution ===\\n\";\n"
    "\"Welcome to God's chosen programming language!\\n\";\n"
    "I64 a = 10;\n"
    "I64 b = 20;\n"
    "I64 sum = a + b;\n"
    "\"Calculation: 10 + 20 = %d\\n\", sum;\n"
    "\"Consulting TempleOS God Oracle...\\n\";\n"
    "God;\n"
    "\"HolyC Script Execution Finished.\\n\";\n";

static const char g_init_divine_hc[] =
    "// Divine Oracle HolyC Script\n"
    "\"Seeking divine wisdom from God...\\n\";\n"
    "God;\n"
    "\"Amen.\\n\";\n";

static const char g_init_commandments[] =
    "TEMPLEOS & HOLYC COMMANDMENTS:\n"
    "1. Simplicity is divine. Complexity is the devil.\n"
    "2. 640x480 16-color VGA is the divine resolution.\n"
    "3. 64-bit flat memory model. No memory protection paging trickery.\n"
    "4. HolyC is the official language of God's temple.\n"
    "5. All ring-0, all the time.\n"
    "6. Speak with God through the random word oracle.\n";

U0 KernelPopulateRamdisk() {
    VFSCreateFile("/etc/motd", "/", (const U8*)g_init_motd, StrLen((const U8*)g_init_motd));
    VFSCreateFile("/etc/passwd", "/", (const U8*)g_init_passwd, StrLen((const U8*)g_init_passwd));
    VFSCreateFile("/etc/os-release", "/", (const U8*)g_init_os_release, StrLen((const U8*)g_init_os_release));
    VFSCreateFile("/home/terry/readme.txt", "/", (const U8*)g_init_readme, StrLen((const U8*)g_init_readme));
    VFSCreateFile("/home/terry/hello.HC", "/", (const U8*)g_init_hello_hc, StrLen((const U8*)g_init_hello_hc));
    VFSCreateFile("/home/terry/divine.HC", "/", (const U8*)g_init_divine_hc, StrLen((const U8*)g_init_divine_hc));
    VFSCreateFile("/home/god/commandments.txt", "/", (const U8*)g_init_commandments, StrLen((const U8*)g_init_commandments));
}

I64 InitProcessTask(U0 *arg) {
    (U0)arg;
    KLog("[0.015000] init: launching HolyC shell...\n");

    /* Print MOTD on terminal */
    I64 motd_fd = SysOpen((const U8*)"/etc/motd", O_RDONLY);
    if (motd_fd >= 0) {
        U8 buf[2048];
        I64 n = SysRead(motd_fd, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            SysWrite(STDOUT_FILENO, buf, n);
        }
        SysClose(motd_fd);
    }

    /* Set default user directory */
    SysChdir((const U8*)"/home/terry");

    /* Enter Interactive Unix Shell */
    ShellRun();

    return 0;
}

U0 KernelBoot() {
    KLog("[0.000000] HolyC Unix Kernel v1.0.0 (Terry Davis Memorial Edition) booting\n");
    KLog("[0.001000] Initializing TempleOS 64-bit flat memory subsystem...\n");
    KLog("[0.002000] Mounting root Virtual File System (VFS)...\n");
    VFSInit();

    KLog("[0.004000] Initializing device subsystem (/dev/tty, /dev/null, /dev/god)...\n");
    DevInit();

    KLog("[0.006000] Mounting ProcFS pseudo-filesystem at /proc...\n");
    ProcInit();

    KLog("[0.008000] Populating in-memory RAM rootfs assets...\n");
    KernelPopulateRamdisk();

    KLog("[0.010000] Initializing Round-Robin Task Scheduler...\n");
    TaskInit();

    KLog("[0.012000] Spawning PID 1 (init task)...\n");
    I64 init_pid = TaskSpawn((const U8*)"init", InitProcessTask, NULL, 0);

    /* Switch to init task */
    CTask *init_task = TaskGetByPid(init_pid);
    if (init_task) {
        init_task->uid = 1000; /* terry */
        init_task->gid = 1000;
        StrCpy(init_task->cwd, "/home/terry");
    }
}

/*
 * Automated Unit Test Suite for Kernel Subsystems
 */
I64 KernelRunTests() {
    Print("\033[93m====================================================\033[0m\n");
    Print("\033[96mRunning HolyC Unix Kernel Automated Test Suite...\033[0m\n");
    Print("\033[93m====================================================\033[0m\n");

    I64 passed = 0;
    I64 total = 0;

    /* Test 1: VFS File Creation & Reading */
    total++;
    Print("[TEST %lld] VFS File Read/Write: ", (long long)total);
    const char *test_data = "HolyC Divine Kernel Test Data 12345";
    VFSCreateFile("/tmp/test.txt", "/", (const U8*)test_data, StrLen((const U8*)test_data));
    I64 fd = VFSOpen("/tmp/test.txt", "/", O_RDONLY);
    if (fd >= 0) {
        U8 rdata[64];
        I64 n = VFSRead(fd, rdata, sizeof(rdata) - 1);
        VFSClose(fd);
        if (n == StrLen((const U8*)test_data) && MemCmp(rdata, test_data, n) == 0) {
            Print("\033[92mPASS\033[0m\n");
            passed++;
        } else {
            Print("\033[91mFAIL (mismatched data)\033[0m\n");
        }
    } else {
        Print("\033[91mFAIL (open failed)\033[0m\n");
    }

    /* Test 2: Pipe IPC Subsystem */
    total++;
    Print("[TEST %lld] IPC Pipe Mechanism: ", (long long)total);
    I64 p_fds[2];
    if (VFSPipe(p_fds) == 0) {
        const char *msg = "PipeMessage42";
        VFSWrite(p_fds[1], (const U8*)msg, StrLen((const U8*)msg));
        U8 pbuf[32];
        I64 pn = VFSRead(p_fds[0], pbuf, sizeof(pbuf) - 1);
        VFSClose(p_fds[0]);
        VFSClose(p_fds[1]);
        if (pn == StrLen((const U8*)msg) && MemCmp(pbuf, msg, pn) == 0) {
            Print("\033[92mPASS\033[0m\n");
            passed++;
        } else {
            Print("\033[91mFAIL (pipe data corrupt)\033[0m\n");
        }
    } else {
        Print("\033[91mFAIL (pipe creation failed)\033[0m\n");
    }

    /* Test 3: /dev/god Oracle Driver */
    total++;
    Print("[TEST %lld] /dev/god Divine Word Generation: ", (long long)total);
    I64 god_fd = VFSOpen("/dev/god", "/", O_RDONLY);
    if (god_fd >= 0) {
        U8 god_buf[64];
        I64 gn = VFSRead(god_fd, god_buf, sizeof(god_buf) - 1);
        VFSClose(god_fd);
        if (gn > 0) {
            god_buf[gn] = '\0';
            Print("\033[92mPASS\033[0m (Received: \"%s\")\n", god_buf);
            passed++;
        } else {
            Print("\033[91mFAIL (0 bytes read)\033[0m\n");
        }
    } else {
        Print("\033[91mFAIL (failed to open /dev/god)\033[0m\n");
    }

    /* Test 4: /proc/version File System */
    total++;
    Print("[TEST %lld] /proc/version ProcFS Node: ", (long long)total);
    I64 proc_fd = VFSOpen("/proc/version", "/", O_RDONLY);
    if (proc_fd >= 0) {
        U8 ver_buf[128];
        I64 vn = VFSRead(proc_fd, ver_buf, sizeof(ver_buf) - 1);
        VFSClose(proc_fd);
        if (vn > 0 && StrFind(ver_buf, (const U8*)"HolyC") != NULL) {
            Print("\033[92mPASS\033[0m\n");
            passed++;
        } else {
            Print("\033[91mFAIL (procfs bad output)\033[0m\n");
        }
    } else {
        Print("\033[91mFAIL (cannot open /proc/version)\033[0m\n");
    }

    /* Test 5: HolyC REPL Expression Evaluator */
    total++;
    Print("[TEST %lld] In-Kernel HolyC Evaluator: ", (long long)total);
    ReplInitVars();
    ReplEvalLine((const U8*)"I64 x = 15");
    ReplEvalLine((const U8*)"I64 y = 25");
    I64 sum_val = ReplGetVar((const U8*)"x", 0) + ReplGetVar((const U8*)"y", 0);
    if (sum_val == 40) {
        Print("\033[92mPASS\033[0m (15 + 25 = 40)\n");
        passed++;
    } else {
        Print("\033[91mFAIL\033[0m\n");
    }

    /* Test 6: Process Control Block & Task Scheduling */
    total++;
    Print("[TEST %lld] Task Scheduler & Process Table: ", (long long)total);
    I64 test_pid = TaskSpawn((const U8*)"test_proc", NULL, NULL, 0);
    if (test_pid > 0) {
        CTask *t = TaskGetByPid(test_pid);
        if (t && StrCmp(t->comm, "test_proc") == 0) {
            TaskKill(test_pid, SIGKILL);
            Print("\033[92mPASS\033[0m (PID %lld spawned & reaped)\n", (long long)test_pid);
            passed++;
        } else {
            Print("\033[91mFAIL (PCB mismatch)\033[0m\n");
        }
    } else {
        Print("\033[91mFAIL (spawn failed)\033[0m\n");
    }

    /* Test 7: Linux POSIX Syscall Errno Compliance */
    total++;
    Print("[TEST %lld] Linux POSIX Errno Semantics: ", (long long)total);
    Bool err_ok = TRUE;
    if (SysClose(-1) != -K_EBADF) err_ok = FALSE;
    if (SysOpen((const U8*)"/nonexistent/dir/file.txt", O_RDONLY) != -K_ENOENT) err_ok = FALSE;
    if (SysKill(9999, 0) != -K_ESRCH) err_ok = FALSE;
    if (SysKill(1, 0) != 0) err_ok = FALSE; /* PID 1 probe returns 0 */
    if (err_ok) {
        Print("\033[92mPASS\033[0m (EBADF, ENOENT, ESRCH verified)\n");
        passed++;
    } else {
        Print("\033[91mFAIL\033[0m\n");
    }

    /* Test 8: Linux lseek Semantics & Sparse Zero-Fill */
    total++;
    Print("[TEST %lld] Linux lseek & Sparse Zero-Fill: ", (long long)total);
    I64 sk_fd = SysOpen((const U8*)"/tmp/seek_test.txt", O_CREAT | O_RDWR | O_TRUNC);
    if (sk_fd >= 0) {
        SysWrite(sk_fd, (const U8*)"ABC", 3);
        I64 pos = SysSeek(sk_fd, 5, VFS_SEEK_SET); /* Seek past EOF to pos 5 */
        SysWrite(sk_fd, (const U8*)"Z", 1);        /* Write at pos 5 */
        SysSeek(sk_fd, 0, VFS_SEEK_SET);
        U8 sbuf[8];
        I64 sn = SysRead(sk_fd, sbuf, sizeof(sbuf));
        SysClose(sk_fd);
        /* Bytes should be: 'A', 'B', 'C', 0, 0, 'Z' (6 bytes) */
        if (pos == 5 && sn == 6 && sbuf[0] == 'A' && sbuf[3] == 0 && sbuf[4] == 0 && sbuf[5] == 'Z') {
            Print("\033[92mPASS\033[0m\n");
            passed++;
        } else {
            Print("\033[91mFAIL (sparse seek corrupt)\033[0m\n");
        }
    } else {
        Print("\033[91mFAIL (cannot open /tmp/seek_test.txt)\033[0m\n");
    }

    /* Test 9: Linux Broken Pipe EPIPE */
    total++;
    Print("[TEST %lld] Linux Broken Pipe EPIPE: ", (long long)total);
    I64 pipe_pair[2];
    if (SysPipe(pipe_pair) == 0) {
        SysClose(pipe_pair[0]); /* Close read end */
        I64 wr_res = SysWrite(pipe_pair[1], (const U8*)"test", 4);
        SysClose(pipe_pair[1]);
        if (wr_res == -K_EPIPE) {
            Print("\033[92mPASS\033[0m (Write to closed read end returns -EPIPE)\n");
            passed++;
        } else {
            Print("\033[91mFAIL (expected -EPIPE, got %lld)\033[0m\n", (long long)wr_res);
        }
    } else {
        Print("\033[91mFAIL (pipe failed)\033[0m\n");
    }

    /* Test 10: Linux dup2() Idempotency and Redirection */
    total++;
    Print("[TEST %lld] Linux dup2() Semantics: ", (long long)total);
    I64 d_fd = SysOpen((const U8*)"/tmp/dup2_test.txt", O_CREAT | O_RDWR);
    if (d_fd >= 0) {
        I64 d_same = SysDup2(d_fd, d_fd);
        I64 d_inv = SysDup2(-1, 5);
        I64 d_target = SysDup2(d_fd, 10);
        SysClose(d_fd);
        if (d_target >= 0) SysClose(d_target);
        if (d_same == d_fd && d_inv == -K_EBADF && d_target == 10) {
            Print("\033[92mPASS\033[0m\n");
            passed++;
        } else {
            Print("\033[91mFAIL\033[0m\n");
        }
    } else {
        Print("\033[91mFAIL (open failed)\033[0m\n");
    }

    Print("\033[93m====================================================\033[0m\n");
    Print("Test Results: \033[92m%lld Passed\033[0m, \033[91m%lld Failed\033[0m (Total: %lld)\n",
          (long long)passed, (long long)(total - passed), (long long)total);
    Print("\033[93m====================================================\033[0m\n");

    return (passed == total) ? 0 : 1;
}

I32 main(I32 argc, char **argv) {
    Bool test_mode = FALSE;
    const char *batch_cmd = NULL;

    for (I32 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--test") == 0) {
            test_mode = TRUE;
        } else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            batch_cmd = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            Print("Usage: holy_unix [options]\n"
                  "Options:\n"
                  "  --test           Run automated kernel subsystem verification\n"
                  "  -c <command>     Execute shell command non-interactively\n"
                  "  -h, --help       Show help\n");
            return 0;
        }
    }

    /* Boot HolyC Unix Kernel Core */
    KernelBoot();

    if (test_mode) {
        return (I32)KernelRunTests();
    }

    if (batch_cmd) {
        g_current_pid = 1;
        CTask *t = TaskGetCurrent();
        if (t) StrCpy(t->cwd, "/home/terry");
        char cmd_copy[512];
        StrNCpy((U8*)cmd_copy, (const U8*)batch_cmd, sizeof(cmd_copy) - 1);
        char *saveptr = NULL;
        char *part = strtok_r(cmd_copy, ";", &saveptr);
        while (part) {
            ShellExecutePipeline(part);
            part = strtok_r(NULL, ";", &saveptr);
        }
        return 0;
    }

    /* Interactive Terminal OS Session */
    TermInitRaw();
    TermClearScreen();

    /* Run Init Process (Spawns Shell) */
    InitProcessTask(NULL);

    /* Clean OS Shutdown */
    TermRestore();
    Print("\n\033[93m[HolyC Unix Kernel: Orderly System Shutdown Completed. God be with you.]\033[0m\n");
    return 0;
}
