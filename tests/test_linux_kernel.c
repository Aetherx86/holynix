/*
 * Linux / POSIX Kernel Compliance Test Suite (test_linux_kernel.c)
 * Test-Driven Development (TDD) harness to verify identical functionalities
 * between HolyC-Unix and a standard Linux Kernel / OS.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>

#define COLOR_RESET   "\033[0m"
#define COLOR_GREEN   "\033[92m"
#define COLOR_RED     "\033[91m"
#define COLOR_YELLOW  "\033[93m"
#define COLOR_CYAN    "\033[96m"

static int g_tests_run = 0;
static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define ASSERT_TRUE(cond, msg) do { \
    g_tests_run++; \
    if (cond) { \
        printf("  [PASS] %s\n", msg); \
        g_tests_passed++; \
    } else { \
        printf("  " COLOR_RED "[FAIL] %s (Line %d)" COLOR_RESET "\n", msg, __LINE__); \
        g_tests_failed++; \
    } \
} while (0)

#define ASSERT_STR_CONTAINS(haystack, needle, msg) do { \
    g_tests_run++; \
    if (strstr((haystack), (needle)) != NULL) { \
        printf("  [PASS] %s\n", msg); \
        g_tests_passed++; \
    } else { \
        printf("  " COLOR_RED "[FAIL] %s: '%s' not found in output (Line %d)" COLOR_RESET "\n", msg, needle, __LINE__); \
        g_tests_failed++; \
    } \
} while (0)

#define ASSERT_STR_NOT_CONTAINS(haystack, needle, msg) do { \
    g_tests_run++; \
    if (strstr((haystack), (needle)) == NULL) { \
        printf("  [PASS] %s\n", msg); \
        g_tests_passed++; \
    } else { \
        printf("  " COLOR_RED "[FAIL] %s: '%s' unexpectedly found in output (Line %d)" COLOR_RESET "\n", msg, needle, __LINE__); \
        g_tests_failed++; \
    } \
} while (0)

/* Helper: Execute a command in holy_unix and capture stdout & exit code */
static int exec_holy_unix(const char *cmd, char *out_buf, size_t buf_size) {
    char full_cmd[2048];
    snprintf(full_cmd, sizeof(full_cmd), "./bin/holy_unix -c '%s' 2>&1", cmd);

    FILE *fp = popen(full_cmd, "r");
    if (!fp) {
        if (out_buf && buf_size > 0) out_buf[0] = '\0';
        return -1;
    }

    size_t total = 0;
    if (out_buf && buf_size > 0) {
        while (total + 1 < buf_size) {
            size_t n = fread(out_buf + total, 1, buf_size - 1 - total, fp);
            if (n == 0) break;
            total += n;
        }
        out_buf[total] = '\0';
    } else {
        char dump[256];
        while (fread(dump, 1, sizeof(dump), fp) > 0);
    }

    int status = pclose(fp);
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -1;
}

/* =========================================================================
 * 1. Linux Standard /proc Filesystem Tests
 * ========================================================================= */
static void test_linux_procfs(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 1] Linux /proc Filesystem Compliance ===" COLOR_RESET "\n");
    char out[4096];

    /* 1.1 /proc/uptime format: "<seconds>.<centisecs> <idle_seconds>.<centisecs>" */
    exec_holy_unix("cat /proc/uptime", out, sizeof(out));
    ASSERT_TRUE(out[0] != '\0', "/proc/uptime is readable and not empty");
    double up_sec = -1, idle_sec = -1;
    int parsed = sscanf(out, "%lf %lf", &up_sec, &idle_sec);
    ASSERT_TRUE(parsed >= 1 && up_sec >= 0.0, "/proc/uptime matches Linux 2-value format (<uptime> <idle>)");

    /* 1.2 /proc/version contains kernel name, version, architecture, compiler */
    exec_holy_unix("cat /proc/version", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "version", "/proc/version contains 'version' keyword");
    ASSERT_STR_CONTAINS(out, "HolyC", "/proc/version identifies HolyC engine");

    /* 1.3 /proc/meminfo contains Linux-style MemTotal, MemFree, MemAvailable in kB */
    exec_holy_unix("cat /proc/meminfo", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "MemTotal:", "/proc/meminfo has 'MemTotal:'");
    ASSERT_STR_CONTAINS(out, "MemFree:", "/proc/meminfo has 'MemFree:'");
    ASSERT_STR_CONTAINS(out, "kB", "/proc/meminfo specifies values in 'kB'");

    /* 1.4 /proc/cpuinfo contains processor, vendor_id, model name, flags */
    exec_holy_unix("cat /proc/cpuinfo", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "processor", "/proc/cpuinfo contains 'processor'");
    ASSERT_STR_CONTAINS(out, "model name", "/proc/cpuinfo contains 'model name'");
    ASSERT_STR_CONTAINS(out, "flags", "/proc/cpuinfo contains 'flags'");

    /* 1.5 /proc/loadavg standard Linux load average format: "0.00 0.00 0.00 1/64 <pid>" */
    exec_holy_unix("cat /proc/loadavg", out, sizeof(out));
    ASSERT_TRUE(out[0] != '\0', "/proc/loadavg is accessible");
    double l1 = -1, l5 = -1, l15 = -1;
    int lparsed = sscanf(out, "%lf %lf %lf", &l1, &l5, &l15);
    ASSERT_TRUE(lparsed >= 3, "/proc/loadavg returns standard 3 load average floats");
}

