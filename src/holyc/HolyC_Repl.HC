/*
 * HolyC Unix Kernel - In-Kernel HolyC Interpreter & REPL (HolyC_Repl.HC)
 * Allows users to run HolyC scripts (.HC) and evaluate HolyC statements inside the Unix shell.
 */

#ifndef HOLYC_REPL_HC
#define HOLYC_REPL_HC

#include "Types.HC"
#include "VFS.HC"
#include "GodWords.HC"
#include "Terminal.HC"

#define MAX_REPL_VARS 64

class CReplVar {
    U8 name[32];
    I64 val;
    Bool is_set;
};

static CReplVar g_repl_vars[MAX_REPL_VARS];

U0 ReplInitVars() {
    MemSet(g_repl_vars, 0, sizeof(g_repl_vars));
}

I64 ReplGetVar(const U8 *name, I64 default_val) {
    for (I64 i = 0; i < MAX_REPL_VARS; ++i) {
        if (g_repl_vars[i].is_set && StrCmp(g_repl_vars[i].name, name) == 0) {
            return g_repl_vars[i].val;
        }
    }
    return default_val;
}

U0 ReplSetVar(const U8 *name, I64 val) {
    for (I64 i = 0; i < MAX_REPL_VARS; ++i) {
        if (g_repl_vars[i].is_set && StrCmp(g_repl_vars[i].name, name) == 0) {
            g_repl_vars[i].val = val;
            return;
        }
    }
    for (I64 i = 0; i < MAX_REPL_VARS; ++i) {
        if (!g_repl_vars[i].is_set) {
            g_repl_vars[i].is_set = TRUE;
            StrNCpy(g_repl_vars[i].name, name, 31);
            g_repl_vars[i].val = val;
            return;
        }
    }
}

/* Simple arithmetic evaluator */
static I64 ReplEvalExpr(const U8 *expr) {
    while (*expr && isspace((unsigned char)*expr)) expr++;
    if (!*expr) return 0;

    /* Check if integer literal */
    if (isdigit((unsigned char)*expr) || (*expr == '-' && isdigit((unsigned char)expr[1]))) {
        return atoll((const char*)expr);
    }

    /* Check variable */
    U8 var_name[32];
    int vi = 0;
    while (*expr && (isalnum((unsigned char)*expr) || *expr == '_') && vi < 31) {
        var_name[vi++] = *expr++;
    }
    var_name[vi] = '\0';

    while (*expr && isspace((unsigned char)*expr)) expr++;

    I64 lhs = ReplGetVar(var_name, 0);
    if (*expr == '+' || *expr == '-' || *expr == '*' || *expr == '/') {
        char op = *expr++;
        I64 rhs = ReplEvalExpr(expr);
        if (op == '+') return lhs + rhs;
        if (op == '-') return lhs - rhs;
        if (op == '*') return lhs * rhs;
        if (op == '/' && rhs != 0) return lhs / rhs;
    }
    return lhs;
}

/*
 * Evaluates a single HolyC statement.
 * Supports:
 * - Implicit prints: "String %d\n", val; or "String\n";
 * - Assignment: x = 10; or I64 x = 10;
 * - Built-in HolyC zero-arg functions: God;, Uptime;, Dir;, Clear;, Yield;, Exit;
 */
