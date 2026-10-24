/*
 * HolyC Transpiler & Compiler Tool (holyc.c)
 * Translates HolyC source files (.HC) to C11 and compiles with host clang/gcc.
 *
 * Implements HolyC syntax extensions:
 * - HolyC primitive types (U0, I8, U8, I16, U16, I32, U32, I64, U64, F64, Bool)
 * - HolyC class definitions:
 *     "class Foo;" -> "typedef struct Foo Foo;"
 *     "class Foo { ... };" -> "typedef struct Foo Foo; struct Foo { ... };"
 * - Recursive #include "file.HC" expansion with include-once guards
 * - HolyC implicit print statements: "String\n"; -> Print("String\n");
 * - Accurate initializer detection (prevents array initializers { "a", "b" } from being turned into Print)
 * - HolyC paren-less 0-argument function calls: e.g. "Yield;" -> "Yield();"
 * - Built-in runtime inclusion and clang/gcc driver invocation.
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdbool.h>
#include <unistd.h>
#include <time.h>
#include <libgen.h>
#include <limits.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define MAX_INCLUDES 256
#define MAX_INC_DIRS 16

static char g_included_files[MAX_INCLUDES][PATH_MAX];
static int g_included_count = 0;

static char g_include_search_dirs[MAX_INC_DIRS][PATH_MAX];
static int g_include_search_dir_count = 0;

typedef struct {
    char *data;
    size_t length;
    size_t capacity;
} Buffer;

static void buf_init(Buffer *b) {
    b->capacity = 4096;
    b->data = (char*)malloc(b->capacity);
    b->length = 0;
    b->data[0] = '\0';
}

static void buf_append_char(Buffer *b, char c) {
    if (b->length + 2 >= b->capacity) {
        b->capacity *= 2;
        b->data = (char*)realloc(b->data, b->capacity);
    }
    b->data[b->length++] = c;
    b->data[b->length] = '\0';
}

static void buf_append_str(Buffer *b, const char *s) {
    if (!s) return;
    size_t slen = strlen(s);
    if (b->length + slen + 2 >= b->capacity) {
        b->capacity = (b->capacity + slen) * 2;
        b->data = (char*)realloc(b->data, b->capacity);
    }
    memcpy(b->data + b->length, s, slen);
    b->length += slen;
    b->data[b->length] = '\0';
}

__attribute__((unused)) static void buf_free(Buffer *b) {
    if (b->data) free(b->data);
    b->data = NULL;
    b->length = b->capacity = 0;
}

static char *read_entire_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = (char*)malloc(size + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t read_bytes = fread(buf, 1, size, f);
    buf[read_bytes] = '\0';
    fclose(f);
    return buf;
}

static bool is_bare_call_target(const char *name) {
    static const char *targets[] = {
        "Yield", "Uptime", "Dir", "Exit", "Clear", "Halt", "TaskSwitch",
        "SysHalt", "KPanic", "Help", "WhoAmI", "Dmesg", "Top", "Reboot",
        NULL
    };
    for (int i = 0; targets[i]; ++i) {
        if (strcmp(name, targets[i]) == 0) return true;
    }
    return false;
}

static bool is_already_included(const char *path) {
    for (int i = 0; i < g_included_count; ++i) {
        if (strcmp(g_included_files[i], path) == 0) return true;
    }
    return false;
}

static void mark_included(const char *path) {
    if (g_included_count < MAX_INCLUDES) {
        snprintf(g_included_files[g_included_count++], PATH_MAX, "%s", path);
    }
}

static char *resolve_include_file(const char *inc_name, const char *current_file_dir) {
    char candidate[PATH_MAX];

    /* 1. Try relative to current file directory */
    if (current_file_dir && current_file_dir[0] != '\0') {
        snprintf(candidate, sizeof(candidate), "%s/%s", current_file_dir, inc_name);
        char *real = realpath(candidate, NULL);
        if (real) return real;
    }

    /* 2. Try in include search dirs */
    for (int i = 0; i < g_include_search_dir_count; ++i) {
        snprintf(candidate, sizeof(candidate), "%s/%s", g_include_search_dirs[i], inc_name);
        char *real = realpath(candidate, NULL);
        if (real) return real;
    }

    /* 3. Try direct path */
    char *real = realpath(inc_name, NULL);
    if (real) return real;

    return NULL;
}

