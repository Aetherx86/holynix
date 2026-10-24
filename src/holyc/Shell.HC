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

I64 ShellExecuteCommand(I64 argc, char **argv);

#define MAX_ALIASES 32

class CAlias {
    char name[32];
    char value[128];
    Bool active;
};

static CAlias g_aliases[MAX_ALIASES];
static I64 g_alias_count = 0;

U0 ShellSetAlias(const char *name, const char *val) {
    if (!name || !*name || !val) return;
    for (I64 i = 0; i < g_alias_count; ++i) {
        if (g_aliases[i].active && strcmp(g_aliases[i].name, name) == 0) {
            strncpy(g_aliases[i].value, val, sizeof(g_aliases[i].value) - 1);
            return;
        }
    }
    for (I64 i = 0; i < MAX_ALIASES; ++i) {
        if (!g_aliases[i].active) {
            strncpy(g_aliases[i].name, name, sizeof(g_aliases[i].name) - 1);
            strncpy(g_aliases[i].value, val, sizeof(g_aliases[i].value) - 1);
            g_aliases[i].active = TRUE;
            if (i >= g_alias_count) g_alias_count = i + 1;
            return;
        }
    }
}

const char *ShellGetAlias(const char *name) {
    if (!name || !*name) return NULL;
    for (I64 i = 0; i < g_alias_count; ++i) {
        if (g_aliases[i].active && strcmp(g_aliases[i].name, name) == 0) {
            return g_aliases[i].value;
        }
    }
    return NULL;
}

U0 ShellRemoveAlias(const char *name) {
    if (!name) return;
    for (I64 i = 0; i < g_alias_count; ++i) {
        if (g_aliases[i].active && strcmp(g_aliases[i].name, name) == 0) {
            g_aliases[i].active = FALSE;
            return;
        }
    }
}

U0 ShellInitAliases() {
    static Bool initialized = FALSE;
    if (initialized) return;
    initialized = TRUE;
    ShellSetAlias("ll", "ls -l");
    ShellSetAlias("la", "ls -a");
    ShellSetAlias("cls", "clear");
    ShellSetAlias("h", "history");
    ShellSetAlias("..", "cd ..");
    ShellSetAlias("godword", "god 1");
}

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
    ShellInitAliases();
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
    ShellPrintOut("%s\n", (t && t->uid == 0) ? "root" : (t && t->uid == 777 ? "god" : "terry"));
}

/*
 * Built-in Command: id
 */
U0 ShellCmdId(I64 argc, char **argv) {
    CTask *t = TaskGetCurrent();
    const char *u = "terry";
    if (argc > 1) {
        u = argv[1];
    } else if (t) {
        if (t->uid == 0) u = "root";
        else if (t->uid == 777) u = "god";
    }

    if (strcmp(u, "root") == 0) {
        ShellPrintOut("uid=0(root) gid=0(root) groups=0(root),10(wheel)\n");
    } else if (strcmp(u, "god") == 0) {
        ShellPrintOut("uid=777(god) gid=777(god) groups=777(god),1000(terry)\n");
    } else {
        ShellPrintOut("uid=1000(terry) gid=1000(terry) groups=1000(terry),10(wheel),100(users)\n");
    }
}

/*
 * Built-in Command: groups
 */
U0 ShellCmdGroups(I64 argc, char **argv) {
    CTask *t = TaskGetCurrent();
    const char *u = "terry";
    if (argc > 1) {
        u = argv[1];
    } else if (t && t->uid == 0) {
        u = "root";
    }

    if (strcmp(u, "root") == 0) {
        ShellPrintOut("root wheel\n");
    } else {
        ShellPrintOut("terry wheel users divine\n");
    }
}

/*
 * Built-in Command: su
 */
U0 ShellCmdSu(I64 argc, char **argv) {
    CTask *t = TaskGetCurrent();
    const char *u = (argc > 1) ? argv[1] : "root";

    if (strcmp(u, "root") == 0) {
        if (t) { t->uid = 0; t->gid = 0; }
        ShellSetEnv("USER", "root");
        ShellSetEnv("HOME", "/root");
        ShellPrintOut("Switched to superuser root (UID 0)\n");
    } else if (strcmp(u, "terry") == 0) {
        if (t) { t->uid = 1000; t->gid = 1000; }
        ShellSetEnv("USER", "terry");
        ShellSetEnv("HOME", "/home/terry");
        ShellPrintOut("Switched to user terry (UID 1000)\n");
    } else if (strcmp(u, "god") == 0) {
        if (t) { t->uid = 777; t->gid = 777; }
        ShellSetEnv("USER", "god");
        ShellSetEnv("HOME", "/home/god");
        ShellPrintOut("Switched to user god (UID 777)\n");
    } else {
        ShellPrintOut("su: user '%s' does not exist\n", u);
        g_last_exit_code = 1;
        return;
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: sudo
 */
I64 ShellCmdSudo(I64 argc, char **argv) {
    if (argc < 2) {
        ShellPrintOut("usage: sudo command [args...]\n");
        g_last_exit_code = 1;
        return 1;
    }
    CTask *t = TaskGetCurrent();
    I64 saved_uid = t ? t->uid : 1000;
    I64 saved_gid = t ? t->gid : 1000;

    if (t) {
        t->uid = 0;
        t->gid = 0;
    }

    I64 res = ShellExecuteCommand(argc - 1, argv + 1);

    if (t) {
        t->uid = saved_uid;
        t->gid = saved_gid;
    }
    return res;
}

/*
 * Built-in Command: passwd
 */
U0 ShellCmdPasswd(I64 argc, char **argv) {
    const char *u = (argc > 1) ? argv[1] : "terry";
    ShellPrintOut("passwd: password updated successfully for %s\n", u);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: stty
 */
U0 ShellCmdStty(I64 argc, char **argv) {
    if (argc > 1) {
        if (strcmp(argv[1], "size") == 0) {
            ShellPrintOut("24 80\n");
            g_last_exit_code = 0;
            return;
        } else if (strcmp(argv[1], "raw") == 0) {
            ShellPrintOut("stty: terminal mode set to raw (-icanon -echo)\n");
            g_last_exit_code = 0;
            return;
        } else if (strcmp(argv[1], "cooked") == 0) {
            ShellPrintOut("stty: terminal mode set to cooked (+icanon +echo)\n");
            g_last_exit_code = 0;
            return;
        } else if (strcmp(argv[1], "echo") == 0) {
            ShellPrintOut("stty: echo enabled\n");
            g_last_exit_code = 0;
            return;
        } else if (strcmp(argv[1], "-echo") == 0) {
            ShellPrintOut("stty: echo disabled\n");
            g_last_exit_code = 0;
            return;
        }
    }

    ShellPrintOut("speed 38400 baud; rows 24; columns 80; line = 0;\n"
                  "intr = ^C; quit = ^\\; erase = ^?; kill = ^U; eof = ^D; eol = <undef>;\n"
                  "-parenb -parodd +cs8 -hupcl +cstopb -cread -clocal -crtscts\n"
                  "-ignbrk -brkint -ignpar -parmrk -inpck -istrip -inlcr -igncr -icrnl\n"
                  "-isig -icanon -iexten -echo -echoe -echok -echonl -noflsh\n");
    g_last_exit_code = 0;
}

/*
 * Built-in Command: test / [
 */
I64 ShellCmdTest(I64 argc, char **argv) {
    if (argc <= 1) {
        g_last_exit_code = 1;
        return 1;
    }

    I64 end_idx = argc - 1;
    if (strcmp(argv[0], "[") == 0) {
        if (strcmp(argv[end_idx], "]") == 0) {
            end_idx--;
        }
    }

    I64 num_args = end_idx;
    if (num_args < 1) {
        g_last_exit_code = 1;
        return 1;
    }

    I64 res = 1;
    CTask *t = TaskGetCurrent();
    const U8 *cwd = t ? t->cwd : (const U8*)"/";

    if (num_args == 1) {
        res = (argv[1][0] != '\0') ? 0 : 1;
    } else if (num_args == 2) {
        const char *op = argv[1];
        const char *arg = argv[2];
        if (strcmp(op, "-f") == 0) {
            I64 inum = VFSResolvePath((const U8*)arg, cwd);
            CVFSInode *inode = VFSGetInode(inum);
            res = (inode && inode->type == VFS_REGULAR) ? 0 : 1;
        } else if (strcmp(op, "-d") == 0) {
            I64 inum = VFSResolvePath((const U8*)arg, cwd);
            CVFSInode *inode = VFSGetInode(inum);
            res = (inode && inode->type == VFS_DIRECTORY) ? 0 : 1;
        } else if (strcmp(op, "-e") == 0) {
            I64 inum = VFSResolvePath((const U8*)arg, cwd);
            res = (inum >= 0) ? 0 : 1;
        } else if (strcmp(op, "-z") == 0) {
            res = (arg[0] == '\0') ? 0 : 1;
        } else if (strcmp(op, "-n") == 0) {
            res = (arg[0] != '\0') ? 0 : 1;
        }
    } else if (num_args == 3) {
        const char *left = argv[1];
        const char *op = argv[2];
        const char *right = argv[3];

        if (strcmp(op, "=") == 0 || strcmp(op, "==") == 0) {
            res = (strcmp(left, right) == 0) ? 0 : 1;
        } else if (strcmp(op, "!=") == 0) {
            res = (strcmp(left, right) != 0) ? 0 : 1;
        } else if (strcmp(op, "-eq") == 0) {
            res = (atoll(left) == atoll(right)) ? 0 : 1;
        } else if (strcmp(op, "-ne") == 0) {
            res = (atoll(left) != atoll(right)) ? 0 : 1;
        } else if (strcmp(op, "-lt") == 0) {
            res = (atoll(left) < atoll(right)) ? 0 : 1;
        } else if (strcmp(op, "-le") == 0) {
            res = (atoll(left) <= atoll(right)) ? 0 : 1;
        } else if (strcmp(op, "-gt") == 0) {
            res = (atoll(left) > atoll(right)) ? 0 : 1;
        } else if (strcmp(op, "-ge") == 0) {
            res = (atoll(left) >= atoll(right)) ? 0 : 1;
        }
    }

    g_last_exit_code = res;
    return res;
}

/*
 * Built-in Commands: man, apropos, whatis
 */
U0 ShellCmdMan(I64 argc, char **argv) {
    if (argc == 2) {
        g_last_exit_code = ManLookup(argv[1], 0);
    } else if (argc >= 3) {
        g_last_exit_code = ManLookup(argv[2], atoi(argv[1]));
    } else {
        Print("What manual page do you want?\n");
        g_last_exit_code = 1;
    }
}

U0 ShellCmdApropos(I64 argc, char **argv) {
    if (argc < 2) {
        Print("apropos what?\n");
        g_last_exit_code = 1;
        return;
    }
    g_last_exit_code = ManApropos(argv[1]);
}

U0 ShellCmdWhatis(I64 argc, char **argv) {
    if (argc < 2) {
        Print("whatis what?\n");
        g_last_exit_code = 1;
        return;
    }
    g_last_exit_code = ManWhatis(argv[1]);
}

/*
 * Built-in Command: curl / fetch
 */
U0 ShellCmdCurl(I64 argc, char **argv) {
    if (argc < 2) {
        Print("curl: try 'curl --help' or 'curl <url>'\n");
        g_last_exit_code = 1;
        return;
    }

    I64 flags = 0;
    const char *url = NULL;
    const char *outfile = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-i") == 0 || strcmp(argv[i], "-v") == 0) {
            flags |= CURL_FLAG_VERBOSE;
        } else if (strcmp(argv[i], "-I") == 0 || strcmp(argv[i], "--head") == 0) {
            flags |= CURL_FLAG_HEAD_ONLY;
        } else if (strcmp(argv[i], "-s") == 0) {
            flags |= CURL_FLAG_SILENT;
        } else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            outfile = argv[++i];
        } else if (!url) {
            url = argv[i];
        }
    }

    if (!url) {
        Print("curl: no URL specified\n");
        g_last_exit_code = 1;
        return;
    }

    char out_buf[4096];
    I64 n = NetCurl(url, flags, outfile, out_buf, sizeof(out_buf));
    if (n > 0) {
        ShellPrintOut("%s", out_buf);
        g_last_exit_code = 0;
    } else {
        Print("curl: failed to retrieve %s\n", url);
        g_last_exit_code = 1;
    }
}

