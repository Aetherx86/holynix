/*
 * HolyC Unix Kernel - POSIX Manual Pages Subsystem (Man.HC)
 * "An idiot admires complexity, a genius admires simplicity." - Terry A. Davis
 *
 * Implements:
 * 1. man <command> / man <section> <command>
 * 2. apropos <keyword> (Search manpage summaries)
 * 3. whatis <command> (Display one-line description)
 * 4. Ramdisk /usr/share/man initialization
 */

#ifndef MAN_HC
#define MAN_HC

#include "Types.HC"
#include "VFS.HC"
#include "Terminal.HC"

typedef struct {
    const char *name;
    int section;
    const char *desc;
    const char *synopsis;
    const char *details;
} ManEntry;

static const ManEntry g_man_pages[] = {
    { "ls", 1, "list directory contents",
      "ls [-l] [-a] [PATH]",
      "List information about the FILEs (the current directory by default).\n"
      "Options:\n"
      "  -a    do not ignore entries starting with .\n"
      "  -l    use a long listing format with permissions, owner, and size" },

    { "cat", 1, "concatenate files and print on standard output",
      "cat [FILE]...",
      "Concatenate FILE(s) to standard output. With no FILE, read standard input." },

    { "grep", 1, "print lines that match patterns",
      "grep [-i] [-n] [-v] PATTERN [FILE]",
      "Search for PATTERN in each FILE or standard input.\n"
      "Options:\n"
      "  -i    ignore case distinctions in patterns and data\n"
      "  -n    prefix each line of output with the 1-based line number\n"
      "  -v    invert the sense of matching, to select non-matching lines" },

    { "man", 1, "format and display on-line manual pages",
      "man [SECTION] PAGE",
      "Display manual page for PAGE. Searches section 1 (commands) and 2 (syscalls)." },

    { "god", 1, "consult the TempleOS 100,000-word divine oracle",
      "god [COUNT]",
      "Generate COUNT divine words from the Holy Spirit via TempleOS oracle." },

    { "holyc", 1, "compile and execute HolyC programs or launch REPL",
      "holyc [SCRIPT.HC]",
      "With no arguments, starts interactive HolyC REPL. Otherwise executes script." },

    { "castle", 1, "3D raycast labyrinth game in HolyC",
      "castle [-m | --map]",
      "Renders a 3D raycast perspective of Castle Frankenstein in ANSI ASCII art.\n"
      "Use -m to display the 2D overhead maze map with player coordinates." },

    { "afteregypt", 1, "Moses at Mount Sinai receiving the commandments",
      "afteregypt",
      "TempleOS Holy Scripture Quest showing the burning bush and falling manna." },

    { "flappy", 1, "terminal obstacle dodging physics simulator",
      "flappy",
      "Terminal ASCII game with gravity, velocity, obstacle columns, and score." },

    { "wintile", 1, "TempleOS tiling dual-pane window manager",
      "wintile [-h | -v]",
      "Splits terminal screen into dual interactive panes (Shell & Divine Top)." },

    { "curl", 1, "transfer a URL via HTTP network client",
      "curl [-i] [-v] [-s] [-o FILE] URL",
      "Transfer data from or to a server using HTTP.\n"
      "Options:\n"
      "  -i, -v    include protocol response headers in the output\n"
      "  -s        silent mode: don't show transfer meter\n"
      "  -o FILE   write output to specified VFS FILE instead of stdout" },

    { "stty", 1, "change and print terminal line settings",
      "stty [-a] [size | raw | cooked | echo | -echo]",
      "Print or change terminal characteristics such as baud rate, rows, and echo." },

    { "su", 1, "change user ID or become superuser",
      "su [USER]",
      "Change the current task user context to USER (default: root)." },

    { "sudo", 1, "execute a command as the superuser (root)",
      "sudo COMMAND [ARGS...]",
      "Execute COMMAND with root (UID 0) privileges, then restore previous user." },

    { "id", 1, "print real and effective user and group IDs",
      "id [USER]",
      "Print user and group information for current or specified USER." },

    { "redsea", 1, "TempleOS 64-bit RedSea filesystem inspector",
      "redsea [inspect | ls | cat] IMAGE",
      "Inspect, list files, and read files from 64-bit RedSea disk images." },

    { "tar", 1, "POSIX USTAR archive utility",
      "tar [-c | -x | -t] -f ARCHIVE [FILES...]",
      "Manipulate archive files in POSIX standard USTAR format." },

    { "sysctl", 1, "configure kernel parameters at runtime",
      "sysctl [-a | -w KEY=VALUE]",
      "Examine and modify kernel parameters under /proc/sys." },

    { "ping", 1, "send ICMP ECHO_REQUEST packets to network hosts",
      "ping [-c COUNT] HOST",
      "Send ICMP echo requests and report round-trip times and packet statistics." },

    { "doldoc", 1, "render TempleOS DolDoc markup documents in ANSI",
      "doldoc FILE.DD",
      "Parse and display DolDoc documents with colors, blinking text, and trees." },

    { "test", 1, "check file types and compare values",
      "test EXPRESSION  or  [ EXPRESSION ]",
      "Evaluate EXPRESSION and return 0 (true) or 1 (false).\n"
      "Supported checks: -f FILE, -d DIR, -z STR, -n STR, S1 = S2, N1 -eq N2" },

    { "open", 2, "open and possibly create a file",
      "int open(const char *pathname, int flags, mode_t mode)",
      "Open the file specified by pathname and return a file descriptor." },

    { "read", 2, "read from a file descriptor",
      "ssize_t read(int fd, void *buf, size_t count)",
      "Attempts to read up to count bytes from file descriptor fd into buf." },

    { "write", 2, "write to a file descriptor",
      "ssize_t write(int fd, const void *buf, size_t count)",
      "Writes up to count bytes from the buffer to the file referred to by fd." },

    { "fork", 2, "create a child process",
      "pid_t fork(void)",
      "Creates a new process by duplicating the calling process." },

    { "stat", 2, "get file status",
      "int stat(const char *pathname, struct stat *statbuf)",
      "Retrieve information about the file pointed to by pathname." }
};

