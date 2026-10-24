# HolyC-Unix: Unix Kernel & Terminal Operating System in HolyC

> *"An idiot admires complexity, a genius admires simplicity."* — **Terry A. Davis**

**HolyC-Unix** is a 64-bit Unix-like microkernel and interactive terminal operating system written entirely in **HolyC** (`.HC`), the C dialect created by Terry A. Davis for TempleOS. It merges the Unix philosophy (*everything is a file, standard I/O streams, pipelines, hierarchical VFS*) with TempleOS principles (*64-bit flat memory, JIT execution, 16-color VGA palette, and the divine oracle*).

The operating system runs directly inside any standard ANSI terminal (macOS Terminal, iTerm2, Alacritty, Linux console) without requiring QEMU or heavy hypervisors.

---

## Architecture Overview

```
                      +---------------------------------------+
                      |       Interactive Terminal Shell      |
                      |        "holysh" (Shell.HC)            |
                      +---------------------------------------+
                      | Built-in Utilities & Text Editor (ed) |
                      | In-Kernel HolyC REPL & Script Runner  |
                      +---------------------------------------+
                      |         POSIX Syscall Layer           |
                      | (read, write, open, pipe, fork, exec) |
                      +-------------------+-------------------+
                                          |
                +-------------------------+-------------------------+
                |                                                   |
    +-----------v-----------+                           +-----------v-----------+
    |  Process / Task Core  |                           |  Virtual File System  |
    |       (Task.HC)       |                           |       (VFS.HC)        |
    +-----------------------+                           +-----------------------+
    | - Round-Robin Sched   |                           | - Inodes & Descriptors|
    | - PCB (CTask) Table   |                           | - Directory Tree      |
    | - Signals (SIGKILL...) |                          | - Anonymous Pipes     |
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
                                +-----------------------+                       +-----------------------+
```

---

## Key Features

1. **Native HolyC Kernel Implementation (`.HC`)**:
   - Written with HolyC primitives: `U0` (void), `I64`, `U8`, `Bool`, `TRUE`, `FALSE`.
   - HolyC class structures (`class CTask`, `class CVFSInode`, `class CFileDesc`).
   - HolyC implicit print statements: `"Format %d\n", val;`
   - HolyC zero-argument bare function invocation: `Yield;`, `God;`, `Uptime;`, `Exit;`.

2. **Unix Kernel Subsystems**:
   - **Task Scheduler (`Task.HC`)**: Preemptive/cooperative multitasking with Process Control Blocks (`CTask`), states (`TASK_READY`, `TASK_RUNNING`, `TASK_SLEEPING`, `TASK_ZOMBIE`), priorities, and signal delivery.
   - **Virtual File System (`VFS.HC`)**: Inodes, directories, file descriptors, and anonymous pipes (`VFSPipe`).
   - **Device Layer (`Dev.HC`)**: `/dev/tty`, `/dev/null`, `/dev/zero`, `/dev/random`, and `/dev/god`.
   - **ProcFS (`Proc.HC`)**: Dynamic runtime metrics exposed through `/proc/version`, `/proc/tasks`, `/proc/uptime`, `/proc/meminfo`, and `/proc/cpuinfo`.
   - **Syscall Dispatcher (`Syscall.HC`)**: POSIX system call interface (`SysRead`, `SysWrite`, `SysOpen`, `SysClose`, `SysPipe`, `SysSeek`, `SysWaitPid`, `SysKill`).

3. **Terminal Operating System Environment**:
   - **Interactive Shell (`holysh`)**: ANSI color prompt showing user, host, current directory (`terry@holy-unix:/home/terry$ `).
   - **VT100 Line Discipline**: Arrow key cursor movement (Left/Right/Home/End), backspace editing, command history (Up/Down arrows), Ctrl+C (cancel), Ctrl+L (clear screen), and **Tab auto-completion** for commands and files.
   - **Unix Pipelines & Redirection**: Run `cat /etc/motd | grep Holy` or `echo hello > /tmp/file.txt`.
   - **Built-in Terminal Text Editor (`ed`)**: Edit and save files directly to VFS inside the terminal.
   - **TempleOS 16-Color VGA Palette**: Switch between Classic TempleOS Blue mode (`theme`) and Modern Dark Unix mode.
   - **Divine Oracle (`god` and `/dev/god`)**: Authentic random oracle word generator inspired by Terry Davis's TempleOS 100,000-word dictionary.
   - **In-Kernel HolyC REPL & Runner (`holyc`)**: Run HolyC `.HC` script files directly or enter an interactive HolyC shell!

