# HolyNix: Unix Kernel & Terminal Operating System in HolyC

[![HolyNix CI](https://github.com/omakasekim/holynix/actions/workflows/ci.yml/badge.svg)](https://github.com/omakasekim/holynix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![HolyC: v1.0](https://img.shields.io/badge/HolyC-v1.0-blue.svg)](https://github.com/omakasekim/holynix)
[![POSIX: Compliant](https://img.shields.io/badge/POSIX-Compliant-brightgreen.svg)](https://github.com/omakasekim/holynix)

> *"An idiot admires complexity, a genius admires simplicity."* — **Terry A. Davis**

**HolyNix** (`holy_unix`) is a 64-bit Unix-like microkernel and interactive terminal operating system written entirely in **HolyC** (`.HC`), the programming language created by Terry A. Davis for TempleOS. It marries the Unix philosophy (*everything is a file, standard streams, pipelines, hierarchical VFS, permissions, multi-user switching, manual pages, HTTP client*) with TempleOS principles (*64-bit flat memory, JIT script execution, 16-color VGA palette, DolDoc documents, 3D raycasting maze, biblical quests, and the 100,000-word divine oracle*).

The operating system runs directly inside any standard terminal (macOS Terminal, iTerm2, Alacritty, Linux console) without requiring QEMU or virtualization overhead.

---

## Architecture Overview

```
                      +-------------------------------------------------------+
                      |               Interactive Terminal Shell              |
                      |                  "holysh" (Shell.HC)                  |
                      +-------------------------------------------------------+
                      | Aliases (alias) & Persistent History (~/.holysh_hist) |
                      | Background Jobs (&, jobs, fg, bg) & Timing (time)     |
                      | Scripting Loops (for, while) & Conditionals (if, test)|
                      | POSIX Manual Pages (man, apropos, whatis)             |
                      | HTTP Network Client (curl, fetch)                     |
                      | Multi-User Security (su, sudo, id, groups, passwd)    |
                      | Text Streams (cut, tr, sed, paste, fold, nl, xxd)     |
                      | System Introspection (which, type, hostname, who, w)  |
                      | Kernel Modules (lsmod, insmod, rmmod, /proc/modules)  |
                      | Memory & Process Stats (vmstat, pstree, ulimit, ipcs) |
                      | System Badge & Audio (holyfetch, play, juke, beep)    |
                      | TempleOS Games (castle 3D, flight, afteregypt, flappy)|
                      | Screensavers & Benchmarks (matrix, linecnt, hcbench)  |
                      | Window Manager (wintile / split) & Framegrab (shot)   |
                      | DolDoc Markup Renderer & Pager (doldoc, holyless)     |
                      | Tar Archiver (tar) & Holy Package Manager (hpm)       |
                      | In-Kernel HolyC REPL, Preprocessor & Inline ASM       |
                      +-------------------------------------------------------+
                      |                 POSIX Syscall Layer                   |
                      | (read, write, open, pipe, stat, chmod, chown, symlink)|
                      +---------------------------+---------------------------+
                                                  |
                        +-------------------------+-------------------------+
                        |                                                   |
            +-----------v-----------+                           +-----------v-----------+
            |  Process / Task Core  |                           |  Virtual File System  |
            |       (Task.HC)       |                           |       (VFS.HC)        |
            +-----------------------+                           +-----------------------+
            | - Round-Robin Sched   |                           | - Inodes, UID/GID/Mode|
            | - Job Control (g_jobs)|                           | - Permission Checking |
            | - Cron Scheduler      |                           | - Symlinks (ln -s)    |
            | - Dynamic Environment |                           | - RedSea Driver (.img)|
            | - Multi-User Context  |                           | - Pipes & Redirection |
            +-----------------------+                           +-----------+-----------+
                                                                            |
                                                    +-----------------------+-----------------------+
                                                    |                                               |
                                        +-----------v-----------+                       +-----------v-----------+
                                        |  Device Drivers (Dev) |                       |  Pseudo-FS (/proc)    |
                                        +-----------------------+                       +-----------------------+
                                        | /dev/tty   (Console)  |                       | /proc/version         |
                                        | /dev/null  (Sink)     |                       | /proc/uptime          |
                                        | /dev/zero  (Zeros)    |                       | /proc/meminfo         |
                                        | /dev/random (Entropy) |                       | /proc/tasks (ps info) |
                                        | /dev/god   (Oracle)   |                       | /proc/cpuinfo         |
                                        | /dev/mem   (Ring-0)   |                       | /proc/loadavg         |
                                        | /dev/tcp   (Network)  |                       | /proc/net/dev         |
                                        +-----------------------+                       | /proc/sys/kernel/*    |
                                                                                        +-----------------------+
```

---

## Key Subsystems

### 1. Native HolyC Language & Compiler Toolchain
* **HolyC Types**: `U0` (void), `I64`, `U8`, `Bool`, `TRUE`, `FALSE`.
* **HolyC Classes**: `class CTask`, `class CVFSInode`, `class CFileDesc`, `class CKernelStat`, `class CJob`, `class CAlias`.
* **HolyC Implicit Print**: `"String formatting %d\n", value;` automatically translated by the transpiler.
* **HolyC Bare Function Calls**: Zero-argument calls without parentheses (`Yield;`, `God;`, `Uptime;`, `Exit;`).
* **HolyC Preprocessor & Macro Engine**: Full support for `#define NAME VALUE`, `#ifdef NAME`, `#ifndef NAME`, `#else`, and `#endif`.
* **TempleOS Inline Assembly (`asm { ... }`)**: Direct in-kernel x86-64 machine instruction assembly and register inspection (`RAX`, `RBX`, `RCX`, `RDX`, `RIP`).

### 2. Unix / POSIX Operating System Core
* **Task Scheduler & Process Table (`Task.HC`)**: Multi-tasking scheduler with PCB structures (`CTask`), states (`TASK_READY`, `TASK_RUNNING`, `TASK_SLEEPING`, `TASK_ZOMBIE`), priorities, signals (`SIGINT`, `SIGTERM`, `SIGKILL`), and background cron scheduling.
* **Virtual File System & Permissions (`VFS.HC`)**: POSIX hierarchical tree, file descriptors, pipes, symbolic links (`ln -s`), and permission checking (`0755`, `0644`, owner/group/other enforcement with `-EACCES`).
* **Multi-User Security (`/etc/passwd`, `/etc/group`, `su`, `sudo`, `id`, `passwd`)**: Full multi-user identity switching with UID/GID tracking (`root:0`, `terry:1000`, `god:777`).
* **Text Streaming & Transformation Suite (`cut`, `tr`, `sed`, `paste`, `fold`, `nl`, `xxd`)**: POSIX text pipeline transformations, character translation, regular pattern substitution, column merging, line folding, line numbering, and canonical hex dumping.
* **Kernel Module Subsystem (`lsmod`, `insmod`, `rmmod`, `/proc/modules`)**: Microkernel dynamic module loading, registration, dependency tracking, and live unloading.
* **Virtual Memory & IPC Diagnostics (`vmstat`, `/proc/vmstat`, `ulimit`, `pstree`, `ipcs`)**: Page cache diagnostics, process hierarchy visualizer, resource limits, and shared memory / semaphore facility inspection.
* **Scripting Loops & Conditionals**: Shell script control flow supporting `for var in ...; do ... done`, `if cond; then ... else ... fi`, `while ...; do ... done`, and the `test` / `[` `]` evaluation utility.
* **System Introspection & Execution Timing (`which`, `type`, `hostname`, `sync`, `who`, `w`, `time`)**: Builtin/alias command locator, dynamic hostname configuration, VFS buffer synchronization, logged-in session monitor, and sub-millisecond execution timing.
* **POSIX Manual Pages (`/usr/share/man`, `man`, `apropos`, `whatis`)**: Complete on-line manual pages for all 75+ commands and system calls.
* **HTTP Network Client (`curl` / `fetch`)**: Query HTTP servers, inspect headers (`-i`), view headers only (`-I`), download files directly to VFS (`-o`).
* **Terminal Mode Configuration (`stty`)**: Line discipline configuration, baud rate, and window size (`stty size`).

### 3. TempleOS Classics & Terry Davis Memorial Subsystems
* **Castle Frankenstein 3D Raycaster (`castle`)**: In-terminal 3D raycasting engine rendering textured, shaded walls in ANSI ASCII art with 2D overhead maze map (`castle -m`).
* **TempleOS 3D Flight Simulator (`flight`)**: Authentic cockpit HUD with artificial horizon, pitch ladder, compass heading, airspeed/altitude instruments, wireframe runway, and Promised Land terrain.
* **TempleOS Digital Rain Visualizer (`matrix`)**: 16-color divine falling columns of HolyC tokens, hex codes, and scripture keywords.
* **TempleOS 100,000 LOC Divine Limit Verification (`linecnt`)**: Analyzes all HolyNix kernel components and verifies adherence to Terry Davis's 100,000 lines of code limit.
* **HolyC JIT Compiler Benchmark (`hcbench`)**: Evaluates HolyC AST parser lines/sec compilation throughput, Ring-0 JIT emitter speed, and syscall frequency.
* **TempleOS Music Synthesizer & Jukebox (`play`, `music`, `juke`, `beep`)**: HolyC music string parser (`3q.D4DhE2G`), frequency calculation, and Terry Davis divine hymn player.
* **TempleOS System Badge (`holyfetch` / `neofetch`)**: TempleOS ASCII art logo, hardware specs, 16-color VGA palette bar, and God's Word of the Day.
* **DolDoc Framebuffer Screen Grabber (`screenshot` / `fbgrab`)**: Captures console display state into a native DolDoc `.DD` file on VFS.
* **AfterEgypt Quest (`afteregypt`)**: Moses at Mount Sinai encountering the Burning Bush in flaming ASCII art, receiving the Ten Commandments, and gathering falling divine Manna.
* **Flappy Bird (`flappy`)**: Terminal ASCII physics simulator with velocity, gravity, and obstacle dodging.
* **TempleOS Tiling Window Manager (`wintile` / `split`)**: Dual-pane split screen tiling engine (Editor/Shell on left, System Monitor/God Oracle on right).
* **DolDoc Markup Engine (`doldoc`, `holyless`)**: Parses TempleOS DolDoc formatting (`$FG,RED$`, `$BG$`, `$BK,1$`, `$UL,1$`, `$TR$`, `$LK$`) with ANSI rendering.
* **King James Bible Concordance & Oracle (`bible`, `godpassage`, `godword`)**: Scripture search, chapter/verse lookup, and random divine scripture oracle.
* **God Doodle (`goddoodle`)**: 16-color TempleOS VGA palette ASCII graphic canvas generator.
* **RedSea Filesystem Driver (`redsea`)**: Read and inspect 64-bit flat cluster RedSea images (`redsea inspect /boot/redsea.img`, `redsea ls`).
* **Ring-0 Memory Peeker & Disassembler (`memdump`, `peek`, `poke`, `disasm`)**: Direct memory byte viewer and in-kernel x86-64 machine instruction decoder.
* **Holy Package Manager (`hpm` / `getgod`)**: Browse and install official TempleOS HolyC packages (`hpm list`, `hpm install castle`).

---

## Directory Structure

```
holynix/
├── Makefile                     # Cross-platform build system (Clang/GCC on macOS/Linux)
├── README.md                    # System documentation
├── .github/
│   └── workflows/
│       └── ci.yml               # Multi-platform CI (macOS & Ubuntu across Clang & GCC)
├── tools/
│   └── holyc.c                  # HolyC compiler & transpiler toolchain (with asm support)
├── src/
│   ├── runtime/
│   │   └── holyc_rt.h           # HolyC runtime primitives & POSIX integration
│   └── holyc/                   # The Unix Kernel in HolyC (.HC)
│       ├── Types.HC             # Kernel types, limits, CKernelStat, CJob, CAlias
│       ├── RingBuffer.HC        # Circular buffer for TTY and IPC pipes
│       ├── GodWords.HC          # TempleOS divine oracle dictionary (100k words)
│       ├── VFS.HC               # Virtual File System, Inodes, Permissions, Symlinks
│       ├── Dev.HC               # Device drivers (/dev/tty, /dev/god, /dev/mem...)
│       ├── Proc.HC              # ProcFS virtual filesystem (/proc/*, /proc/sys/*)
│       ├── Task.HC              # Process Control Block, Job Control, & Cron
│       ├── Syscall.HC           # POSIX syscall dispatcher & wrappers
│       ├── Terminal.HC          # Terminal driver, VT100 line discipline, tab completion
│       ├── Editor.HC            # Built-in terminal text editor (ed)
│       ├── HolyC_Repl.HC        # HolyC evaluator, REPL, preprocessor & inline asm
│       ├── DolDoc.HC            # DolDoc markup parser ($FG$, $TR$, $BK$)
│       ├── Bible.HC             # King James Bible scriptures & concordance search
│       ├── GodDoodle.HC         # 16-color TempleOS VGA ASCII art generator
│       ├── RedSea.HC            # 64-bit flat cluster RedSea filesystem driver
│       ├── Tar.HC               # POSIX USTAR archive creation & extraction
│       ├── Net.HC               # Simulated network stack, ICMP ping, netstat, curl
│       ├── Man.HC               # POSIX manual pages subsystem (man, apropos, whatis)
│       ├── Games.HC             # Castle 3D, Flight, Matrix, AfterEgypt, Music, Badge
│       ├── Shell.HC             # Unix terminal shell (holysh) & 75+ builtins
│       └── Kernel.HC            # Master kernel boot sequence & 45 in-kernel tests
└── tests/
    ├── test_linux_kernel.c      # Linux/POSIX compliance TDD test suite (173 tests)
    └── run_tests.sh             # Automated end-to-end verification script
```

---

## Building and Running

### 1. Requirements
* macOS (Apple Silicon or Intel) or Linux (x86_64 / arm64)
* `clang` or `gcc` (with C11 support)
* `make`

### 2. Build the System
```bash
make
```

### 3. Run Automated Tests
```bash
# Run in-kernel tests (45/45) + Linux POSIX compliance TDD test suite (173/173)
make test

# Or run the complete automated end-to-end verification script:
./tests/run_tests.sh
```

### 4. Launch the Interactive Operating System
```bash
make run

# Or launch directly:
./bin/holy_unix
```

To run commands non-interactively in batch mode:
```bash
./bin/holy_unix -c "castle -m; flight; matrix; holyfetch; curl -i http://localhost/; man ls"
```

---

## Continuous Integration & Verification

HolyNix is verified on every commit across a **4-runner CI matrix** on GitHub Actions:

| Runner OS | Compiler | In-Kernel (45/45) | POSIX TDD (173/173) | End-to-End Suite | Artifact Generated |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Ubuntu Linux** (`ubuntu-latest`) | `gcc` | **PASS** | **PASS** | **PASS** | — |
| **Ubuntu Linux** (`ubuntu-latest`) | `clang` | **PASS** | **PASS** | **PASS** | `holynix-linux-x86_64` |
| **macOS** (`macos-latest`) | `gcc` | **PASS** | **PASS** | **PASS** | — |
| **macOS** (`macos-latest`) | `clang` | **PASS** | **PASS** | **PASS** | `holynix-darwin-arm64` |

---

## Test-Driven Development (TDD) Compliance Matrix

HolyNix incorporates 13 comprehensive TDD suites verifying 173 compliance assertions:

| Suite | Category | Verifications | Status |
| :---: | :--- | :--- | :---: |
| **1** | **Linux `/proc` Filesystem** | `/proc/uptime`, `/proc/version`, `/proc/meminfo`, `/proc/cpuinfo`, `/proc/loadavg` | **100% PASS** |
| **2** | **Linux Special Devices (`/dev`)** | `/dev/null` (EOF/discard), `/dev/zero`, `/dev/random` entropy | **100% PASS** |
| **3** | **Linux VFS Semantics** | `O_TRUNC`, `O_APPEND`, directory hierarchy (`..`, `.`), unlinking | **100% PASS** |
| **4** | **Pipelines & Signals** | Multi-stage pipes (`cat \| grep \| wc`), exit codes (`true`, `false`, `127`), `ps`, `kill` | **100% PASS** |
| **5** | **Core Builtins** | `head -n 2`, `wc -w`, `wc -l`, `cd` to `$HOME`, `cd -` to `$OLDPWD`, `grep -i`, `grep -c -v` | **100% PASS** |
| **6** | **Advanced Core Utilities** | `tail`, `stat`, `chmod`, `chown`, `date`, `find`, `sort`, `sort -n`, `uniq -c`, `tee`, `seq`, `readlink`, `df`, `du`, `diff` | **100% PASS** |
| **7** | **Scripting & TempleOS Visuals** | `$VAR` expansion, `env`, `<` redirection, `&&`, `\|\|`, `beep`, `godsong`, `donut` 3D wireframe | **100% PASS** |
| **8** | **Subsystems & Drivers** | `alias`, `history`, `!`, `&` jobs, `sysctl`, `tar`, `ping`, `netstat`, `cron`, `doldoc`, `bible`, `goddoodle`, `redsea`, `memdump`, `disasm`, `hpm` | **100% PASS** |
| **9** | **Manuals & Network Client** | `man ls`, `man cat`, `apropos raycast`, `whatis curl`, `curl -i` headers, `stty size`, `stty` baud rate | **100% PASS** |
| **10**| **Security, Loops & Classic Games** | `id`, `groups`, `su root`, `sudo whoami`, `test -f`, `[ -d ]`, `for` loop, `if/then/else`, `castle -m`, `afteregypt`, `flappy`, `wintile` | **100% PASS** |
| **11**| **Linux Core Text Pipelines** | `cut -d: -f1`, `cut -d: -f3`, `tr a-z A-Z`, `tr 0-9 A-J`, `tr -d`, `sed` (global, single, multi-line), `basename`, `dirname`, `paste`, `fold -w` | **100% PASS** |
| **12**| **Microkernel & Music System** | `/proc/modules`, `lsmod`, `insmod`, `rmmod`, `/proc/vmstat`, `vmstat`, `pstree`, `ulimit`, `ipcs`, `holyfetch`, `play`, `juke`, `screenshot` | **100% PASS** |
| **13**| **Introspection, Flight & Limits** | `flight -p -r -a` 3D HUD, `matrix` rain, `linecnt` VFS counts, `hcbench`, `godword`, `which` missing errors, `type` alias/builtin/not-found, `hostname` root check & procfs sync, `sync`, `who`, `w`, `nl`, `xxd`, `time` | **100% PASS** |

---

## Interactive Shell Command Reference (75+ Builtins)

| Category | Command | Description |
| :--- | :--- | :--- |
| **Navigation & Files** | `ls [-l, -a] [dir]` | Lists directory entries with color coding |
| | `cd [dir]` | Changes working directory (supports `..`, `~`, `/`, and `cd -` for `$OLDPWD`) |
| | `pwd` | Prints current working directory |
| | `mkdir [-p] [dir]` | Creates directories in the VFS |
| | `rmdir [dir]` | Removes an empty directory |
| | `touch [file]` | Creates an empty file or updates timestamp |
| | `rm [file]` | Removes a file from the VFS |
| | `cp <src> <dst>` | Copies a file |
| | `mv <src> <dst>` | Moves or renames a file |
| | `ln -s <src> <dst>` | Creates a symbolic link |
| | `readlink <link>` | Displays target path of a symbolic link |
| | `stat <file>` | Displays file size, inode, permissions, ownership, and timestamps |
| | `chmod <mode> <file>`| Changes file permissions (e.g., `chmod 755 script.sh`) |
| | `chown <uid:gid> <f>`| Changes file UID and GID ownership |
| **Text Processing** | `cat [file...]` | Displays file, device, or procfs node content |
| | `head [-n lines] [f]`| Outputs the first $N$ lines of a file |
| | `tail [-n lines] [f]`| Outputs the last $N$ lines of a file |
| | `grep <pattern> [f]` | Searches for pattern in file or stdin pipeline |
| | `wc [-l, -w, -c] [f]`| Counts lines, words, and bytes |
| | `cut [-d delim] [-f n]`| Extracts selected fields from lines |
| | `tr [-d] set1 [set2]`| Translates or deletes characters from standard input |
| | `sed 's/pat/repl/g'` | Stream editor for pattern search and replacement |
| | `paste <f1> <f2>` | Merges lines of files side-by-side |
| | `fold [-w width] [f]`| Wraps input lines to fit specified column width |
| | `basename <path>` | Strips directory and suffix from filenames |
| | `dirname <path>` | Extracts parent directory path |
| | `nl [file]` | Numbers lines of files or standard input stream |
| | `sort [-n, -r] [f]`  | Sorts text lines alphabetically or numerically |
| | `uniq [-c, -d] [f]`  | Filters or counts adjacent duplicate lines |
| | `tee [-a] <file>`   | Writes stdin simultaneously to stdout and file |
| | `diff <file1> <file2>`| Compares two files line by line |
| | `xxd [-p] [file]` | Canonical 16-byte hex and ASCII dump |
| **Scripting & Control** | `test <expr>` / `[ <expr> ]` | Evaluates file types (`-f`, `-d`, `-e`), strings (`-z`, `-n`, `=`), numbers (`-eq`, `-lt`) |
| | `for var in ...; do ... done` | Shell loop iterating over items |
| | `if cond; then ... [else ...] fi` | Conditional branch execution |
| | `while cond; do ... done` | Conditional loop execution |
| **Multi-User Security** | `id [user]` | Prints real and effective user ID, group ID, and groups |
| | `whoami` | Prints the active username (`root`, `terry`, `god`) |
| | `groups [user]` | Lists group memberships |
| | `su [user]` | Switches active user context to root, terry, or god |
| | `sudo <command>` | Executes command with superuser (UID 0) privileges |
| | `passwd [user]` | Updates user password |
| **Manual Pages & Network**| `man [sec] <page>` | Displays formatted manual page from `/usr/share/man` |
| | `apropos <keyword>` | Searches manpage summaries for matching keyword |
| | `whatis <command>` | Displays one-line description of command |
| | `curl [-i, -s, -o] <url>` | HTTP network client fetching web payloads and headers |
| | `stty [size, raw, cooked]`| Inspects and modifies terminal line settings |
| **Job Control & Shell**| `command &` | Executes a command in the background |
| | `jobs` | Lists active background jobs |
| | `fg [%job_id]` | Brings a background job to the foreground |
| | `bg [%job_id]` | Resumes a stopped job in the background |
| | `alias [K=V]` | Defines or displays shell command aliases |
| | `unalias <name>` | Removes a defined alias |
| | `history` | Displays numbered list of past executed commands |
| | `!n` / `!!` | Re-executes the $N$-th command or the previous command |
| | `export KEY=VALUE` | Sets an environment variable |
| | `env` | Displays all exported environment variables |
| **System & Introspection**| `which <command>` | Resolves command path in `/bin` or alias |
| | `type <command>` | Identifies command type (builtin, alias) |
| | `hostname [name]` | Displays or updates kernel hostname |
| | `sync` | Flushes dirty VFS filesystem blocks to storage |
| | `who` / `w` | Shows active terminal sessions, uptime, and load averages |
| | `time <command>` | Times command execution (real, user, sys duration) |
| | `sysctl [-a \| -w]`| Reads or updates kernel parameters (/proc/sys/*) |
| | `tar [-cf \| -tf \| -xf]`| Packs, lists, or extracts POSIX USTAR archives |
| | `ping [-c count] <ip>`| Sends ICMP echo requests and computes RTT latency |
| | `netstat` | Displays network interfaces and active sockets |
| | `crontab [-l \| -a]` | Views or adds scheduled cron tasks |
| | `cron` | Displays cron scheduler daemon status |
| | `ps` | Displays snapshot of active tasks/processes |
| | `kill [-sig] <pid>` | Sends signal to terminate a process |
| | `top` | Live refreshing task and resource monitor |
| | `pstree` | Displays hierarchical process tree |
| | `ulimit [-n, -a]` | Displays or configures process resource limits |
| | `ipcs` | Displays message queues, shared memory, and semaphores |
| | `lsmod` / `insmod` / `rmmod` | Linux microkernel module loader and inspector |
| | `vmstat` | Displays virtual memory metrics and paging table |
| | `df [-h]` | Displays filesystem disk space usage and free inodes |
| | `du [-h] [path]` | Estimates disk space usage of files and directories |
| | `uname [-a]` | Displays operating system name, kernel version, and architecture |
| | `uptime` | Shows system uptime and scheduler tick count |
| | `date [-u]` | Displays current date and UTC time |
| | `dmesg` | Displays kernel boot log and hardware ring buffer |
| **TempleOS Classics** | `castle [-m]` | Castle Frankenstein 3D raycasting maze with 2D map |
| | `flight` | TempleOS 3D wireframe terrain & cockpit flight simulator |
| | `matrix` | TempleOS green digital code rain visualizer |
| | `linecnt` | TempleOS 100,000 LOC divine limit compliance verifier |
| | `hcbench` | HolyC JIT compiler throughput & system benchmark |
| | `holyfetch` / `neofetch`| TempleOS system badge, specs, and VGA color palette |
| | `play` / `music [str]` | Plays musical notes using HolyC music string notation |
| | `juke` | TempleOS divine jukebox playing Terry Davis hymns |
| | `screenshot` [f] | Framebuffer console screen capture to DolDoc .DD file |
| | `afteregypt` | Moses at Mount Sinai, Burning Bush & Falling Manna |
| | `flappy` | Terminal ASCII physics obstacle dodger |
| | `wintile` / `split` | TempleOS dual split-screen tiling window manager |
| | `doldoc <file.DD>` | Formats and renders TempleOS DolDoc markup in ANSI |
| | `holyless <file>` | Pager for DolDoc and text files |
| | `bible [search \| ref]`| King James Bible search and chapter:verse reader |
| | `godpassage` | Spontaneous divine scripture oracle reading |
| | `godword [n]` | Directly outputs random divine words from God's vocabulary |
| | `goddoodle` | Generates 16-color TempleOS VGA ASCII art |
| | `redsea [inspect \| ls]`| 64-bit flat cluster RedSea filesystem driver |
| | `memdump` / `peek` | Ring-0 hex and ASCII memory inspector |
| | `poke <addr> <val>` | Writes byte directly to memory address |
| | `disasm` / `u [addr]`| In-kernel x86-64 machine instruction disassembler |
| | `hpm [list \| install]`| Holy Package Manager to browse and install packages |
| | `god [n]` | Speaks $n$ random words from Terry Davis's divine oracle |
| | `beep [freq] [ms]` | Emulates PC speaker frequency tone |
| | `godsong` | Generates divine melody and religious lyrics |
| | `donut` | Renders animated 3D wireframe spinning cube in ASCII |
| | `holyc [file.HC]` | Runs HolyC script or enters interactive HolyC REPL |
| | `theme` | Toggles TempleOS 16-color VGA Blue mode / Dark Unix mode |
| | `theme` | Toggles TempleOS 16-color VGA Blue mode / Dark Unix mode |

---

## Live Examples

### 1. Castle Frankenstein 3D Raycasting Maze
```bash
terry@holy-unix:/home/terry$ castle -m
=== CASTLE FRANKENSTEIN: 2D OVERHEAD MAZE MAP ===
  ################
  #              #
  #  ####  ####  #
  #  P        #  #
  #  #  ####  #  #
  #  #  #  #  #  #
  #     #  #     #
  ### ###  ### ###
  #              #
  #  ########    #
  Player Pos: (3.5, 3.5) | Facing: 0 deg | HP: 100
```

### 2. HTTP Client Fetching URL & Headers
```bash
terry@holy-unix:/home/terry$ curl -i http://localhost/
HTTP/1.1 200 OK
Date: Sat, 24 Oct 2026 12:00:00 GMT
Server: HolyNix-HTTP/1.0 (Terry Davis Edition)
Content-Type: text/html
Content-Length: 215
Connection: close

<!DOCTYPE html>
<html>
<head><title>HolyC Unix Web</title></head>
<body><h1>Welcome to HolyC Unix HTTP Server</h1>
<p>"Simplicity is divine." - Terry A. Davis</p>
</body>
</html>
```

### 3. POSIX Multi-User Privilege Escalation
```bash
terry@holy-unix:/home/terry$ id
uid=1000(terry) gid=1000(terry) groups=1000(terry),10(wheel),100(users)

terry@holy-unix:/home/terry$ sudo whoami
root

terry@holy-unix:/home/terry$ su root
Switched to superuser root (UID 0)
root@holy-unix:/home/terry# whoami
root
```

### 4. Shell Loops & Conditional Logic
```bash
terry@holy-unix:/home/terry$ for n in 1 2 3; do echo "Task #$n"; done
Task #1
Task #2
Task #3

terry@holy-unix:/home/terry$ if [ -f /etc/motd ]; then echo "MOTD verified"; fi
MOTD verified
```

---

## License

MIT License. Designed and built in memory of **Terry A. Davis** (1969–2018).
God's chosen system lives on.