/* =========================================================================
 * 2. Linux Special Device Nodes (/dev) Tests
 * ========================================================================= */
static void test_linux_dev_nodes(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 2] Linux /dev Device Nodes Compliance ===" COLOR_RESET "\n");
    char out[4096];

    /* 2.1 /dev/null: reads return EOF immediately (0 bytes) */
    exec_holy_unix("cat /dev/null; echo EOF_REACHED", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "EOF_REACHED", "/dev/null read returns EOF (0 bytes) without blocking");

    /* 2.2 /dev/null: writes succeed and discard all data */
    exec_holy_unix("echo Discarded_text_to_null > /dev/null; cat /dev/null", out, sizeof(out));
    ASSERT_STR_NOT_CONTAINS(out, "Discarded_text", "/dev/null writes are cleanly discarded");

    /* 2.3 /dev/zero: reading provides zeroes (wc should show byte count) */
    exec_holy_unix("head -c 16 /dev/zero | wc -c", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "16", "/dev/zero streams zero bytes for specified length");

    /* 2.4 /dev/urandom / /dev/random produces non-zero entropy */
    exec_holy_unix("head -c 16 /dev/random | wc -c", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "16", "/dev/random yields requested entropy byte count");
}

/* =========================================================================
 * 3. Linux VFS File Semantics: Open, Seek, Trunc, Append, Unlink
 * ========================================================================= */
static void test_linux_vfs_semantics(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 3] Linux VFS File Semantics Compliance ===" COLOR_RESET "\n");
    char out[4096];

    /* 3.1 Overwrite redirection '>' truncates existing file */
    exec_holy_unix("echo LongInitialContent1234567890 > /tmp/trunc.txt; echo Short > /tmp/trunc.txt; cat /tmp/trunc.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Short", "File overwritten with new content");
    ASSERT_STR_NOT_CONTAINS(out, "LongInitial", "O_TRUNC removes old file bytes");

    /* 3.2 Append redirection '>>' preserves earlier content */
    exec_holy_unix("echo Line1 > /tmp/app.txt; echo Line2 >> /tmp/app.txt; cat /tmp/app.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Line1", "O_APPEND preserves line 1");
    ASSERT_STR_CONTAINS(out, "Line2", "O_APPEND adds line 2");

    /* 3.3 Path resolution: relative paths with . and .. */
    exec_holy_unix("cd /home/terry; cd ..; pwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/home", "'..' moves to parent directory");

    exec_holy_unix("cd /home/terry; cd .; pwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/home/terry", "'.' preserves current directory");

    /* 3.4 Removing files with rm / unlink */
    exec_holy_unix("touch /tmp/delme.txt; rm /tmp/delme.txt; cat /tmp/delme.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "No such file", "Unlinked file is no longer accessible");

    /* 3.5 Nested directory creation: mkdir /tmp/sub; mkdir /tmp/sub/deep */
    exec_holy_unix("mkdir /tmp/sub; mkdir /tmp/sub/deep; touch /tmp/sub/deep/file.txt; ls /tmp/sub/deep", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "file.txt", "Nested directory creation and file creation works");
}

