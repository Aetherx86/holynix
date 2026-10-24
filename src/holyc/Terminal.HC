/*
 * HolyC Unix Kernel - Terminal Driver & Interactive Line Discipline (Terminal.HC)
 * Supports ANSI/VT100 codes, TempleOS 16-color palette, history, line editing, and tab completion.
 */

#ifndef TERMINAL_HC
#define TERMINAL_HC

#include "Types.HC"
#include "RingBuffer.HC"

#define MAX_HISTORY 64
#define HISTORY_LINE_LEN 256

static struct termios g_orig_termios;
static Bool g_raw_mode_active = FALSE;
static Bool g_templeos_blue_theme = FALSE;

static U8 g_history[MAX_HISTORY][HISTORY_LINE_LEN];
static I64 g_history_count = 0;

static CRingBuffer *g_dmesg_buf = NULL;

U0 KLog(const U8 *fmt, ...) {
    if (!g_dmesg_buf) {
        g_dmesg_buf = RingBufCreate(DMESG_BUFFER_SIZE);
    }
    va_list args;
    va_start(args, fmt);
    char buf[512];
    vsnprintf(buf, sizeof(buf), (const char*)fmt, args);
    va_end(args);

    RingBufWrite(g_dmesg_buf, (const U8*)buf, (I64)strlen(buf));
}

I64 DmesgRead(U8 *buf, I64 max_len) {
    if (!g_dmesg_buf || !buf || max_len <= 0) return 0;
    I64 n = Min(g_dmesg_buf->count, max_len - 1);
    for (I64 i = 0; i < n; ++i) {
        I64 idx = (g_dmesg_buf->tail + i) % g_dmesg_buf->capacity;
        buf[i] = g_dmesg_buf->buf[idx];
    }
    buf[n] = '\0';
    return n;
}

U0 TermRestore() {
    if (g_raw_mode_active) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_orig_termios);
        /* Reset terminal color & attributes */
        write(STDOUT_FILENO, "\033[0m\033[?25h", 9);
        g_raw_mode_active = FALSE;
    }
}

U0 TermInitRaw() {
    if (!isatty(STDIN_FILENO)) return;

    if (tcgetattr(STDIN_FILENO, &g_orig_termios) == -1) return;

    struct termios raw = g_orig_termios;
    /* Input: disable ICRNL, IXON, ISTRIP */
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    /* Output: keep ONLCR for proper newline */
    raw.c_oflag |= (OPOST | ONLCR);
    /* Local: disable ECHO, ICANON, IEXTEN, ISIG */
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    /* Control: 8-bit chars */
    raw.c_cflag |= (CS8);
    /* Min bytes to read: 1, timeout: 0 */
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != -1) {
        g_raw_mode_active = TRUE;
        atexit(TermRestore);
    }
}

I64 TermRead(U8 *buf, I64 count) {
    if (!buf || count <= 0) return 0;
    ssize_t n = read(STDIN_FILENO, buf, (size_t)count);
    return (n >= 0) ? (I64)n : -1;
}

I64 TermWrite(const U8 *buf, I64 count) {
    if (!buf || count <= 0) return 0;
    ssize_t n = write(STDOUT_FILENO, buf, (size_t)count);
    return (n >= 0) ? (I64)n : -1;
}

U0 TermClearScreen() {
    if (g_templeos_blue_theme) {
        write(STDOUT_FILENO, "\033[44;97m\033[2J\033[H", 16);
    } else {
        write(STDOUT_FILENO, "\033[0m\033[2J\033[H", 11);
    }
}

U0 TermToggleTheme() {
    g_templeos_blue_theme = !g_templeos_blue_theme;
    TermClearScreen();
    if (g_templeos_blue_theme) {
        Print("\033[93m[TempleOS VGA Mode: 640x480 16-Color Palette Activated]\033[0m\n");
    } else {
        Print("\033[92m[Modern Dark Unix ANSI Mode Activated]\033[0m\n");
    }
}

