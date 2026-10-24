import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np

fig, ax = plt.subplots(figsize=(24, 14), dpi=100)
fig.patch.set_facecolor('#0d1117')
ax.set_facecolor('#0d1117')
ax.set_xlim(0, 100)
ax.set_ylim(100)
ax.set_ylim(0, 100)
ax.axis('off')

# Title & Header
ax.text(50, 96, "HolyNix: Hybrid HolyC-Unix Kernel Architecture", 
        fontsize=28, weight='bold', color='#ffd700', ha='center', fontfamily='Helvetica')
ax.text(50, 93, "Terry A. Davis TempleOS Architecture × POSIX Linux Compatibility Matrix", 
        fontsize=16, color='#58a6ff', ha='center', fontfamily='Helvetica')

def draw_layer_card(x, y, w, h, title, subtitle, items, border_color, header_bg, accent_color):
    card = patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.5,rounding_size=1.2",
                                  facecolor='#161b22', edgecolor=border_color, linewidth=2.5)
    ax.add_patch(card)
    
    hdr = patches.FancyBboxPatch((x + 0.3, y + h - 4.2), w - 0.6, 3.8, boxstyle="round,pad=0.2,rounding_size=0.8",
                                 facecolor=header_bg, edgecolor='none')
    ax.add_patch(hdr)
    
    ax.text(x + w/2, y + h - 2.2, title, fontsize=15, weight='bold', color='#ffffff', ha='center', fontfamily='Helvetica', parse_math=False)
    ax.text(x + w/2, y + h - 3.4, subtitle, fontsize=10.5, color=accent_color, ha='center', fontfamily='Helvetica', weight='bold', parse_math=False)
    
    start_y = y + h - 5.5
    for i, (head, desc) in enumerate(items):
        cur_y = start_y - (i * 3.4)
        ax.plot(x + 2.0, cur_y - 0.2, marker='o', markersize=6, color=border_color)
        ax.text(x + 3.5, cur_y, head, fontsize=11.5, weight='bold', color='#f0f6fc', fontfamily='Helvetica', parse_math=False)
        ax.text(x + 3.5, cur_y - 1.3, desc, fontsize=9.5, color='#8b949e', fontfamily='Helvetica', parse_math=False)

card_w = 43.5
card_h = 21.0
c1_x = 4.5
c2_x = 52.0

# ROW 1 (TOP)
draw_layer_card(
    c1_x, 67, card_w, card_h,
    "Layer 1: HolyC Compiler & JIT Engine", "NATIVE TRANSPILER & RUNTIME CORE",
    [
        ("HolyC Lexer & AST Parser (tools/holyc)", "Translates U0, I64, implicit Print(), inline strings to ISO C99/LLVM"),
        ("Dual-Target Transpiler (GCC / Clang)", "Enables cross-platform builds on macOS (Darwin arm64) & Linux (x86_64)"),
        ("In-Kernel HolyC REPL & Dynamic Evaluator", "Direct execution of .HC scripts with Ring-0 function pointer dispatch"),
        ("Standard HolyC ABI & Runtime Library", "Implements Terry Davis StrLen, StrCpy, MemSet, MemCmp primitives")
    ],
    border_color='#ffd700', header_bg='#3b2d00', accent_color='#ffd700'
)

draw_layer_card(
    c2_x, 67, card_w, card_h,
    "Layer 2: Ring-0 Task Scheduler & PCB", "ROUND-ROBIN MULTITASKING & CREDENTIALS",
    [
        ("Preemptive Round-Robin Scheduler (Task.HC)", "Time-sliced scheduling across 64 active task control blocks (PCBs)"),
        ("POSIX Credentials & Context Switching", "UID/GID permissions, effective root (0) & terry (1000) credential tokens"),
        ("IPC File Descriptor Table (fd_table)", "Per-task open file table supporting stdin(0), stdout(1), stderr(2), pipes"),
        ("Process Tree & Signals (pstree, kill)", "Full parent-child PID hierarchy, SIGTERM, SIGKILL & zombie reaping")
    ],
    border_color='#1f6feb', header_bg='#0d2347', accent_color='#58a6ff'
)

# ROW 2 (MIDDLE)
draw_layer_card(
    c1_x, 42, card_w, card_h,
    "Layer 3: Dual VFS & RedSea Storage Engine", "UNIX INODE VFS & TEMPLEOS FLAT CLUSTER",
    [
        ("Hierarchical Unix Inode VFS (VFS.HC)", "1,024-inode memory storage for /etc, /bin, /tmp, /home, permissions (chmod)"),
        ("Linux Pseudo-Filesystems (/proc & /dev)", "Dynamic /proc/uptime, meminfo, cpuinfo, /dev/null, zero, urandom, god"),
        ("64-Bit Flat Cluster RedSea Driver (RedSea.HC)", "Parses raw TempleOS .ISO/.BIN images, contiguous zero-fragmentation blocks"),
        ("POSIX I/O Semantics & Tar Archiver", "True O_TRUNC, O_APPEND, lseek sparse writes, dup2(), and USTAR tar")
    ],
    border_color='#238636', header_bg='#0e3a1a', accent_color='#3fb950'
)