---

## Directory Structure

```
TerryDavis/
├── Makefile                     # Build system
├── README.md                    # Documentation
├── tools/
│   └── holyc.c                  # HolyC compiler & transpiler toolchain
├── src/
│   ├── runtime/
│   │   └── holyc_rt.h           # HolyC runtime primitives & POSIX layer
│   └── holyc/                   # The Unix Kernel in HolyC!
│       ├── Types.HC             # Kernel types, limits, and syscall numbers
│       ├── RingBuffer.HC        # Circular buffer for TTY and IPC pipes
│       ├── GodWords.HC          # TempleOS divine oracle dictionary
│       ├── VFS.HC               # Virtual File System & Inode Table
│       ├── Dev.HC               # Device drivers (/dev/tty, /dev/god...)
│       ├── Proc.HC              # ProcFS virtual pseudo-filesystem
│       ├── Task.HC              # Process Control Block & Scheduler
│       ├── Syscall.HC           # POSIX syscall dispatcher
│       ├── Terminal.HC          # Terminal driver, VT100 line discipline, tab completion
│       ├── Editor.HC            # Built-in terminal text editor (ed)
│       ├── HolyC_Repl.HC        # In-kernel HolyC evaluator & REPL
│       ├── Shell.HC             # Unix terminal shell (holysh)
│       └── Kernel.HC            # Kernel entrypoint, ramdisk init, boot sequence
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
    └── run_tests.sh             # Automated end-to-end test suite
```

---

## Building and Running

### 1. Requirements
- macOS (Apple Silicon / Intel) or Linux
- `clang` or `gcc`
- `make`

### 2. Build the System
To compile both the HolyC compiler (`tools/holyc`) and the kernel (`bin/holy_unix`):
```bash
make
```

### 3. Run Automated Tests
```bash
# Run in-kernel tests + Linux compliance TDD test suite
make test

# Or run the complete automated end-to-end verification script:
./tests/run_tests.sh
```

---

## Test-Driven Development (TDD) & Linux Kernel Compliance

To ensure identical functionality to a real Linux OS and POSIX kernel, the system was developed and validated using rigorous **Test-Driven Development (TDD)**:

```
+------------------------------------------------------------------------+
|                            TDD Cycle                                   |
|                                                                        |
|   1. RED: Write failing assertions for Linux / POSIX behaviors         |
|      (e.g., standard errno codes, /proc formats, sparse lseek, $OLDPWD)|
|                                                                        |
|   2. GREEN: Implement precise kernel semantics in HolyC                |
|      (VFS.HC, Task.HC, Syscall.HC, Proc.HC, Shell.HC)                  |
|                                                                        |
|   3. REFACTOR: Expand edge cases & verify zero regressions (46 passed) |
+------------------------------------------------------------------------+
```

### Verified Linux Functionality Matrix

| Linux Subsystem | Test Coverage | Status |
| :--- | :--- | :--- |
| **`/proc` Virtual Filesystem** | `/proc/uptime` (two-value `<up> <idle>` format), `/proc/version`, `/proc/meminfo` (`MemTotal`, `MemFree`, `kB`), `/proc/cpuinfo`, `/proc/loadavg` | **100% PASS** |
| **Special Devices (`/dev`)** | `/dev/null` (immediate 0-byte EOF on read, discard writes), `/dev/zero` (streams arbitrary zero bytes), `/dev/random` | **100% PASS** |
| **VFS File Semantics** | `O_TRUNC` file truncation, `O_APPEND` append semantics, `O_CREAT \| O_EXCL` collision handling, `..` and `.` path traversal | **100% PASS** |
| **Sparse Files & `lseek`** | `SEEK_SET`, `SEEK_CUR`, `SEEK_END`, seeking past EOF with automatic zero-fill on write, `-EINVAL` on negative offsets | **100% PASS** |
| **IPC Pipes & Descriptors** | Anonymous pipes, multi-stage pipelines (`cat \| grep \| wc`), `-EPIPE` on write to closed read end, `dup2` idempotency | **100% PASS** |
| **POSIX Errno Codes** | Accurate negative returns: `-EBADF`, `-ENOENT`, `-EEXIST`, `-ESRCH`, `-EPIPE`, `-EINVAL`, `-ESPIPE`, `-EISDIR` | **100% PASS** |
| **Process & Signals** | Process table, PID 1 `init`, `kill(pid, 0)` existence probe, `-ESRCH` on invalid PID, termination signals | **100% PASS** |
| **Shell & Utilities** | Exit codes (`$?`, `true` -> 0, `false` -> 1, command not found -> 127), `cd -` (`$OLDPWD`), `head -n` / `head -c`, `wc -l` / `wc -w` / `wc -c` | **100% PASS** |