static void transpile_file_content(const char *src, const char *curr_dir, Buffer *out) {
    size_t i = 0;
    size_t len = strlen(src);
    bool at_statement_start = true;
    bool seen_equal = false;
    int initializer_depth = 0;

    while (i < len) {
        /* Whitespace */
        if (isspace((unsigned char)src[i])) {
            buf_append_char(out, src[i]);
            i++;
            continue;
        }

        /* Line comments // */
        if (src[i] == '/' && i + 1 < len && src[i + 1] == '/') {
            while (i < len && src[i] != '\n') {
                buf_append_char(out, src[i++]);
            }
            continue;
        }

        /* Block comments */
        if (src[i] == '/' && i + 1 < len && src[i + 1] == '*') {
            buf_append_char(out, src[i++]);
            buf_append_char(out, src[i++]);
            while (i + 1 < len && !(src[i] == '*' && src[i + 1] == '/')) {
                buf_append_char(out, src[i++]);
            }
            if (i + 1 < len) {
                buf_append_char(out, src[i++]);
                buf_append_char(out, src[i++]);
            }
            continue;
        }

        /* Preprocessor directive check */
        if (src[i] == '#') {
            size_t hash_pos = i;
            while (i < len && src[i] != '\n') i++;
            size_t line_len = i - hash_pos;
            char line_buf[1024];
            if (line_len < sizeof(line_buf)) {
                memcpy(line_buf, &src[hash_pos], line_len);
                line_buf[line_len] = '\0';

                char *inc_kw = strstr(line_buf, "include");
                if (inc_kw) {
                    char *quote_start = strchr(inc_kw, '"');
                    if (quote_start) {
                        char *quote_end = strchr(quote_start + 1, '"');
                        if (quote_end) {
                            *quote_end = '\0';
                            const char *inc_file = quote_start + 1;
                            if (strstr(inc_file, ".HC") != NULL || strstr(inc_file, ".hc") != NULL) {
                                char *resolved = resolve_include_file(inc_file, curr_dir);
                                if (resolved) {
                                    if (!is_already_included(resolved)) {
                                        mark_included(resolved);
                                        char *inc_src = read_entire_file(resolved);
                                        if (inc_src) {
                                            char resolved_dir[PATH_MAX];
                                            strncpy(resolved_dir, resolved, sizeof(resolved_dir) - 1);
                                            resolved_dir[sizeof(resolved_dir) - 1] = '\0';
                                            char *dname = dirname(resolved_dir);

                                            buf_append_str(out, "\n/* Begin HolyC Include: ");
                                            buf_append_str(out, inc_file);
                                            buf_append_str(out, " */\n");

                                            transpile_file_content(inc_src, dname, out);

                                            buf_append_str(out, "\n/* End HolyC Include: ");
                                            buf_append_str(out, inc_file);
                                            buf_append_str(out, " */\n");

                                            free(inc_src);
                                        }
                                    }
                                    free(resolved);
                                    at_statement_start = true;
                                    continue;
                                }
                            }
                        }
                    }
                }
            }

            for (size_t k = hash_pos; k < i; ++k) {
                buf_append_char(out, src[k]);
            }
            at_statement_start = true;
            continue;
        }

        /* Track '=' for array/struct initializers */
        if (src[i] == '=') {
            seen_equal = true;
            buf_append_char(out, src[i++]);
            at_statement_start = false;
            continue;
        }

        /* Statement and block boundary markers */
        if (src[i] == '{') {
            if (seen_equal) {
                initializer_depth++;
                seen_equal = false;
            }
            buf_append_char(out, src[i++]);
            at_statement_start = true;
            continue;
        }

        if (src[i] == '}') {
            if (initializer_depth > 0) {
                initializer_depth--;
            }
            buf_append_char(out, src[i++]);
            at_statement_start = true;
            continue;
        }

        if (src[i] == ';') {
            seen_equal = false;
            buf_append_char(out, src[i++]);
            at_statement_start = true;
            continue;
        }

        /*
         * HolyC implicit Print statement:
         * ONLY active when at statement start AND NOT inside an initializer array/struct!
         */
        if (at_statement_start && initializer_depth == 0 && src[i] == '"') {
            buf_append_str(out, "Print(");
            while (i < len && src[i] != ';') {
                if (src[i] == '"') {
                    buf_append_char(out, src[i++]);
                    while (i < len && src[i] != '"') {
                        if (src[i] == '\\' && i + 1 < len) {
                            buf_append_char(out, src[i++]);
                        }
                        buf_append_char(out, src[i++]);
                    }
                    if (i < len && src[i] == '"') {
                        buf_append_char(out, src[i++]);
                    }
                } else {
                    buf_append_char(out, src[i++]);
                }
            }
            buf_append_char(out, ')');
            if (i < len && src[i] == ';') {
                buf_append_char(out, src[i++]);
            }
            at_statement_start = true;
            continue;
        }

        /* Check for HolyC 'class' keyword */
        if (src[i] == 'c' && strncmp(&src[i], "class", 5) == 0 &&
            !isalnum((unsigned char)src[i + 5]) && src[i + 5] != '_') {
            i += 5;
            while (i < len && isspace((unsigned char)src[i])) i++;
            char cname[256];
            int ci = 0;
            while (i < len && (isalnum((unsigned char)src[i]) || src[i] == '_') && ci < 255) {
                cname[ci++] = src[i++];
            }
            cname[ci] = '\0';

            /* Peek ahead for ';' (forward declaration) vs '{' (definition) */
            size_t peek = i;
            while (peek < len && isspace((unsigned char)src[peek])) peek++;

            if (peek < len && src[peek] == ';') {
                /* Forward declaration: "typedef struct CName CName;" */
                buf_append_str(out, "typedef struct ");
                buf_append_str(out, cname);
                buf_append_str(out, " ");
                buf_append_str(out, cname);
                buf_append_str(out, ";");
                i = peek + 1;
                at_statement_start = true;
                continue;
            } else {
                /* Struct definition: "typedef struct CName CName; struct CName " */
                buf_append_str(out, "typedef struct ");
                buf_append_str(out, cname);
                buf_append_str(out, " ");
                buf_append_str(out, cname);
                buf_append_str(out, "; struct ");
                buf_append_str(out, cname);
                buf_append_char(out, ' ');
                at_statement_start = false;
                continue;
            }
        }

        /* Read identifier */
        if (isalpha((unsigned char)src[i]) || src[i] == '_') {
            char ident[256];
            int id_len = 0;
            while (i < len && (isalnum((unsigned char)src[i]) || src[i] == '_') && id_len < 255) {
                ident[id_len++] = src[i++];
            }
            ident[id_len] = '\0';

            /* Check bare zero-arg function call */
            if (at_statement_start && initializer_depth == 0 && is_bare_call_target(ident)) {
                size_t peek = i;
                while (peek < len && isspace((unsigned char)src[peek])) peek++;
                if (peek < len && src[peek] == ';') {
                    buf_append_str(out, ident);
                    buf_append_str(out, "();");
                    i = peek + 1;
                    at_statement_start = true;
                    continue;
                }
            }

            buf_append_str(out, ident);
            at_statement_start = false;
            continue;
        }

        /* String literal in other expressions / initializers */
        if (src[i] == '"') {
            buf_append_char(out, src[i++]);
            while (i < len && src[i] != '"') {
                if (src[i] == '\\' && i + 1 < len) {
                    buf_append_char(out, src[i++]);
                }
                buf_append_char(out, src[i++]);
            }
            if (i < len && src[i] == '"') {
                buf_append_char(out, src[i++]);
            }
            at_statement_start = false;
            continue;
        }

        /* Character literal */
        if (src[i] == '\'') {
            buf_append_char(out, src[i++]);
            while (i < len && src[i] != '\'') {
                if (src[i] == '\\' && i + 1 < len) {
                    buf_append_char(out, src[i++]);
                }
                buf_append_char(out, src[i++]);
            }
            if (i < len && src[i] == '\'') {
                buf_append_char(out, src[i++]);
            }
            at_statement_start = false;
            continue;
        }

        /* Default char */
        buf_append_char(out, src[i++]);
        at_statement_start = false;
    }
}

