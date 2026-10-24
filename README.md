# HolyNix: Unix Kernel & Terminal Operating System in HolyC

[![HolyNix CI](https://github.com/omakasekim/holynix/actions/workflows/ci.yml/badge.svg)](https://github.com/omakasekim/holynix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![HolyC: v1.0](https://img.shields.io/badge/HolyC-v1.0-blue.svg)](https://github.com/omakasekim/holynix)
[![POSIX: Compliant](https://img.shields.io/badge/POSIX-Compliant-brightgreen.svg)](https://github.com/omakasekim/holynix)

> *"An idiot admires complexity, a genius admires simplicity."* — **Terry A. Davis**

**HolyNix** (`holy_unix`) is a 64-bit Unix-like microkernel and interactive terminal operating system written entirely in **HolyC** (`.HC`), the programming language created by Terry A. Davis for TempleOS. It marries the Unix philosophy (*everything is a file, standard streams, pipelines, hierarchical VFS*) with TempleOS principles (*64-bit flat memory, JIT script execution, 16-color VGA palette, and the divine oracle*).

The operating system runs directly inside any standard terminal (macOS Terminal, iTerm2, Alacritty, Linux console) without requiring QEMU or virtualization overhead.

---

## Architecture Overview

```
                      +---------------------------------------+
                      |       Interactive Terminal Shell      |
                      |        "holysh" (Shell.HC)            |
                      +---------------------------------------+
                      | Unix Core Utilities & Text Editor(ed) |
                      | In-Kernel HolyC REPL & Script Runner  |
                      | Logical Operators (&&, ||) & Redirect |
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
    | - PCB (CTask) Table   |                           | - Directory Hierarchy |
    | - Signals (SIGKILL...) |                          | - Symlinks (ln -s)    |
    | - Environment ($VAR)  |                           | - Pipes & Redirection |
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
                                +-----------------------+                       | /proc/loadavg         |
                                                                                +-----------------------+
```

---

## Key Features

1. **Native HolyC Kernel Implementation (`.HC`)**:
   - Engineered with HolyC primitive types: `U0` (void), `I64`, `U8`, `Bool`, `TRUE`, `FALSE`.
   - HolyC class declarations (`class CTask`, `class CVFSInode`, `class CFileDesc`, `class CKernelStat`).
   - HolyC implicit print syntax: `"Format string %s\n", val;`
   - HolyC zero-argument bare function invocation: `Yield;`, `God;`, `Uptime;`, `Exit;`.

2. **Unix Kernel Subsystems**:
   - **Task Scheduler (`Task.HC`)**: Preemptive/cooperative multitasking with Process Control Blocks (`CTask`), process states (`TASK_READY`, `TASK_RUNNING`, `TASK_SLEEPING`, `TASK_ZOMBIE`), priorities, and signal delivery.
   - **Virtual File System (`VFS.HC`)**: Inodes, directories, file descriptors, anonymous pipes (`VFSPipe`), and symbolic links (`VFS_SYMLINK`).
   - **Device Layer (`Dev.HC`)**: `/dev/tty`, `/dev/null`, `/dev/zero`, `/dev/random`, and `/dev/god`.
   - **ProcFS (`Proc.HC`)**: Dynamic runtime metrics exposed through `/proc/version`, `/proc/tasks`, `/proc/uptime`, `/proc/meminfo`, `/proc/cpuinfo`, and `/proc/loadavg`.
   - **Syscall Dispatcher (`Syscall.HC`)**: POSIX system calls (`SysRead`, `SysWrite`, `SysOpen`, `SysClose`, `SysPipe`, `SysSeek`, `SysWaitPid`, `SysKill`, `SysStat`, `SysChmod`, `SysChown`, `SysSymlink`, `SysReadlink`).

3. **Terminal Operating System Environment**:
   - **Interactive Shell (`holysh`)**: ANSI color prompt displaying current user, hostname, and path (`terry@holy-unix:/home/terry$ `).
   - **VT100 Line Discipline**: Arrow-key cursor navigation, history recall (Up/Down), line editing, Ctrl+C (cancel), Ctrl+L (clear screen), and **Tab auto-completion** for builtins and paths.
   - **Shell Execution Engine**:
     - Command pipelines: `cat /etc/motd | grep Holy | wc -l`
     - Redirection: Output overwrite (`>`), output append (`>>`), and input redirection (`<`).
     - Logical chaining: `cmd1 && cmd2` (execute on success), `cmd1 || cmd2` (execute on failure).
     - Environment variables: Dynamic `$VAR` expansion (`$HOME`, `$USER`, `$PWD`, `$OLDPWD`, `export`, `env`).
   - **Built-in Terminal Text Editor (`ed`)**: Edit, view, delete lines, and save files directly in VFS.
   - **TempleOS 16-Color VGA Palette**: Switch on the fly between Classic TempleOS Blue (`theme`) and Modern Dark Unix terminal mode.
   - **TempleOS Features**:
     - Divine Oracle (`god`, `/dev/god`): Authentic random oracle word generator from Terry Davis's 100,000-word dictionary.
     - PC Speaker Tone Simulator (`beep`): Audio simulation of vintage PC speaker frequencies.
     - Divine Hymn Composer (`godsong`): Algorithmic melody and spiritual lyrics generation.
     - 3D Wireframe Graphics (`donut`): Real-time rotating 3D ASCII torus rendered in the terminal.
   - **In-Kernel HolyC REPL & Runner (`holyc`)**: Run HolyC `.HC` script files directly or enter an interactive HolyC shell!

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
│       ├── Types.HC             # Kernel types, limits, CKernelStat, syscall numbers
│       ├── RingBuffer.HC        # Circular buffer for TTY and IPC pipes
│       ├── GodWords.HC          # TempleOS divine oracle dictionary (100k words)
│       ├── VFS.HC               # Virtual File System, Inodes, and Symlinks
│       ├── Dev.HC               # Device drivers (/dev/tty, /dev/god, /dev/null...)
│       ├── Proc.HC              # ProcFS virtual pseudo-filesystem (/proc/*)
│       ├── Task.HC              # Process Control Block & Scheduler
│       ├── Syscall.HC           # POSIX syscall dispatcher & wrappers
│       ├── Terminal.HC          # Terminal driver, VT100 line discipline, tab completion
│       ├── Editor.HC            # Built-in terminal text editor (ed)
│       ├── HolyC_Repl.HC        # In-kernel HolyC evaluator & REPL
│       ├── Shell.HC             # Unix terminal shell (holysh) & 40+ builtins
│       └── Kernel.HC            # Kernel boot sequence, ramdisk, automated test runner
├── rootfs/                      # Initial ramdisk files placed into VFS
│   ├── etc/
│   │   ├── motd                 # Message of the Day
│   │   ├── passwd               # System users (root, terry, god)
│   │   └── os-release           # OS release specification
│   └── home/
│       ├── terry/
│       │   ├── hello.HC         # HolyC demo script
│       │   ├── divine.HC        # HolyC oracle script
│       │   └── readme.txt       # Welcome guide
│       └── god/
│           └── commandments.txt # TempleOS commandments
└── tests/
    ├── test_linux_kernel.c      # Linux/POSIX compliance TDD test suite (62 tests)
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
# Run in-kernel tests (15/15) + Linux POSIX compliance TDD test suite (62/62)
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
./bin/holy_unix -c "uname -a; df -h; god 5; donut"
```

---

## Continuous Integration & Verification

HolyNix is verified on every commit across a **4-runner CI matrix** on GitHub Actions:

| Runner OS | Compiler | In-Kernel (15/15) | POSIX TDD (62/62) | End-to-End Suite | Artifact Generated |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Ubuntu Linux** (`ubuntu-latest`) | `gcc` | **PASS** | **PASS** | **PASS** | — |
| **Ubuntu Linux** (`ubuntu-latest`) | `clang` | **PASS** | **PASS** | **PASS** | `holynix-linux-x86_64` |
| **macOS** (`macos-latest`) | `gcc` | **PASS** | **PASS** | **PASS** | — |
| **macOS** (`macos-latest`) | `clang` | **PASS** | **PASS** | **PASS** | `holynix-darwin-arm64` |

---

## Test-Driven Development (TDD) & Linux Kernel Compliance

To ensure identical functionality to a real Linux OS and POSIX kernel, HolyNix incorporates 7 comprehensive TDD suites:

```
+------------------------------------------------------------------------+
|                            TDD Cycle                                   |
|                                                                        |
|   1. RED: Write failing assertions for Linux / POSIX behaviors         |
|      (e.g., standard errno codes, /proc formats, sparse lseek, symlinks)|
|                                                                        |
|   2. GREEN: Implement precise kernel semantics in HolyC                |
|      (VFS.HC, Task.HC, Syscall.HC, Proc.HC, Shell.HC)                  |
|                                                                        |
|   3. REFACTOR: Expand edge cases & verify zero regressions (62 passed) |
+------------------------------------------------------------------------+
```

### Verified Linux Functionality Matrix

| Linux Subsystem | Test Coverage | Status |
| :--- | :--- | :---: |
| **`/proc` Virtual Filesystem** | `/proc/uptime` (two-value `<up> <idle>` format), `/proc/version`, `/proc/meminfo` (`MemTotal`, `MemFree`, `kB`), `/proc/cpuinfo`, `/proc/loadavg` (3 standard load averages) | **100% PASS** |
| **Special Devices (`/dev`)** | `/dev/null` (immediate 0-byte EOF on read, discard writes), `/dev/zero` (streams arbitrary zero bytes), `/dev/random` (entropy), `/dev/god` (divine oracle stream) | **100% PASS** |
| **VFS File Semantics** | `O_TRUNC` file truncation, `O_APPEND` append semantics, `O_CREAT \| O_EXCL` collision handling, `..` and `.` path traversal, recursive directory creation | **100% PASS** |
| **Symbolic Links (`ln -s`)** | Symlink creation (`SysSymlink`), path resolution through symlink targets, `readlink` semantics (`SysReadlink`), symlink file opens | **100% PASS** |
| **Sparse Files & `lseek`** | `SEEK_SET`, `SEEK_CUR`, `SEEK_END`, seeking past EOF with automatic zero-fill on subsequent write, `-EINVAL` on negative offsets | **100% PASS** |
| **IPC Pipes & Descriptors** | Anonymous pipes, multi-stage pipelines (`cat \| grep \| wc`), `-EPIPE` on write to closed read end, `dup2` idempotency | **100% PASS** |
| **POSIX Errno Codes** | Accurate negative returns: `-EBADF`, `-ENOENT`, `-EEXIST`, `-ESRCH`, `-EPIPE`, `-EINVAL`, `-ESPIPE`, `-EISDIR` | **100% PASS** |
| **Process & Signals** | Process table, PID 1 `init`, `kill(pid, 0)` existence probe, `-ESRCH` on invalid PID, termination signals (`SIGKILL`, `SIGTERM`) | **100% PASS** |
| **Shell & Utilities** | Exit codes (`$?`, `true` -> 0, `false` -> 1, command not found -> 127), `cd -` (`$OLDPWD`), `head -n` / `tail -n`, `wc -l` / `wc -w` / `wc -c`, `stat`, `chmod`, `sort`, `uniq` | **100% PASS** |
| **Logical Chaining & Redirection** | Command chaining with `&&` and `||`, input redirection with `<`, output redirection with `>` and `>>` | **100% PASS** |

---

## Interactive Shell Command Reference

HolyNix provides a comprehensive suite of 40+ Unix built-in utilities and TempleOS tools:

| Category | Command | Description |
| :--- | :--- | :--- |
| **Navigation & Files** | `ls [-l, -a] [dir]` | Lists directory entries with color coding (dirs cyan, files white, .HC green) |
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
| | `head [-n lines] [f]`| Outputs the first $N$ lines of a file (default: 10) |
| | `tail [-n lines] [f]`| Outputs the last $N$ lines of a file (default: 10) |
| | `grep <pattern> [f]` | Searches for pattern in file or stdin pipeline |
| | `wc [-l, -w, -c] [f]`| Counts lines, words, and bytes |
| | `sort [-n, -r] [f]`  | Sorts text lines alphabetically or numerically |
| | `uniq [-c, -d] [f]`  | Filters or counts adjacent duplicate lines |
| | `tee [-a] <file>`   | Writes stdin simultaneously to stdout and file |
| | `diff <file1> <file2>`| Compares two files line by line |
| | `hexdump` / `xxd [f]`| Displays hex and ASCII dump of file contents |
| **Process & System** | `ps` | Displays snapshot of active tasks/processes |
| | `kill [-sig] <pid>` | Sends signal to terminate a process |
| | `top` | Live refreshing task and resource monitor |
| | `df [-h]` | Displays filesystem disk space usage and free inodes |
| | `du [-h] [path]` | Estimates disk space usage of files and directories |
| | `uname [-a]` | Displays operating system name, kernel version, and architecture |
| | `uptime` | Shows system uptime and scheduler tick count |
| | `whoami` | Shows current user name |
| | `date [-u]` | Displays current date and UTC time |
| | `cal` | Displays visual calendar for current month |
| | `seq <start> [end]` | Generates sequences of numbers |
| | `sleep <seconds>` | Suspends execution for specified seconds |
| | `dmesg` | Displays kernel boot log and hardware ring buffer |
| | `clear` | Clears terminal screen (`Ctrl+L`) |
| | `true` / `false` | Returns exit status 0 / 1 |
| **Shell & Environment**| `export KEY=VALUE` | Sets an environment variable |
| | `env` | Displays all exported environment variables |
| | `echo [args...]` | Prints text, expanding dynamic variables (`$VAR`) |
| | `source` / `run <f>` | Executes shell commands from a script file |
| | `ed <file>` | Built-in terminal line/text editor |
| **TempleOS Tools** | `god [n]` | Speaks $n$ random words from Terry Davis's divine oracle |
| | `beep [freq] [ms]` | Emulates PC speaker frequency tone |
| | `godsong` | Generates divine melody and religious lyrics |
| | `donut` | Renders animated 3D wireframe spinning donut in ASCII |
| | `holyc [file.HC]` | Runs HolyC script or enters interactive HolyC REPL |
| | `theme` | Toggles TempleOS 16-color VGA Blue mode / Dark Unix mode |
| | `exit` / `reboot` | Clean operating system shutdown |

---

## Example Usage

### 1. Running HolyC Scripts
```bash
terry@holy-unix:/home/terry$ holyc hello.HC
=== Divine HolyC Execution ===
Welcome to God's chosen programming language!
Calculation: 10 + 20 = 30
Consulting TempleOS God Oracle...
God says: disciple spirit omnipresent simplicity last disciple firmament
HolyC Script Execution Finished.
```

### 2. Consulting the TempleOS Divine Oracle
```bash
terry@holy-unix:/home/terry$ god 7
God says: seraphim covenant wisdom tabernacle righteousness altar glory

terry@holy-unix:/home/terry$ cat /dev/god | grep temple
```

### 3. Advanced Shell Pipelines & Redirections
```bash
# Multi-stage pipelines with sorting and counting
terry@holy-unix:/home/terry$ cat /etc/passwd | sort | uniq | wc -l
3

# Input and output redirection
terry@holy-unix:/home/terry$ wc -l < /etc/motd > /tmp/motd_count.txt
terry@holy-unix:/home/terry$ cat /tmp/motd_count.txt
12

# Logical command execution
terry@holy-unix:/home/terry$ test -f /etc/motd && echo "Found motd" || echo "Missing"
Found motd
```

### 4. Symbolic Links and Metadata
```bash
terry@holy-unix:/home/terry$ ln -s /etc/motd /tmp/motd_symlink
terry@holy-unix:/home/terry$ readlink /tmp/motd_symlink
/etc/motd
terry@holy-unix:/home/terry$ stat /tmp/motd_symlink
  File: /tmp/motd_symlink -> /etc/motd
  Size: 9         Blocks: 1          IO Block: 512    symbolic link
Device: 1h/1d     Inode: 42          Links: 1
Access: (0777/lrwxrwxrwx)  Uid: ( 1000/   terry)   Gid: ( 1000/   terry)
```

### 5. TempleOS 3D Donut & Divine Songs
```bash
# Render 3D ASCII Donut
terry@holy-unix:/home/terry$ donut

# Compose Divine Hymn
terry@holy-unix:/home/terry$ godsong
[GodSong: Melody composed in C Major - 140 BPM]
Verse: Praise the simplicity, righteous foundation of light.
Chorus: Holy is the Lord, Creator of all things.
```

---

## License

This project is licensed under the MIT License — dedicated to the memory and vision of **Terry A. Davis**.