### 4. Launch the Interactive Operating System
To launch the full terminal operating system session:
```bash
make run
# Or directly:
./bin/holy_unix
```

To run commands non-interactively in batch mode:
```bash
./bin/holy_unix -c "uname -a; cat /proc/tasks; god 7"
```

---

## Interactive Shell Commands

| Command | Description |
| :--- | :--- |
| `ls [-l, -a] [dir]` | Lists directory entries with color coding (dirs cyan, files white, .HC green) |
| `cd [dir]` | Changes current working directory (supports `..`, `~`, `/`) |
| `pwd` | Prints current working directory |
| `cat [file...]` | Displays file, device, or procfs node content |
| `echo [args...]` | Prints text, expands `$USER`, `$HOME`, `$SHELL`, `$PWD`, `$OS` |
| `mkdir [dir]` | Creates a directory in the VFS |
| `touch [file]` | Creates an empty file or updates timestamp |
| `rm [file]` | Removes a file from the VFS |
| `cp <src> <dst>` | Copies a file |
| `mv <src> <dst>` | Moves or renames a file |
| `ps` | Displays snapshot of active tasks/processes |
| `kill [-sig] <pid>` | Sends signal to terminate a process |
| `top` | Live refreshing task and resource monitor |
| `grep <pat> [file]` | Searches for matching pattern in file or stdin pipeline |
| `wc <file>` | Displays line, word, and byte counts |
| `clear` | Clears terminal screen (or press `Ctrl+L`) |
| `uname [-a]` | Displays operating system and hardware information |
| `uptime` | Shows system uptime and scheduler tick count |
| `whoami` | Shows current user |
| `dmesg` | Displays kernel boot log and hardware ring buffer |
| `ed <file>` | Built-in terminal text editor (ed/nano style) |
| `god [n]` | Speaks $n$ random words from Terry Davis's TempleOS divine oracle |
| `holyc [file.HC]` | Runs HolyC script or enters interactive HolyC REPL |
| `theme` | Toggles TempleOS 16-color VGA Blue mode / Dark Unix mode |
| `exit` / `reboot` | Clean operating system shutdown |

---

## Example Usage

### Running HolyC Scripts
Inside HolyC-Unix:
```bash
terry@holy-unix:/home/terry$ holyc hello.HC
=== Divine HolyC Execution ===
Welcome to God's chosen programming language!
Calculation: 10 + 20 = 30
Consulting TempleOS God Oracle...
God says: disciple spirit omnipresent simplicity last disciple firmament
HolyC Script Execution Finished.
```

### Consulting the Divine Oracle
```bash
terry@holy-unix:/home/terry$ god 7
God says: seraphim covenant wisdom tabernacle righteousness altar glory
```

Or read raw divine words from the device node:
```bash
terry@holy-unix:/home/terry$ cat /dev/god | grep temple
```

### Pipelines and Redirection
```bash
terry@holy-unix:/home/terry$ cat /etc/motd | grep Holy
  HolyC Unix Kernel & Terminal Operating System (v1.0.0)
 * Native In-Kernel HolyC Scripting Engine & REPL
 Type holyc hello.HC to run a HolyC script!

terry@holy-unix:/home/terry$ echo "Simplicity is divine" > /tmp/note.txt
terry@holy-unix:/home/terry$ cat /tmp/note.txt
Simplicity is divine
```

### Editing Files with Built-in Editor
```bash
terry@holy-unix:/home/terry$ ed myfile.txt
=== HolyC Editor ('myfile.txt') ===
Commands: 'p' (print), 'a' (append), 'd <n>' (delete), 'w' (save), 'wq' (save & exit), 'q' (exit)
ed: a
  1 | First line of HolyC text
  2 | Second line of text
  3 | .
ed: wq
[Saved 46 bytes to 'myfile.txt']
```