static const I64 g_man_page_count = sizeof(g_man_pages) / sizeof(g_man_pages[0]);

U0 ManDisplayPage(const ManEntry *e) {
    Print("\033[93m%s(%d)\033[0m                      \033[96mHolyC Unix Manual\033[0m                      \033[93m%s(%d)\033[0m\n\n",
          e->name, e->section, e->name, e->section);

    Print("\033[92mNAME\033[0m\n");
    Print("       %s - %s\n\n", e->name, e->desc);

    Print("\033[92mSYNOPSIS\033[0m\n");
    Print("       \033[97m%s\033[0m\n\n", e->synopsis);

    Print("\033[92mDESCRIPTION\033[0m\n");
    Print("       %s\n\n", e->details);

    Print("\033[92mAUTHOR\033[0m\n");
    Print("       HolyC-Unix Kernel Team (Terry A. Davis Memorial Architecture)\n\n");

    Print("\033[93mHolyC-Unix 1.0.0\033[0m                 \033[90mOctober 2026\033[0m                       \033[93m%s(%d)\033[0m\n",
          e->name, e->section);
}

I64 ManLookup(const char *page, int sec_filter) {
    for (I64 i = 0; i < g_man_page_count; ++i) {
        if (strcmp(g_man_pages[i].name, page) == 0) {
            if (sec_filter == 0 || g_man_pages[i].section == sec_filter) {
                ManDisplayPage(&g_man_pages[i]);
                return 0;
            }
        }
    }
    Print("No manual entry for %s\n", page);
    return 1;
}

I64 ManApropos(const char *keyword) {
    I64 matches = 0;
    Print("\033[93m=== Manpage Keyword Search for '%s' ===\033[0m\n", keyword);
    for (I64 i = 0; i < g_man_page_count; ++i) {
        if (strcasestr(g_man_pages[i].name, keyword) != NULL ||
            strcasestr(g_man_pages[i].desc, keyword) != NULL ||
            strcasestr(g_man_pages[i].details, keyword) != NULL) {
            Print("  \033[92m%-12s\033[0m (%d) - %s\n",
                  g_man_pages[i].name, g_man_pages[i].section, g_man_pages[i].desc);
            matches++;
        }
    }
    if (matches == 0) {
        Print("  No matching manpages found for '%s'.\n", keyword);
        return 1;
    }
    return 0;
}

I64 ManWhatis(const char *cmd) {
    for (I64 i = 0; i < g_man_page_count; ++i) {
        if (strcmp(g_man_pages[i].name, cmd) == 0) {
            Print("%s (%d) - %s\n", g_man_pages[i].name, g_man_pages[i].section, g_man_pages[i].desc);
            return 0;
        }
    }
    Print("%s: nothing appropriate.\n", cmd);
    return 1;
}

U0 ManInitRamdisk() {
    VFSMkdir("usr", "/");
    VFSMkdir("share", "/usr");
    VFSMkdir("man", "/usr/share");
    VFSMkdir("man1", "/usr/share/man");
    VFSMkdir("man2", "/usr/share/man");

    for (I64 i = 0; i < g_man_page_count; ++i) {
        char path[128];
        snprintf(path, sizeof(path), "/usr/share/man/man%d/%s.%d",
                 g_man_pages[i].section, g_man_pages[i].name, g_man_pages[i].section);
        VFSCreateFile(path, "/", (const U8*)g_man_pages[i].desc, strlen(g_man_pages[i].desc));
    }
}

#endif /* MAN_HC */
