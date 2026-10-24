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

static I64 g_last_exit_code = 0;
static U8 g_oldpwd[MAX_PATH_LEN] = "/home/terry";

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
    CTask *t = TaskGetCurrent();
    Bool newline = TRUE;
    I64 start = 1;
    if (argc > 1 && StrCmp((const U8*)argv[1], "-n") == 0) {
        newline = FALSE;
        start = 2;
    }

    char exit_str[16];
    snprintf(exit_str, sizeof(exit_str), "%lld", (long long)g_last_exit_code);

    for (I64 i = start; i < argc; ++i) {
        const char *arg = argv[i];
        if (strcmp(arg, "$?") == 0) arg = exit_str;
        else if (strcmp(arg, "$USER") == 0) arg = (t && t->uid == 0) ? "root" : "terry";
        else if (strcmp(arg, "$HOME") == 0) arg = "/home/terry";
        else if (strcmp(arg, "$SHELL") == 0) arg = "/bin/holysh";
        else if (strcmp(arg, "$PWD") == 0) arg = (t ? (const char*)t->cwd : "/");
        else if (strcmp(arg, "$OS") == 0) arg = "HolyC-Unix";

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
    Print("%s\n", t ? (const char*)t->cwd : "/");
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
        Print("HolyC-Unix holy-unix 1.0.0-holyc Darwin arm64 HolyC-Compiler-v1 GNU/TempleOS\n");
    } else {
        Print("HolyC-Unix\n");
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
    Print(" %02lld:%02lld:%02lld up %lld seconds, %lld ticks, load average: 0.08, 0.02, 0.01\n",
          (long long)hours, (long long)mins, (long long)secs,
          (long long)sec, (long long)KernelGetTicks());
}

/*
 * Built-in Command: whoami
 */
U0 ShellCmdWhoami(I64 argc, char **argv) {
    (U0)argc; (U0)argv;
    CTask *t = TaskGetCurrent();
    Print("%s\n", (t && t->uid == 0) ? "root" : "terry");
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

    if (opt_l && !opt_w && !opt_c) {
        if (filepath) Print("%lld %s\n", (long long)lines, filepath);
        else Print("%lld\n", (long long)lines);
    } else if (!opt_l && opt_w && !opt_c) {
        if (filepath) Print("%lld %s\n", (long long)words, filepath);
        else Print("%lld\n", (long long)words);
    } else if (!opt_l && !opt_w && opt_c) {
        if (filepath) Print("%lld %s\n", (long long)bytes, filepath);
        else Print("%lld\n", (long long)bytes);
    } else {
        if (filepath) {
            Print(" %5lld %5lld %5lld %s\n",
                  (long long)lines, (long long)words, (long long)bytes, filepath);
        } else {
            Print(" %5lld %5lld %5lld\n",
                  (long long)lines, (long long)words, (long long)bytes);
        }
    }
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
    Print("  \033[92mecho [args...]\033[0m      Display a line of text, expand $USER, $HOME\n");
    Print("  \033[92mmkdir [dir]\033[0m         Create directories\n");
    Print("  \033[92mtouch [file]\033[0m        Create empty files or update timestamps\n");
    Print("  \033[92mrm [file]\033[0m           Remove files from the VFS\n");
    Print("  \033[92mcp <src> <dst>\033[0m      Copy files\n");
    Print("  \033[92mmv <src> <dst>\033[0m      Move / rename files\n");
    Print("  \033[92mps\033[0m                  Report snapshot of current processes\n");
    Print("  \033[92mkill <pid>\033[0m          Send termination signal to process\n");
    Print("  \033[92mtop\033[0m                 Live process and resource monitor\n");
    Print("  \033[92mgrep <pat> [file]\033[0m   Search pattern in file or stream\n");
    Print("  \033[92mwc <file>\033[0m           Count lines, words, and bytes\n");
    Print("  \033[92mclear\033[0m               Clear terminal screen (also Ctrl+L)\n");
    Print("  \033[92muname [-a]\033[0m          Print operating system name & hardware info\n");
    Print("  \033[92muptime\033[0m              Show how long system has been running\n");
    Print("  \033[92mwhoami\033[0m              Print current effective user\n");
    Print("  \033[92mdmesg\033[0m               Print kernel message buffer & boot logs\n");
    Print("  \033[92med <file>\033[0m           Built-in terminal text editor (ed/nano style)\n");
    Print("  \033[92mgod [n]\033[0m             Consult Terry Davis's TempleOS Divine Oracle\n");
    Print("  \033[92mholyc [file.HC]\033[0m     Run HolyC scripts or enter interactive HolyC REPL\n");
    Print("  \033[92mtheme\033[0m               Toggle TempleOS 16-Color VGA Blue / Dark Unix theme\n");
    Print("  \033[92mexit / reboot\033[0m       Shut down or reboot the operating system\n");
    Print("Features: Pipelines (\033[96mcmd1 | cmd2\033[0m), Redirections (\033[96m> file\033[0m, \033[96m>> file\033[0m), Tab completion\n");
    Print("\033[93m=========================================================================\033[0m\n");
}

