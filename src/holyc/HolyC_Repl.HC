/*
 * HolyC Unix Kernel - In-Kernel HolyC Interpreter & REPL (HolyC_Repl.HC)
 * Allows users to run HolyC scripts (.HC) and evaluate HolyC statements inside the Unix shell.
 *
 * Implements:
 * 1. Arithmetic expressions, variable assignments, and prints
 * 2. Preprocessor macro engine (#define, #ifdef, #ifndef, #else, #endif)
 * 3. TempleOS inline assembly (asm { ... }) and x86-64 virtual register state
 * 4. Interactive REPL and batch script runner
 */

#ifndef HOLYC_REPL_HC
#define HOLYC_REPL_HC

#include "Types.HC"
#include "VFS.HC"
#include "GodWords.HC"
#include "Terminal.HC"

#define MAX_REPL_VARS 64
#define MAX_REPL_MACROS 32

class CReplVar {
    U8 name[32];
    I64 val;
    Bool is_set;
};

typedef struct {
    char name[32];
    char val[64];
    Bool is_defined;
} CReplMacro;

typedef struct {
    I64 rax;
    I64 rbx;
    I64 rcx;
    I64 rdx;
    I64 rsi;
    I64 rdi;
    I64 rsp;
    I64 rbp;
    I64 rip;
} CReplAsmCpu;

static CReplVar g_repl_vars[MAX_REPL_VARS];
static CReplMacro g_repl_macros[MAX_REPL_MACROS];
static Bool g_preproc_active = TRUE;
static CReplAsmCpu g_asm_cpu = { 0, 0, 0, 0, 0, 0, 0x7FFF0000, 0x7FFF0000, 0x401000 };

U0 ReplInitVars() {
    MemSet(g_repl_vars, 0, sizeof(g_repl_vars));
    MemSet(g_repl_macros, 0, sizeof(g_repl_macros));
    g_preproc_active = TRUE;

    /* Predefine standard HolyC macros */
    strncpy(g_repl_macros[0].name, "__HOLYC__", 31);
    strncpy(g_repl_macros[0].val, "1", 63);
    g_repl_macros[0].is_defined = TRUE;

    strncpy(g_repl_macros[1].name, "TEMPLEOS", 31);
    strncpy(g_repl_macros[1].val, "1", 63);
    g_repl_macros[1].is_defined = TRUE;

    strncpy(g_repl_macros[2].name, "HOLYNIX", 31);
    strncpy(g_repl_macros[2].val, "1", 63);
    g_repl_macros[2].is_defined = TRUE;
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

Bool ReplIsMacroDefined(const char *name) {
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (g_repl_macros[i].is_defined && strcmp(g_repl_macros[i].name, name) == 0) {
            return TRUE;
        }
    }
    return FALSE;
}

U0 ReplDefineMacro(const char *name, const char *val) {
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (g_repl_macros[i].is_defined && strcmp(g_repl_macros[i].name, name) == 0) {
            strncpy(g_repl_macros[i].val, val ? val : "1", 63);
            return;
        }
    }
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (!g_repl_macros[i].is_defined) {
            g_repl_macros[i].is_defined = TRUE;
            strncpy(g_repl_macros[i].name, name, 31);
            strncpy(g_repl_macros[i].val, val ? val : "1", 63);
            return;
        }
    }
}

U0 ReplUndefMacro(const char *name) {
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (g_repl_macros[i].is_defined && strcmp(g_repl_macros[i].name, name) == 0) {
            g_repl_macros[i].is_defined = FALSE;
            return;
        }
    }
}