static char *transpile_holyc_file(const char *src_path, const char *rt_header_path) {
    char *src_code = read_entire_file(src_path);
    if (!src_code) return NULL;

    Buffer out;
    buf_init(&out);

    buf_append_str(&out, "/* Generated by HolyC Transpiler */\n");
    if (rt_header_path) {
        buf_append_str(&out, "#include \"");
        buf_append_str(&out, rt_header_path);
        buf_append_str(&out, "\"\n\n");
    }

    char src_dir[PATH_MAX];
    strncpy(src_dir, src_path, sizeof(src_dir) - 1);
    src_dir[sizeof(src_dir) - 1] = '\0';
    char *dname = dirname(src_dir);

    char *real_src = realpath(src_path, NULL);
    if (real_src) {
        mark_included(real_src);
        free(real_src);
    }

    transpile_file_content(src_code, dname, &out);
    free(src_code);

    return out.data;
}

static void print_usage(const char *prog) {
    fprintf(stderr,
        "HolyC Compiler & Transpiler (holyc)\n"
        "Usage: %s [options] <source.HC> [-o output_binary]\n"
        "Options:\n"
        "  -o <file>       Specify output binary or object file\n"
        "  -E              Preprocess and transpile to C stdout\n"
        "  -c              Compile to object file without linking\n"
        "  --run           Transpile, compile, and run immediately\n"
        "  -I <dir>        Add include search path\n"
        "  -v, --version   Display version\n"
        "  -h, --help      Display this help message\n", prog);
}