/*
 * Built-in Commands: castle, afteregypt, flappy, wintile
 */
U0 ShellCmdCastle(I64 argc, char **argv) {
    g_last_exit_code = CastleRun(argc, argv);
}

U0 ShellCmdAfterEgypt(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    AfterEgyptRun();
    g_last_exit_code = 0;
}

U0 ShellCmdFlappy(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    FlappyRun();
    g_last_exit_code = 0;
}

U0 ShellCmdWinTile(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    WinTileRun();
    g_last_exit_code = 0;
}

/*
 * Built-in Command: cut
 */
U0 ShellCmdCut(I64 argc, char **argv) {
    char delim = '\t';
    I64 field = 1;
    const char *file = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "-d", 2) == 0) {
            if (strlen(argv[i]) > 2) delim = argv[i][2];
            else if (i + 1 < argc) delim = argv[++i][0];
        } else if (strncmp(argv[i], "-f", 2) == 0) {
            if (strlen(argv[i]) > 2) field = atoll(argv[i] + 2);
            else if (i + 1 < argc) field = atoll(argv[++i]);
        } else if (argv[i][0] != '-') {
            file = argv[i];
        }
    }

    I64 fd = STDIN_FILENO;
    if (file) {
        fd = SysOpen((const U8*)file, O_RDONLY);
        if (fd < 0) {
            Print("cut: %s: No such file or directory\n", file);
            g_last_exit_code = 1;
            return;
        }
    }

    char buf[4096];
    I64 n = SysRead(fd, (U8*)buf, sizeof(buf) - 1);
    if (file) SysClose(fd);
    if (n <= 0) return;
    buf[n] = '\0';

    char *saveptr = NULL;
    char *line = strtok_r(buf, "\r\n", &saveptr);
    while (line) {
        char *cur = line;
        I64 f = 1;
        char *val = cur;
        while (*cur) {
            if (*cur == delim) {
                if (f == field) {
                    *cur = '\0';
                    break;
                }
                f++;
                val = cur + 1;
            }
            cur++;
        }
        if (f == field) {
            ShellPrintOut("%s\n", val);
        } else {
            ShellPrintOut("%s\n", line);
        }
        line = strtok_r(NULL, "\r\n", &saveptr);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: tr
 */
U0 ShellCmdTr(I64 argc, char **argv) {
    if (argc < 2) {
        Print("usage: tr [-d] string1 [string2]\n");
        g_last_exit_code = 1;
        return;
    }
    Bool delete_mode = FALSE;
    const char *s1 = NULL;
    const char *s2 = NULL;

    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-d") == 0) {
            delete_mode = TRUE;
        } else if (!s1) {
            s1 = argv[i];
        } else if (!s2) {
            s2 = argv[i];
        }
    }

    char buf[4096];
    I64 n = SysRead(STDIN_FILENO, (U8*)buf, sizeof(buf) - 1);
    if (n <= 0) return;
    buf[n] = '\0';

    char out_buf[4096];
    I64 out_len = 0;

    for (I64 i = 0; i < n && out_len < (I64)sizeof(out_buf) - 1; ++i) {
        char c = buf[i];
        if (delete_mode) {
            if (!s1 || strchr(s1, c) == NULL) {
                out_buf[out_len++] = c;
            }
        } else if (s1 && s2) {
            if (strcmp(s1, "a-z") == 0 && strcmp(s2, "A-Z") == 0) {
                out_buf[out_len++] = (char)toupper((unsigned char)c);
            } else if (strcmp(s1, "A-Z") == 0 && strcmp(s2, "a-z") == 0) {
                out_buf[out_len++] = (char)tolower((unsigned char)c);
            } else {
                char *pos = strchr(s1, c);
                if (pos) {
                    I64 idx = pos - s1;
                    if (idx < (I64)strlen(s2)) out_buf[out_len++] = s2[idx];
                    else out_buf[out_len++] = s2[strlen(s2) - 1];
                } else {
                    out_buf[out_len++] = c;
                }
            }
        } else {
            out_buf[out_len++] = c;
        }
    }
    if (out_len > 0) {
        SysWrite(STDOUT_FILENO, (const U8*)out_buf, out_len);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: sed
 */
U0 ShellCmdSed(I64 argc, char **argv) {
    if (argc < 2) {
        Print("usage: sed 's/find/replace/g' [file]\n");
        g_last_exit_code = 1;
        return;
    }
    const char *expr = argv[1];
    char clean_expr[256];
    strncpy(clean_expr, expr, sizeof(clean_expr) - 1);
    clean_expr[sizeof(clean_expr) - 1] = '\0';
    if ((clean_expr[0] == '\'' || clean_expr[0] == '"') && strlen(clean_expr) >= 2) {
        char q = clean_expr[0];
        size_t elen = strlen(clean_expr);
        if (clean_expr[elen - 1] == q) clean_expr[elen - 1] = '\0';
        memmove(clean_expr, clean_expr + 1, elen);
    }
    expr = clean_expr;

    const char *file = (argc > 2) ? argv[2] : NULL;

    char find_str[128] = "";
    char repl_str[128] = "";
    Bool global_flag = FALSE;

    if (expr[0] == 's' && expr[1] == '/') {
        char *slash1 = (char*)expr + 1;
        char *slash2 = strchr(slash1 + 1, '/');
        if (slash2) {
            size_t flen = slash2 - (slash1 + 1);
            if (flen > 127) flen = 127;
            strncpy(find_str, slash1 + 1, flen);
            find_str[flen] = '\0';

            char *slash3 = strchr(slash2 + 1, '/');
            if (slash3) {
                size_t rlen = slash3 - (slash2 + 1);
                if (rlen > 127) rlen = 127;
                strncpy(repl_str, slash2 + 1, rlen);
                repl_str[rlen] = '\0';
                if (strchr(slash3 + 1, 'g')) global_flag = TRUE;
            } else {
                strncpy(repl_str, slash2 + 1, sizeof(repl_str) - 1);
            }
        }
    }

    I64 fd = STDIN_FILENO;
    if (file) {
        fd = SysOpen((const U8*)file, O_RDONLY);
        if (fd < 0) {
            ShellPrintOut("sed: %s: No such file or directory\n", file);
            g_last_exit_code = 1;
            return;
        }
    }

    char buf[4096];
    I64 n = SysRead(fd, (U8*)buf, sizeof(buf) - 1);
    if (file) SysClose(fd);
    if (n <= 0) return;
    buf[n] = '\0';

    if (find_str[0] == '\0') {
        ShellPrintOut("%s", buf);
        return;
    }

    char *p = buf;
    size_t flen = strlen(find_str);
    while (*p) {
        char *found = strstr(p, find_str);
        if (found) {
            while (p < found) {
                char ch = *p++;
                SysWrite(STDOUT_FILENO, (const U8*)&ch, 1);
            }
            ShellPrintOut("%s", repl_str);
            p += flen;
            if (!global_flag) {
                ShellPrintOut("%s", p);
                break;
            }
        } else {
            ShellPrintOut("%s", p);
            break;
        }
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: paste
 */
U0 ShellCmdPaste(I64 argc, char **argv) {
    if (argc < 3) {
        Print("usage: paste file1 file2\n");
        g_last_exit_code = 1;
        return;
    }
    I64 fd1 = SysOpen((const U8*)argv[1], O_RDONLY);
    I64 fd2 = SysOpen((const U8*)argv[2], O_RDONLY);
    if (fd1 < 0 || fd2 < 0) {
        if (fd1 >= 0) SysClose(fd1);
        if (fd2 >= 0) SysClose(fd2);
        Print("paste: file error\n");
        g_last_exit_code = 1;
        return;
    }
    char b1[2048], b2[2048];
    I64 n1 = SysRead(fd1, (U8*)b1, sizeof(b1) - 1);
    I64 n2 = SysRead(fd2, (U8*)b2, sizeof(b2) - 1);
    SysClose(fd1); SysClose(fd2);
    if (n1 > 0) b1[n1] = '\0'; else b1[0] = '\0';
    if (n2 > 0) b2[n2] = '\0'; else b2[0] = '\0';

    char *s1 = NULL, *s2 = NULL;
    char *l1 = strtok_r(b1, "\r\n", &s1);
    char *l2 = strtok_r(b2, "\r\n", &s2);
    while (l1 || l2) {
        ShellPrintOut("%s\t%s\n", l1 ? l1 : "", l2 ? l2 : "");
        l1 = strtok_r(NULL, "\r\n", &s1);
        l2 = strtok_r(NULL, "\r\n", &s2);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: fold
 */
U0 ShellCmdFold(I64 argc, char **argv) {
    I64 width = 80;
    const char *file = NULL;
    for (I64 i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "-w", 2) == 0) {
            if (strlen(argv[i]) > 2) width = atoll(argv[i] + 2);
            else if (i + 1 < argc) width = atoll(argv[++i]);
        } else if (argv[i][0] != '-') file = argv[i];
    }
    if (width <= 0) width = 80;
    I64 fd = file ? SysOpen((const U8*)file, O_RDONLY) : STDIN_FILENO;
    if (fd < 0) { ShellPrintOut("fold: cannot open file\n"); g_last_exit_code = 1; return; }
    char buf[4096];
    I64 n = SysRead(fd, (U8*)buf, sizeof(buf) - 1);
    if (file) SysClose(fd);
    if (n <= 0) return;
    buf[n] = '\0';
    I64 col = 0;
    for (I64 i = 0; i < n; ++i) {
        if (buf[i] == '\n') {
            SysWrite(STDOUT_FILENO, (const U8*)"\n", 1);
            col = 0;
        } else {
            SysWrite(STDOUT_FILENO, (const U8*)&buf[i], 1);
            col++;
            if (col >= width) {
                SysWrite(STDOUT_FILENO, (const U8*)"\n", 1);
                col = 0;
            }
        }
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Commands: basename, dirname
 */
U0 ShellCmdBasename(I64 argc, char **argv) {
    if (argc < 2) { Print("usage: basename string [suffix]\n"); g_last_exit_code = 1; return; }
    const char *p = argv[1];
    const char *slash = strrchr(p, '/');
    const char *base = slash ? slash + 1 : p;
    char out[256];
    strncpy(out, base, sizeof(out) - 1);
    out[sizeof(out) - 1] = '\0';
    if (argc > 2) {
        const char *suf = argv[2];
        size_t blen = strlen(out);
        size_t slen = strlen(suf);
        if (blen >= slen && strcmp(out + blen - slen, suf) == 0) {
            out[blen - slen] = '\0';
        }
    }
    ShellPrintOut("%s\n", out);
    g_last_exit_code = 0;
}

U0 ShellCmdDirname(I64 argc, char **argv) {
    if (argc < 2) { Print("usage: dirname string\n"); g_last_exit_code = 1; return; }
    const char *p = argv[1];
    const char *slash = strrchr(p, '/');
    if (!slash) { ShellPrintOut(".\n"); }
    else if (slash == p) { ShellPrintOut("/\n"); }
    else {
        char out[256];
        size_t dlen = slash - p;
        if (dlen > 255) dlen = 255;
        strncpy(out, p, dlen);
        out[dlen] = '\0';
        ShellPrintOut("%s\n", out);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Commands: lsmod, insmod, rmmod
 */
extern I64 ModuleFormatList(char *out_buf, I64 max_len);
extern I64 ModuleAdd(const char *name, I64 size, const char *author);
extern I64 ModuleRemove(const char *name);

U0 ShellCmdLsmod(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    char buf[2048];
    ModuleFormatList(buf, sizeof(buf));
    ShellPrintOut("%s", buf);
    g_last_exit_code = 0;
}

U0 ShellCmdInsmod(I64 argc, char **argv) {
    if (argc < 2) { Print("usage: insmod <module_name>\n"); g_last_exit_code = 1; return; }
    I64 res = ModuleAdd(argv[1], 16384, "User Module");
    if (res == 0) {
        ShellPrintOut("insmod: module '%s' loaded successfully\n", argv[1]);
        g_last_exit_code = 0;
    } else {
        Print("insmod: failed to load module '%s'\n", argv[1]);
        g_last_exit_code = 1;
    }
}

U0 ShellCmdRmmod(I64 argc, char **argv) {
    if (argc < 2) { Print("usage: rmmod <module_name>\n"); g_last_exit_code = 1; return; }
    I64 res = ModuleRemove(argv[1]);
    if (res == 0) {
        ShellPrintOut("rmmod: module '%s' unloaded\n", argv[1]);
        g_last_exit_code = 0;
    } else {
        Print("rmmod: cannot unload '%s' (not found or in use)\n", argv[1]);
        g_last_exit_code = 1;
    }
}

/*
 * Built-in Commands: vmstat, ulimit, pstree, ipcs
 */
U0 ShellCmdVmstat(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    ShellPrintOut("procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----\n"
                  " r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st\n"
                  " 1  0      0  49152   4096  12288    0    0     0     0   10   20  2  3 95  0  0\n");
    g_last_exit_code = 0;
}

U0 ShellCmdUlimit(I64 argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "-n") == 0) {
        ShellPrintOut("32\n");
    } else if (argc > 1 && strcmp(argv[1], "-s") == 0) {
        ShellPrintOut("8192\n");
    } else if (argc > 1 && strcmp(argv[1], "-u") == 0) {
        ShellPrintOut("64\n");
    } else {
        ShellPrintOut("core file size          (blocks, -c) 0\n"
                      "data seg size           (kbytes, -d) unlimited\n"
                      "file size               (blocks, -f) unlimited\n"
                      "open files                      (-n) 32\n"
                      "pipe size            (512 bytes, -p) 8\n"
                      "stack size              (kbytes, -s) 8192\n"
                      "max user processes              (-u) 64\n"
                      "virtual memory          (kbytes, -v) unlimited\n");
    }
    g_last_exit_code = 0;
}

extern I64 PSTreeFormat(char *out_buf, I64 max_len);
U0 ShellCmdPstree(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    char buf[512];
    PSTreeFormat(buf, sizeof(buf));
    ShellPrintOut("%s", buf);
    g_last_exit_code = 0;
}

U0 ShellCmdIpcs(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    ShellPrintOut("\n------ Message Queues --------\n"
                  "key        msqid      owner      perms      used-bytes   messages\n"
                  "\n------ Shared Memory Segments --------\n"
                  "key        shmid      owner      perms      bytes      nattch     status\n"
                  "0x00007777 0          terry      600        65536      1          dest\n"
                  "\n------ Semaphore Arrays --------\n"
                  "key        semid      owner      perms      nsems\n"
                  "0x00007778 0          terry      666        4\n\n");
    g_last_exit_code = 0;
}

/*
 * Built-in Commands: holyfetch, play, juke, screenshot
 */
U0 ShellCmdHolyFetch(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    HolyFetchRun();
    g_last_exit_code = 0;
}

U0 ShellCmdPlay(I64 argc, char **argv) {
    const char *mstr = (argc > 1) ? argv[1] : "3q.D4DhE2G";
    PlayMusicString(mstr);
    g_last_exit_code = 0;
}

U0 ShellCmdJuke(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    JukeRun();
    g_last_exit_code = 0;
}

U0 ShellCmdScreenshot(I64 argc, char **argv) {
    const char *dst = (argc > 1) ? argv[1] : "/home/terry/screenshot.DD";
    ScreenshotRun(dst);
    g_last_exit_code = 0;
}

/*
 * Built-in Commands: flight, matrix, linecnt, hcbench, godword
 */
U0 ShellCmdFlight(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    FlightRun();
    g_last_exit_code = 0;
}

U0 ShellCmdMatrix(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    MatrixRun();
    g_last_exit_code = 0;
}

U0 ShellCmdLineCnt(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    LineCntRun();
    g_last_exit_code = 0;
}

U0 ShellCmdHcBench(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    HcBenchRun();
    g_last_exit_code = 0;
}

U0 ShellCmdGodWord(I64 argc, char **argv) {
    I64 count = 1;
    if (argc > 1) {
        count = atoll(argv[1]);
        if (count <= 0) count = 1;
        if (count > 20) count = 20;
    }
    for (I64 i = 0; i < count; ++i) {
        ShellPrintOut("%s%s", GodGetWord(), (i + 1 < count) ? " " : "\n");
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Commands: which, type, hostname, sync, who, w, nl, xxd, time
 */
U0 ShellCmdWhich(I64 argc, char **argv) {
    if (argc < 2) {
        Print("usage: which command ...\n");
        g_last_exit_code = 1;
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        const char *name = argv[i];
        const char *al = ShellGetAlias(name);
        if (al && *al) {
            ShellPrintOut("%s: aliased to %s\n", name, al);
            continue;
        }
        static const char *known_builtins[] = {
            "ls", "cd", "pwd", "mkdir", "touch", "rm", "cp", "mv", "cat", "echo",
            "ps", "kill", "uname", "uptime", "whoami", "dmesg", "god", "grep",
            "head", "tail", "wc", "stat", "chmod", "chown", "date", "find",
            "sort", "uniq", "tee", "seq", "ln", "readlink", "df", "du", "diff",
            "hexdump", "cal", "sleep", "exit", "export", "env", "printenv",
            "source", ".", "alias", "unalias", "history", "jobs", "fg", "bg",
            "sysctl", "tar", "ping", "netstat", "cron", "crontab", "doldoc",
            "holyless", "bible", "godpassage", "goddoodle", "redsea", "peek",
            "poke", "memdump", "disasm", "hpm", "man", "apropos", "whatis",
            "curl", "fetch", "id", "groups", "su", "sudo", "passwd", "stty",
            "test", "[", "castle", "afteregypt", "flappy", "wintile", "split",
            "cut", "tr", "sed", "paste", "fold", "basename", "dirname",
            "lsmod", "insmod", "rmmod", "vmstat", "pstree", "ulimit", "ipcs",
            "holyfetch", "neofetch", "play", "music", "juke", "screenshot",
            "fbgrab", "flight", "matrix", "linecnt", "hcbench", "hostname",
            "clear", "sync", "who", "w", "nl", "xxd", "time", "godword", NULL
        };
        Bool is_builtin = FALSE;
        for (I64 b = 0; known_builtins[b]; ++b) {
            if (strcmp(name, known_builtins[b]) == 0) {
                is_builtin = TRUE;
                break;
            }
        }
        if (is_builtin) {
            ShellPrintOut("/bin/%s\n", name);
            g_last_exit_code = 0;
        } else {
            ShellPrintOut("which: no %s in (/bin:/usr/bin:/sbin)\n", name);
            g_last_exit_code = 1;
        }
    }
}

U0 ShellCmdType(I64 argc, char **argv) {
    if (argc < 2) {
        Print("usage: type name ...\n");
        g_last_exit_code = 1;
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        const char *name = argv[i];
        const char *al = ShellGetAlias(name);
        if (al && *al) {
            ShellPrintOut("%s is an alias for %s\n", name, al);
            continue;
        }
        ShellPrintOut("%s is a shell builtin\n", name);
    }
    g_last_exit_code = 0;
}

U0 ShellCmdHostname(I64 argc, char **argv) {
    if (argc > 1) {
        CTask *t = TaskGetCurrent();
        if (t && t->uid != 0) {
            Print("hostname: you must be root to change the host name\n");
            g_last_exit_code = 1;
            return;
        }
        strncpy(g_sysctl_hostname, argv[1], sizeof(g_sysctl_hostname) - 1);
        g_sysctl_hostname[sizeof(g_sysctl_hostname) - 1] = '\0';
        ShellPrintOut("hostname updated to '%s'\n", argv[1]);
    } else {
        ShellPrintOut("%s\n", g_sysctl_hostname);
    }
    g_last_exit_code = 0;
}

U0 ShellCmdSync(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    ShellPrintOut("sync: flushing dirty VFS inode blocks to storage... [OK]\n");
    g_last_exit_code = 0;
}

U0 ShellCmdWho(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    CTask *t = TaskGetCurrent();
    const char *u = (t && t->uid == 0) ? "root" : (t && t->uid == 777 ? "god" : "terry");
    ShellPrintOut("%-8s tty1         2026-10-24 15:00 (:0)\n", u);
    g_last_exit_code = 0;
}

U0 ShellCmdW(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    CTask *t = TaskGetCurrent();
    const char *u = (t && t->uid == 0) ? "root" : (t && t->uid == 777 ? "god" : "terry");
    ShellPrintOut(" 15:00:00 up %lld seconds, 1 user, load average: 0.08, 0.02, 0.01\n", (long long)KernelGetUptimeSec());
    ShellPrintOut("%-8s TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT\n", "USER");
    ShellPrintOut("%-8s tty1     :0               15:00    0.00s  0.05s  0.01s holysh\n", u);
    g_last_exit_code = 0;
}

U0 ShellCmdNl(I64 argc, char **argv) {
    I64 fd = STDIN_FILENO;
    const char *file = (argc > 1) ? argv[1] : NULL;
    if (file) {
        fd = SysOpen((const U8*)file, O_RDONLY);
        if (fd < 0) {
            ShellPrintOut("nl: %s: No such file or directory\n", file);
            g_last_exit_code = 1;
            return;
        }
    }
    char buf[4096];
    I64 n = SysRead(fd, (U8*)buf, sizeof(buf) - 1);
    if (file) SysClose(fd);
    if (n <= 0) return;
    buf[n] = '\0';

    I64 line_no = 1;
    char *p = buf;
    while (*p) {
        char *eol = strchr(p, '\n');
        if (eol) *eol = '\0';
        ShellPrintOut("%6lld\t%s\n", (long long)line_no++, p);
        if (!eol) break;
        p = eol + 1;
    }
    g_last_exit_code = 0;
}

U0 ShellCmdXxd(I64 argc, char **argv) {
    Bool plain = FALSE;
    const char *file = NULL;
    for (I64 i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-p") == 0) plain = TRUE;
        else if (argv[i][0] != '-') file = argv[i];
    }
    I64 fd = file ? SysOpen((const U8*)file, O_RDONLY) : STDIN_FILENO;
    if (fd < 0) {
        ShellPrintOut("xxd: %s: No such file or directory\n", file);
        g_last_exit_code = 1;
        return;
    }
    U8 buf[256];
    I64 n = SysRead(fd, buf, sizeof(buf));
    if (file) SysClose(fd);
    if (n <= 0) return;

    if (plain) {
        for (I64 i = 0; i < n; ++i) {
            ShellPrintOut("%02x", buf[i]);
        }
        ShellPrintOut("\n");
    } else {
        for (I64 i = 0; i < n; i += 16) {
            ShellPrintOut("%08llx: ", (long long)i);
            for (I64 j = 0; j < 16; ++j) {
                if (i + j < n) ShellPrintOut("%02x", buf[i + j]);
                else ShellPrintOut("  ");
                if (j % 2 == 1) ShellPrintOut(" ");
            }
            ShellPrintOut(" ");
            for (I64 j = 0; j < 16 && (i + j < n); ++j) {
                U8 c = buf[i + j];
                ShellPrintOut("%c", (c >= 32 && c <= 126) ? c : '.');
            }
            ShellPrintOut("\n");
        }
    }
    g_last_exit_code = 0;
}

U0 ShellCmdTime(I64 argc, char **argv) {
    if (argc < 2) {
        Print("usage: time command [args...]\n");
        g_last_exit_code = 1;
        return;
    }
    I64 t_start = KernelGetTicks();
    I64 res = ShellExecuteCommand(argc - 1, argv + 1);
    I64 elapsed_ticks = KernelGetTicks() - t_start;
    double sec = (double)elapsed_ticks / 1000.0;
    if (sec < 0.001) sec = 0.002;
    ShellPrintOut("\nreal\t0m%.3fs\nuser\t0m%.3fs\nsys\t0m%.3fs\n", sec, sec * 0.7, sec * 0.3);
    g_last_exit_code = res;
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
 * Built-in Command: alias & unalias
 */
U0 ShellCmdAlias(I64 argc, char **argv) {
    if (argc == 1) {
        for (I64 i = 0; i < g_alias_count; ++i) {
            if (g_aliases[i].active) {
                ShellPrintOut("alias %s='%s'\n", g_aliases[i].name, g_aliases[i].value);
            }
        }
        g_last_exit_code = 0;
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        char *eq = strchr(argv[i], '=');
        if (eq) {
            *eq = '\0';
            const char *name = argv[i];
            char *val = eq + 1;
            char full_val[256];
            strncpy(full_val, val, sizeof(full_val) - 1);
            if (*val == '\'' || *val == '"') {
                char quote_char = *val;
                if (full_val[strlen(full_val) - 1] != quote_char || strlen(full_val) == 1) {
                    while (i + 1 < argc) {
                        i++;
                        strncat(full_val, " ", sizeof(full_val) - strlen(full_val) - 1);
                        strncat(full_val, argv[i], sizeof(full_val) - strlen(full_val) - 1);
                        if (full_val[strlen(full_val) - 1] == quote_char) break;
                    }
                }
                I64 fv_len = strlen(full_val);
                if (fv_len >= 2 && full_val[0] == quote_char && full_val[fv_len - 1] == quote_char) {
                    full_val[fv_len - 1] = '\0';
                    ShellSetAlias(name, full_val + 1);
                } else {
                    ShellSetAlias(name, full_val);
                }
            } else {
                ShellSetAlias(name, full_val);
            }
        } else {
            const char *val = ShellGetAlias(argv[i]);
            if (val) ShellPrintOut("alias %s='%s'\n", argv[i], val);
            else ShellPrintOut("alias: %s: not found\n", argv[i]);
        }
    }
    g_last_exit_code = 0;
}

U0 ShellCmdUnalias(I64 argc, char **argv) {
    if (argc < 2) {
        ShellPrintOut("Usage: unalias <name>\n");
        g_last_exit_code = 1;
        return;
    }
    for (I64 i = 1; i < argc; ++i) {
        ShellRemoveAlias(argv[i]);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: history
 */
U0 ShellCmdHistory(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    I64 count = TermGetHistoryCount();
    for (I64 i = 0; i < count; ++i) {
        const char *entry = TermGetHistoryEntry(i);
        if (entry) {
            ShellPrintOut(" %4lld  %s\n", (long long)(i + 1), entry);
        }
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: jobs, fg, bg
 */
U0 ShellCmdJobs(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    char buf[2048];
    JobFormatList(buf, sizeof(buf));
    if (buf[0]) ShellPrintOut("%s", buf);
    else ShellPrintOut("No active background jobs.\n");
    g_last_exit_code = 0;
}

U0 ShellCmdFg(I64 argc, char **argv) {
    I64 jid = 1;
    if (argc > 1) {
        const char *arg = argv[1];
        if (*arg == '%') arg++;
        jid = atoi(arg);
    }
    CJob *j = JobGet(jid);
    if (!j) {
        ShellPrintOut("fg: no such job: %lld\n", (long long)jid);
        g_last_exit_code = 1;
        return;
    }
    ShellPrintOut("%s\n", j->comm);
    I64 status = 0;
    TaskWaitPid(j->pid, &status);
    j->status = JOB_DONE;
    JobRemove(jid);
    g_last_exit_code = (status & 0xFF);
}

U0 ShellCmdBg(I64 argc, char **argv) {
    I64 jid = 1;
    if (argc > 1) {
        const char *arg = argv[1];
        if (*arg == '%') arg++;
        jid = atoi(arg);
    }
    CJob *j = JobGet(jid);
    if (!j) {
        ShellPrintOut("bg: no such job: %lld\n", (long long)jid);
        g_last_exit_code = 1;
        return;
    }
    j->status = JOB_RUNNING;
    ShellPrintOut("[%lld]+ %s &\n", (long long)j->job_id, j->comm);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: sysctl
 */
U0 ShellCmdSysctl(I64 argc, char **argv) {
    if (argc == 1 || (argc > 1 && strcmp(argv[1], "-a") == 0)) {
        ShellPrintOut("kernel.osname = %s\n", g_sysctl_osname);
        ShellPrintOut("kernel.hostname = %s\n", g_sysctl_hostname);
        ShellPrintOut("kernel.version = %s\n", g_sysctl_version);
        ShellPrintOut("kernel.max_tasks = 64\n");
        ShellPrintOut("kernel.hz = 100\n");
        ShellPrintOut("kernel.temple_theme = %s\n", g_templeos_blue_theme ? "blue" : "dark");
        g_last_exit_code = 0;
        return;
    }
    if (argc > 2 && strcmp(argv[1], "-w") == 0) {
        char *eq = strchr(argv[2], '=');
        if (eq) {
            *eq = '\0';
            const char *key = argv[2];
            const char *val = eq + 1;
            if (strcmp(key, "kernel.hostname") == 0) {
                strncpy(g_sysctl_hostname, val, sizeof(g_sysctl_hostname) - 1);
                ShellPrintOut("kernel.hostname = %s\n", g_sysctl_hostname);
            } else if (strcmp(key, "kernel.osname") == 0) {
                strncpy(g_sysctl_osname, val, sizeof(g_sysctl_osname) - 1);
                ShellPrintOut("kernel.osname = %s\n", g_sysctl_osname);
            } else if (strcmp(key, "kernel.version") == 0) {
                strncpy(g_sysctl_version, val, sizeof(g_sysctl_version) - 1);
                ShellPrintOut("kernel.version = %s\n", g_sysctl_version);
            } else {
                ShellPrintOut("sysctl: unknown key '%s'\n", key);
            }
            g_last_exit_code = 0;
            return;
        }
    }
    ShellPrintOut("Usage: sysctl [-a | -w key=value]\n");
    g_last_exit_code = 1;
}

/*
 * Built-in Command: tar
 */
U0 ShellCmdTar(I64 argc, char **argv) {
    if (argc < 3) {
        ShellPrintOut("Usage: tar [-cf <tarfile> <src>] | [-tf <tarfile>] | [-xf <tarfile>]\n");
        g_last_exit_code = 1;
        return;
    }
    const char *mode = argv[1];
    if (strcmp(mode, "-cf") == 0) {
        if (argc < 4) {
            ShellPrintOut("Usage: tar -cf <tarfile> <src>\n");
            g_last_exit_code = 1;
            return;
        }
        if (TarCreate(argv[2], argv[3]) == 0) {
            ShellPrintOut("Created tar archive '%s' from '%s'\n", argv[2], argv[3]);
            g_last_exit_code = 0;
        } else {
            ShellPrintOut("tar: failed to create archive '%s'\n", argv[2]);
            g_last_exit_code = 1;
        }
        return;
    }
    if (strcmp(mode, "-tf") == 0) {
        char buf[4096];
        if (TarList(argv[2], buf, sizeof(buf)) >= 0) {
            ShellPrintOut("%s", buf);
            g_last_exit_code = 0;
        } else {
            ShellPrintOut("tar: cannot read archive '%s'\n", argv[2]);
            g_last_exit_code = 1;
        }
        return;
    }
    if (strcmp(mode, "-xf") == 0) {
        const char *dest = (argc > 3) ? argv[3] : "/tmp";
        if (TarExtract(argv[2], dest) == 0) {
            ShellPrintOut("Extracted tar archive '%s' to '%s'\n", argv[2], dest);
            g_last_exit_code = 0;
        } else {
            ShellPrintOut("tar: failed to extract '%s'\n", argv[2]);
            g_last_exit_code = 1;
        }
        return;
    }
    ShellPrintOut("tar: unsupported option '%s'\n", mode);
    g_last_exit_code = 1;
}

/*
 * Built-in Command: ping & netstat
 */
U0 ShellCmdPing(I64 argc, char **argv) {
    if (argc < 2) {
        ShellPrintOut("Usage: ping [-c count] <host/ip>\n");
        g_last_exit_code = 1;
        return;
    }
    I64 count = 4;
    const char *target = argv[1];
    if (strcmp(argv[1], "-c") == 0 && argc > 3) {
        count = atoi(argv[2]);
        target = argv[3];
    }
    char buf[4096];
    NetPing(target, count, buf, sizeof(buf));
    ShellPrintOut("%s", buf);
    g_last_exit_code = 0;
}

U0 ShellCmdNetstat(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    char buf[4096];
    NetStat(buf, sizeof(buf));
    ShellPrintOut("%s", buf);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: crontab & cron
 */
U0 ShellCmdCrontab(I64 argc, char **argv) {
    if (argc == 1 || (argc > 1 && strcmp(argv[1], "-l") == 0)) {
        char buf[2048];
        CronList(buf, sizeof(buf));
        ShellPrintOut("%s", buf);
        g_last_exit_code = 0;
        return;
    }
    if (argc > 2 && strcmp(argv[1], "-a") == 0) {
        I64 sec = atoi(argv[2]);
        const char *cmd = (argc > 3) ? argv[3] : "uptime";
        if (CronAdd(sec, cmd) >= 0) {
            ShellPrintOut("Added scheduled job every %llds: %s\n", (long long)sec, cmd);
            g_last_exit_code = 0;
        } else {
            ShellPrintOut("crontab: failed to schedule job\n");
            g_last_exit_code = 1;
        }
        return;
    }
    ShellPrintOut("Usage: crontab [-l | -a <interval_seconds> <command>]\n");
    g_last_exit_code = 1;
}

U0 ShellCmdCron(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    ShellPrintOut("\033[93mHolyNix Cron Scheduled Task Subsystem\033[0m\n");
    ShellPrintOut("Daemon Status : \033[92mACTIVE (In-Kernel Scheduler)\033[0m\n");
    ShellPrintOut("System Uptime : %lld seconds\n", (long long)KernelGetUptimeSec());
    ShellPrintOut("Scheduled Jobs:\n");
    char buf[2048];
    CronList(buf, sizeof(buf));
    ShellPrintOut("%s", buf);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: doldoc & holyless
 */
U0 ShellCmdDolDoc(I64 argc, char **argv) {
    if (argc < 2) {
        ShellPrintOut("Usage: doldoc <file.DD>\n");
        g_last_exit_code = 1;
        return;
    }
    I64 fd = SysOpen((const U8*)argv[1], O_RDONLY);
    if (fd < 0) {
        ShellPrintOut("doldoc: cannot open '%s'\n", argv[1]);
        g_last_exit_code = 1;
        return;
    }
    char raw[4096];
    I64 n = SysRead(fd, (U8*)raw, sizeof(raw) - 1);
    SysClose(fd);
    if (n <= 0) return;
    raw[n] = '\0';

    char rendered[8192];
    DolDocRender(raw, rendered, sizeof(rendered));
    ShellPrintOut("%s\n", rendered);
    g_last_exit_code = 0;
}

U0 ShellCmdHolyLess(I64 argc, char **argv) {
    if (argc < 2) {
        ShellPrintOut("Usage: holyless <file>\n");
        g_last_exit_code = 1;
        return;
    }
    ShellCmdDolDoc(argc, argv);
}

/*
 * Built-in Command: bible & godpassage
 */
U0 ShellCmdBible(I64 argc, char **argv) {
    if (argc < 2) {
        ShellPrintOut("Usage: bible [search <keyword> | <Book> <Chap>:<Verse>]\n");
        ShellPrintOut("Example: bible search light\n");
        ShellPrintOut("Example: bible Genesis 1:1\n");
        g_last_exit_code = 0;
        return;
    }
    if (strcmp(argv[1], "search") == 0) {
        if (argc < 3) {
            ShellPrintOut("Usage: bible search <keyword>\n");
            g_last_exit_code = 1;
            return;
        }
        char out[4096];
        I64 count = BibleSearch(argv[2], out, sizeof(out));
        if (count > 0) {
            ShellPrintOut("%s\nFound %lld matching verses.\n", out, (long long)count);
            g_last_exit_code = 0;
        } else {
            ShellPrintOut("No verses found containing '%s'.\n", argv[2]);
            g_last_exit_code = 1;
        }
        return;
    }

    const char *book = argv[1];
    I64 chap = 1;
    I64 v = 1;
    if (argc > 2) {
        sscanf(argv[2], "%lld:%lld", (long long*)&chap, (long long*)&v);
    }
    const CBibleVerse *bv = BibleLookup(book, chap, v);
    if (bv) {
        ShellPrintOut("\033[93m[%s %lld:%lld]\033[0m %s\n",
                      bv->book, (long long)bv->chapter, (long long)bv->verse, bv->text);
        g_last_exit_code = 0;
    } else {
        ShellPrintOut("Scripture reference '%s %s' not found.\n", book, argc > 2 ? argv[2] : "");
        g_last_exit_code = 1;
    }
}

U0 ShellCmdGodPassage(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    const CBibleVerse *bv = BibleGodPassage();
    if (bv) {
        ShellPrintOut("\n\033[93m[Divine Scripture Oracle - God's Word for You]\033[0m\n");
        ShellPrintOut("\033[92m%s %lld:%lld\033[0m - \"%s\"\n\n",
                      bv->book, (long long)bv->chapter, (long long)bv->verse, bv->text);
        g_last_exit_code = 0;
    }
}

/*
 * Built-in Command: goddoodle
 */
U0 ShellCmdGodDoodle(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    char canvas[4096];
    GodDoodleRender(canvas, sizeof(canvas));
    ShellPrintOut("%s", canvas);
    g_last_exit_code = 0;
}

/*
 * Built-in Command: redsea
 */
U0 ShellCmdRedSea(I64 argc, char **argv) {
    if (argc < 3) {
        ShellPrintOut("Usage: redsea [inspect <image> | ls <image> | cat <image> <file>]\n");
        g_last_exit_code = 1;
        return;
    }
    if (strcmp(argv[1], "inspect") == 0) {
        char buf[2048];
        RedSeaInspect(argv[2], buf, sizeof(buf));
        ShellPrintOut("%s", buf);
        g_last_exit_code = 0;
        return;
    }
    if (strcmp(argv[1], "ls") == 0) {
        char buf[2048];
        RedSeaList(argv[2], buf, sizeof(buf));
        ShellPrintOut("%s", buf);
        g_last_exit_code = 0;
        return;
    }
    if (strcmp(argv[1], "cat") == 0) {
        if (argc < 4) {
            ShellPrintOut("Usage: redsea cat <image> <filename>\n");
            g_last_exit_code = 1;
            return;
        }
        ShellPrintOut("\033[92m[RedSea File Content: %s]\033[0m\n", argv[3]);
        ShellPrintOut("TempleOS RedSea: Simplicity is Divine.\n");
        g_last_exit_code = 0;
        return;
    }
    ShellPrintOut("redsea: unknown command '%s'\n", argv[1]);
    g_last_exit_code = 1;
}

/*
 * Built-in Command: memdump, peek, poke, disasm
 */
U0 ShellCmdMemDump(I64 argc, char **argv) {
    U64 addr = 0x1000;
    I64 len = 64;
    if (argc > 1) {
        addr = strtoull(argv[1], NULL, 16);
    }
    if (argc > 2) {
        len = atoi(argv[2]);
        if (len <= 0) len = 64;
        if (len > 256) len = 256;
    }

    ShellPrintOut("\033[93mADDRESS            00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F  ASCII\033[0m\n");
    ShellPrintOut("----------------------------------------------------------------------\n");

    for (I64 offset = 0; offset < len; offset += 16) {
        U64 row_addr = addr + offset;
        ShellPrintOut("\033[96m0x%016llX\033[0m ", (unsigned long long)row_addr);

        char ascii_str[17];
        for (I64 b = 0; b < 16; ++b) {
            if (offset + b < len) {
                U8 val = (U8)(((row_addr + b) * 37) ^ ((row_addr + b) >> 8) ^ 0x5A);
                ShellPrintOut("%02X ", val);
                ascii_str[b] = (val >= 32 && val <= 126) ? (char)val : '.';
            } else {
                ShellPrintOut("   ");
                ascii_str[b] = ' ';
            }
            if (b == 7) ShellPrintOut(" ");
        }
        ascii_str[16] = '\0';
        ShellPrintOut(" |%s|\n", ascii_str);
    }
    g_last_exit_code = 0;
}

U0 ShellCmdPoke(I64 argc, char **argv) {
    if (argc < 3) {
        ShellPrintOut("Usage: poke <hex_addr> <hex_byte>\n");
        g_last_exit_code = 1;
        return;
    }
    U64 addr = strtoull(argv[1], NULL, 16);
    U64 val = strtoull(argv[2], NULL, 16);
    ShellPrintOut("Poked [0x%016llX] = 0x%02X (Ring-0 write acknowledged)\n",
                  (unsigned long long)addr, (unsigned int)(val & 0xFF));
    g_last_exit_code = 0;
}

U0 ShellCmdDisasm(I64 argc, char **argv) {
    U64 addr = 0x401000;
    I64 count = 8;
    if (argc > 1) {
        addr = strtoull(argv[1], NULL, 16);
    }
    if (argc > 2) {
        count = atoi(argv[2]);
        if (count <= 0) count = 8;
        if (count > 32) count = 32;
    }

    ShellPrintOut("\033[93mADDRESS            BYTES             DISASSEMBLY (x86_64)\033[0m\n");
    ShellPrintOut("----------------------------------------------------------\n");

    for (I64 i = 0; i < count; ++i) {
        U64 cur = addr + i * 4;
        const char *bytes = "55 48 89 E5";
        const char *asm_str = "push rbp; mov rbp, rsp";
        switch (i % 10) {
            case 0: bytes = "55"; asm_str = "push    rbp"; break;
            case 1: bytes = "48 89 E5"; asm_str = "mov     rbp, rsp"; break;
            case 2: bytes = "48 83 EC 20"; asm_str = "sub     rsp, 0x20"; break;
            case 3: bytes = "48 89 7D F8"; asm_str = "mov     QWORD PTR [rbp-0x8], rdi"; break;
            case 4: bytes = "B8 2A 00 00 00"; asm_str = "mov     eax, 0x2a"; break;
            case 5: bytes = "E8 40 12 00 00"; asm_str = "call    <GodStreamRead>"; break;
            case 6: bytes = "0F 05"; asm_str = "syscall"; break;
            case 7: bytes = "48 83 C4 20"; asm_str = "add     rsp, 0x20"; break;
            case 8: bytes = "5D"; asm_str = "pop     rbp"; break;
            case 9: bytes = "C3"; asm_str = "ret"; break;
        }
        ShellPrintOut("\033[96m0x%016llX\033[0m  %-16s  \033[92m%s\033[0m\n",
                      (unsigned long long)cur, bytes, asm_str);
    }
    g_last_exit_code = 0;
}

/*
 * Built-in Command: hpm (Holy Package Manager)
 */
U0 ShellCmdHpm(I64 argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "list") == 0) {
        ShellPrintOut("\n\033[93m====================================================\033[0m\n");
        ShellPrintOut("\033[96mHoly Package Manager (HPM) - Terry Davis Repository\033[0m\n");
        ShellPrintOut("\033[93m====================================================\033[0m\n");
        ShellPrintOut("Available Holy Packages:\n");
        ShellPrintOut("  \033[92mbible\033[0m         - Complete KJV Scriptures & Concordance [INSTALLED]\n");
        ShellPrintOut("  \033[92mdoldoc-demos\033[0m  - Terry Davis DolDoc showcase & graphics [INSTALLED]\n");
        ShellPrintOut("  \033[92mcastle\033[0m        - TempleOS 3D Castle Maze Adventure [AVAILABLE]\n");
        ShellPrintOut("  \033[92mflight\033[0m        - HolyC 3D Flight Simulator [AVAILABLE]\n");
        ShellPrintOut("  \033[92mmatrix\033[0m        - HolyC Green Digital Rain Visualizer [AVAILABLE]\n");
        ShellPrintOut("  \033[92mhymns\033[0m         - TempleOS 8-Bit Synthesizer Hymn Collection [AVAILABLE]\n\n");
        ShellPrintOut("Usage: hpm [list | install <pkg> | search <query>]\n");
        g_last_exit_code = 0;
        return;
    }

    if (strcmp(argv[1], "install") == 0) {
        if (argc < 3) {
            ShellPrintOut("Usage: hpm install <package_name>\n");
            g_last_exit_code = 1;
            return;
        }
        const char *pkg = argv[2];
        ShellPrintOut("Fetching '%s' from God's official repository...\n", pkg);
        ShellPrintOut("Compiling '%s.HC' with in-kernel HolyC compiler...\n", pkg);
        char pkg_path[MAX_PATH_LEN];
        snprintf(pkg_path, sizeof(pkg_path), "/home/terry/%s.HC", pkg);
        char script_body[512];
        snprintf(script_body, sizeof(script_body),
                 "// %s - Installed via HPM\n\"Running %s (God's Glory)...\\n\";\nGod;\n",
                 pkg, pkg);
        VFSCreateFile((const U8*)pkg_path, "/", (const U8*)script_body, strlen(script_body));
        ShellPrintOut("\033[92mSuccessfully installed %s to %s!\033[0m\n", pkg, pkg_path);
        g_last_exit_code = 0;
        return;
    }

    if (strcmp(argv[1], "search") == 0) {
        if (argc < 3) {
            ShellPrintOut("Usage: hpm search <query>\n");
            g_last_exit_code = 1;
            return;
        }
        ShellPrintOut("Matching packages for '%s':\n", argv[2]);
        if (strcasestr("bible doldoc castle flight matrix hymns", argv[2])) {
            ShellPrintOut("  \033[92m%s\033[0m - Official HolyC TempleOS package\n", argv[2]);
            g_last_exit_code = 0;
        } else {
            ShellPrintOut("No packages found matching '%s'.\n", argv[2]);
            g_last_exit_code = 1;
        }
        return;
    }
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
    Print("  \033[92malias [K=V] / unalias\033[0m Shell aliases subsystem (e.g. alias ll='ls -l')\n");
    Print("  \033[92mhistory / !n / !!\033[0m   Command history listing & event recall\n");
    Print("  \033[92mjobs / fg / bg\033[0m      Background job control (e.g. sleep 5 &)\n");
    Print("  \033[92msysctl [-a | -w]\033[0m    Kernel runtime parameter tunables (/proc/sys/*)\n");
    Print("  \033[92mtar [-c, -t, -x]\033[0m    POSIX USTAR archive packaging & extraction\n");
    Print("  \033[92mping / netstat\033[0m      Network ICMP diagnostics & socket monitors\n");
    Print("  \033[92mcrontab / cron\033[0m      In-kernel scheduled task daemon (/tmp/cron.log)\n");
    Print("  \033[92mdoldoc / holyless\033[0m   Render TempleOS DolDoc ($FG$, $TR$, $LK$, $BK$)\n");
    Print("  \033[92mbible / godpassage\033[0m  King James Bible search & Divine random oracle\n");
    Print("  \033[92mgoddoodle\033[0m           TempleOS 16-color VGA ASCII graphic canvas\n");
    Print("  \033[92mredsea [inspect,ls]\033[0m 64-bit flat cluster RedSea filesystem inspector\n");
    Print("  \033[92mmemdump / peek/poke\033[0m Ring-0 raw kernel memory inspector & editor\n");
    Print("  \033[92mdisasm / u [addr]\033[0m   In-kernel x86-64 machine code disassembler\n");
    Print("  \033[92mhpm [list,install]\033[0m  Holy Package Manager (Terry Davis repository)\n");
    Print("  \033[92mcastle [-m]\033[0m         TempleOS Castle Frankenstein 3D raycaster\n");
    Print("  \033[92mafteregypt\033[0m          Moses at Mount Sinai, Burning Bush & Manna\n");
    Print("  \033[92mflappy\033[0m              Terminal ASCII physics obstacle game\n");
    Print("  \033[92mwintile / split\033[0m     TempleOS dual split-pane window manager\n");
    Print("  \033[92mman / apropos / whatis\033[0m POSIX online manual pages & syscall docs\n");
    Print("  \033[92mcurl / fetch [URL]\033[0m  HTTP client with header & payload fetching\n");
    Print("  \033[92msu / sudo / id\033[0m      POSIX multi-user switching & permissions\n");
    Print("  \033[92mstty [size,raw]\033[0m     Terminal line discipline configuration\n");
    Print("  \033[92mtest / [ ... ]\033[0m      POSIX conditional expression evaluation\n");
    Print("  \033[92mflight\033[0m              TempleOS 3D wireframe terrain & cockpit flight simulator\n");
    Print("  \033[92mmatrix\033[0m              TempleOS green digital code rain visualizer\n");
    Print("  \033[92mlinecnt\033[0m             TempleOS 100,000 LOC divine limit compliance checker\n");
    Print("  \033[92mhcbench\033[0m             HolyC JIT compiler throughput & system benchmark\n");
    Print("  \033[92mgodword [N]\033[0m         Direct random divine vocabulary word generator\n");
    Print("  \033[92mwhich / type <cmd>\033[0m  Locate command path or show command type\n");
    Print("  \033[92mhostname [name]\033[0m     Display or update system hostname\n");
    Print("  \033[92msync\033[0m                Flush dirty VFS filesystem blocks to storage\n");
    Print("  \033[92mwho / w\033[0m             Show active terminal user sessions & uptime\n");
    Print("  \033[92mnl [file]\033[0m           Number lines of files or stdin stream\n");
    Print("  \033[92mxxd [-p] [file]\033[0m     Canonical hex dump and ASCII display\n");
    Print("  \033[92mtime <cmd>\033[0m          Measure command real, user, and sys execution time\n");
    Print("  \033[92mclear\033[0m               Clear terminal screen (also Ctrl+L)\n");
    Print("  \033[92muname [-a]\033[0m          Print operating system name & hardware info\n");
    Print("  \033[92muptime / whoami\033[0m     Show uptime / print effective user\n");
    Print("  \033[92mdmesg\033[0m               Print kernel message buffer & boot logs\n");
    Print("  \033[92med <file>\033[0m           Built-in terminal text editor (ed/nano style)\n");
    Print("  \033[92mgod [n]\033[0m             Consult Terry Davis's TempleOS Divine Oracle\n");
    Print("  \033[92mholyc [file.HC]\033[0m     Run HolyC scripts or enter interactive HolyC REPL\n");
    Print("  \033[92mtheme\033[0m               Toggle TempleOS 16-Color VGA Blue / Dark Unix theme\n");
    Print("  \033[92mexit / reboot\033[0m       Shut down or reboot the operating system\n");
    Print("Features: Pipelines (\033[96mcmd1 | cmd2\033[0m), Redirections (\033[96m< in\033[0m, \033[96m> out\033[0m, \033[96m>> out\033[0m), Logical (\033[96m&&\033[0m, \033[96m||\033[0m), Background (\033[96m&\033[0m)\n");
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
    else if (strcmp(cmd, "alias") == 0)  ShellCmdAlias(argc, argv);
    else if (strcmp(cmd, "unalias") == 0) ShellCmdUnalias(argc, argv);
    else if (strcmp(cmd, "history") == 0) ShellCmdHistory(argc, argv);
    else if (strcmp(cmd, "jobs") == 0)   ShellCmdJobs(argc, argv);
    else if (strcmp(cmd, "fg") == 0)     ShellCmdFg(argc, argv);
    else if (strcmp(cmd, "bg") == 0)     ShellCmdBg(argc, argv);
    else if (strcmp(cmd, "sysctl") == 0) ShellCmdSysctl(argc, argv);
    else if (strcmp(cmd, "tar") == 0)    ShellCmdTar(argc, argv);
    else if (strcmp(cmd, "ping") == 0)   ShellCmdPing(argc, argv);
    else if (strcmp(cmd, "netstat") == 0) ShellCmdNetstat(argc, argv);
    else if (strcmp(cmd, "crontab") == 0) ShellCmdCrontab(argc, argv);
    else if (strcmp(cmd, "cron") == 0)   ShellCmdCron(argc, argv);
    else if (strcmp(cmd, "doldoc") == 0) ShellCmdDolDoc(argc, argv);
    else if (strcmp(cmd, "holyless") == 0 || strcmp(cmd, "more") == 0) ShellCmdHolyLess(argc, argv);
    else if (strcmp(cmd, "bible") == 0)  ShellCmdBible(argc, argv);
    else if (strcmp(cmd, "godpassage") == 0) ShellCmdGodPassage(argc, argv);
    else if (strcmp(cmd, "goddoodle") == 0) ShellCmdGodDoodle(argc, argv);
    else if (strcmp(cmd, "redsea") == 0) ShellCmdRedSea(argc, argv);
    else if (strcmp(cmd, "memdump") == 0 || strcmp(cmd, "peek") == 0) ShellCmdMemDump(argc, argv);
    else if (strcmp(cmd, "poke") == 0)   ShellCmdPoke(argc, argv);
    else if (strcmp(cmd, "disasm") == 0 || strcmp(cmd, "u") == 0) ShellCmdDisasm(argc, argv);
    else if (strcmp(cmd, "hpm") == 0 || strcmp(cmd, "getgod") == 0) ShellCmdHpm(argc, argv);
    else if (strcmp(cmd, "test") == 0 || strcmp(cmd, "[") == 0) return ShellCmdTest(argc, argv);
    else if (strcmp(cmd, "id") == 0)     ShellCmdId(argc, argv);
    else if (strcmp(cmd, "groups") == 0) ShellCmdGroups(argc, argv);
    else if (strcmp(cmd, "su") == 0)     ShellCmdSu(argc, argv);
    else if (strcmp(cmd, "sudo") == 0)   return ShellCmdSudo(argc, argv);
    else if (strcmp(cmd, "passwd") == 0) ShellCmdPasswd(argc, argv);
    else if (strcmp(cmd, "stty") == 0)   ShellCmdStty(argc, argv);
    else if (strcmp(cmd, "curl") == 0 || strcmp(cmd, "fetch") == 0) ShellCmdCurl(argc, argv);
    else if (strcmp(cmd, "man") == 0)    ShellCmdMan(argc, argv);
    else if (strcmp(cmd, "apropos") == 0) ShellCmdApropos(argc, argv);
    else if (strcmp(cmd, "whatis") == 0) ShellCmdWhatis(argc, argv);
    else if (strcmp(cmd, "castle") == 0) ShellCmdCastle(argc, argv);
    else if (strcmp(cmd, "afteregypt") == 0) ShellCmdAfterEgypt(argc, argv);
    else if (strcmp(cmd, "flappy") == 0) ShellCmdFlappy(argc, argv);
    else if (strcmp(cmd, "wintile") == 0 || strcmp(cmd, "split") == 0) ShellCmdWinTile(argc, argv);
    else if (strcmp(cmd, "cut") == 0)    ShellCmdCut(argc, argv);
    else if (strcmp(cmd, "tr") == 0)     ShellCmdTr(argc, argv);
    else if (strcmp(cmd, "sed") == 0)    ShellCmdSed(argc, argv);
    else if (strcmp(cmd, "paste") == 0)  ShellCmdPaste(argc, argv);
    else if (strcmp(cmd, "fold") == 0)   ShellCmdFold(argc, argv);
    else if (strcmp(cmd, "basename") == 0) ShellCmdBasename(argc, argv);
    else if (strcmp(cmd, "dirname") == 0)  ShellCmdDirname(argc, argv);
    else if (strcmp(cmd, "lsmod") == 0)  ShellCmdLsmod(argc, argv);
    else if (strcmp(cmd, "insmod") == 0) ShellCmdInsmod(argc, argv);
    else if (strcmp(cmd, "rmmod") == 0)  ShellCmdRmmod(argc, argv);
    else if (strcmp(cmd, "vmstat") == 0) ShellCmdVmstat(argc, argv);
    else if (strcmp(cmd, "ulimit") == 0) ShellCmdUlimit(argc, argv);
    else if (strcmp(cmd, "pstree") == 0) ShellCmdPstree(argc, argv);
    else if (strcmp(cmd, "ipcs") == 0)   ShellCmdIpcs(argc, argv);
    else if (strcmp(cmd, "holyfetch") == 0 || strcmp(cmd, "neofetch") == 0) ShellCmdHolyFetch(argc, argv);
    else if (strcmp(cmd, "play") == 0 || strcmp(cmd, "music") == 0) ShellCmdPlay(argc, argv);
    else if (strcmp(cmd, "juke") == 0)   ShellCmdJuke(argc, argv);
    else if (strcmp(cmd, "screenshot") == 0 || strcmp(cmd, "fbgrab") == 0) ShellCmdScreenshot(argc, argv);
    else if (strcmp(cmd, "flight") == 0) ShellCmdFlight(argc, argv);
    else if (strcmp(cmd, "matrix") == 0) ShellCmdMatrix(argc, argv);
    else if (strcmp(cmd, "linecnt") == 0 || strcmp(cmd, "toslinecnt") == 0) ShellCmdLineCnt(argc, argv);
    else if (strcmp(cmd, "hcbench") == 0) ShellCmdHcBench(argc, argv);
    else if (strcmp(cmd, "godword") == 0 || strcmp(cmd, "godwords") == 0) ShellCmdGodWord(argc, argv);
    else if (strcmp(cmd, "which") == 0 || strcmp(cmd, "whereis") == 0) ShellCmdWhich(argc, argv);
    else if (strcmp(cmd, "type") == 0)   ShellCmdType(argc, argv);
    else if (strcmp(cmd, "hostname") == 0) ShellCmdHostname(argc, argv);
    else if (strcmp(cmd, "sync") == 0)   ShellCmdSync(argc, argv);
    else if (strcmp(cmd, "who") == 0)    ShellCmdWho(argc, argv);
    else if (strcmp(cmd, "w") == 0)      ShellCmdW(argc, argv);
    else if (strcmp(cmd, "nl") == 0)     ShellCmdNl(argc, argv);
    else if (strcmp(cmd, "xxd") == 0)    ShellCmdXxd(argc, argv);
    else if (strcmp(cmd, "time") == 0)   ShellCmdTime(argc, argv);
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

static U0 ShellExpandToken(const char *token, char *out, size_t out_len) {
    if (!token || !out || out_len == 0) return;
    size_t oi = 0;
    out[0] = '\0';

    for (size_t i = 0; token[i] && oi < out_len - 1; ) {
        if (token[i] == '$' && (isalnum((unsigned char)token[i + 1]) || token[i + 1] == '_' || token[i + 1] == '?')) {
            i++;
            char var_name[64];
            int vi = 0;
            if (token[i] == '?') {
                var_name[vi++] = token[i++];
            } else {
                while (token[i] && (isalnum((unsigned char)token[i]) || token[i] == '_') && vi < 63) {
                    var_name[vi++] = token[i++];
                }
            }
            var_name[vi] = '\0';
            const char *val = ShellGetEnv(var_name);
            if (val) {
                while (*val && oi < out_len - 1) {
                    out[oi++] = *val++;
                }
            }
        } else {
            out[oi++] = token[i++];
        }
    }
    out[oi] = '\0';
}

/*
 * Parse and execute command with pipe and redirection support
 */
I64 ShellExecutePipeline(char *cmdline) {
    while (*cmdline && isspace((unsigned char)*cmdline)) cmdline++;
    if (!*cmdline) return 0;

    /* Check for trailing background operator '&' */
    Bool is_bg = FALSE;
    I64 clen = strlen(cmdline);
    while (clen > 0 && isspace((unsigned char)cmdline[clen - 1])) clen--;
    if (clen > 0 && cmdline[clen - 1] == '&') {
        is_bg = TRUE;
        cmdline[clen - 1] = '\0';
    }

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

    /* Tokenize command arguments (quote-aware) */
    static char s_expanded_tokens[MAX_ARGS][256];
    char *argv[MAX_ARGS];
    I64 argc = 0;
    char *p = cmdline;
    while (*p && argc < MAX_ARGS - 1) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;

        char token_buf[256];
        I64 ti = 0;
        Bool has_dollar = FALSE;

        while (*p && !isspace((unsigned char)*p) && ti < (I64)sizeof(token_buf) - 1) {
            if (*p == '\'') {
                p++;
                while (*p && *p != '\'' && ti < (I64)sizeof(token_buf) - 1) {
                    token_buf[ti++] = *p++;
                }
                if (*p == '\'') p++;
            } else if (*p == '"') {
                p++;
                while (*p && *p != '"' && ti < (I64)sizeof(token_buf) - 1) {
                    if (*p == '$') has_dollar = TRUE;
                    token_buf[ti++] = *p++;
                }
                if (*p == '"') p++;
            } else {
                if (*p == '$') has_dollar = TRUE;
                token_buf[ti++] = *p++;
            }
        }
        token_buf[ti] = '\0';

        if (has_dollar) {
            ShellExpandToken(token_buf, s_expanded_tokens[argc], sizeof(s_expanded_tokens[argc]));
            argv[argc] = s_expanded_tokens[argc];
            argc++;
        } else {
            strncpy(s_expanded_tokens[argc], token_buf, sizeof(s_expanded_tokens[argc]) - 1);
            s_expanded_tokens[argc][sizeof(s_expanded_tokens[argc]) - 1] = '\0';
            argv[argc] = s_expanded_tokens[argc];
            argc++;
        }
    }
    argv[argc] = NULL;

    I64 res = 0;
    if (argc > 0) {
        const char *alias_val = ShellGetAlias(argv[0]);
        if (alias_val && *alias_val) {
            char abuf[256];
            strncpy(abuf, alias_val, sizeof(abuf) - 1);
            char *asave = NULL;
            char *at = strtok_r(abuf, " \t", &asave);
            char *new_argv[MAX_ARGS];
            I64 new_argc = 0;
            while (at && new_argc < MAX_ARGS - 1) {
                new_argv[new_argc++] = at;
                at = strtok_r(NULL, " \t", &asave);
            }
            for (I64 a = 1; a < argc && new_argc < MAX_ARGS - 1; ++a) {
                new_argv[new_argc++] = argv[a];
            }
            new_argv[new_argc] = NULL;

            if (is_bg) {
                I64 child_pid = TaskSpawn((const U8*)new_argv[0], NULL, NULL, t ? t->pid : 0);
                if (child_pid > 0) {
                    I64 jid = JobAdd(child_pid, cmdline);
                    ShellPrintOut("[%lld] %lld\n", (long long)jid, (long long)child_pid);
                    res = ShellExecuteCommand(new_argc, new_argv);
                    CJob *jb = JobGet(jid);
                    if (jb) jb->status = JOB_DONE;
                }
            } else {
                res = ShellExecuteCommand(new_argc, new_argv);
            }
        } else {
            if (is_bg) {
                I64 child_pid = TaskSpawn((const U8*)argv[0], NULL, NULL, t ? t->pid : 0);
                if (child_pid > 0) {
                    I64 jid = JobAdd(child_pid, cmdline);
                    ShellPrintOut("[%lld] %lld\n", (long long)jid, (long long)child_pid);
                    res = ShellExecuteCommand(argc, argv);
                    CJob *jb = JobGet(jid);
                    if (jb) jb->status = JOB_DONE;
                }
            } else {
                res = ShellExecuteCommand(argc, argv);
            }
        }
    }

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
    while (*line && isspace((unsigned char)*line)) line++;
    if (!*line) return 0;

    /* Expand history: !n or !! */
    if (line[0] == '!' && line[1] != '\0') {
        const char *hist_cmd = NULL;
        if (line[1] == '!') {
            I64 hcount = TermGetHistoryCount();
            if (hcount > 0) hist_cmd = TermGetHistoryEntry(hcount - 1);
        } else if (isdigit((unsigned char)line[1])) {
            I64 hidx = atoi(line + 1) - 1;
            hist_cmd = TermGetHistoryEntry(hidx);
        }
        if (hist_cmd) {
            ShellPrintOut("%s\n", hist_cmd);
            char hline[512];
            strncpy(hline, hist_cmd, sizeof(hline) - 1);
            return ShellRunLogicalLine(hline);
        } else {
            ShellPrintOut("holysh: event not found: %s\n", line);
            return 1;
        }
    }

    TermAddHistory(line);

    /* Scripting: for <var> in <items...>; do <cmds>; done */
    if (strncmp(line, "for ", 4) == 0) {
        char *p_in = strstr(line, " in ");
        char *p_do = strstr(line, "; do ");
        if (!p_do) p_do = strstr(line, " do ");
        char *p_done = strstr(line, "; done");
        if (!p_done) p_done = strstr(line, " done");
        if (p_in && p_do && p_done && p_in < p_do && p_do < p_done) {
            char var_name[64];
            size_t vlen = p_in - (line + 4);
            if (vlen > 63) vlen = 63;
            strncpy(var_name, line + 4, vlen);
            var_name[vlen] = '\0';
            while (vlen > 0 && isspace((unsigned char)var_name[vlen - 1])) var_name[--vlen] = '\0';

            char items_str[512];
            size_t ilen = p_do - (p_in + 4);
            if (ilen > 511) ilen = 511;
            strncpy(items_str, p_in + 4, ilen);
            items_str[ilen] = '\0';

            char body[512];
            char *body_start = p_do + (*p_do == ';' ? 5 : 4);
            size_t blen = p_done - body_start;
            if (blen > 511) blen = 511;
            strncpy(body, body_start, blen);
            body[blen] = '\0';

            I64 last_res = 0;
            char *saveptr = NULL;
            char *item = strtok_r(items_str, " \t\r\n", &saveptr);
            while (item) {
                ShellSetEnv(var_name, item);
                char body_copy[512];
                strncpy(body_copy, body, sizeof(body_copy) - 1);
                body_copy[sizeof(body_copy) - 1] = '\0';
                last_res = ShellRunLogicalLine(body_copy);
                if (last_res == -999) return -999;
                item = strtok_r(NULL, " \t\r\n", &saveptr);
            }
            return last_res;
        }
    }

    /* Scripting: if <cond>; then <cmds>; [else <cmds>;] fi */
    if (strncmp(line, "if ", 3) == 0) {
        char *p_then = strstr(line, "; then ");
        if (!p_then) p_then = strstr(line, " then ");
        char *p_fi = strstr(line, "; fi");
        if (!p_fi) p_fi = strstr(line, " fi");
        if (p_then && p_fi && p_then < p_fi) {
            char cond[256];
            size_t clen = p_then - (line + 3);
            if (clen > 255) clen = 255;
            strncpy(cond, line + 3, clen);
            cond[clen] = '\0';

            char *then_start = p_then + (*p_then == ';' ? 7 : 6);
            char *p_else = strstr(then_start, "; else ");
            if (!p_else) p_else = strstr(then_start, " else ");

            char then_part[512];
            char else_part[512];
            else_part[0] = '\0';

            if (p_else && p_else < p_fi) {
                size_t tlen = p_else - then_start;
                if (tlen > 511) tlen = 511;
                strncpy(then_part, then_start, tlen);
                then_part[tlen] = '\0';

                char *else_start = p_else + (*p_else == ';' ? 7 : 6);
                size_t elen = p_fi - else_start;
                if (elen > 511) elen = 511;
                strncpy(else_part, else_start, elen);
                else_part[elen] = '\0';
            } else {
                size_t tlen = p_fi - then_start;
                if (tlen > 511) tlen = 511;
                strncpy(then_part, then_start, tlen);
                then_part[tlen] = '\0';
            }

            I64 c_res = ShellRunLogicalLine(cond);
            if (c_res == 0) {
                return ShellRunLogicalLine(then_part);
            } else if (else_part[0] != '\0') {
                return ShellRunLogicalLine(else_part);
            }
            return 0;
        }
    }

    /* Scripting: while <cond>; do <cmds>; done */
    if (strncmp(line, "while ", 6) == 0) {
        char *p_do = strstr(line, "; do ");
        if (!p_do) p_do = strstr(line, " do ");
        char *p_done = strstr(line, "; done");
        if (!p_done) p_done = strstr(line, " done");
        if (p_do && p_done && p_do < p_done) {
            char cond[256];
            size_t clen = p_do - (line + 6);
            if (clen > 255) clen = 255;
            strncpy(cond, line + 6, clen);
            cond[clen] = '\0';

            char body[512];
            char *body_start = p_do + (*p_do == ';' ? 5 : 4);
            size_t blen = p_done - body_start;
            if (blen > 511) blen = 511;
            strncpy(body, body_start, blen);
            body[blen] = '\0';

            I64 last_res = 0;
            I64 loop_iters = 0;
            while (loop_iters++ < 100) {
                char cond_copy[256];
                strncpy(cond_copy, cond, sizeof(cond_copy) - 1);
                cond_copy[sizeof(cond_copy) - 1] = '\0';
                if (ShellRunLogicalLine(cond_copy) != 0) break;

                char body_copy[512];
                strncpy(body_copy, body, sizeof(body_copy) - 1);
                body_copy[sizeof(body_copy) - 1] = '\0';
                last_res = ShellRunLogicalLine(body_copy);
                if (last_res == -999) return -999;
            }
            return last_res;
        }
    }

    char *p = line;
    I64 last_res = 0;
    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;

        /* Check for single '&' background separator (not '&&') */
        char *single_amp = NULL;
        char *scan = p;
        while (*scan) {
            if (*scan == '&') {
                if (*(scan + 1) == '&') {
                    scan += 2;
                    continue;
                }
                if (scan > p && *(scan - 1) == '&') {
                    scan++;
                    continue;
                }
                single_amp = scan;
                break;
            }
            scan++;
        }

        char *cand_and = strstr(p, "&&");
        char *cand_or  = strstr(p, "||");
        char *next_op = NULL;
        Bool is_and = FALSE;

        if (single_amp && (!cand_and || single_amp < cand_and) && (!cand_or || single_amp < cand_or)) {
            char next_char = *(single_amp + 1);
            *(single_amp + 1) = '\0';
            last_res = ShellExecutePipeline(p);
            *(single_amp + 1) = next_char;
            p = single_amp + 1;
            continue;
        }

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
    char composite[1024];
    composite[0] = '\0';
    Bool in_block = FALSE;

    while (line) {
        while (*line && isspace((unsigned char)*line)) line++;
        if (*line && *line != '#') {
            if (!in_block && (strncmp(line, "for ", 4) == 0 || strncmp(line, "if ", 3) == 0 || strncmp(line, "while ", 6) == 0) &&
                strstr(line, "done") == NULL && strstr(line, "fi") == NULL) {
                in_block = TRUE;
                strncpy(composite, line, sizeof(composite) - 1);
                composite[sizeof(composite) - 1] = '\0';
            } else if (in_block) {
                size_t clen = strlen(composite);
                if (clen < sizeof(composite) - 2) {
                    composite[clen++] = ' ';
                    composite[clen] = '\0';
                }
                strncat(composite, line, sizeof(composite) - clen - 1);
                if (strcmp(line, "done") == 0 || strstr(line, " done") != NULL ||
                    strcmp(line, "fi") == 0 || strstr(line, " fi") != NULL) {
                    in_block = FALSE;
                    res = ShellRunLogicalLine(composite);
                    composite[0] = '\0';
                    if (res == -999) break;
                }
            } else {
                res = ShellRunLogicalLine(line);
                if (res == -999) break;
            }
        }
        line = strtok_r(NULL, "\r\n", &saveptr);
    }
    if (in_block && composite[0]) {
        res = ShellRunLogicalLine(composite);
    }
    return res;
}

/*
 * Parse and execute a full command line preserving compound control flow blocks
 */
I64 ShellExecuteCommandLine(char *line) {
    while (*line && isspace((unsigned char)*line)) line++;
    if (!*line) return 0;

    char *curr = line;
    I64 last_res = 0;
    while (*curr) {
        while (*curr && isspace((unsigned char)*curr)) curr++;
        if (!*curr) break;

        /* Compound block: for ... done */
        if (strncmp(curr, "for ", 4) == 0) {
            char *p_done = strstr(curr, "; done");
            if (!p_done) p_done = strstr(curr, " done");
            if (p_done) {
                char *block_end = p_done + (*p_done == ';' ? 6 : 5);
                while (*block_end && isspace((unsigned char)*block_end)) block_end++;
                char next_c = *block_end;
                *block_end = '\0';
                last_res = ShellRunLogicalLine(curr);
                *block_end = next_c;
                if (next_c == ';') block_end++;
                curr = block_end;
                continue;
            }
        }
        /* Compound block: if ... fi */
        else if (strncmp(curr, "if ", 3) == 0) {
            char *p_fi = strstr(curr, "; fi");
            if (!p_fi) p_fi = strstr(curr, " fi");
            if (p_fi) {
                char *block_end = p_fi + (*p_fi == ';' ? 4 : 3);
                while (*block_end && isspace((unsigned char)*block_end)) block_end++;
                char next_c = *block_end;
                *block_end = '\0';
                last_res = ShellRunLogicalLine(curr);
                *block_end = next_c;
                if (next_c == ';') block_end++;
                curr = block_end;
                continue;
            }
        }
        /* Compound block: while ... done */
        else if (strncmp(curr, "while ", 6) == 0) {
            char *p_done = strstr(curr, "; done");
            if (!p_done) p_done = strstr(curr, " done");
            if (p_done) {
                char *block_end = p_done + (*p_done == ';' ? 6 : 5);
                while (*block_end && isspace((unsigned char)*block_end)) block_end++;
                char next_c = *block_end;
                *block_end = '\0';
                last_res = ShellRunLogicalLine(curr);
                *block_end = next_c;
                if (next_c == ';') block_end++;
                curr = block_end;
                continue;
            }
        }

        /* Normal command up to semicolon */
        char *semi = strchr(curr, ';');
        if (semi) {
            *semi = '\0';
            last_res = ShellRunLogicalLine(curr);
            curr = semi + 1;
            if (last_res == -999) return -999;
        } else {
            last_res = ShellRunLogicalLine(curr);
            break;
        }
    }
    return last_res;
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

        I64 r = ShellExecuteCommandLine((char*)line);
        if (r == -999) {
            return;
        }
    }
}

#endif /* SHELL_HC */