U0 TermAddHistory(const U8 *cmd) {
    if (!cmd || cmd[0] == '\0') return;
    if (g_history_count > 0 && StrCmp(g_history[g_history_count - 1], cmd) == 0) {
        return; /* Avoid consecutive duplicates */
    }
    if (g_history_count < MAX_HISTORY) {
        StrNCpy(g_history[g_history_count++], cmd, HISTORY_LINE_LEN - 1);
    } else {
        for (I64 i = 0; i < MAX_HISTORY - 1; ++i) {
            StrCpy(g_history[i], g_history[i + 1]);
        }
        StrNCpy(g_history[MAX_HISTORY - 1], cmd, HISTORY_LINE_LEN - 1);
    }
}

/* Tab completion candidates list */
static const char *g_builtin_commands[] = {
    "cat", "cd", "clear", "cp", "dmesg", "echo", "ed",
    "exit", "false", "god", "grep", "head", "help", "holyc",
    "kill", "ls", "mkdir", "mv", "ps", "pwd", "reboot",
    "rm", "theme", "top", "touch", "true", "uname", "uptime",
    "wc", "whoami", NULL
};

static U0 TermDoTabCompletion(U8 *line_buf, I64 *pos, I64 *len, I64 max_len) {
    /* Find prefix to complete */
    I64 word_start = *pos;
    while (word_start > 0 && line_buf[word_start - 1] != ' ') {
        word_start--;
    }
    I64 prefix_len = *pos - word_start;
    if (prefix_len <= 0) return;

    U8 prefix[64];
    I64 copy_len = Min(prefix_len, 63);
    MemCpy(prefix, line_buf + word_start, copy_len);
    prefix[copy_len] = '\0';

    const char *matches[64];
    I64 match_count = 0;

    /* Match commands if at first word */
    if (word_start == 0) {
        for (int i = 0; g_builtin_commands[i] && match_count < 64; ++i) {
            if (strncmp(g_builtin_commands[i], (const char*)prefix, copy_len) == 0) {
                matches[match_count++] = g_builtin_commands[i];
            }
        }
    }

    if (match_count == 1) {
        /* Single match: auto-complete */
        const char *match = matches[0];
        I64 match_len = strlen(match);
        for (I64 i = prefix_len; i < match_len && *len + 1 < max_len; ++i) {
            line_buf[(*pos)++] = match[i];
            (*len)++;
            write(STDOUT_FILENO, &match[i], 1);
        }
        if (*len + 1 < max_len) {
            line_buf[(*pos)++] = ' ';
            (*len)++;
            write(STDOUT_FILENO, " ", 1);
        }
        line_buf[*len] = '\0';
    } else if (match_count > 1) {
        /* Multiple matches: show options */
        write(STDOUT_FILENO, "\n\033[96m", 6);
        for (I64 i = 0; i < match_count; ++i) {
            write(STDOUT_FILENO, matches[i], strlen(matches[i]));
            write(STDOUT_FILENO, "  ", 2);
        }
        write(STDOUT_FILENO, "\033[0m\n", 5);
        /* Redraw line */
        write(STDOUT_FILENO, (const char*)line_buf, *len);
    }
}

/*
 * TermReadLine: Read an interactive command line with full VT100 navigation,
 * history browsing, character insertion/deletion, Ctrl+C, Ctrl+L, and tab completion.
 */
