# HolyNix: Unix Kernel & Terminal Operating System in HolyC

[![HolyNix CI](https://github.com/omakasekim/holynix/actions/workflows/ci.yml/badge.svg)](https://github.com/omakasekim/holynix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![HolyC: v1.0](https://img.shields.io/badge/HolyC-v1.0-blue.svg)](https://github.com/omakasekim/holynix)
[![POSIX: Compliant](https://img.shields.io/badge/POSIX-Compliant-brightgreen.svg)](https://github.com/omakasekim/holynix)

> *"An idiot admires complexity, a genius admires simplicity."* — **Terry A. Davis**

**HolyNix** (`holy_unix`) is a 64-bit Unix-like microkernel and interactive terminal operating system written entirely in **HolyC** (`.HC`), the programming language created by Terry A. Davis for TempleOS. It marries the Unix philosophy (*everything is a file, standard streams, pipelines, hierarchical VFS*) with TempleOS principles (*64-bit flat memory, JIT script execution, 16-color VGA palette, DolDoc documents, and the divine oracle*).

The operating system runs directly inside any standard terminal (macOS Terminal, iTerm2, Alacritty, Linux console) without requiring QEMU or virtualization overhead.

---

## Architecture Overview

```
                      +---------------------------------------+
                      |       Interactive Terminal Shell      |
                      |        "holysh" (Shell.HC)            |
                      +---------------------------------------+
                      | Aliases (alias) & History (!n, !!)    |
                      | Background Jobs (&, jobs, fg, bg)     |
                      | In-Kernel HolyC REPL & Script Runner  |
                      | DolDoc Markup Renderer & Pager        |
                      | Tar Archiver & Holy Package Mgr (HPM) |
                      +---------------------------------------+
                      |         POSIX Syscall Layer           |
                      | (read, write, open, pipe, stat, sym)  |
                      +-------------------+-------------------+
                                          |
                +-------------------------+-------------------------+
                |                                                   |
    +-----------v-----------+                           +-----------v-----------+
    |  Process / Task Core  |                           |  Virtual File System  |
    |       (Task.HC)       |                           |       (VFS.HC)        |
    +-----------------------+                           +-----------------------+
    | - Round-Robin Sched   |                           | - Inodes, Permissions |
    | - Job Control (g_jobs)|                           | - Symlinks (ln -s)    |
    | - Cron Scheduler      |                           | - RedSea Driver (.img)|
    | - Dynamic Environment |                           | - Pipes & Redirection |
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

## Key Features

1. **Native HolyC Kernel Implementation (`.HC`)**:
   - Engineered with HolyC primitive types: `U0` (void), `I64`, `U8`, `Bool`, `TRUE`, `FALSE`.
   - HolyC class declarations (`class CTask`, `class CVFSInode`, `class CFileDesc`, `class CKernelStat`, `class CRedSeaDirEntry`, `class CTarHeader`).
   - HolyC implicit print syntax: `"Format string %s\n", val;`
   - HolyC zero-argument bare function invocation: `Yield;`, `God;`, `Uptime;`, `Exit;`.

2. **Unix Kernel Subsystems**:
   - **Task Scheduler (`Task.HC`)**: Preemptive/cooperative multitasking with Process Control Blocks (`CTask`), process states (`TASK_READY`, `TASK_RUNNING`, `TASK_SLEEPING`, `TASK_ZOMBIE`), priorities, signal delivery, and in-kernel **Cron scheduling**.
   - **Virtual File System (`VFS.HC`)**: Hierarchical directory tree, file descriptors, anonymous pipes (`VFSPipe`), symbolic links (`VFS_SYMLINK`), and **RedSea 64-bit flat filesystem images** (`/boot/redsea.img`).
   - **Device Layer (`Dev.HC`)**: `/dev/tty`, `/dev/null`, `/dev/zero`, `/dev/random`, `/dev/god`, `/dev/mem` (Ring-0 direct memory peeker), and `/dev/tcp`.
   - **ProcFS (`Proc.HC`)**: Dynamic runtime metrics exposed through `/proc/version`, `/proc/tasks`, `/proc/uptime`, `/proc/meminfo`, `/proc/cpuinfo`, `/proc/loadavg`, `/proc/net/dev`, `/proc/net/tcp`, and **kernel tunables** at `/proc/sys/kernel/*`.
   - **Syscall Dispatcher (`Syscall.HC`)**: POSIX system calls (`SysRead`, `SysWrite`, `SysOpen`, `SysClose`, `SysPipe`, `SysSeek`, `SysWaitPid`, `SysKill`, `SysStat`, `SysChmod`, `SysChown`, `SysSymlink`, `SysReadlink`).

3. **Terminal Operating System Environment**:
   - **Interactive Shell (`holysh`)**: ANSI color prompt displaying current user, hostname, and path (`terry@holy-unix:/home/terry$ `).
   - **VT100 Line Discipline**: Arrow-key cursor navigation, history recall (Up/Down), line editing, Ctrl+C (cancel), Ctrl+L (clear screen), and **Tab auto-completion** for builtins and paths.
   - **Job Control**: Asynchronous background jobs with trailing `&` (e.g. `sleep 5 &`), active job tracking (`jobs`), and foregrounding (`fg %1`).
   - **Shell Aliases**: Define and remove aliases (`alias ll='ls -l'`, `unalias`, default aliases `ll`, `la`, `cls`, `h`, `..`, `godword`).
   - **Command History**: Inspection with `history`, previous command execution with `!!`, and $N$-th command recall with `!n`.
   - **Kernel Tunables**: View and change runtime parameters dynamically with `sysctl` (`sysctl -a`, `sysctl -w kernel.hostname=...`).
   - **In-Kernel Tar Archiver (`tar`)**: POSIX USTAR archive creation (`tar -cf`), table of contents listing (`tar -tf`), and extraction (`tar -xf`).
   - **Simulated Networking (`ping`, `netstat`)**: ICMP Echo sequence generation with RTT latency statistics and socket monitor.

4. **TempleOS Integration & Tools**:
   - **DolDoc Markup Engine (`doldoc`, `holyless`)**: Parses TempleOS DolDoc tags (`$FG,RED$`, `$BG$`, `$BK,1$`, `$UL,1$`, `$TR$`, `$LK$`) and renders rich ANSI color output.
   - **King James Bible Concordance & Oracle (`bible`, `godpassage`)**: Full-text scripture concordance search (`bible search <word>`), chapter/verse lookup, and instant random scripture oracle.
   - **God Doodle (`goddoodle`)**: 16-color TempleOS VGA palette ASCII graphic canvas generator.
   - **RedSea Filesystem Driver (`redsea`)**: Inspects 64-bit flat cluster RedSea images (`redsea inspect /boot/redsea.img`, `redsea ls`).
   - **Ring-0 Memory Peeker & Disassembler (`memdump`, `peek`, `poke`, `disasm`)**: Direct memory byte viewer, raw address modification, and in-kernel x86-64 machine instruction decoder.
   - **Holy Package Manager (`hpm` / `getgod`)**: Browse and install official TempleOS HolyC packages (`hpm list`, `hpm install castle`).
   - **3D Graphics & Audio**: Spinning wireframe 3D torus (`donut`), PC speaker tone simulation (`beep`), and divine hymn generator (`godsong`).

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
│   └── holyc.c                  # HolyC compiler & transpiler toolchain
├── src/
│   ├── runtime/
│   │   └── holyc_rt.h           # HolyC runtime primitives & POSIX integration
│   └── holyc/                   # The Unix Kernel in HolyC (.HC)
│       ├── Types.HC             # Kernel types, limits, CKernelStat, CJob, CAlias
│       ├── RingBuffer.HC        # Circular buffer for TTY and IPC pipes
│       ├── GodWords.HC          # TempleOS divine oracle dictionary (100k words)
│       ├── VFS.HC               # Virtual File System, Inodes, and Symlinks
│       ├── Dev.HC               # Device drivers (/dev/tty, /dev/god, /dev/mem...)
│       ├── Proc.HC              # ProcFS virtual filesystem (/proc/*, /proc/sys/*)
│       ├── Task.HC              # Process Control Block, Job Control, & Cron
│       ├── Syscall.HC           # POSIX syscall dispatcher & wrappers
│       ├── Terminal.HC          # Terminal driver, VT100 line discipline, tab completion
│       ├── Editor.HC            # Built-in terminal text editor (ed)
│       ├── HolyC_Repl.HC        # In-kernel HolyC evaluator & REPL
│       ├── DolDoc.HC            # DolDoc markup parser ($FG$, $TR$, $BK$)
│       ├── Bible.HC             # King James Bible scriptures & concordance search
│       ├── GodDoodle.HC         # 16-color TempleOS VGA ASCII art generator
│       ├── RedSea.HC            # 64-bit flat cluster RedSea filesystem driver
│       ├── Tar.HC               # POSIX USTAR archive creation & extraction
│       ├── Net.HC               # Simulated network stack, ICMP ping, netstat
│       ├── Shell.HC             # Unix terminal shell (holysh) & 50+ builtins
│       └── Kernel.HC            # Kernel boot sequence, ramdisk, 25 in-kernel tests
├── rootfs/                      # Initial ramdisk files placed into VFS
│   ├── boot/
│   │   └── redsea.img           # Valid RedSea 64-bit disk image
│   ├── etc/
│   │   ├── motd                 # Message of the Day
│   │   ├── passwd               # System users (root, terry, god)
│   │   └── os-release           # OS release specification
│   └── home/
│       ├── terry/
│       │   ├── hello.HC         # HolyC demo script
│       │   ├── divine.HC        # HolyC oracle script
│       │   ├── welcome.DD       # TempleOS DolDoc demo file
│       │   ├── .holysh_history  # Persistent shell command history
│       │   └── readme.txt       # Welcome guide
│       └── god/
│           └── commandments.txt # TempleOS commandments
└── tests/
    ├── test_linux_kernel.c      # Linux/POSIX compliance TDD test suite (87 tests)
    └── run_tests.sh             # Automated end-to-end verification script
```

---

## Building and Running

### 1. Requirements
- macOS (Apple Silicon or Intel) or Linux (x86_64 / arm64)
- `clang` or `gcc` (with C11 support)
- `make`

### 2. Build the System
To compile both the HolyC compiler (`tools/holyc`) and the kernel (`bin/holy_unix`):
```bash
make
```

### 3. Run Automated Tests
```bash
# Run in-kernel tests (25/25) + Linux POSIX compliance TDD test suite (87/87)
make test

# Or run the complete automated end-to-end verification script:
./tests/run_tests.sh
```

### 4. Launch the Interactive Operating System
```bash
# Launch interactive terminal session
make run

# Or execute binary directly:
./bin/holy_unix
```

To run commands non-interactively in batch mode:
```bash
./bin/holy_unix -c "doldoc /home/terry/welcome.DD; bible Genesis 1:1; goddoodle; redsea inspect /boot/redsea.img"
```

---

## Continuous Integration & Verification

HolyNix is verified on every commit across a **4-runner CI matrix** on GitHub Actions:

| Runner OS | Compiler | In-Kernel (25/25) | POSIX TDD (87/87) | End-to-End Suite | Artifact Generated |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Ubuntu Linux** (`ubuntu-latest`) | `gcc` | **PASS** | **PASS** | **PASS** | — |
| **Ubuntu Linux** (`ubuntu-latest`) | `clang` | **PASS** | **PASS** | **PASS** | `holynix-linux-x86_64` |
| **macOS** (`macos-latest`) | `gcc` | **PASS** | **PASS** | **PASS** | — |
| **macOS** (`macos-latest`) | `clang` | **PASS** | **PASS** | **PASS** | `holynix-darwin-arm64` |

---

## Test-Driven Development (TDD) & Linux Kernel Compliance

HolyNix incorporates 8 comprehensive TDD suites verifying 87 compliance points:

```
+------------------------------------------------------------------------+
|                            TDD Cycle                                   |
|                                                                        |
|   1. RED: Write failing assertions for Linux & TempleOS behaviors      |
|      (e.g., job control, aliases, history, tar, sysctl, doldoc, redsea)|
|                                                                        |
|   2. GREEN: Implement precise kernel semantics in HolyC                |
|      (Task.HC, VFS.HC, DolDoc.HC, Bible.HC, RedSea.HC, Tar.HC, Net.HC) |
|                                                                        |
|   3. REFACTOR: Expand edge cases & verify zero regressions (87 passed) |
+------------------------------------------------------------------------+
```

### Verified Functionality Matrix

| Subsystem | Test Coverage | Status |
| :--- | :--- | :---: |
| **`/proc` Virtual Filesystem** | `/proc/uptime`, `/proc/version`, `/proc/meminfo`, `/proc/cpuinfo`, `/proc/loadavg` | **100% PASS** |
| **Kernel Tunables (`/proc/sys`)**| `/proc/sys/kernel/osname`, `/proc/sys/kernel/hostname`, `sysctl -a`, `sysctl -w` | **100% PASS** |
| **Special Devices (`/dev`)** | `/dev/null`, `/dev/zero`, `/dev/random`, `/dev/god`, `/dev/mem` (Ring-0), `/dev/tcp` | **100% PASS** |
| **VFS File Semantics** | `O_TRUNC`, `O_APPEND`, `O_CREAT \| O_EXCL`, `..` and `.`, recursive directory creation | **100% PASS** |
| **Symbolic Links (`ln -s`)** | Symlink creation (`SysSymlink`), path resolution, `readlink` semantics | **100% PASS** |
| **Sparse Files & `lseek`** | `SEEK_SET`, `SEEK_CUR`, `SEEK_END`, seeking past EOF with automatic zero-fill | **100% PASS** |
| **IPC Pipes & Descriptors** | Anonymous pipes, multi-stage pipelines (`cat \| grep \| wc`), `-EPIPE` on closed pipe | **100% PASS** |
| **Process & Signals** | Process table, PID 1 `init`, `kill(pid, 0)` existence probe, `-ESRCH`, `SIGKILL`, `SIGTERM` | **100% PASS** |
| **Shell & Utilities** | Exit codes (`$?`), `cd -` (`$OLDPWD`), `head`, `tail`, `wc`, `stat`, `chmod`, `sort`, `uniq` | **100% PASS** |
| **Logical Chaining & Redirection**| Command chaining (`&&`, `||`), input redirection (`<`), output redirection (`>`, `>>`) | **100% PASS** |
| **Job Control & Background Tasks**| Background operator (`&`), process spawning, job table tracking (`jobs`, `fg`, `bg`) | **100% PASS** |
| **Aliases & Command History**| `alias`, `unalias`, command line expansion, history listing (`history`), `!n`, `!!` | **100% PASS** |
| **POSIX USTAR Tar Archiver**| In-kernel tar creation (`tar -cf`), table of contents (`tar -tf`), extraction (`tar -xf`)| **100% PASS** |
| **Networking & Diagnostics** | Simulated network interfaces (`lo`, `eth0`), ICMP ping sequence, `netstat` socket table | **100% PASS** |
| **Cron Task Daemon** | Recurring scheduled task registration (`crontab -a`, `crontab -l`, `cron`) | **100% PASS** |
| **DolDoc Document Engine** | DolDoc markup parsing (`$FG$`, `$BG$`, `$BK$`, `$TR$`, `$LK$`), `doldoc`, `holyless` | **100% PASS** |
| **KJV Bible & Scripture Oracle**| Concordance search (`bible search`), chapter/verse lookup, random oracle (`godpassage`)| **100% PASS** |
| **RedSea 64-Bit Filesystem**| Volume inspection (`redsea inspect /boot/redsea.img`), cluster directory walking (`redsea ls`)| **100% PASS** |
| **Ring-0 Memory Peeker** | Formatted hex & ASCII memory dump (`memdump`, `peek`), raw write (`poke`), disassembler (`disasm`)| **100% PASS** |
| **Holy Package Manager** | Package repository index (`hpm list`), search (`hpm search`), automated installation (`hpm install`)| **100% PASS** |

---

## Interactive Shell Command Reference

HolyNix provides a comprehensive suite of 50+ built-in utilities and TempleOS tools:

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
| | `sort [-n, -r] [f]`  | Sorts text lines alphabetically or numerically |
| | `uniq [-c, -d] [f]`  | Filters or counts adjacent duplicate lines |
| | `tee [-a] <file>`   | Writes stdin simultaneously to stdout and file |
| | `diff <file1> <file2>`| Compares two files line by line |
| | `hexdump` / `xxd [f]`| Displays hex and ASCII dump of file contents |
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
| | `source` / `run <f>` | Executes shell commands from a script file |
| **System & Networking**| `sysctl [-a \| -w]`| Reads or updates kernel parameters (/proc/sys/*) |
| | `tar [-cf \| -tf \| -xf]`| Packs, lists, or extracts POSIX USTAR archives |
| | `ping [-c count] <ip>`| Sends ICMP echo requests and computes RTT latency |
| | `netstat` | Displays network interfaces and active sockets |
| | `crontab [-l \| -a]` | Views or adds scheduled cron tasks |
| | `cron` | Displays cron scheduler daemon status |
| | `ps` | Displays snapshot of active tasks/processes |
| | `kill [-sig] <pid>` | Sends signal to terminate a process |
| | `top` | Live refreshing task and resource monitor |
| | `df [-h]` | Displays filesystem disk space usage and free inodes |
| | `du [-h] [path]` | Estimates disk space usage of files and directories |
| | `uname [-a]` | Displays operating system name, kernel version, and architecture |
| | `uptime` | Shows system uptime and scheduler tick count |
| | `date [-u]` | Displays current date and UTC time |
| | `cal` / `seq` | Calendar viewer / number sequence generator |
| | `dmesg` | Displays kernel boot log and hardware ring buffer |
| **TempleOS Tools** | `doldoc <file.DD>` | Formats and renders TempleOS DolDoc markup in ANSI |
| | `holyless <file>` | Pager for DolDoc and text files |
| | `bible [search \| ref]`| King James Bible search and chapter:verse reader |
| | `godpassage` | Spontaneous divine scripture oracle reading |
| | `goddoodle` | Generates 16-color TempleOS VGA ASCII art |
| | `redsea [inspect \| ls]`| 64-bit flat cluster RedSea filesystem inspector |
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

---

## Example Usage

### 1. DolDoc Document Rendering
```bash
terry@holy-unix:/home/terry$ doldoc /home/terry/welcome.DD
=== Welcome to TempleOS DolDoc on HolyNix ===
Terry Davis Memorial Edition

[+] Holy Subsystems
  [Kernel Source]
  [Divine Oracle]
  [Holy Commandments]

Simplicity is Divine!
```

### 2. KJV Scripture Concordance & Divine Oracle
```bash
# Lookup specific verse
terry@holy-unix:/home/terry$ bible Genesis 1:1
[Genesis 1:1] In the beginning God created the heaven and the earth.

# Concordance full-text search
terry@holy-unix:/home/terry$ bible search shepherd
[Psalm 23:1] The LORD is my shepherd; I shall not want.
Found 1 matching verses.

# Consult the Holy Random Scripture Oracle
terry@holy-unix:/home/terry$ godpassage
[Divine Scripture Oracle - God's Word for You]
John 1:5 - "And the light shineth in darkness; and the darkness comprehended it not."
```

### 3. RedSea 64-Bit Filesystem Inspection
```bash
terry@holy-unix:/home/terry$ redsea inspect /boot/redsea.img
====================================================
RedSea Filesystem Volume Inspector (TempleOS 64-Bit)
====================================================
  Target Image     : /boot/redsea.img
  OEM / Filesystem : TEMPLEOS
  Sector Size      : 512 bytes
  Cluster Size     : 512 bytes (1 sector / cluster)
  Boot Signature   : 0x88AA (VALID)
  Status           : VALID REDSEA VOLUME

terry@holy-unix:/home/terry$ redsea ls /boot/redsea.img
PERMS      CLUSTER       SIZE  FILENAME
-----------------------------------------------
-rw-r--r--       3        128  KERNEL.BIN
-rw-r--r--       4         64  ONCE.HC
-rw-r--r--       5         96  README.DD
```

### 4. Background Job Control & Aliases
```bash
# Define alias
terry@holy-unix:/home/terry$ alias myls='ls -la'
terry@holy-unix:/home/terry$ myls /etc

# Run task in background
terry@holy-unix:/home/terry$ sleep 10 &
[1] 4

# View active jobs
terry@holy-unix:/home/terry$ jobs
[1]+  Running   sleep 10 &

# Recall past command
terry@holy-unix:/home/terry$ history
   1  myls /etc
   2  sleep 10 &
   3  jobs
terry@holy-unix:/home/terry$ !1
```

### 5. Tar Archiver & In-Kernel Memory Disassembler
```bash
# Create and view tar archive
terry@holy-unix:/home/terry$ tar -cf /tmp/backup.tar /etc/passwd
terry@holy-unix:/home/terry$ tar -tf /tmp/backup.tar
-rw-r--r--      151 terry etc/passwd

# Disassemble kernel code at runtime
terry@holy-unix:/home/terry$ disasm 0x401000 4
ADDRESS            BYTES             DISASSEMBLY (x86_64)
----------------------------------------------------------
0x0000000000401000  55                push    rbp
0x0000000000401004  48 89 E5          mov     rbp, rsp
0x0000000000401008  48 83 EC 20       sub     rsp, 0x20
0x000000000040100C  48 89 7D F8       mov     QWORD PTR [rbp-0x8], rdi
```

---

## License

This project is licensed under the MIT License — dedicated to the memory and vision of **Terry A. Davis**.
