/*
 * HolyC Unix Kernel - Built-in Terminal Text Editor (Editor.HC)
 * Line-based interactive text editor for creating and modifying files in VFS.
 */

#ifndef EDITOR_HC
#define EDITOR_HC

#include "Types.HC"
#include "VFS.HC"
#include "Terminal.HC"

#define MAX_EDITOR_LINES 512
#define MAX_LINE_WIDTH   256

class CEditor {
    U8 lines[MAX_EDITOR_LINES][MAX_LINE_WIDTH];
    I64 line_count;
    U8 filepath[MAX_PATH_LEN];
    Bool modified;
};

static CEditor g_editor;

U0 EditorPrintLines() {
    Print("\033[96m--- %s (%lld lines) ---\033[0m\n",
          g_editor.filepath, (long long)g_editor.line_count);
    for (I64 i = 0; i < g_editor.line_count; ++i) {
        Print("\033[90m%3lld | \033[0m%s\n", (long long)(i + 1), g_editor.lines[i]);
    }
    Print("\033[96m------------------------------\033[0m\n");
}

U0 EditorSave() {
    /* Concatenate all lines with newline */
    I64 total_len = 0;
    for (I64 i = 0; i < g_editor.line_count; ++i) {
        total_len += StrLen(g_editor.lines[i]) + 1;
    }

    U8 *buf = (U8*)MAlloc(total_len + 1);
    buf[0] = '\0';
    for (I64 i = 0; i < g_editor.line_count; ++i) {
        StrCat(buf, g_editor.lines[i]);
        StrCat(buf, "\n");
    }

    CTask *t = TaskGetCurrent();
    const U8 *cwd = t ? t->cwd : (const U8*)"/";
    I64 inum = VFSCreateFile(g_editor.filepath, cwd, buf, total_len);
    Free(buf);

    if (inum >= 0) {
        g_editor.modified = FALSE;
        Print("\033[92m[Saved %lld bytes to '%s']\033[0m\n",
              (long long)total_len, g_editor.filepath);
    } else {
        Print("\033[91m[Error: Failed to save file '%s']\033[0m\n", g_editor.filepath);
    }
}

U0 EditorRun(const U8 *path) {
    if (!path || path[0] == '\0') {
        Print("Usage: ed <filename>\n");
        return;
    }

    MemSet(&g_editor, 0, sizeof(CEditor));
    StrNCpy(g_editor.filepath, path, MAX_PATH_LEN - 1);
    g_editor.modified = FALSE;

    /* Check if file exists in VFS and read its contents */
    CTask *t = TaskGetCurrent();
    const U8 *cwd = t ? t->cwd : (const U8*)"/";
    I64 fd = VFSOpen(path, cwd, O_RDONLY);
    if (fd >= 0) {
        U8 chunk[4096];
        I64 bytes_read = VFSRead(fd, chunk, sizeof(chunk) - 1);
        VFSClose(fd);
        if (bytes_read > 0) {
            chunk[bytes_read] = '\0';
            char *saveptr = NULL;
            char *line = strtok_r((char*)chunk, "\r\n", &saveptr);
            while (line && g_editor.line_count < MAX_EDITOR_LINES) {
                StrNCpy(g_editor.lines[g_editor.line_count++], (const U8*)line, MAX_LINE_WIDTH - 1);
                line = strtok_r(NULL, "\r\n", &saveptr);
            }
        }
    }

    Print("\033[93m=== HolyC Editor ('%s') ===\033[0m\n", g_editor.filepath);
    Print("Commands: 'p' (print), 'a' (append), 'd <n>' (delete), 'w' (save), 'wq' (save & exit), 'q' (exit)\n");

    EditorPrintLines();

    U8 cmd_buf[128];
    while (1) {
        I64 n = TermReadLine(cmd_buf, sizeof(cmd_buf), (const U8*)"\033[93med:\033[0m ");
        if (n < 0) break;
        if (n == 0) continue;

        if (StrCmp(cmd_buf, "q") == 0) {
            if (g_editor.modified) {
                Print("\033[91mFile has unsaved changes! Use 'w' to save, or 'q!' to discard.\033[0m\n");
            } else {
                break;
            }
        } else if (StrCmp(cmd_buf, "q!") == 0) {
            Print("\033[90m[Changes discarded]\033[0m\n");
            break;
        } else if (StrCmp(cmd_buf, "w") == 0) {
            EditorSave();
        } else if (StrCmp(cmd_buf, "wq") == 0 || StrCmp(cmd_buf, "x") == 0) {
            EditorSave();
            break;
        } else if (StrCmp(cmd_buf, "p") == 0 || StrCmp(cmd_buf, "list") == 0) {
            EditorPrintLines();
        } else if (StrCmp(cmd_buf, "a") == 0) {
            Print("\033[90m[Enter text. Type '.' on an empty line to finish]\033[0m\n");
            while (g_editor.line_count < MAX_EDITOR_LINES) {
                U8 in_line[MAX_LINE_WIDTH];
                char pbuf[32];
                snprintf(pbuf, sizeof(pbuf), "%3lld | ", (long long)(g_editor.line_count + 1));
                I64 in_len = TermReadLine(in_line, sizeof(in_line), (const U8*)pbuf);
                if (in_len < 0 || StrCmp(in_line, ".") == 0) break;
                StrNCpy(g_editor.lines[g_editor.line_count++], in_line, MAX_LINE_WIDTH - 1);
                g_editor.modified = TRUE;
            }
        } else if (cmd_buf[0] == 'd' && cmd_buf[1] == ' ') {
            I64 del_idx = atoll((const char*)&cmd_buf[2]) - 1;
            if (del_idx >= 0 && del_idx < g_editor.line_count) {
                for (I64 i = del_idx; i < g_editor.line_count - 1; ++i) {
                    StrCpy(g_editor.lines[i], g_editor.lines[i + 1]);
                }
                g_editor.line_count--;
                g_editor.modified = TRUE;
                Print("\033[92m[Deleted line %lld]\033[0m\n", (long long)(del_idx + 1));
            } else {
                Print("\033[91mInvalid line number.\033[0m\n");
            }
        } else {
            Print("Commands: p (print), a (append), d <line>, w (save), wq (save & exit), q (exit)\n");
        }
    }
}

#endif /* EDITOR_HC */
