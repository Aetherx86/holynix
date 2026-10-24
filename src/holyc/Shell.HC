/*
 * HolyC Unix Kernel - Interactive Unix Shell: "holysh" (Shell.HC)
 * Command parser, pipelines, redirection, environment expansion, and built-in Unix utilities.
 */

#ifndef SHELL_HC
#define SHELL_HC

#include "Types.HC"
#include "VFS.HC"
#include "Task.HC"
#include "Syscall.HC"
#include "Terminal.HC"
#include "GodWords.HC"
#include "Editor.HC"
#include "HolyC_Repl.HC"

#define MAX_ARGS 32
#define MAX_ENV_VARS 64

class CEnvVar {
    char key[64];
    char val[MAX_PATH_LEN];
};

static CEnvVar g_env_vars[MAX_ENV_VARS];
static I64 g_env_count = 0;
static I64 g_last_exit_code = 0;
static U8 g_oldpwd[MAX_PATH_LEN] = "/home/terry";

U0 ShellSetEnv(const char *key, const char *val) {
    if (!key || !*key) return;
    for (I64 i = 0; i < g_env_count; ++i) {
        if (strcmp(g_env_vars[i].key, key) == 0) {
            if (val) StrNCpy((U8*)g_env_vars[i].val, (const U8*)val, MAX_PATH_LEN - 1);
            else g_env_vars[i].val[0] = '\0';
            return;
        }
    }
    if (g_env_count < MAX_ENV_VARS) {
        StrNCpy((U8*)g_env_vars[g_env_count].key, (const U8*)key, 63);
        if (val) StrNCpy((U8*)g_env_vars[g_env_count].val, (const U8*)val, MAX_PATH_LEN - 1);
        else g_env_vars[g_env_count].val[0] = '\0';
        g_env_count++;
    }
}

const char *ShellGetEnv(const char *key) {
    if (!key) return NULL;
    CTask *t = TaskGetCurrent();
    if (strcmp(key, "?") == 0) {
        static char code_buf[16];
        snprintf(code_buf, sizeof(code_buf), "%lld", (long long)g_last_exit_code);
        return code_buf;
    }
    if (strcmp(key, "PWD") == 0) {
        return t ? (const char*)t->cwd : "/";
    }
    if (strcmp(key, "OLDPWD") == 0) {
        return (const char*)g_oldpwd;
    }
    for (I64 i = 0; i < g_env_count; ++i) {
        if (strcmp(g_env_vars[i].key, key) == 0) {
            return g_env_vars[i].val;
        }
    }
    return NULL;
}

U0 ShellInitEnv() {
    if (g_env_count > 0) return;
    ShellSetEnv("USER", "terry");
    ShellSetEnv("HOME", "/home/terry");
    ShellSetEnv("SHELL", "/bin/holysh");
    ShellSetEnv("PATH", "/bin:/usr/bin");
    ShellSetEnv("TERM", "xterm-256color");
    ShellSetEnv("OS", "HolyC-Unix");
    ShellSetEnv("ARCH", "x86_64");
    ShellSetEnv("EDITOR", "ed");
}

static inline U0 ShellPrintOut(const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    SysWrite(STDOUT_FILENO, (const U8*)buf, strlen(buf));
}

/*
 * Built-in Command: ls
 */
U0 ShellCmdLs(I64 argc, char **argv) {
    CTask *t = TaskGetCurrent();
    const U8 *target_path = ".";
    Bool opt_l = FALSE;
    Bool opt_a = FALSE;

    for (I64 i = 1; i < argc; ++i) {
        if (argv[i][0] == '-') {
            for (I64 j = 1; argv[i][j]; ++j) {
                if (argv[i][j] == 'l') opt_l = TRUE;
                if (argv[i][j] == 'a') opt_a = TRUE;
            }
        } else {
            target_path = (const U8*)argv[i];
        }
    }

    I64 inum = VFSResolvePath(target_path, t ? t->cwd : (const U8*)"/");
    if (inum < 0) {
        Print("ls: cannot access '%s': No such file or directory\n", target_path);
        return;
    }

    CVFSInode *node = VFSGetInode(inum);
    if (!node) return;

    if (node->type != VFS_DIRECTORY) {
        /* Single file */
        Print("%s\n", node->name);
        return;
    }

    for (I64 i = 0; i < node->num_children; ++i) {
        I64 cinum = node->children[i];
        CVFSInode *child = VFSGetInode(cinum);
        if (!child) continue;

        if (!opt_a && child->name[0] == '.') continue;

        if (opt_l) {
            char type_char = '-';
            const char *color_code = "\033[0m";
            if (child->type == VFS_DIRECTORY) { type_char = 'd'; color_code = "\033[96m"; }
            else if (child->type == VFS_CHARDEV) { type_char = 'c'; color_code = "\033[93m"; }
            else if (child->type == VFS_PIPE) { type_char = 'p'; color_code = "\033[95m"; }
            else if (child->type == VFS_PROC) { type_char = 'r'; color_code = "\033[92m"; }
            else if (StrFind(child->name, (const U8*)".HC") != NULL) { color_code = "\033[92m"; }

            Print("%crwxr-xr-x  1 terry  wheel %6lld Oct 24 %s%s\033[0m\n",
                  type_char, (long long)child->size, color_code, child->name);
        } else {
            const char *color_code = "\033[0m";
            if (child->type == VFS_DIRECTORY) color_code = "\033[96m";
            else if (child->type == VFS_CHARDEV) color_code = "\033[93m";
            else if (child->type == VFS_PIPE) color_code = "\033[95m";
            else if (StrFind(child->name, (const U8*)".HC") != NULL) color_code = "\033[92m";

            Print("%s%s\033[0m  ", color_code, child->name);
        }
    }
    if (!opt_l) Print("\n");
}

/*
 * Built-in Command: cat
 */
U0 ShellCmdCat(I64 argc, char **argv) {
    if (argc < 2) {
        /* Read from STDIN */
        U8 buf[256];
        I64 n;
        while ((n = SysRead(STDIN_FILENO, buf, sizeof(buf) - 1)) > 0) {
            buf[n] = '\0';
            SysWrite(STDOUT_FILENO, buf, n);
        }
        return;
    }

    for (I64 i = 1; i < argc; ++i) {
        I64 fd = SysOpen((const U8*)argv[i], O_RDONLY);
        if (fd < 0) {
            Print("cat: %s: No such file or directory\n", argv[i]);
            continue;
        }

        U8 buf[1024];
        I64 n;
        while ((n = SysRead(fd, buf, sizeof(buf) - 1)) > 0) {
            buf[n] = '\0';
            SysWrite(STDOUT_FILENO, buf, n);
        }
        SysClose(fd);
    }
}

/*
 * Built-in Command: echo
 */