/* Simple arithmetic evaluator */
static I64 ReplEvalExpr(const U8 *expr) {
    while (*expr && isspace((unsigned char)*expr)) expr++;
    if (!*expr) return 0;

    /* Check if integer literal (hex or decimal) */
    if (expr[0] == '0' && (expr[1] == 'x' || expr[1] == 'X')) {
        return strtoll((const char*)expr, NULL, 16);
    }
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
 * Evaluates TempleOS inline assembly block: asm { ... }
 */
static U0 ReplEvalAsm(const char *body) {
    Print("\033[93m[HolyC Ring-0 Inline Assembly Evaluator]\033[0m\n");
    char copy[512];
    strncpy(copy, body, sizeof(copy) - 1);
    copy[sizeof(copy) - 1] = '\0';

    char *saveptr = NULL;
    char *inst = strtok_r(copy, ";\n", &saveptr);
    while (inst) {
        while (*inst && isspace((unsigned char)*inst)) inst++;
        if (*inst && *inst != '}') {
            if (strncmp(inst, "nop", 3) == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96m90                  \033[0m nop\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 1;
            } else if (strncmp(inst, "mov rax,", 8) == 0 || strncmp(inst, "mov  rax,", 9) == 0) {
                char *val_str = strchr(inst, ',');
                if (val_str) {
                    val_str++;
                    while (*val_str && isspace((unsigned char)*val_str)) val_str++;
                    I64 val = strtoll(val_str, NULL, 0);
                    g_asm_cpu.rax = val;
                    Print("  \033[90m0x%08llX:\033[0m \033[96m48 c7 c0 %02X %02X %02X %02X\033[0m mov rax, 0x%llX\n",
                          (long long)g_asm_cpu.rip,
                          (unsigned int)(val & 0xFF), (unsigned int)((val >> 8) & 0xFF),
                          (unsigned int)((val >> 16) & 0xFF), (unsigned int)((val >> 24) & 0xFF),
                          (long long)val);
                    g_asm_cpu.rip += 7;
                }
            } else if (strncmp(inst, "int 0x80", 8) == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96mcd 80               \033[0m int 0x80 (syscall dispatch)\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 2;
            } else if (strncmp(inst, "syscall", 7) == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96m0f 05               \033[0m syscall\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 2;
            } else if (strncmp(inst, "ret", 3) == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96mc3                  \033[0m ret\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 1;
            } else {
                Print("  \033[90m0x%08llX:\033[0m \033[96m90                  \033[0m %s\n",
                      (long long)g_asm_cpu.rip, inst);
                g_asm_cpu.rip += 1;
            }
        }
        inst = strtok_r(NULL, ";\n", &saveptr);
    }

    Print("  \033[92mRegisters: RAX=0x%llX RBX=0x%llX RCX=0x%llX RDX=0x%llX RIP=0x%llX\033[0m\n",
          (long long)g_asm_cpu.rax, (long long)g_asm_cpu.rbx,
          (long long)g_asm_cpu.rcx, (long long)g_asm_cpu.rdx, (long long)g_asm_cpu.rip);
}

/*
 * Evaluates a single HolyC statement.
 */
Bool ReplEvalLine(const U8 *raw_line) {
    while (*raw_line && isspace((unsigned char)*raw_line)) raw_line++;
    if (!*raw_line || (raw_line[0] == '/' && raw_line[1] == '/')) {
        return TRUE;
    }

    /* Preprocessor directives */
    if (raw_line[0] == '#') {
        const char *cmd = (const char*)raw_line + 1;
        while (*cmd && isspace((unsigned char)*cmd)) cmd++;

        if (strncmp(cmd, "define", 6) == 0) {
            char name[32], val[64] = "1";
            if (sscanf(cmd + 6, "%31s %63s", name, val) >= 1) {
                ReplDefineMacro(name, val);
                Print("\033[90m#define %s %s\033[0m\n", name, val);
            }
            return TRUE;
        } else if (strncmp(cmd, "undef", 5) == 0) {
            char name[32];
            if (sscanf(cmd + 5, "%31s", name) == 1) {
                ReplUndefMacro(name);
            }
            return TRUE;
        } else if (strncmp(cmd, "ifdef", 5) == 0) {
            char name[32];
            if (sscanf(cmd + 5, "%31s", name) == 1) {
                g_preproc_active = ReplIsMacroDefined(name);
            }
            return TRUE;
        } else if (strncmp(cmd, "ifndef", 6) == 0) {
            char name[32];
            if (sscanf(cmd + 6, "%31s", name) == 1) {
                g_preproc_active = !ReplIsMacroDefined(name);
            }
            return TRUE;
        } else if (strncmp(cmd, "else", 4) == 0) {
            g_preproc_active = !g_preproc_active;
            return TRUE;
        } else if (strncmp(cmd, "endif", 5) == 0) {
            g_preproc_active = TRUE;
            return TRUE;
        }
        return TRUE;
    }

    /* If conditional compilation block is inactive, skip execution */
    if (!g_preproc_active) {
        return TRUE;
    }

    U8 line[512];
    StrNCpy(line, raw_line, 511);

    /* Strip trailing semicolon if present */
    I64 llen = StrLen(line);
    if (llen > 0 && line[llen - 1] == ';') {
        line[--llen] = '\0';
    }

    /* Inline Assembly: asm { ... } or _asm { ... } */
    if (strncmp((char*)line, "asm", 3) == 0 || strncmp((char*)line, "_asm", 4) == 0) {
        char *brace = strchr((char*)line, '{');
        if (brace) {
            char *end_brace = strrchr(brace, '}');
            if (end_brace) *end_brace = '\0';
            ReplEvalAsm(brace + 1);
            return TRUE;
        }
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