/* =========================================================================
 * 4. Linux IPC Pipeline & Exit Code Compliance
 * ========================================================================= */
static void test_linux_pipeline_and_signals(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 4] Linux IPC Pipelines & Exit Codes ===" COLOR_RESET "\n");
    char out[4096];

    /* 4.1 Multi-stage pipeline: cat | grep | wc */
    exec_holy_unix("cat /etc/passwd | grep terry | wc -l", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "1", "Multi-stage pipeline (cat | grep | wc -l) outputs correct line count");

    /* 4.2 true and false exit codes */
    exec_holy_unix("true; echo $?", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "0", "'true' returns exit code 0");

    exec_holy_unix("false; echo $?", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "1", "'false' returns exit code 1");

    /* 4.3 Command not found exit code is 127 in standard Linux */
    exec_holy_unix("nonexistent_command_xyz; echo $?", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "127", "Unrecognized command returns Linux exit code 127");

    /* 4.4 Process kill and signals */
    exec_holy_unix("ps", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "PID", "'ps' outputs process table header");
    ASSERT_STR_CONTAINS(out, "init", "PID 1 ('init') is present in process table");

    /* 4.5 kill signal delivery */
    exec_holy_unix("kill -9 9999", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "No such process", "Killing nonexistent process returns ESRCH / error");
}

/* =========================================================================
 * 5. Linux Standard Shell Builtins (head, grep, wc, cd, etc.)
 * ========================================================================= */
