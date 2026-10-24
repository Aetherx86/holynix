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
    char escaped[4096];
    size_t ei = 0;
    for (size_t i = 0; cmd[i] && ei + 5 < sizeof(escaped); ++i) {
        if (cmd[i] == '\'') {
            escaped[ei++] = '\'';
            escaped[ei++] = '\\';
            escaped[ei++] = '\'';
            escaped[ei++] = '\'';
        } else {
            escaped[ei++] = cmd[i];
        }
    }
    escaped[ei] = '\0';

    char full_cmd[8192];
    snprintf(full_cmd, sizeof(full_cmd), "./bin/holy_unix -c '%s' 2>&1", escaped);

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

    /* 5.5 grep options: -i (ignore case), -v (invert), -c (count) */
    exec_holy_unix("grep -i TERRY /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "terry", "grep -i performs case-insensitive match");

    exec_holy_unix("grep -c -v root /etc/passwd", out, sizeof(out));
    ASSERT_TRUE(atoi(out) >= 1, "grep -c -v counts non-matching lines");
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

    /* 6.13 diff line-by-line file comparison */
    exec_holy_unix("echo lineA > /tmp/d1.txt; echo lineB > /tmp/d2.txt; diff /tmp/d1.txt /tmp/d2.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "< lineA", "diff reports removed line from first file");
    ASSERT_STR_CONTAINS(out, "> lineB", "diff reports added line from second file");

    exec_holy_unix("echo lineA > /tmp/d1.txt; diff /tmp/d1.txt /tmp/d1.txt; echo identical_$?", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "identical_0", "diff on identical files exits with code 0");
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

/*
 * [TDD Suite 9] POSIX Manual System & HTTP Network Client (curl / man)
 */
static void test_posix_manual_and_network_client(void) {
    char out[8192];
    printf(COLOR_CYAN "\n=== [TDD Suite 9] POSIX Manual System & HTTP Network Client ===\n" COLOR_RESET);

    /* 9.1 man pages */
    exec_holy_unix("man ls", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "list directory contents", "man ls displays command description");
    ASSERT_STR_CONTAINS(out, "SYNOPSIS", "man ls displays standard SYNOPSIS section");

    exec_holy_unix("man cat", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "concatenate files", "man cat displays cat manual page");

    /* 9.2 apropos and whatis */
    exec_holy_unix("apropos raycast", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "castle", "apropos raycast locates matching castle utility");

    exec_holy_unix("whatis curl", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "transfer a URL via HTTP", "whatis curl prints one-line summary");

    /* 9.3 HTTP Network Client (curl) */
    exec_holy_unix("curl -i http://localhost/", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "HTTP/1.1 200 OK", "curl -i outputs HTTP status line");
    ASSERT_STR_CONTAINS(out, "Server: HolyNix-HTTP/1.0", "curl -i outputs server identification header");

    exec_holy_unix("curl http://god.oracle/verse", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "God Oracle Response:", "curl retrieves payload from divine endpoint");

    /* 9.4 Terminal Line Discipline (stty) */
    exec_holy_unix("stty size", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "24 80", "stty size reports terminal rows and columns");

    exec_holy_unix("stty", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "38400 baud", "stty reports terminal baud rate and flags");
}

/*
 * [TDD Suite 10] Multi-User Security, Scripting Loops & TempleOS Classic Games
 */
static void test_posix_security_and_templeos_games(void) {
    char out[8192];
    printf(COLOR_CYAN "\n=== [TDD Suite 10] Multi-User Security, Scripting Loops & TempleOS Games ===\n" COLOR_RESET);

    /* 10.1 Multi-User Identity and Privileges (id, groups, su, sudo) */
    exec_holy_unix("id", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "uid=1000(terry)", "id reports terry as default UID 1000");

    exec_holy_unix("groups", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "terry", "groups lists groups for current user");

    exec_holy_unix("su root; whoami", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "root", "su root switches active user context to root");

    exec_holy_unix("sudo whoami", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "root", "sudo temporarily escalates execution privileges to root");

    /* 10.2 Conditional Expression Evaluation (test / [ ]) */
    exec_holy_unix("test -f /etc/motd && echo TEST_FILE_OK", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "TEST_FILE_OK", "test -f verifies regular file existence");

    exec_holy_unix("[ -d /home/terry ] && echo TEST_DIR_OK", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "TEST_DIR_OK", "[ -d evaluates directory presence");

    /* 10.3 Shell Scripting Control Flow (for / in / do / done, if / then / else) */
    exec_holy_unix("for i in 1 2; do echo loop_$i; done", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "loop_1", "for loop executes body for first iteration");
    ASSERT_STR_CONTAINS(out, "loop_2", "for loop executes body for second iteration");

    exec_holy_unix("if [ -f /etc/motd ]; then echo COND_TRUE; else echo COND_FALSE; fi", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "COND_TRUE", "if/then conditional branch evaluates and executes");

    /* 10.4 TempleOS Classic Games & Window Manager */
    exec_holy_unix("castle -m", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "CASTLE FRANKENSTEIN: 2D OVERHEAD MAZE MAP", "castle -m renders 2D overhead maze map");

    exec_holy_unix("afteregypt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "AFTER EGYPT: THE BURNING BUSH & SINAI", "afteregypt renders Moses quest and burning bush");

    exec_holy_unix("flappy", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "FLAPPY BIRD: TEMPLEOS EDITION", "flappy renders terminal obstacle simulation");

    exec_holy_unix("wintile", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "PANE 1: HolyC Shell & Editor", "wintile displays left editor pane");
    ASSERT_STR_CONTAINS(out, "PANE 2: Divine Oracle & System Top", "wintile displays right divine system pane");
}

/*
 * [TDD Suite 11] Linux Core Text Streaming Pipelines (cut, tr, sed, paste, fold, basename, dirname)
 */
static void test_linux_text_streaming_pipelines(void) {
    char out[8192];
    printf(COLOR_CYAN "\n=== [TDD Suite 11] Linux Core Text Streaming Pipelines ===\n" COLOR_RESET);

    /* 11.1 cut delimiter extraction */
    exec_holy_unix("cut -d: -f1 /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "root", "cut -d: -f1 extracts root user");
    ASSERT_STR_CONTAINS(out, "terry", "cut -d: -f1 extracts terry user");

    exec_holy_unix("cut -d: -f3 /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "1000", "cut -d: -f3 extracts numeric UID 1000");

    /* 11.2 tr translation and deletion */
    exec_holy_unix("echo 'holynix operating system' | tr a-z A-Z", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "HOLYNIX OPERATING SYSTEM", "tr a-z A-Z translates lowercase to uppercase");

    exec_holy_unix("echo '12345' | tr 0-9 A-J", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "BCDEF", "tr 0-9 A-J translates numeric range to letters");

    exec_holy_unix("echo 'hello divine world' | tr -d 'ei'", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "hllo dvn world", "tr -d deletes specified character set");

    /* 11.3 sed substitution (global and single) */
    exec_holy_unix("echo 'apple banana apple' | sed 's/apple/orange/g'", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "orange banana orange", "sed s/apple/orange/g replaces all occurrences");

    exec_holy_unix("echo 'apple banana apple' | sed 's/apple/orange/'", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "orange banana apple", "sed s/apple/orange/ replaces only first occurrence");

    exec_holy_unix("echo 'line one\nline one' | sed 's/one/two/g'", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "line two", "sed processes multiple lines across stream");

    /* 11.4 basename and dirname */
    exec_holy_unix("basename /usr/share/man/ls.1 .1", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "ls", "basename strips directory path and suffix");

    exec_holy_unix("dirname /usr/share/man", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/usr/share", "dirname extracts parent directory path");

    exec_holy_unix("dirname foo.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, ".", "dirname returns . for plain filename");

    /* 11.5 paste and fold */
    exec_holy_unix("echo line1 > /tmp/pst1.txt; echo line2 > /tmp/pst2.txt; paste /tmp/pst1.txt /tmp/pst2.txt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "line1\tline2", "paste merges files side-by-side");

    exec_holy_unix("echo '1234567890' | fold -w 5", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "12345", "fold wraps long lines to specified width");
}

/*
 * [TDD Suite 12] Microkernel Subsystems, Music & System Badge (holyfetch, play, modules, vmstat)
 */
static void test_microkernel_subsystems_and_music(void) {
    char out[8192];
    printf(COLOR_CYAN "\n=== [TDD Suite 12] Microkernel Subsystems, Music & System Badge ===\n" COLOR_RESET);

    /* 12.1 Kernel Modules (/proc/modules, lsmod, insmod, rmmod) */
    exec_holy_unix("cat /proc/modules", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "god_oracle", "/proc/modules lists preloaded god_oracle module");

    exec_holy_unix("lsmod", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "vga_16color", "lsmod reports active vga_16color module");

    exec_holy_unix("insmod net_filter; lsmod", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "net_filter", "insmod dynamically loads kernel module");

    exec_holy_unix("insmod net_filter; rmmod net_filter", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "unloaded", "rmmod dynamically unloads kernel module");

    /* 12.2 Virtual Memory (/proc/vmstat, vmstat) */
    exec_holy_unix("cat /proc/vmstat", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "nr_free_pages", "/proc/vmstat reports page metrics");

    exec_holy_unix("vmstat", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "procs", "vmstat prints standard memory and processor table");

    /* 12.3 Process Tree & Limits (pstree, ulimit, ipcs) */
    exec_holy_unix("pstree", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "init(1)", "pstree displays hierarchical process tree");

    exec_holy_unix("ulimit -n", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "32", "ulimit -n reports file descriptor limit");

    exec_holy_unix("ipcs", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Message Queues", "ipcs displays IPC facilities");

    /* 12.4 TempleOS System Badge, Music & Screenshot */
    exec_holy_unix("holyfetch", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "terry@holy-unix", "holyfetch displays user and host header");
    ASSERT_STR_CONTAINS(out, "640x480", "holyfetch displays divine 640x480 resolution");

    exec_holy_unix("play '3q.D4DhE2G'", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Frequency:", "play parses music notation and computes note frequencies");

    exec_holy_unix("juke", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "The Promised Land", "juke plays Terry Davis divine hymn");

    exec_holy_unix("screenshot /tmp/sc.DD; cat /tmp/sc.DD", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "HolyNix Framebuffer Screen Capture", "screenshot saves framebuffer state to DolDoc file");
}

/*
 * [TDD Suite 13] System Introspection, Flight Simulation & Code Limit Compliance
 */
static void test_system_introspection_and_templeos_flight(void) {
    char out[8192];
    printf(COLOR_CYAN "\n=== [TDD Suite 13] System Introspection, Flight Simulation & Limits ===\n" COLOR_RESET);

    /* 13.1 TempleOS 3D Flight Simulator (flight) */
    exec_holy_unix("flight", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "TEMPLEOS 3D FLIGHT SIMULATOR", "flight renders flight simulator title");
    ASSERT_STR_CONTAINS(out, "RUNWAY", "flight renders 3D wireframe runway");
    ASSERT_STR_CONTAINS(out, "DIVINE PROMISED LAND", "flight displays promised land terrain");

    exec_holy_unix("flight -p 10 -r -5 -a 9000", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "ALT: 9000 ft", "flight updates dynamic altitude");
    ASSERT_STR_CONTAINS(out, "VS: +500 fpm", "flight computes dynamic vertical speed from pitch");

    /* 13.2 TempleOS Digital Rain Visualizer (matrix) */
    exec_holy_unix("matrix", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "Divine Digital Rain", "matrix displays digital rain header");
    ASSERT_STR_CONTAINS(out, "HolyC", "matrix drops HolyC symbol tokens");

    /* 13.3 TempleOS 100,000 LOC Divine Limit Verification (linecnt) */
    exec_holy_unix("linecnt", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "DIVINE LIMIT VERIFICATION", "linecnt displays 100,000 LOC verification");
    ASSERT_STR_CONTAINS(out, "Live VFS Storage State", "linecnt counts live VFS filesystem storage state");
    ASSERT_STR_CONTAINS(out, "COMPLIANT", "linecnt verifies codebase adheres to divine limit");

    /* 13.4 HolyC JIT Compilation & Benchmark (hcbench) */
    exec_holy_unix("hcbench", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "HolyC JIT Compilation", "hcbench benchmarks compiler engine");
    ASSERT_STR_CONTAINS(out, "lines/sec", "hcbench reports compilation lines per second");

    /* 13.5 Random Divine Word Generator (godword) */
    exec_holy_unix("godword 5", out, sizeof(out));
    ASSERT_TRUE(strlen(out) > 10, "godword outputs multiple divine words from vocabulary");

    /* 13.6 Command Path and Type Resolution (which, type) */
    exec_holy_unix("which ls", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "/bin/ls", "which resolves built-in command path");

    exec_holy_unix("which definitely_missing_xyz", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "no definitely_missing_xyz", "which reports error for missing command");

    exec_holy_unix("type cd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "shell builtin", "type identifies cd as shell builtin");

    exec_holy_unix("type which", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "shell builtin", "type identifies which as shell builtin");

    exec_holy_unix("alias testal='echo ok'; type testal", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "alias for", "type identifies alias correctly");

    exec_holy_unix("type missing_binary_foo", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "not found", "type reports not found for nonexistent binary");

    /* 13.7 Hostname and Filesystem Cache Sync (hostname, sync) */
    exec_holy_unix("hostname", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "holy-unix", "hostname displays current system host name");

    exec_holy_unix("su root; hostname myholystation; hostname; cat /proc/sys/kernel/hostname", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "myholystation", "hostname updates kernel hostname and procfs reflects it");

    exec_holy_unix("sync", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "[OK]", "sync confirms dirty VFS buffer flush");

    /* 13.8 Active User Sessions (who, w) */
    exec_holy_unix("who", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "tty1", "who displays active terminal session tty");

    exec_holy_unix("w", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "load average", "w reports system uptime and load averages");

    /* 13.9 Number Lines Filter (nl) */
    exec_holy_unix("nl /etc/passwd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "1\troot", "nl numbers lines with sequential indices");

    /* 13.10 Canonical Hex Dumper (xxd) */
    exec_holy_unix("echo 'HolyNix' | xxd", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "00000000:", "xxd outputs canonical 16-byte hex dump");

    /* 13.11 Execution Timing Builtin (time) */
    exec_holy_unix("time echo quick", out, sizeof(out));
    ASSERT_STR_CONTAINS(out, "quick", "time executes target command");
    ASSERT_STR_CONTAINS(out, "real", "time reports real execution duration");
    ASSERT_STR_CONTAINS(out, "user", "time reports user execution duration");
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
    test_posix_manual_and_network_client();
    test_posix_security_and_templeos_games();
    test_linux_text_streaming_pipelines();
    test_microkernel_subsystems_and_music();
    test_system_introspection_and_templeos_flight();

    printf("\n" COLOR_YELLOW "========================================================\n");
    printf("  TDD Test Results: " COLOR_GREEN "%d Passed" COLOR_RESET ", "
           COLOR_RED "%d Failed" COLOR_RESET " (Total: %d)\n",
           g_tests_passed, g_tests_failed, g_tests_run);
    printf("========================================================\n" COLOR_RESET);

    return (g_tests_failed == 0) ? 0 : 1;
}