int main(int argc, char **argv) {
    const char *src_path = NULL;
    const char *out_path = NULL;
    bool flag_E = false;
    bool flag_c = false;
    bool flag_run = false;
    char inc_dirs[4096] = "";

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        } else if (strcmp(argv[i], "-E") == 0) {
            flag_E = true;
        } else if (strcmp(argv[i], "-c") == 0) {
            flag_c = true;
        } else if (strcmp(argv[i], "--run") == 0) {
            flag_run = true;
        } else if (strcmp(argv[i], "-I") == 0 && i + 1 < argc) {
            const char *idir = argv[++i];
            strcat(inc_dirs, " -I");
            strcat(inc_dirs, idir);
            if (g_include_search_dir_count < MAX_INC_DIRS) {
                snprintf(g_include_search_dirs[g_include_search_dir_count++], PATH_MAX, "%s", idir);
            }
        } else if (strncmp(argv[i], "-I", 2) == 0) {
            const char *idir = argv[i] + 2;
            strcat(inc_dirs, " ");
            strcat(inc_dirs, argv[i]);
            if (g_include_search_dir_count < MAX_INC_DIRS) {
                snprintf(g_include_search_dirs[g_include_search_dir_count++], PATH_MAX, "%s", idir);
            }
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            printf("HolyC Compiler v1.0 (Darwin/Linux) - Designed for TerryDavis OS\n");
            return 0;
        } else if (argv[i][0] != '-') {
            src_path = argv[i];
        } else {
            fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    if (!src_path) {
        print_usage(argv[0]);
        return 1;
    }

    /* Locate holyc_rt.h using realpath(path, NULL) for POSIX/glibc safety */
    char *real_rt = realpath("src/runtime/holyc_rt.h", NULL);
    if (!real_rt) {
        real_rt = realpath("../src/runtime/holyc_rt.h", NULL);
    }
    if (!real_rt) {
        real_rt = realpath("holyc_rt.h", NULL);
    }

    char abs_rt_path[PATH_MAX];
    if (real_rt) {
        snprintf(abs_rt_path, sizeof(abs_rt_path), "%s", real_rt);
        free(real_rt);
    } else {
        snprintf(abs_rt_path, sizeof(abs_rt_path), "src/runtime/holyc_rt.h");
    }

    char *transpiled = transpile_holyc_file(src_path, abs_rt_path);
    if (!transpiled) {
        fprintf(stderr, "Error: Could not transpile source file '%s'\n", src_path);
        return 1;
    }

    if (flag_E) {
        printf("%s\n", transpiled);
        free(transpiled);
        return 0;
    }

    char tmp_c_path[PATH_MAX];
    snprintf(tmp_c_path, sizeof(tmp_c_path), "/tmp/holyc_%d_%u.c", getpid(), (unsigned int)time(NULL));
    FILE *ftmp = fopen(tmp_c_path, "w");
    if (!ftmp) {
        fprintf(stderr, "Error: Could not create temp C file '%s'\n", tmp_c_path);
        free(transpiled);
        return 1;
    }
    fputs(transpiled, ftmp);
    fclose(ftmp);
    free(transpiled);

    char cmd[PATH_MAX * 4];
    char target_out[PATH_MAX];
    if (out_path) {
        strncpy(target_out, out_path, sizeof(target_out) - 1);
        target_out[sizeof(target_out) - 1] = '\0';
    } else if (flag_run) {
        snprintf(target_out, sizeof(target_out), "/tmp/holyc_bin_%d", getpid());
    } else if (flag_c) {
        snprintf(target_out, sizeof(target_out), "out.o");
    } else {
        snprintf(target_out, sizeof(target_out), "a.out");
    }

    const char *cc = getenv("CC");
    if (!cc || cc[0] == '\0') cc = "clang";

    if (flag_c) {
        snprintf(cmd, sizeof(cmd),
                 "%s -std=c11 -Wall -Wno-unused-function -Wno-pointer-sign -O2%s -c \"%s\" -o \"%s\"",
                 cc, inc_dirs, tmp_c_path, target_out);
    } else {
        snprintf(cmd, sizeof(cmd),
                 "%s -std=c11 -Wall -Wno-unused-function -Wno-pointer-sign -O2%s \"%s\" -o \"%s\"",
                 cc, inc_dirs, tmp_c_path, target_out);
    }

    int compile_res = system(cmd);
    unlink(tmp_c_path);

    if (compile_res != 0) {
        fprintf(stderr, "HolyC Compilation failed (exit code %d).\n", compile_res);
        return compile_res;
    }

    if (flag_run) {
        int run_res = system(target_out);
        unlink(target_out);
        return run_res;
    }

    return 0;
}