U0 ShellCmdEcho(I64 argc, char **argv) {
    Bool newline = TRUE;
    I64 start = 1;
    if (argc > 1 && StrCmp((const U8*)argv[1], "-n") == 0) {
        newline = FALSE;
        start = 2;
    }

    for (I64 i = start; i < argc; ++i) {
        const char *arg = argv[i];
        if (arg[0] == '$') {
            const char *val = ShellGetEnv(arg + 1);
            if (val) arg = val;
            else arg = "";
        }

        SysWrite(STDOUT_FILENO, (const U8*)arg, StrLen((const U8*)arg));
        if (i + 1 < argc) {
            SysWrite(STDOUT_FILENO, (const U8*)" ", 1);
        }
    }
    if (newline) SysWrite(STDOUT_FILENO, (const U8*)"\n", 1);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: ps
 */
U0 ShellCmdPs(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    U8 buf[2048];
    I64 n = TaskFormatProcTasks(buf, sizeof(buf));
    if (n > 0) {
        Print("%s", buf);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: cd
 */
U0 ShellCmdCd(I64 argc, char **argv) {
    CTask *t = TaskGetCurrent();
    U8 current_dir[MAX_PATH_LEN];
    if (t) StrNCpy(current_dir, t->cwd, MAX_PATH_LEN - 1);
    else StrCpy(current_dir, "/");

    const char *target = "/home/terry";
    if (argc < 2) {
        target = "/home/terry";
    } else if (strcmp(argv[1], "~") == 0) {
        target = "/home/terry";
    } else if (strcmp(argv[1], "-") == 0) {
        target = (const char*)g_oldpwd;
        Print("%s\n", target);
    } else {
        target = argv[1];
    }

    if (SysChdir((const U8*)target) < 0) {
        Print("cd: %s: No such file or directory\n", target);
        g_last_exit_code = 1;
    } else {
        StrNCpy(g_oldpwd, current_dir, MAX_PATH_LEN - 1);
        g_last_exit_code = 0;
    }
}

/*
 * Built-in Command: pwd
 */
U0 ShellCmdPwd(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    CTask *t = TaskGetCurrent();
    ShellPrintOut("%s\n", t ? (const char*)t->cwd : "/");
}

/*
 * Built-in Command: mkdir
 */
U0 ShellCmdMkdir(I64 argc, char **argv) {
    if (argc < 2) {
        Print("mkdir: missing operand\n");
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        if (SysMkdir((const U8*)argv[i]) < 0) {
            Print("mkdir: cannot create directory '%s'\n", argv[i]);
        }
    }
}

/*
 * Built-in Command: touch
 */
U0 ShellCmdTouch(I64 argc, char **argv) {
    if (argc < 2) {
        Print("touch: missing file operand\n");
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        I64 fd = SysOpen((const U8*)argv[i], O_CREAT | O_WRONLY);
        if (fd >= 0) SysClose(fd);
        else Print("touch: cannot touch '%s'\n", argv[i]);
    }
}

/*
 * Built-in Command: rm
 */
U0 ShellCmdRm(I64 argc, char **argv) {
    if (argc < 2) {
        Print("rm: missing operand\n");
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        if (argv[i][0] == '-') continue;
        if (SysUnlink((const U8*)argv[i]) < 0) {
            Print("rm: cannot remove '%s'\n", argv[i]);
        }
    }
}

/*
 * Built-in Command: cp
 */
U0 ShellCmdCp(I64 argc, char **argv) {
    if (argc < 3) {
        Print("Usage: cp <source> <dest>\n");
        return;
    }
    I64 src_fd = SysOpen((const U8*)argv[1], O_RDONLY);
    if (src_fd < 0) {
        Print("cp: cannot open '%s'\n", argv[1]);
        return;
    }
    I64 dst_fd = SysOpen((const U8*)argv[2], O_CREAT | O_WRONLY | O_TRUNC);
    if (dst_fd < 0) {
        Print("cp: cannot create '%s'\n", argv[2]);
        SysClose(src_fd);
        return;
    }

    U8 buf[1024];
    I64 n;
    while ((n = SysRead(src_fd, buf, sizeof(buf))) > 0) {
        SysWrite(dst_fd, buf, n);
    }
    SysClose(src_fd);
    SysClose(dst_fd);
}

/*
 * Built-in Command: mv
 */
U0 ShellCmdMv(I64 argc, char **argv) {
    if (argc < 3) {
        Print("Usage: mv <source> <dest>\n");
        return;
    }
    ShellCmdCp(argc, argv);
    SysUnlink((const U8*)argv[1]);
}

/*
 * Built-in Command: kill
 */
U0 ShellCmdKill(I64 argc, char **argv) {
    if (argc < 2) {
        Print("Usage: kill [-sig] <pid>\n");
        return;
    }
    I64 sig = SIGTERM;
    I64 pid_idx = 1;
    if (argv[1][0] == '-') {
        sig = atoll(&argv[1][1]);
        pid_idx = 2;
    }
    if (pid_idx < argc) {
        I64 pid = atoll(argv[pid_idx]);
        if (SysKill(pid, sig) < 0) {
            Print("kill: (%lld) - No such process\n", (long long)pid);
        }
    }
}

/*
 * Built-in Command: uname
 */
U0 ShellCmdUname(I64 argc, char **argv) {
    Bool all = FALSE;
    if (argc > 1 && StrCmp((const U8*)argv[1], "-a") == 0) all = TRUE;

    if (all) {
        ShellPrintOut("HolyC-Unix holy-unix 1.0.0-holyc Darwin arm64 HolyC-Compiler-v1 GNU/TempleOS\n");
    } else {
        ShellPrintOut("HolyC-Unix\n");
    }
}

/*
 * Built-in Command: uptime
 */
U0 ShellCmdUptime(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    I64 sec = KernelGetUptimeSec();
    I64 mins = (sec / 60) % 60;
    I64 hours = (sec / 3600);
    I64 secs = sec % 60;
    ShellPrintOut(" %02lld:%02lld:%02lld up %lld seconds, %lld ticks, load average: 0.08, 0.02, 0.01\n",
          (long long)hours, (long long)mins, (long long)secs,
          (long long)sec, (long long)KernelGetTicks());
}

/*
 * Built-in Command: whoami
 */
U0 ShellCmdWhoami(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    CTask *t = TaskGetCurrent();
    ShellPrintOut("%s\n", (t && t->uid == 0) ? "root" : "terry");
}

/*
 * Built-in Command: dmesg
 */
U0 ShellCmdDmesg(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    U8 dmesg_buf[4096];
    I64 n = DmesgRead(dmesg_buf, sizeof(dmesg_buf));
    if (n > 0) {
        Print("%s", dmesg_buf);
    }
}

/*
 * Built-in Command: god (TempleOS Oracle)
 */
U0 ShellCmdGod(I64 argc, char **argv) {
    I64 words = 7;
    if (argc > 1) {
        words = atoll(argv[1]);
        if (words <= 0) words = 7;
    }
    GodSpeak(words);
}

/*
 * Built-in Command: grep
 */
U0 ShellCmdGrep(I64 argc, char **argv) {
    if (argc < 2) {
        Print("Usage: grep <pattern> [file]\n");
        return;
    }
    const char *pattern = argv[1];
    I64 fd = STDIN_FILENO;
    if (argc >= 3) {
        fd = SysOpen((const U8*)argv[2], O_RDONLY);
        if (fd < 0) {
            Print("grep: %s: No such file or directory\n", argv[2]);
            return;
        }
    }

    U8 chunk[4096];
    I64 bytes_read = SysRead(fd, chunk, sizeof(chunk) - 1);
    if (fd != STDIN_FILENO) SysClose(fd);

    if (bytes_read > 0) {
        chunk[bytes_read] = '\0';
        char *saveptr = NULL;
        char *line = strtok_r((char*)chunk, "\r\n", &saveptr);
        while (line) {
            if (strstr(line, pattern) != NULL) {
                Print("%s\n", line);
            }
            line = strtok_r(NULL, "\r\n", &saveptr);
        }
    }
}

/*
 * Built-in Command: head
 */
U0 ShellCmdHead(I64 argc, char **argv) {
    I64 max_lines = 10;
    I64 max_bytes = -1;
    const char *filepath = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-n") == 0 && i + 1 < argc) {
            max_lines = atoll(argv[++i]);
        } else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            max_bytes = atoll(argv[++i]);
        } else if (argv[i][0] != '-') {
            filepath = argv[i];
        }
    }

    I64 fd = STDIN_FILENO;
    if (filepath) {
        fd = SysOpen((const U8*)filepath, O_RDONLY);
        if (fd < 0) {
            Print("head: cannot open '%s': No such file or directory\n", filepath);
            g_last_exit_code = 1;
            return;
        }
    }

    U8 ch;
    I64 lines_seen = 0;
    I64 bytes_seen = 0;
    while (SysRead(fd, &ch, 1) > 0) {
        if (max_bytes >= 0) {
            if (bytes_seen >= max_bytes) break;
        } else {
            if (lines_seen >= max_lines) break;
        }
        SysWrite(STDOUT_FILENO, &ch, 1);
        bytes_seen++;
        if (ch == '\n') lines_seen++;
    }

    if (filepath && fd != STDIN_FILENO) SysClose(fd);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: wc
 */
U0 ShellCmdWc(I64 argc, char **argv) {
    Bool opt_l = FALSE, opt_w = FALSE, opt_c = FALSE;
    const char *filepath = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (argv[i][0] == '-') {
            for (I64 j = 1; argv[i][j]; ++j) {
                if (argv[i][j] == 'l') opt_l = TRUE;
                if (argv[i][j] == 'w') opt_w = TRUE;
                if (argv[i][j] == 'c') opt_c = TRUE;
            }
        } else {
            filepath = argv[i];
        }
    }

    if (!opt_l && !opt_w && !opt_c) {
        opt_l = opt_w = opt_c = TRUE;
    }

    I64 fd = STDIN_FILENO;
    if (filepath) {
        fd = SysOpen((const U8*)filepath, O_RDONLY);
        if (fd < 0) {
            Print("wc: %s: No such file or directory\n", filepath);
            g_last_exit_code = 1;
            return;
        }
    }

    U8 buf[4096];
    I64 lines = 0, words = 0, bytes = 0;
    bool in_word = false;
    I64 n;

    while ((n = SysRead(fd, buf, sizeof(buf))) > 0) {
        bytes += n;
        for (I64 i = 0; i < n; ++i) {
            if (buf[i] == '\n') lines++;
            if (isspace((unsigned char)buf[i])) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                words++;
            }
        }
    }

    if (filepath && fd != STDIN_FILENO) SysClose(fd);

    char out_str[128];
    if (opt_l && !opt_w && !opt_c) {
        if (filepath) snprintf(out_str, sizeof(out_str), "%lld %s\n", (long long)lines, filepath);
        else snprintf(out_str, sizeof(out_str), "%lld\n", (long long)lines);
    } else if (!opt_l && opt_w && !opt_c) {
        if (filepath) snprintf(out_str, sizeof(out_str), "%lld %s\n", (long long)words, filepath);
        else snprintf(out_str, sizeof(out_str), "%lld\n", (long long)words);
    } else if (!opt_l && !opt_w && opt_c) {
        if (filepath) snprintf(out_str, sizeof(out_str), "%lld %s\n", (long long)bytes, filepath);
        else snprintf(out_str, sizeof(out_str), "%lld\n", (long long)bytes);
    } else {
        if (filepath) {
            snprintf(out_str, sizeof(out_str), " %5lld %5lld %5lld %s\n",
                     (long long)lines, (long long)words, (long long)bytes, filepath);
        } else {
            snprintf(out_str, sizeof(out_str), " %5lld %5lld %5lld\n",
                     (long long)lines, (long long)words, (long long)bytes);
        }
    }
    SysWrite(STDOUT_FILENO, (const U8*)out_str, strlen(out_str));
    g_last_exit_code = 0;
}

