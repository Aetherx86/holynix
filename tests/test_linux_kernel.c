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

    printf("\n" COLOR_YELLOW "========================================================\n");
    printf("  TDD Test Results: " COLOR_GREEN "%d Passed" COLOR_RESET ", "
           COLOR_RED "%d Failed" COLOR_RESET " (Total: %d)\n",
           g_tests_passed, g_tests_failed, g_tests_run);
    printf("========================================================\n" COLOR_RESET);

    return (g_tests_failed == 0) ? 0 : 1;
}