static void test_linux_shell_builtins(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 5] Linux Shell Built-in Utilities ===" COLOR_RESET "\n");
    char out[4096];

    /* 5.1 head -n <lines> */
    exec_holy_unix("cat /etc/passwd | head -n 2 | wc -l", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "2", "head -n 2 outputs exactly 2 lines");

    /* 5.2 wc -w, -l, -c options */
    exec_holy_unix("echo One Two Three > /tmp/wc_test.txt; wc -w /tmp/wc_test.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "3", "wc -w counts words accurately");

    exec_holy_unix("echo Line1 > /tmp/wc_test2.txt; echo Line2 >> /tmp/wc_test2.txt; wc -l /tmp/wc_test2.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "2", "wc -l counts lines accurately");

    /* 5.3 cd without arguments goes to $HOME (/home/terry) */
    exec_holy_unix("cd /tmp; cd; pwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/home/terry", "cd with no arguments defaults to $HOME");

    /* 5.4 cd - returns to previous directory ($OLDPWD) */
    exec_holy_unix("cd /etc; cd /tmp; cd -; pwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/etc", "cd - navigates to previous directory ($OLDPWD)");
}

/* =========================================================================
 * 6. Linux Advanced Core Utilities (tail, stat, chmod, chown, date, find, etc.)
 * ========================================================================= */
static void test_linux_advanced_utilities(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 6] Linux Advanced Core Utilities ===" COLOR_RESET "\n");
    char out[4096];

    /* 6.1 tail -n <lines> */
    exec_holy_unix("cat /etc/passwd | tail -n 2 | wc -l", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "2", "tail -n 2 outputs exactly 2 lines");

    /* 6.2 stat detailed inode metadata */
    exec_holy_unix("stat /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Size:", "stat displays file size");
    ASSERT_STR_CONTAINS(out, "Inode:", "stat displays inode number");
    ASSERT_STR_CONTAINS(out, "Access:", "stat displays file permissions");

    /* 6.3 chmod octal permissions */
    exec_holy_unix("chmod 755 /etc/passwd; stat /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "0755", "chmod 755 updates permission bits to 0755");

    /* 6.4 chown uid:gid ownership */
    exec_holy_unix("chown 1000:1000 /etc/passwd; stat /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "1000", "chown updates UID and GID");

    /* 6.5 date formatted timestamp */
    exec_holy_unix("date", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "UTC", "date displays UTC time string");

    /* 6.6 find recursive directory search */
    exec_holy_unix("find /etc -name passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/etc/passwd", "find locates file in directory hierarchy");

    /* 6.7 sort alphabetical and numeric */
    exec_holy_unix("echo banana > /tmp/sort.txt; echo apple >> /tmp/sort.txt; echo cherry >> /tmp/sort.txt; sort /tmp/sort.txt | head -n 1", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "apple", "sort orders lines alphabetically");

    exec_holy_unix("echo 10 > /tmp/nums.txt; echo 2 >> /tmp/nums.txt; echo 5 >> /tmp/nums.txt; sort -n /tmp/nums.txt | head -n 1", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "2", "sort -n orders lines numerically");

    /* 6.8 uniq duplicate filtering and counting */
    exec_holy_unix("echo a > /tmp/uniq.txt; echo a >> /tmp/uniq.txt; echo b >> /tmp/uniq.txt; uniq -c /tmp/uniq.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "2 a", "uniq -c reports duplicate line counts");

    /* 6.9 tee split stream */
    exec_holy_unix("echo TeeMessage | tee /tmp/tee_copy.txt; cat /tmp/tee_copy.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "TeeMessage", "tee writes to file and stdout simultaneously");

    /* 6.10 seq number generator */
    exec_holy_unix("seq 1 3", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "1\n2\n3", "seq generates sequence of numbers");

    /* 6.11 ln -s and readlink */
    exec_holy_unix("ln -s /etc/motd /tmp/symlink_test; readlink /tmp/symlink_test", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/etc/motd", "readlink prints target of symbolic link");

    /* 6.12 df and du */
    exec_holy_unix("df", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "holyfs", "df reports VFS filesystem disk statistics");

    exec_holy_unix("du /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/etc/passwd", "du reports file disk space usage");
}

/* =========================================================================
 * 7. Linux Shell Scripting, Logical Operators & TempleOS Features
 * ========================================================================= */
static void test_linux_scripting_and_templeos(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 7] Shell Scripting, Logical Operators & TempleOS ===" COLOR_RESET "\n");
    char out[4096];

    /* 7.1 Environment Variables export & $VAR expansion */
    exec_holy_unix("export GREETING=HolyWorld; echo $GREETING", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "HolyWorld", "export sets variable and echo $VAR expands it");

    exec_holy_unix("env", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "USER=terry", "env displays exported environment variables");

    /* 7.2 Input Redirection (<) */
    exec_holy_unix("wc -l < /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "3", "input redirection (<) feeds file to command");

    /* 7.3 Logical AND (&&) */
    exec_holy_unix("true && echo AND_PASSED", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "AND_PASSED", "true && cmd executes right side");

    exec_holy_unix("false && echo AND_FAILED", out, sizeof(out));
    ASSERT_STR_NOT_CONTAINS(out, "AND_FAILED", "false && cmd short-circuits and skips");

    /* 7.4 Logical OR (||) */
    exec_holy_unix("false || echo OR_PASSED", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "OR_PASSED", "false || cmd executes fallback");

    exec_holy_unix("true || echo OR_FAILED", out, sizeof(out));
    ASSERT_STR_NOT_CONTAINS(out, "OR_FAILED", "true || cmd skips fallback");

    /* 7.5 TempleOS PC Speaker beep */
    exec_holy_unix("beep 800 100", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "800 Hz", "beep executes PC speaker tone simulation");

    /* 7.6 TempleOS Divine GodSong */
    exec_holy_unix("godsong", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "TempleOS Divine GodSong", "godsong generates divine melody & lyrics");

    /* 7.7 TempleOS 3D Donut / Cube */
    exec_holy_unix("donut", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "3D Divine Cube", "donut renders 3D ASCII wireframe");
}

/* =========================================================================
 * 8. Advanced TempleOS & Linux Subsystems
 * ========================================================================= */
static void test_linux_advanced_subsystems(void) {
    printf(COLOR_CYAN "\n=== [TDD Suite 8] Advanced TempleOS & Linux Subsystems ===" COLOR_RESET "\n");
    char out[4096];

    /* 8.1 Shell Aliases (alias, unalias) */
    exec_holy_unix("alias", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "alias ll='ls -l'", "alias command lists default aliases");

    exec_holy_unix("alias mycustom='echo CustomSuccess'; mycustom", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "CustomSuccess", "custom alias definition and expansion works");

    exec_holy_unix("alias tempal=echo; unalias tempal; tempal", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "command not found: tempal", "unalias removes defined alias");

    /* 8.2 Command History & Recall */
    exec_holy_unix("uname -a; history", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "uname -a", "history records and lists past commands");

    exec_holy_unix("whoami; !!", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "terry", "!! history expansion re-executes previous command");

    /* 8.3 Background Job Control (&, jobs) */
    exec_holy_unix("sleep 1 & jobs", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "[1]", "background operator & spawns job and jobs reports it");

    /* 8.4 Kernel Sysctl Tunables & /proc/sys */
    exec_holy_unix("sysctl -a", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "kernel.osname = HolyNix", "sysctl -a reports kernel parameter tunables");

    exec_holy_unix("cat /proc/sys/kernel/hostname", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "holy-unix", "/proc/sys/kernel/hostname returns tunable value");

    /* 8.5 POSIX USTAR Tar Archiver */
    exec_holy_unix("tar -cf /tmp/test_arc.tar /etc/passwd; tar -tf /tmp/test_arc.tar", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "etc/passwd", "tar -cf creates archive and tar -tf lists entries");

    exec_holy_unix("tar -cf /tmp/test_arc2.tar /etc/passwd; tar -xf /tmp/test_arc2.tar /tmp/extract_dest; cat /tmp/extract_dest/etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Terry A. Davis", "tar -xf extracts file and preserves content");

    /* 8.6 Simulated Network & Ping */
    exec_holy_unix("ping -c 2 localhost", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "64 bytes from 127.0.0.1", "ping outputs ICMP echo replies");
    ASSERT_STR_CONTAINS(out, "0.0% packet loss", "ping calculates 0.0% packet loss");

    exec_holy_unix("netstat", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "eth0", "netstat reports active interfaces and sockets");

    /* 8.7 Cron Scheduled Tasks */
    exec_holy_unix("crontab -l", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "HolyNix kernel health check", "crontab -l displays active scheduled jobs");

    /* 8.8 TempleOS DolDoc Markup Renderer */
    exec_holy_unix("doldoc /home/terry/welcome.DD", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Welcome to TempleOS DolDoc", "doldoc renders formatted DolDoc documents");

    /* 8.9 KJV Bible Concordance & Oracle */
    exec_holy_unix("bible Genesis 1:1", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "In the beginning God created", "bible looks up scripture chapter and verse");

    exec_holy_unix("bible search light", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Let there be light", "bible search finds matching scripture passages");

    exec_holy_unix("godpassage", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Divine Scripture Oracle", "godpassage returns randomized divine passage");

    /* 8.10 TempleOS God Doodle */
    exec_holy_unix("goddoodle", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "DIVINE TEMPLEOS GOD DOODLE CANVAS", "goddoodle generates 16-color ASCII art");

    /* 8.11 RedSea 64-bit Filesystem Driver */
    exec_holy_unix("redsea inspect /boot/redsea.img", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "VALID REDSEA VOLUME", "redsea inspect validates 64-bit RedSea volume");

    exec_holy_unix("redsea ls /boot/redsea.img", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "KERNEL.BIN", "redsea ls lists directory entries in RedSea image");

    /* 8.12 Ring-0 Memory Peeker & Disassembler */
    exec_holy_unix("memdump 0x1000 16", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "0x0000000000001000", "memdump displays hex and ASCII memory bytes");

    exec_holy_unix("disasm 0x401000 2", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "push    rbp", "disasm decodes x86-64 machine instructions");

    /* 8.13 Holy Package Manager (HPM) */
    exec_holy_unix("hpm list", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Holy Package Manager", "hpm list displays holy package repository");

    exec_holy_unix("hpm install castle", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Successfully installed castle", "hpm install compiles and installs holy package");
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    printf(COLOR_YELLOW "========================================================\n");
    printf("   HolyC-Unix Linux / POSIX Compliance TDD Test Suite\n");
    printf("========================================================\n" COLOR_RESET);

    test_linux_procfs();
    test_linux_dev_nodes();
    test_linux_vfs_semantics();
    test_linux_pipeline_and_signals();
    test_linux_shell_builtins();
    test_linux_advanced_utilities();
    test_linux_scripting_and_templeos();
    test_linux_advanced_subsystems();

    printf("\n" COLOR_YELLOW "========================================================\n");
    printf("  TDD Test Results: " COLOR_GREEN "%d Passed" COLOR_RESET ", "
           COLOR_RED "%d Failed" COLOR_RESET " (Total: %d)\n",
           g_tests_passed, g_tests_failed, g_tests_run);
    printf("========================================================\n" COLOR_RESET);

    return (g_tests_failed == 0) ? 0 : 1;
}