draw_layer_card(
    c2_x, 42, card_w, card_h,
    "Layer 4: DolDoc-to-ANSI Streaming Parser", "TEMPLEOS DOCUMENT MARKUP TRANSLATION",
    [
        ("DolDoc Document Tokenizer (DolDoc.HC)", "Parses $FG,COLOR$, $BK,COLOR$, $TR,\"Tree\"$, $LK,\"Link\",Path$ tags"),
        ("Real-Time ANSI / VT100 Escape Generator", "Converts 16-color VGA palette & blinking attributes to modern ANSI terminals"),
        ("Interactive Terminal Pager (holyless, more)", "Navigates TempleOS .DD help manuals, tree views, and scripture documents"),
        ("Screen Capture & Framebuffer Dumper (fbgrab)", "Serializes live terminal display buffers directly to DolDoc formatted files")
    ],
    border_color='#a371f7', header_bg='#321b59', accent_color='#d2a8ff'
)

# ROW 3 (BOTTOM)
draw_layer_card(
    c1_x, 17, card_w, card_h,
    "Layer 5: HolyShell Streaming & Pipelines", "120+ POSIX BUILTINS, SIGNALS & JOB CONTROL",
    [
        ("Streaming Pipelines & Redirections", "Arbitrary multi-stage cmd1 | cmd2 | cmd3, < in, > out, >> append"),
        ("Asynchronous Job Control (&, jobs, fg, bg)", "Runs background tasks, tracks job status, and resumes to foreground"),
        ("Comprehensive Text Stream Filters", "Full range tr a-z, sed s/old/new/g, line-by-line diff, cut -d:, grep -i/-v"),
        ("POSIX Core Utilities & Environment", "80+ builtins: ulimit, vmstat, ipcs, ps, date, find, sort, uniq, tar, cron")
    ],
    border_color='#f0883e', header_bg='#4d2204', accent_color='#ffab70'
)

draw_layer_card(
    c2_x, 17, card_w, card_h,
    "Layer 6: TempleOS Divine Subsystems & 3D", "TERRY DAVIS MEMORIAL TOOLS & 100K LOC COMPLIANCE",
    [
        ("Divine Random Oracle & KJV Bible Concordance", "100,000-word vocabulary (/dev/god, godword) & full Genesis-Revelation search"),
        ("3D Wireframe Graphics & Simulator Engine", "TempleOS Flight Simulator with 3D HUD (flight), Castle Frankenstein, Donut"),
        ("PC Speaker Synthesizer & Jukebox (play, juke)", "Generates divine hymns, C1-B8 frequency calculations, 8-bit chiptune audio"),
        ("100,000 LOC Divine Limit Verifier (linecnt)", "Kernel introspection ensuring simplicity constraint: 10,370 / 100,000 LOC")
    ],
    border_color='#f85149', header_bg='#491818', accent_color='#ff7b72'
)

# Footer bar
ftr = patches.FancyBboxPatch((4.5, 4.0), 91.0, 8.5, boxstyle="round,pad=0.4,rounding_size=0.8",
                             facecolor='#161b22', edgecolor='#30363d', linewidth=1.5)
ax.add_patch(ftr)

ax.text(6.5, 9.5, "VERIFICATION & BUILD PIPELINE", fontsize=11, weight='bold', color='#58a6ff', fontfamily='Helvetica')
ax.text(6.5, 6.8, "• In-Kernel Self Tests: 45 / 45 PASS   • POSIX Compliance TDD: 216 / 216 PASS (14 Suites)   • Codebase: 10,370 LOC (Compliant)", 
        fontsize=12, color='#f0f6fc', fontfamily='Helvetica')
ax.text(6.5, 5.0, "• GitHub Actions CI Matrix: Ubuntu Linux (GCC/Clang) + macOS Darwin (GCC/Clang) 100% All-Green   • GitHub: omakasekim/holynix", 
        fontsize=10.5, color='#8b949e', fontfamily='Helvetica')

plt.tight_layout()
plt.savefig('docs/fig1_architecture.png', dpi=100, bbox_inches='tight', facecolor='#0d1117')
print("Successfully generated docs/fig1_architecture.png")