/*
 * Dispatch a single command with argv
 */
I64 ShellExecuteCommand(I64 argc, char **argv) {
    if (argc == 0) return 0;
    const char *cmd = argv[0];

    if (strcmp(cmd, "ls") == 0)         ShellCmdLs(argc, argv);
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
    else if (strcmp(cmd, "wc") == 0)     ShellCmdWc(argc, argv);
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

    /* Check for output redirection '>' or '>>' */
    char *redir_out = strchr(cmdline, '>');
    I64 redir_fd = -1;
    CTask *t = TaskGetCurrent();
    I64 saved_stdout = t ? t->fd_table[STDOUT_FILENO] : -1;

    if (redir_out) {
        *redir_out = '\0';
        redir_out++;
        I64 flags = O_CREAT | O_WRONLY;
        if (*redir_out == '>') {
            flags |= O_APPEND;
            redir_out++;
        } else {
            flags |= O_TRUNC;
        }
        while (*redir_out && isspace((unsigned char)*redir_out)) redir_out++;
        /* Strip trailing spaces from filename */
        char *end_fn = redir_out + strlen(redir_out) - 1;
        while (end_fn > redir_out && isspace((unsigned char)*end_fn)) {
            *end_fn = '\0';
            end_fn--;
        }

        redir_fd = SysOpen((const U8*)redir_out, flags);
        if (redir_fd >= 0) {
            t->fd_table[STDOUT_FILENO] = t->fd_table[redir_fd];
        }
    }

    /* Tokenize command arguments */
    char *argv[MAX_ARGS];
    I64 argc = 0;
    char *saveptr = NULL;
    char *token = strtok_r(cmdline, " \t\r\n", &saveptr);
    while (token && argc < MAX_ARGS - 1) {
        argv[argc++] = token;
        token = strtok_r(NULL, " \t\r\n", &saveptr);
    }
    argv[argc] = NULL;

    I64 res = ShellExecuteCommand(argc, argv);

    /* Restore stdout if redirected */
    if (redir_out && t) {
        if (redir_fd >= 0) SysClose(redir_fd);
        t->fd_table[STDOUT_FILENO] = saved_stdout;
    }

    return res;
}

/*
 * Main Shell REPL Loop
 */
U0 ShellRun() {
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
            /* EOF or terminal closed */
            break;
        }
        if (n == 0) continue;

        /* Handle semicolon separated commands */
        char *saveptr = NULL;
        char *cmd_part = strtok_r((char*)line, ";", &saveptr);
        while (cmd_part) {
            I64 r = ShellExecutePipeline(cmd_part);
            if (r == -999) {
                return; /* Clean exit */
            }
            cmd_part = strtok_r(NULL, ";", &saveptr);
        }
    }
}

#endif /* SHELL_HC */