I64 TermReadLine(U8 *buf, I64 max_len, const U8 *prompt) {
    if (!buf || max_len <= 0) return -1;

    if (prompt) {
        Print("%s", prompt);
    }

    I64 pos = 0;
    I64 len = 0;
    I64 hist_idx = g_history_count;
    buf[0] = '\0';

    if (!g_raw_mode_active) {
        /* Non-raw fallback (e.g. redirected stdin in batch mode) */
        if (fgets((char*)buf, (int)max_len, stdin) == NULL) {
            return -1;
        }
        I64 l = StrLen(buf);
        if (l > 0 && buf[l - 1] == '\n') buf[--l] = '\0';
        return l;
    }

    while (1) {
        U8 c;
        if (read(STDIN_FILENO, &c, 1) <= 0) {
            return -1;
        }

        /* Enter / Return */
        if (c == '\r' || c == '\n') {
            buf[len] = '\0';
            write(STDOUT_FILENO, "\r\n", 2);
            if (len > 0) {
                TermAddHistory(buf);
            }
            return len;
        }

        /* Ctrl+C: Cancel command */
        if (c == 3) {
            write(STDOUT_FILENO, "^C\r\n", 4);
            buf[0] = '\0';
            return 0;
        }

        /* Ctrl+D: EOF */
        if (c == 4) {
            if (len == 0) {
                write(STDOUT_FILENO, "\r\n", 2);
                return -1;
            }
            continue;
        }

        /* Ctrl+L: Clear screen & repaint */
        if (c == 12) {
            TermClearScreen();
            if (prompt) Print("%s", prompt);
            write(STDOUT_FILENO, (const char*)buf, len);
            /* Move cursor back to pos */
            if (len > pos) {
                char back[32];
                snprintf(back, sizeof(back), "\033[%lldD", (long long)(len - pos));
                write(STDOUT_FILENO, back, strlen(back));
            }
            continue;
        }

        /* Tab completion */
        if (c == '\t') {
            TermDoTabCompletion(buf, &pos, &len, max_len);
            continue;
        }

        /* Backspace (DEL or BS) */
        if (c == 127 || c == 8) {
            if (pos > 0) {
                for (I64 i = pos - 1; i < len - 1; ++i) {
                    buf[i] = buf[i + 1];
                }
                pos--;
                len--;
                buf[len] = '\0';

                write(STDOUT_FILENO, "\b\033[K", 4);
                if (pos < len) {
                    write(STDOUT_FILENO, (const char*)&buf[pos], len - pos);
                    char back[32];
                    snprintf(back, sizeof(back), "\033[%lldD", (long long)(len - pos));
                    write(STDOUT_FILENO, back, strlen(back));
                }
            }
            continue;
        }

        /* Escape sequence (Arrows, Home, End, Del) */
        if (c == 27) {
            U8 seq[3];
            if (read(STDIN_FILENO, &seq[0], 1) <= 0) continue;
            if (read(STDIN_FILENO, &seq[1], 1) <= 0) continue;

            if (seq[0] == '[') {
                switch (seq[1]) {
                    case 'A': /* Up Arrow: History Previous */
                        if (hist_idx > 0) {
                            hist_idx--;
                            /* Clear current typed line on screen */
                            while (pos > 0) { write(STDOUT_FILENO, "\b", 1); pos--; }
                            write(STDOUT_FILENO, "\033[K", 3);
                            StrNCpy(buf, g_history[hist_idx], max_len - 1);
                            len = StrLen(buf);
                            pos = len;
                            write(STDOUT_FILENO, (const char*)buf, len);
                        }
                        break;
                    case 'B': /* Down Arrow: History Next */
                        if (hist_idx < g_history_count) {
                            hist_idx++;
                            while (pos > 0) { write(STDOUT_FILENO, "\b", 1); pos--; }
                            write(STDOUT_FILENO, "\033[K", 3);
                            if (hist_idx < g_history_count) {
                                StrNCpy(buf, g_history[hist_idx], max_len - 1);
                            } else {
                                buf[0] = '\0';
                            }
                            len = StrLen(buf);
                            pos = len;
                            write(STDOUT_FILENO, (const char*)buf, len);
                        }
                        break;
                    case 'C': /* Right Arrow */
                        if (pos < len) {
                            write(STDOUT_FILENO, "\033[C", 3);
                            pos++;
                        }
                        break;
                    case 'D': /* Left Arrow */
                        if (pos > 0) {
                            write(STDOUT_FILENO, "\033[D", 3);
                            pos--;
                        }
                        break;
                    case 'H': /* Home */
                        while (pos > 0) { write(STDOUT_FILENO, "\033[D", 3); pos--; }
                        break;
                    case 'F': /* End */
                        while (pos < len) { write(STDOUT_FILENO, "\033[C", 3); pos++; }
                        break;
                }
            }
            continue;
        }

        /* Printable characters */
        if (c >= 32 && c < 127 && len + 1 < max_len) {
            /* Insert character at pos */
            for (I64 i = len; i > pos; --i) {
                buf[i] = buf[i - 1];
            }
            buf[pos] = c;
            pos++;
            len++;
            buf[len] = '\0';

            write(STDOUT_FILENO, &c, 1);
            if (pos < len) {
                write(STDOUT_FILENO, (const char*)&buf[pos], len - pos);
                char back[32];
                snprintf(back, sizeof(back), "\033[%lldD", (long long)(len - pos));
                write(STDOUT_FILENO, back, strlen(back));
            }
        }
    }
}

#endif /* TERMINAL_HC */