/* Helper string duplication with kernel MAlloc */
static char *HolyCStrDup(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char *copy = (char*)MAlloc(len + 1);
    if (copy) {
        memcpy(copy, s, len);
        copy[len] = '\0';
    }
    return copy;
}

/*
 * Built-in Command: tail
 */
U0 ShellCmdTail(I64 argc, char **argv) {
    I64 count = 10;
    const char *filepath = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-n") == 0 && i + 1 < argc) {
            count = atoll(argv[++i]);
            if (count < 0) count = 10;
        } else if (argv[i][0] == '-' && isdigit((unsigned char)argv[i][1])) {
            count = atoll(&argv[i][1]);
            if (count < 0) count = 10;
        } else {
            filepath = argv[i];
        }
    }

    I64 fd = STDIN_FILENO;
    if (filepath) {
        fd = SysOpen((const U8*)filepath, O_RDONLY);
        if (fd < 0) {
            Print("tail: cannot open '%s': No such file or directory\n", filepath);
            g_last_exit_code = 1;
            return;
        }
    }

    char lines[256][256];
    I64 total_lines = 0;
    char line_buf[256];
    I64 line_pos = 0;
    U8 ch;

    while (SysRead(fd, &ch, 1) > 0) {
        if (ch == '\n') {
            line_buf[line_pos] = '\0';
            I64 slot = total_lines % 256;
            strncpy(lines[slot], line_buf, 255);
            lines[slot][255] = '\0';
            total_lines++;
            line_pos = 0;
        } else if (line_pos < 254) {
            line_buf[line_pos++] = ch;
        }
    }
    if (line_pos > 0) {
        line_buf[line_pos] = '\0';
        I64 slot = total_lines % 256;
        strncpy(lines[slot], line_buf, 255);
        lines[slot][255] = '\0';
        total_lines++;
    }

    if (filepath && fd != STDIN_FILENO) SysClose(fd);

    I64 start = (total_lines > count) ? (total_lines - count) : 0;
    for (I64 i = start; i < total_lines; ++i) {
        I64 slot = i % 256;
        SysWrite(STDOUT_FILENO, (const U8*)lines[slot], strlen(lines[slot]));
        SysWrite(STDOUT_FILENO, (const U8*)"\n", 1);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: stat
 */
U0 ShellCmdStat(I64 argc, char **argv) {
    if (argc <= 1) {
        Print("stat: missing operand\n");
        g_last_exit_code = 1;
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        CKernelStat st;
        if (SysStat((const U8*)argv[i], &st) < 0) {
            Print("stat: cannot stat '%s': No such file or directory\n", argv[i]);
            g_last_exit_code = 1;
            continue;
        }
        const char *type_str = "regular file";
        if (st.st_mode & 0040000) type_str = "directory";
        else if (st.st_mode & 0120000) type_str = "symbolic link";
        else if (st.st_mode & 0020000) type_str = "character device";
        else if (st.st_mode & 0010000) type_str = "fifo / pipe";

        ShellPrintOut("  File: %s\n", argv[i]);
        ShellPrintOut("  Size: %-10lld Blocks: %-10lld IO Block: 4096   %s\n",
              (long long)st.st_size, (long long)((st.st_size + 511) / 512), type_str);
        ShellPrintOut("Device: 1          Inode: %-10lld Links: %lld\n",
              (long long)st.st_ino, (long long)st.st_nlink);
        ShellPrintOut("Access: (0%03o)  Uid: (%4lld)   Gid: (%4lld)\n",
              (unsigned int)(st.st_mode & 0777), (long long)st.st_uid, (long long)st.st_gid);
        ShellPrintOut("Modify: %lld\n", (long long)st.st_mtime);
        ShellPrintOut("Change: %lld\n", (long long)st.st_ctime);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: chmod
 */
U0 ShellCmdChmod(I64 argc, char **argv) {
    if (argc < 3) {
        Print("chmod: missing operand\nUsage: chmod <octal_mode> <file...>\n");
        g_last_exit_code = 1;
        return;
    }
    I64 mode = strtol(argv[1], NULL, 8);
    for (I64 i = 2; i < argc; ++i) {
        if (SysChmod((const U8*)argv[i], mode) < 0) {
            Print("chmod: cannot access '%s': No such file or directory\n", argv[i]);
            g_last_exit_code = 1;
            return;
        }
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: chown
 */
U0 ShellCmdChown(I64 argc, char **argv) {
    if (argc < 3) {
        Print("chown: missing operand\nUsage: chown <uid[:gid]> <file...>\n");
        g_last_exit_code = 1;
        return;
    }
    I64 uid = -1, gid = -1;
    char *colon = strchr(argv[1], ':');
    if (colon) {
        *colon = '\0';
        uid = atoll(argv[1]);
        gid = atoll(colon + 1);
    } else {
        uid = atoll(argv[1]);
    }

    for (I64 i = 2; i < argc; ++i) {
        if (SysChown((const U8*)argv[i], uid, gid) < 0) {
            Print("chown: cannot access '%s': No such file or directory\n", argv[i]);
            g_last_exit_code = 1;
            return;
        }
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: date
 */
U0 ShellCmdDate(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    time_t now = time(NULL);
    struct tm *tm_info = gmtime(&now);
    char buf[64];
    strftime(buf, sizeof(buf), "%a %b %d %H:%M:%S UTC %Y\n", tm_info);
    SysWrite(STDOUT_FILENO, (const U8*)buf, strlen(buf));
    g_last_exit_code = 0;
}

/*
 * Built-in Command: find
 */
static U0 ShellFindRecursive(CVFSInode *dir, const char *cur_path, const char *pat) {
    if (!dir || dir->type != VFS_DIRECTORY) return;
    for (I64 i = 0; i < dir->num_children; ++i) {
        I64 cinum = dir->children[i];
        CVFSInode *child = VFSGetInode(cinum);
        if (!child) continue;

        char subpath[MAX_PATH_LEN];
        if (strcmp(cur_path, "/") == 0) {
            snprintf(subpath, sizeof(subpath), "/%s", (const char*)child->name);
        } else {
            snprintf(subpath, sizeof(subpath), "%s/%s", cur_path, (const char*)child->name);
        }

        Bool match = TRUE;
        if (pat) {
            if (strstr((const char*)child->name, pat) == NULL) {
                match = FALSE;
            }
        }
        if (match) {
            SysWrite(STDOUT_FILENO, (const U8*)subpath, strlen(subpath));
            SysWrite(STDOUT_FILENO, (const U8*)"\n", 1);
        }

        if (child->type == VFS_DIRECTORY) {
            ShellFindRecursive(child, subpath, pat);
        }
    }
}

U0 ShellCmdFind(I64 argc, char **argv) {
    const char *start_path = ".";
    const char *pat = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-name") == 0 && i + 1 < argc) {
            pat = argv[++i];
        } else if (argv[i][0] != '-') {
            start_path = argv[i];
        }
    }

    CTask *t = TaskGetCurrent();
    I64 inum = VFSResolvePath((const U8*)start_path, t ? t->cwd : (const U8*)"/");
    if (inum < 0) {
        Print("find: '%s': No such file or directory\n", start_path);
        g_last_exit_code = 1;
        return;
    }
    CVFSInode *node = VFSGetInode(inum);
    if (!node) return;

    if (!pat || strstr((const char*)node->name, pat) != NULL) {
        SysWrite(STDOUT_FILENO, (const U8*)start_path, strlen(start_path));
        SysWrite(STDOUT_FILENO, (const U8*)"\n", 1);
    }
    if (node->type == VFS_DIRECTORY) {
        ShellFindRecursive(node, start_path, pat);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: sort
 */
static int StrCompareAsc(const void *a, const void *b) {
    return strcmp(*(const char**)a, *(const char**)b);
}
static int StrCompareDesc(const void *a, const void *b) {
    return strcmp(*(const char**)b, *(const char**)a);
}
static int NumCompareAsc(const void *a, const void *b) {
    long long na = atoll(*(const char**)a);
    long long nb = atoll(*(const char**)b);
    if (na < nb) return -1;
    if (na > nb) return 1;
    return 0;
}
static int NumCompareDesc(const void *a, const void *b) {
    long long na = atoll(*(const char**)a);
    long long nb = atoll(*(const char**)b);
    if (na > nb) return -1;
    if (na < nb) return 1;
    return 0;
}

U0 ShellCmdSort(I64 argc, char **argv) {
    Bool opt_r = FALSE;
    Bool opt_n = FALSE;
    const char *filepath = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-r") == 0) opt_r = TRUE;
        else if (strcmp(argv[i], "-n") == 0) opt_n = TRUE;
        else filepath = argv[i];
    }

    I64 fd = STDIN_FILENO;
    if (filepath) {
        fd = SysOpen((const U8*)filepath, O_RDONLY);
        if (fd < 0) {
            Print("sort: cannot open '%s'\n", filepath);
            g_last_exit_code = 1;
            return;
        }
    }

    char *lines[256];
    I64 count = 0;
    char line_buf[256];
    I64 lpos = 0;
    U8 ch;
    while (SysRead(fd, &ch, 1) > 0 && count < 256) {
        if (ch == '\n') {
            line_buf[lpos] = '\0';
            lines[count++] = HolyCStrDup(line_buf);
            lpos = 0;
        } else if (lpos < 254) {
            line_buf[lpos++] = ch;
        }
    }
    if (lpos > 0 && count < 256) {
        line_buf[lpos] = '\0';
        lines[count++] = HolyCStrDup(line_buf);
    }
    if (filepath && fd != STDIN_FILENO) SysClose(fd);

    if (opt_n) {
        qsort(lines, count, sizeof(char*), opt_r ? NumCompareDesc : NumCompareAsc);
    } else {
        qsort(lines, count, sizeof(char*), opt_r ? StrCompareDesc : StrCompareAsc);
    }

    for (I64 i = 0; i < count; ++i) {
        SysWrite(STDOUT_FILENO, (const U8*)lines[i], strlen(lines[i]));
        SysWrite(STDOUT_FILENO, (const U8*)"\n", 1);
        Free(lines[i]);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: uniq
 */
U0 ShellCmdUniq(I64 argc, char **argv) {
    Bool opt_c = FALSE;
    const char *filepath = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-c") == 0) opt_c = TRUE;
        else filepath = argv[i];
    }

    I64 fd = STDIN_FILENO;
    if (filepath) {
        fd = SysOpen((const U8*)filepath, O_RDONLY);
        if (fd < 0) {
            Print("uniq: cannot open '%s'\n", filepath);
            g_last_exit_code = 1;
            return;
        }
    }

    char prev_line[256] = "";
    Bool has_prev = FALSE;
    I64 repeat_count = 0;
    char line_buf[256];
    I64 lpos = 0;
    U8 ch;

    while (SysRead(fd, &ch, 1) > 0) {
        if (ch == '\n') {
            line_buf[lpos] = '\0';
            if (has_prev) {
                if (strcmp(prev_line, line_buf) == 0) {
                    repeat_count++;
                } else {
                    if (opt_c) ShellPrintOut("%4lld %s\n", (long long)repeat_count, prev_line);
                    else ShellPrintOut("%s\n", prev_line);
                    strcpy(prev_line, line_buf);
                    repeat_count = 1;
                }
            } else {
                strcpy(prev_line, line_buf);
                has_prev = TRUE;
                repeat_count = 1;
            }
            lpos = 0;
        } else if (lpos < 254) {
            line_buf[lpos++] = ch;
        }
    }
    if (lpos > 0) {
        line_buf[lpos] = '\0';
        if (has_prev && strcmp(prev_line, line_buf) == 0) {
            repeat_count++;
        } else {
            if (has_prev) {
                if (opt_c) ShellPrintOut("%4lld %s\n", (long long)repeat_count, prev_line);
                else ShellPrintOut("%s\n", prev_line);
            }
            strcpy(prev_line, line_buf);
            repeat_count = 1;
            has_prev = TRUE;
        }
    }
    if (has_prev) {
        if (opt_c) ShellPrintOut("%4lld %s\n", (long long)repeat_count, prev_line);
        else ShellPrintOut("%s\n", prev_line);
    }
    if (filepath && fd != STDIN_FILENO) SysClose(fd);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: tee
 */
U0 ShellCmdTee(I64 argc, char **argv) {
    Bool append = FALSE;
    I64 file_start = 1;
    if (argc > 1 && strcmp(argv[1], "-a") == 0) {
        append = TRUE;
        file_start = 2;
    }

    I64 file_fds[MAX_ARGS];
    I64 num_fds = 0;
    I64 flags = O_CREAT | O_WRONLY | (append ? O_APPEND : O_TRUNC);

    for (I64 i = file_start; i < argc; ++i) {
        I64 fd = SysOpen((const U8*)argv[i], flags);
        if (fd >= 0) {
            file_fds[num_fds++] = fd;
        }
    }

    U8 buf[512];
    I64 n = 0;
    while ((n = SysRead(STDIN_FILENO, buf, sizeof(buf))) > 0) {
        SysWrite(STDOUT_FILENO, buf, n);
        for (I64 i = 0; i < num_fds; ++i) {
            SysWrite(file_fds[i], buf, n);
        }
    }

    for (I64 i = 0; i < num_fds; ++i) {
        SysClose(file_fds[i]);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: sleep
 */
U0 ShellCmdSleep(I64 argc, char **argv) {
    if (argc < 2) {
        Print("sleep: missing operand\n");
        g_last_exit_code = 1;
        return;
    }
    I64 sec = atoll(argv[1]);
    if (sec > 0) {
        SysSleep(sec * 1000);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: df
 */
U0 ShellCmdDf(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    ShellPrintOut("Filesystem     1K-blocks      Used Available Use% Mounted on\n");
    ShellPrintOut("holyfs              4096       128      3968   3% /\n");
    ShellPrintOut("devfs                512         5       507   1% /dev\n");
    ShellPrintOut("procfs               512         6       506   1% /proc\n");
    g_last_exit_code = 0;
}

/*
 * Built-in Command: du
 */
U0 ShellCmdDu(I64 argc, char **argv) {
    const char *target = (argc > 1) ? argv[1] : ".";
    CTask *t = TaskGetCurrent();
    I64 inum = VFSResolvePath((const U8*)target, t ? t->cwd : (const U8*)"/");
    if (inum < 0) {
        Print("du: cannot access '%s': No such file or directory\n", target);
        g_last_exit_code = 1;
        return;
    }
    CVFSInode *node = VFSGetInode(inum);
    if (!node) return;
    I64 kbytes = (node->size + 1023) / 1024;
    if (kbytes == 0) kbytes = 4;
    ShellPrintOut("%lld\t%s\n", (long long)kbytes, target);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: diff
 */
U0 ShellCmdDiff(I64 argc, char **argv) {
    if (argc < 3) {
        Print("diff: missing operands\nUsage: diff <file1> <file2>\n");
        g_last_exit_code = 2;
        return;
    }
    I64 fd1 = SysOpen((const U8*)argv[1], O_RDONLY);
    I64 fd2 = SysOpen((const U8*)argv[2], O_RDONLY);
    if (fd1 < 0 || fd2 < 0) {
        Print("diff: cannot open input files\n");
        if (fd1 >= 0) SysClose(fd1);
        if (fd2 >= 0) SysClose(fd2);
        g_last_exit_code = 2;
        return;
    }

    U8 b1[4096], b2[4096];
    I64 n1 = SysRead(fd1, b1, sizeof(b1) - 1);
    I64 n2 = SysRead(fd2, b2, sizeof(b2) - 1);
    SysClose(fd1);
    SysClose(fd2);

    if (n1 < 0) n1 = 0;
    if (n2 < 0) n2 = 0;
    b1[n1] = '\0';
    b2[n2] = '\0';

    if (strcmp((char*)b1, (char*)b2) == 0) {
        g_last_exit_code = 0; /* Identical */
    } else {
        ShellPrintOut("< %s\n> %s\n", argv[1], argv[2]);
        g_last_exit_code = 1; /* Different */
    }
}

/*
 * Built-in Command: hexdump / xxd
 */
U0 ShellCmdHexdump(I64 argc, char **argv) {
    const char *filepath = (argc > 1) ? argv[1] : NULL;
    I64 fd = STDIN_FILENO;
    if (filepath) {
        fd = SysOpen((const U8*)filepath, O_RDONLY);
        if (fd < 0) {
            Print("hexdump: cannot open '%s'\n", filepath);
            g_last_exit_code = 1;
            return;
        }
    }
    U8 buf[16];
    I64 offset = 0;
    I64 n = 0;
    while ((n = SysRead(fd, buf, 16)) > 0) {
        ShellPrintOut("%08llx: ", (long long)offset);
        for (I64 i = 0; i < 16; ++i) {
            if (i < n) ShellPrintOut("%02x ", buf[i]);
            else ShellPrintOut("   ");
            if (i == 7) ShellPrintOut(" ");
        }
        ShellPrintOut(" |");
        for (I64 i = 0; i < n; ++i) {
            char c = (buf[i] >= 32 && buf[i] < 127) ? buf[i] : '.';
            ShellPrintOut("%c", c);
        }
        ShellPrintOut("|\n");
        offset += n;
        if (offset >= 256) break;
    }
    if (filepath && fd != STDIN_FILENO) SysClose(fd);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: cal
 */
U0 ShellCmdCal(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    time_t now = time(NULL);
    struct tm *t = gmtime(&now);
    char title[32];
    strftime(title, sizeof(title), "%B %Y", t);
    ShellPrintOut("     %s\n", title);
    ShellPrintOut("Su Mo Tu We Th Fr Sa\n");
    I64 day = 1;
    for (I64 row = 0; row < 5; ++row) {
        for (I64 col = 0; col < 7; ++col) {
            if (day <= 31) {
                ShellPrintOut("%2lld ", (long long)day++);
            }
        }
        ShellPrintOut("\n");
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: seq
 */
U0 ShellCmdSeq(I64 argc, char **argv) {
    if (argc < 2) {
        Print("seq: missing operand\n");
        g_last_exit_code = 1;
        return;
    }
    I64 first = 1, step = 1, last = 1;
    if (argc == 2) {
        last = atoll(argv[1]);
    } else if (argc == 3) {
        first = atoll(argv[1]);
        last = atoll(argv[2]);
    } else if (argc >= 4) {
        first = atoll(argv[1]);
        step = atoll(argv[2]);
        last = atoll(argv[3]);
    }
    if (step == 0) step = 1;
    for (I64 i = first; (step > 0 ? i <= last : i >= last); i += step) {
        ShellPrintOut("%lld\n", (long long)i);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: ln
 */
U0 ShellCmdLn(I64 argc, char **argv) {
    Bool is_symlink = FALSE;
    I64 start = 1;
    if (argc > 1 && strcmp(argv[1], "-s") == 0) {
        is_symlink = TRUE;
        start = 2;
    }
    if (argc - start < 2) {
        Print("ln: missing file operand\nUsage: ln [-s] <target> <linkname>\n");
        g_last_exit_code = 1;
        return;
    }
    const char *target = argv[start];
    const char *linkname = argv[start + 1];

    if (is_symlink) {
        if (SysSymlink((const U8*)target, (const U8*)linkname) < 0) {
            Print("ln: failed to create symbolic link '%s': File exists or invalid\n", linkname);
            g_last_exit_code = 1;
            return;
        }
    } else {
        char *cp_argv[3] = { (char*)"cp", (char*)target, (char*)linkname };
        ShellCmdCp(3, cp_argv);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: readlink
 */
U0 ShellCmdReadlink(I64 argc, char **argv) {
    if (argc < 2) {
        Print("readlink: missing operand\n");
        g_last_exit_code = 1;
        return;
    }
    U8 buf[MAX_PATH_LEN];
    I64 len = SysReadlink((const U8*)argv[1], buf, sizeof(buf));
    if (len < 0) {
        g_last_exit_code = 1;
        return;
    }
    ShellPrintOut("%s\n", buf);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: export
 */
U0 ShellCmdExport(I64 argc, char **argv) {
    if (argc <= 1) {
        for (I64 i = 0; i < g_env_count; ++i) {
            ShellPrintOut("export %s=\"%s\"\n", g_env_vars[i].key, g_env_vars[i].val);
        }
        g_last_exit_code = 0;
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        char *eq = strchr(argv[i], '=');
        if (eq) {
            *eq = '\0';
            char *k = argv[i];
            char *v = eq + 1;
            if (v[0] == '$') {
                const char *exp = ShellGetEnv(v + 1);
                if (exp) v = (char*)exp;
            }
            ShellSetEnv(k, v);
        } else {
            ShellSetEnv(argv[i], "");
        }
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: env / printenv
 */
U0 ShellCmdEnv(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    for (I64 i = 0; i < g_env_count; ++i) {
        ShellPrintOut("%s=%s\n", g_env_vars[i].key, g_env_vars[i].val);
    }
    g_last_exit_code = 0;
}

/* Forward declarations */
I64 ShellRunLogicalLine(char *line);
I64 ShellExecutePipeline(char *cmdline);

/*
 * Built-in Command: source / .
 */
U0 ShellCmdSource(I64 argc, char **argv) {
    if (argc < 2) {
        Print("source: filename argument required\n");
        g_last_exit_code = 1;
        return;
    }
    I64 fd = SysOpen((const U8*)argv[1], O_RDONLY);
    if (fd < 0) {
        Print("source: %s: file not found\n", argv[1]);
        g_last_exit_code = 1;
        return;
    }
    char buf[4096];
    I64 n = SysRead(fd, (U8*)buf, sizeof(buf) - 1);
    SysClose(fd);
    if (n > 0) {
        buf[n] = '\0';
        char *saveptr = NULL;
        char *line = strtok_r(buf, "\r\n", &saveptr);
        while (line) {
            while (*line && isspace((unsigned char)*line)) line++;
            if (*line && *line != '#') {
                ShellRunLogicalLine(line);
            }
            line = strtok_r(NULL, "\r\n", &saveptr);
        }
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: run (Execute HolyC script file)
 */
U0 ShellCmdRun(I64 argc, char **argv) {
    if (argc < 2) {
        Print("run: missing script filename (.HC)\nUsage: run <script.HC>\n");
        g_last_exit_code = 1;
        return;
    }
    HolyCRunScript((const U8*)argv[1]);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: beep (TempleOS PC Speaker Simulation)
 */
U0 ShellCmdBeep(I64 argc, char **argv) {
    I64 freq = (argc > 1) ? atoll(argv[1]) : 440;
    I64 dur  = (argc > 2) ? atoll(argv[2]) : 200;
    Print("\a");
    KLog("[PC SPEAKER] Beep: %lld Hz for %lld ms", (long long)freq, (long long)dur);
    Print("\033[93m[Beep: %lld Hz, %lld ms]\033[0m\n", (long long)freq, (long long)dur);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: godsong (TempleOS Divine Melody Generator)
 */
U0 ShellCmdGodSong(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    const char *notes[] = { "C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5" };
    Print("\033[93m=== TempleOS Divine GodSong ===\033[0m\n");
    Print("Melody: ");
    for (I64 i = 0; i < 8; ++i) {
        Print("%s ", notes[RandU64() % 8]);
    }
    Print("\nLyrics: \033[96m");
    for (I64 i = 0; i < 6; ++i) {
        Print("%s ", GodGetWord());
    }
    Print("\033[0m\n");
    Print("\a");
    g_last_exit_code = 0;
}

/*
 * Built-in Command: donut (TempleOS 3D Wireframe Cube)
 */
U0 ShellCmdDonut(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    Print("\033[2J\033[H\033[93m=== TempleOS 3D Divine Cube ===\033[0m\n");
    Print("\033[96m");
    Print("       +---------+\n");
    Print("      /         /|\n");
    Print("     /         / |\n");
    Print("    +---------+  |\n");
    Print("    |  God    |  |\n");
    Print("    | Speaks  |  +\n");
    Print("    | 64-bit  | /\n");
    Print("    | Ring0   |/\n");
    Print("    +---------+\n");
    Print("\033[0m");
    Print("Divine Word: \033[92m%s %s %s\033[0m\n",
          GodGetWord(), GodGetWord(), GodGetWord());
    g_last_exit_code = 0;
}

/*
 * Built-in Command: top (Live System Monitor)
 */
U0 ShellCmdTop(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    Print("\033[?25l"); /* Hide cursor */
    for (I64 iter = 0; iter < 10; ++iter) {
        TermClearScreen();
        Print("\033[93m================= HolyC Unix Process Monitor (top) =================\033[0m\n");
        Print("Uptime: %llds | Tasks: %lld active | Kernel: 64-bit HolyC | Mode: Ring0 Flat\n\n",
              (long long)KernelGetUptimeSec(), (long long)MAX_TASKS);
        U8 buf[2048];
        TaskFormatProcTasks(buf, sizeof(buf));
        Print("%s\n", buf);
        Print("\033[90m(Auto-refreshing... Press Ctrl+C or wait 5s to exit)\033[0m\n");
        SleepMs(500);
    }
    Print("\033[?25h"); /* Restore cursor */
}

/*
 * Built-in Command: help
 */
U0 ShellCmdHelp(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    Print("\033[93m======================= HolyC Unix Shell (holysh) =======================\033[0m\n");
    Print("Built-in Unix Commands:\n");
    Print("  \033[92mls [-l, -a] [dir]\033[0m   List directory contents with color\n");
    Print("  \033[92mcd [dir]\033[0m            Change current working directory\n");
    Print("  \033[92mpwd\033[0m                 Print current working directory\n");
    Print("  \033[92mcat [file...]\033[0m       Concatenate and display files or devices\n");
    Print("  \033[92mecho [args...]\033[0m      Display text, expand $USER, $HOME, $VAR\n");
    Print("  \033[92mmkdir [dir]\033[0m         Create directories\n");
    Print("  \033[92mtouch [file]\033[0m        Create empty files or update timestamps\n");
    Print("  \033[92mrm [file]\033[0m           Remove files from the VFS\n");
    Print("  \033[92mcp <src> <dst>\033[0m      Copy files\n");
    Print("  \033[92mmv <src> <dst>\033[0m      Move / rename files\n");
    Print("  \033[92mps\033[0m                  Report snapshot of current processes\n");
    Print("  \033[92mkill <pid>\033[0m          Send termination signal to process\n");
    Print("  \033[92mtop\033[0m                 Live process and resource monitor\n");
    Print("  \033[92mgrep <pat> [file]\033[0m   Search pattern in file or stream\n");
    Print("  \033[92mhead [-n N] [file]\033[0m  Output the first lines of files\n");
    Print("  \033[92mtail [-n N] [file]\033[0m  Output the last lines of files\n");
    Print("  \033[92mwc [file]\033[0m           Count lines, words, and bytes\n");
    Print("  \033[92mstat <file>\033[0m         Display detailed inode status\n");
    Print("  \033[92mchmod <octal> <f>\033[0m   Change file permission bits\n");
    Print("  \033[92mchown <uid:gid> <f>\033[0m Change file owner and group\n");
    Print("  \033[92mdate\033[0m                Display current system date and time\n");
    Print("  \033[92mfind [dir] [-name]\033[0m  Search for files in a directory hierarchy\n");
    Print("  \033[92msort [-n, -r] [f]\033[0m   Sort lines of text files\n");
    Print("  \033[92muniq [-c] [file]\033[0m    Report or omit repeated lines\n");
    Print("  \033[92mtee [-a] [file...]\033[0m  Read from stdin and write to stdout & files\n");
    Print("  \033[92msleep <seconds>\033[0m     Delay for a specified amount of time\n");
    Print("  \033[92mdf / du\033[0m             Report filesystem disk space usage\n");
    Print("  \033[92mdiff <f1> <f2>\033[0m      Compare two files line by line\n");
    Print("  \033[92mhexdump / xxd\033[0m       ASCII / Hexadecimal dump\n");
    Print("  \033[92mcal / seq\033[0m           Display calendar / print number sequence\n");
    Print("  \033[92mln [-s] <tgt> <lnk>\033[0m Create hard or symbolic link\n");
    Print("  \033[92mreadlink <link>\033[0m     Print value of a symbolic link\n");
    Print("  \033[92mexport [K=V] / env\033[0m  Set or print environment variables\n");
    Print("  \033[92msource <script.sh>\033[0m  Execute shell commands from a script\n");
    Print("  \033[92mrun <script.HC>\033[0m     Execute a HolyC script with in-kernel JIT\n");
    Print("  \033[92mbeep [freq] [ms]\033[0m    Simulate PC Speaker terminal audio\n");
    Print("  \033[92mgodsong\033[0m             TempleOS Divine melody and lyric generator\n");
    Print("  \033[92mdonut\033[0m               Render TempleOS 3D wireframe ASCII cube\n");
    Print("  \033[92mclear\033[0m               Clear terminal screen (also Ctrl+L)\n");
    Print("  \033[92muname [-a]\033[0m          Print operating system name & hardware info\n");
    Print("  \033[92muptime / whoami\033[0m     Show uptime / print effective user\n");
    Print("  \033[92mdmesg\033[0m               Print kernel message buffer & boot logs\n");
    Print("  \033[92med <file>\033[0m           Built-in terminal text editor (ed/nano style)\n");
    Print("  \033[92mgod [n]\033[0m             Consult Terry Davis's TempleOS Divine Oracle\n");
    Print("  \033[92mholyc [file.HC]\033[0m     Run HolyC scripts or enter interactive HolyC REPL\n");
    Print("  \033[92mtheme\033[0m               Toggle TempleOS 16-Color VGA Blue / Dark Unix theme\n");
    Print("  \033[92mexit / reboot\033[0m       Shut down or reboot the operating system\n");
    Print("Features: Pipelines (\033[96mcmd1 | cmd2\033[0m), Redirections (\033[96m< in\033[0m, \033[96m> out\033[0m, \033[96m>> out\033[0m), Logical (\033[96m&&\033[0m, \033[96m||\033[0m)\n");
    Print("\033[93m=========================================================================\033[0m\n");
}

/*
 * Dispatch a single command with argv
 */
I64 ShellExecuteCommand(I64 argc, char **argv) {
    if (argc == 0) return 0;
    const char *cmd = argv[0];

    if (strcmp(cmd, "ls") == 0)          ShellCmdLs(argc, argv);
    else if (strcmp(cmd, "cat") == 0)    ShellCmdCat(argc, argv);
    else if (strcmp(cmd, "echo") == 0)   ShellCmdEcho(argc, argv);
    else if (strcmp(cmd, "cd") == 0)     ShellCmdCd(argc, argv);
    else if (strcmp(cmd, "pwd") == 0)    ShellCmdPwd(argc, argv);
    else if (strcmp(cmd, "mkdir") == 0)  ShellCmdMkdir(argc, argv);
    else if (strcmp(cmd, "touch") == 0)  ShellCmdTouch(argc, argv);
    else if (strcmp(cmd, "rm") == 0)     ShellCmdRm(argc, argv);
    else if (strcmp(cmd, "cp") == 0)     ShellCmdCp(argc, argv);
    else if (strcmp(cmd, "mv") == 0)     ShellCmdMv(argc, argv);
    else if (strcmp(cmd, "ps") == 0)     ShellCmdPs(argc, argv);
    else if (strcmp(cmd, "kill") == 0)   ShellCmdKill(argc, argv);
    else if (strcmp(cmd, "uname") == 0)  ShellCmdUname(argc, argv);
    else if (strcmp(cmd, "uptime") == 0) ShellCmdUptime(argc, argv);
    else if (strcmp(cmd, "whoami") == 0) ShellCmdWhoami(argc, argv);
    else if (strcmp(cmd, "dmesg") == 0)  ShellCmdDmesg(argc, argv);
    else if (strcmp(cmd, "god") == 0)    ShellCmdGod(argc, argv);
    else if (strcmp(cmd, "grep") == 0)   ShellCmdGrep(argc, argv);
    else if (strcmp(cmd, "head") == 0)   ShellCmdHead(argc, argv);
    else if (strcmp(cmd, "tail") == 0)   ShellCmdTail(argc, argv);
    else if (strcmp(cmd, "wc") == 0)     ShellCmdWc(argc, argv);
    else if (strcmp(cmd, "stat") == 0)   ShellCmdStat(argc, argv);
    else if (strcmp(cmd, "chmod") == 0)  ShellCmdChmod(argc, argv);
    else if (strcmp(cmd, "chown") == 0)  ShellCmdChown(argc, argv);
    else if (strcmp(cmd, "date") == 0)   ShellCmdDate(argc, argv);
    else if (strcmp(cmd, "find") == 0)   ShellCmdFind(argc, argv);
    else if (strcmp(cmd, "sort") == 0)   ShellCmdSort(argc, argv);
    else if (strcmp(cmd, "uniq") == 0)   ShellCmdUniq(argc, argv);
    else if (strcmp(cmd, "tee") == 0)    ShellCmdTee(argc, argv);
    else if (strcmp(cmd, "sleep") == 0)  ShellCmdSleep(argc, argv);
    else if (strcmp(cmd, "df") == 0)     ShellCmdDf(argc, argv);
    else if (strcmp(cmd, "du") == 0)     ShellCmdDu(argc, argv);
    else if (strcmp(cmd, "diff") == 0)   ShellCmdDiff(argc, argv);
    else if (strcmp(cmd, "hexdump") == 0 || strcmp(cmd, "xxd") == 0) ShellCmdHexdump(argc, argv);
    else if (strcmp(cmd, "cal") == 0)    ShellCmdCal(argc, argv);
    else if (strcmp(cmd, "seq") == 0)    ShellCmdSeq(argc, argv);
    else if (strcmp(cmd, "ln") == 0)     ShellCmdLn(argc, argv);
    else if (strcmp(cmd, "readlink") == 0) ShellCmdReadlink(argc, argv);
    else if (strcmp(cmd, "export") == 0) ShellCmdExport(argc, argv);
    else if (strcmp(cmd, "env") == 0 || strcmp(cmd, "printenv") == 0) ShellCmdEnv(argc, argv);
    else if (strcmp(cmd, "source") == 0 || strcmp(cmd, ".") == 0) ShellCmdSource(argc, argv);
    else if (strcmp(cmd, "run") == 0)    ShellCmdRun(argc, argv);
    else if (strcmp(cmd, "beep") == 0)   ShellCmdBeep(argc, argv);
    else if (strcmp(cmd, "godsong") == 0) ShellCmdGodSong(argc, argv);
    else if (strcmp(cmd, "donut") == 0)  ShellCmdDonut(argc, argv);
    else if (strcmp(cmd, "true") == 0)   { g_last_exit_code = 0; return 0; }
    else if (strcmp(cmd, "false") == 0)  { g_last_exit_code = 1; return 1; }
    else if (strcmp(cmd, "top") == 0)    ShellCmdTop(argc, argv);
    else if (strcmp(cmd, "clear") == 0)  TermClearScreen();
    else if (strcmp(cmd, "theme") == 0)  TermToggleTheme();
    else if (strcmp(cmd, "help") == 0)   ShellCmdHelp(argc, argv);
    else if (strcmp(cmd, "ed") == 0) {
        if (argc > 1) EditorRun((const U8*)argv[1]);
        else Print("Usage: ed <filename>\n");
    } else if (strcmp(cmd, "holyc") == 0) {
        if (argc > 1) HolyCRunScript((const U8*)argv[1]);
        else HolyCRepl();
    } else if (strcmp(cmd, "exit") == 0 || strcmp(cmd, "reboot") == 0 || strcmp(cmd, "halt") == 0) {
        return -999; /* Signal to exit shell loop */
    } else {
        /* Check if argv[0] is a HolyC script in VFS */
        CTask *t = TaskGetCurrent();
        I64 inum = VFSResolvePath((const U8*)cmd, t ? t->cwd : (const U8*)"/");
        if (inum >= 0) {
            HolyCRunScript((const U8*)cmd);
            g_last_exit_code = 0;
        } else {
            Print("holysh: command not found: %s (type 'help' for commands)\n", cmd);
            g_last_exit_code = 127;
            return 127;
        }
    }
    return 0;
}

/*
 * Parse and execute command with pipe and redirection support
 */
I64 ShellExecutePipeline(char *cmdline) {
    while (*cmdline && isspace((unsigned char)*cmdline)) cmdline++;
    if (!*cmdline) return 0;

    /* Check for pipe '|' */
    char *pipe_pos = strchr(cmdline, '|');
    if (pipe_pos) {
        *pipe_pos = '\0';
        char *cmd1_str = cmdline;
        char *cmd2_str = pipe_pos + 1;

        /* Create pipe */
        I64 pipe_fds[2];
        if (SysPipe(pipe_fds) < 0) {
            Print("holysh: error creating pipe\n");
            return -1;
        }

        /* Save stdout and stdin */
        CTask *t = TaskGetCurrent();
        I64 saved_stdout = t->fd_table[STDOUT_FILENO];
        I64 saved_stdin  = t->fd_table[STDIN_FILENO];

        /* Redirect stdout to pipe write end */
        t->fd_table[STDOUT_FILENO] = t->fd_table[pipe_fds[1]];
        ShellExecutePipeline(cmd1_str);
        SysClose(pipe_fds[1]);

        /* Redirect stdin to pipe read end */
        t->fd_table[STDOUT_FILENO] = saved_stdout;
        t->fd_table[STDIN_FILENO]  = t->fd_table[pipe_fds[0]];
        ShellExecutePipeline(cmd2_str);
        SysClose(pipe_fds[0]);

        /* Restore stdin */
        t->fd_table[STDIN_FILENO]  = saved_stdin;
        return 0;
    }

    CTask *t = TaskGetCurrent();
    I64 saved_stdout = t ? t->fd_table[STDOUT_FILENO] : -1;
    I64 saved_stdin  = t ? t->fd_table[STDIN_FILENO]  : -1;
    I64 redir_fd = -1;
    I64 redir_in_fd = -1;

    char in_file[MAX_PATH_LEN] = "";
    char out_file[MAX_PATH_LEN] = "";
    Bool is_append = FALSE;

    char *rin = strchr(cmdline, '<');
    char *rout = strchr(cmdline, '>');

    if (rout) {
        char *pout = rout;
        if (*(pout + 1) == '>') {
            is_append = TRUE;
            pout += 2;
        } else {
            pout += 1;
        }
        while (*pout && isspace((unsigned char)*pout)) pout++;
        I64 idx = 0;
        while (*pout && !isspace((unsigned char)*pout) && *pout != '<' && idx < MAX_PATH_LEN - 1) {
            out_file[idx++] = *pout++;
        }
        out_file[idx] = '\0';
    }

    if (rin) {
        char *pin = rin + 1;
        while (*pin && isspace((unsigned char)*pin)) pin++;
        I64 idx = 0;
        while (*pin && !isspace((unsigned char)*pin) && *pin != '>' && idx < MAX_PATH_LEN - 1) {
            in_file[idx++] = *pin++;
        }
        in_file[idx] = '\0';
    }

    /* Cut cmdline at the first redirection symbol */
    if (rin && rout) {
        if (rin < rout) *rin = '\0';
        else *rout = '\0';
    } else if (rin) {
        *rin = '\0';
    } else if (rout) {
        *rout = '\0';
    }

    if (in_file[0] != '\0') {
        redir_in_fd = SysOpen((const U8*)in_file, O_RDONLY);
        if (redir_in_fd >= 0 && t) {
            t->fd_table[STDIN_FILENO] = t->fd_table[redir_in_fd];
        } else {
            Print("holysh: cannot open input file '%s'\n", in_file);
            g_last_exit_code = 1;
        }
    }

    if (out_file[0] != '\0') {
        I64 flags = O_CREAT | O_WRONLY | (is_append ? O_APPEND : O_TRUNC);
        redir_fd = SysOpen((const U8*)out_file, flags);
        if (redir_fd >= 0 && t) {
            t->fd_table[STDOUT_FILENO] = t->fd_table[redir_fd];
        }
    }

    /* Tokenize command arguments */
    char *argv[MAX_ARGS];
    I64 argc = 0;
    char *saveptr = NULL;
    char *token = strtok_r(cmdline, " \t\r\n", &saveptr);
    while (token && argc < MAX_ARGS - 1) {
        if (token[0] == '$') {
            const char *val = ShellGetEnv(token + 1);
            if (val) argv[argc++] = (char*)val;
            else argv[argc++] = (char*)"";
        } else {
            argv[argc++] = token;
        }
        token = strtok_r(NULL, " \t\r\n", &saveptr);
    }
    argv[argc] = NULL;

    I64 res = ShellExecuteCommand(argc, argv);

    /* Restore stdout if redirected */
    if (out_file[0] != '\0' && t) {
        if (redir_fd >= 0) SysClose(redir_fd);
        t->fd_table[STDOUT_FILENO] = saved_stdout;
    }
    /* Restore stdin if redirected */
    if (in_file[0] != '\0' && t) {
        if (redir_in_fd >= 0) SysClose(redir_in_fd);
        t->fd_table[STDIN_FILENO] = saved_stdin;
    }

    return res;
}

/*
 * Execute logical line with && and ||
 */
I64 ShellRunLogicalLine(char *line) {
    char *p = line;
    I64 last_res = 0;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;

        char *cand_and = strstr(p, "&&");
        char *cand_or  = strstr(p, "||");
        char *next_op = NULL;
        Bool is_and = FALSE;

        if (cand_and && cand_or) {
            if (cand_and < cand_or) { next_op = cand_and; is_and = TRUE; }
            else { next_op = cand_or; is_and = FALSE; }
        } else if (cand_and) {
            next_op = cand_and;
            is_and = TRUE;
        } else if (cand_or) {
            next_op = cand_or;
            is_and = FALSE;
        }

        if (next_op) {
            *next_op = '\0';
            last_res = ShellExecutePipeline(p);
            p = next_op + 2;
            if (last_res == -999) return -999;

            if (is_and && last_res != 0) {
                char *skip_or = strstr(p, "||");
                if (skip_or) p = skip_or + 2;
                else break;
            } else if (!is_and && last_res == 0) {
                char *skip_and = strstr(p, "&&");
                if (skip_and) p = skip_and + 2;
                else break;
            }
        } else {
            last_res = ShellExecutePipeline(p);
            break;
        }
    }
    return last_res;
}

/*
 * Execute batch script file line-by-line
 */
I64 ShellExecuteScript(const char *path) {
    ShellInitEnv();
    I64 fd = SysOpen((const U8*)path, O_RDONLY);
    if (fd < 0) {
        Print("holysh: cannot open '%s'\n", path);
        return 1;
    }
    char buf[8192];
    I64 n = SysRead(fd, (U8*)buf, sizeof(buf) - 1);
    SysClose(fd);
    if (n <= 0) return 0;
    buf[n] = '\0';

    char *saveptr = NULL;
    char *line = strtok_r(buf, "\r\n", &saveptr);
    I64 res = 0;
    while (line) {
        while (*line && isspace((unsigned char)*line)) line++;
        if (*line && *line != '#') {
            res = ShellRunLogicalLine(line);
            if (res == -999) break;
        }
        line = strtok_r(NULL, "\r\n", &saveptr);
    }
    return res;
}

/*
 * Main Shell REPL Loop
 */
U0 ShellRun() {
    ShellInitEnv();
    U8 line[512];
    CTask *t = TaskGetCurrent();

    while (1) {
        TaskYield();

        /* Format Prompt */
        U8 prompt[128];
        const char *user = (t && t->uid == 0) ? "root" : "terry";
        const char *prompt_char = (t && t->uid == 0) ? "#" : "$";
        const char *cwd = t ? (const char*)t->cwd : "/";

        if (g_templeos_blue_theme) {
            snprintf((char*)prompt, sizeof(prompt),
                     "\033[93m%s@holy-unix\033[97m:\033[96m%s\033[97m%s ",
                     user, cwd, prompt_char);
        } else {
            snprintf((char*)prompt, sizeof(prompt),
                     "\033[92m%s@holy-unix\033[0m:\033[94m%s\033[0m%s ",
                     user, cwd, prompt_char);
        }

        I64 n = TermReadLine(line, sizeof(line), prompt);
        if (n < 0) {
            break;
        }
        if (n == 0) continue;

        /* Handle semicolon separated commands */
        char *saveptr = NULL;
        char *cmd_part = strtok_r((char*)line, ";", &saveptr);
        while (cmd_part) {
            I64 r = ShellRunLogicalLine(cmd_part);
            if (r == -999) {
                return; /* Clean exit */
            }
            cmd_part = strtok_r(NULL, ";", &saveptr);
        }
    }
}

#endif /* SHELL_HC */