Bool ReplEvalLine(const U8 *raw_line) {
    while (*raw_line && isspace((unsigned char)*raw_line)) raw_line++;
    if (!*raw_line || raw_line[0] == '#' || (raw_line[0] == '/' && raw_line[1] == '/')) {
        return TRUE;
    }

    U8 line[256];
    StrNCpy(line, raw_line, 255);
    /* Strip trailing semicolon if present */
    I64 llen = StrLen(line);
    if (llen > 0 && line[llen - 1] == ';') {
        line[--llen] = '\0';
    }

    /* Exit command */
    if (StrCmp(line, "Exit") == 0 || StrCmp(line, "exit") == 0 || StrCmp(line, "quit") == 0) {
        return FALSE;
    }

    /* Bare HolyC commands */
    if (StrCmp(line, "God") == 0 || StrCmp(line, "God;") == 0) {
        GodSpeak(7);
        return TRUE;
    }
    if (StrCmp(line, "Clear") == 0) {
        TermClearScreen();
        return TRUE;
    }
    if (StrCmp(line, "Uptime") == 0) {
        Print("Uptime: %lld seconds, %lld ticks\n",
              (long long)KernelGetUptimeSec(), (long long)KernelGetTicks());
        return TRUE;
    }

    /* HolyC Print statement: starts with '"' */
    if (line[0] == '"') {
        /* Find closing quote */
        char *close_quote = strchr((char*)line + 1, '"');
        if (close_quote) {
            *close_quote = '\0';
            const char *fmt = (char*)line + 1;
            const char *args = close_quote + 1;
            while (*args && (*args == ' ' || *args == ',')) args++;

            if (*args != '\0') {
                /* Format with evaluated expression */
                I64 val = ReplEvalExpr((const U8*)args);
                /* Replace \n escapes */
                for (int i = 0; fmt[i]; ++i) {
                    if (fmt[i] == '\\' && fmt[i + 1] == 'n') {
                        Print("\n");
                        i++;
                    } else if (fmt[i] == '%' && (fmt[i + 1] == 'd' || fmt[i + 1] == 's')) {
                        Print("%lld", (long long)val);
                        i++;
                    } else {
                        PutChars(fmt[i]);
                    }
                }
            } else {
                for (int i = 0; fmt[i]; ++i) {
                    if (fmt[i] == '\\' && fmt[i + 1] == 'n') {
                        Print("\n");
                        i++;
                    } else {
                        PutChars(fmt[i]);
                    }
                }
            }
            return TRUE;
        }
    }

    /* Variable declaration or assignment: "I64 x = ..." or "x = ..." */
    const char *p = (const char*)line;
    if (strncmp(p, "I64 ", 4) == 0 || strncmp(p, "U0 ", 3) == 0 || strncmp(p, "U8 ", 3) == 0) {
        p = strchr(p, ' ') + 1;
    }
    while (*p && isspace((unsigned char)*p)) p++;

    char *eq = strchr(p, '=');
    if (eq) {
        char vname[32];
        int vi = 0;
        const char *vp = p;
        while (vp < eq && (isalnum((unsigned char)*vp) || *vp == '_') && vi < 31) {
            vname[vi++] = *vp++;
        }
        vname[vi] = '\0';
        I64 val = ReplEvalExpr((const U8*)(eq + 1));
        ReplSetVar((const U8*)vname, val);
        Print("\033[90m%s = %lld\033[0m\n", vname, (long long)val);
        return TRUE;
    }

    /* If it's an expression, evaluate and print */
    I64 eval_res = ReplEvalExpr((const U8*)line);
    Print("\033[92m%lld\033[0m\n", (long long)eval_res);
    return TRUE;
}

U0 HolyCRunScript(const U8 *path) {
    CTask *t = TaskGetCurrent();
    const U8 *cwd = t ? t->cwd : (const U8*)"/";
    I64 fd = VFSOpen(path, cwd, O_RDONLY);
    if (fd < 0) {
        Print("\033[91mError: Cannot open HolyC script '%s'\033[0m\n", path);
        return;
    }

    U8 chunk[8192];
    I64 bytes_read = VFSRead(fd, chunk, sizeof(chunk) - 1);
    VFSClose(fd);
    if (bytes_read <= 0) {
        Print("\033[90m[Empty script]\033[0m\n");
        return;
    }
    chunk[bytes_read] = '\0';

    char *saveptr = NULL;
    char *line = strtok_r((char*)chunk, "\r\n", &saveptr);
    while (line) {
        ReplEvalLine((const U8*)line);
        line = strtok_r(NULL, "\r\n", &saveptr);
    }
}

U0 HolyCRepl() {
    ReplInitVars();
    Print("\033[93m====================================================\033[0m\n");
    Print("\033[96mHolyC Interactive REPL v1.0 (TempleOS Environment)\033[0m\n");
    Print("\033[90mType HolyC statements, \"String\\n\";, God;, or Exit;\033[0m\n");
    Print("\033[93m====================================================\033[0m\n");

    U8 line[256];
    while (1) {
        I64 n = TermReadLine(line, sizeof(line), (const U8*)"\033[95mHolyC>\033[0m ");
        if (n < 0) break;
        if (n == 0) continue;
        if (!ReplEvalLine(line)) {
            break;
        }
    }
    Print("\033[90m[Exited HolyC REPL]\033[0m\n");
}

#endif /* HOLYC_REPL_HC */
