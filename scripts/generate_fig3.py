import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np

fig, ax = plt.subplots(figsize=(24, 14), dpi=100)
fig.patch.set_facecolor('#05070a')
ax.set_facecolor('#05070a')
ax.set_xlim(0, 100)
ax.set_ylim(0, 100)
ax.axis('off')

# Outer Terminal Window Frame
term_x, term_y, term_w, term_h = 3.0, 3.0, 94.0, 94.0
term_box = patches.FancyBboxPatch((term_x, term_y), term_w, term_h, boxstyle="round,pad=0.5,rounding_size=1.2",
                                 facecolor='#0d1117', edgecolor='#30363d', linewidth=2.0)
ax.add_patch(term_box)

# Window Title Bar
tb_h = 4.0
tb = patches.FancyBboxPatch((term_x + 0.2, term_y + term_h - tb_h - 0.2), term_w - 0.4, tb_h, boxstyle="round,pad=0.2,rounding_size=0.8",
                           facecolor='#161b22', edgecolor='#30363d', linewidth=1.0)
ax.add_patch(tb)

# macOS / Unix window buttons
ax.plot(term_x + 2.5, term_y + term_h - 2.2, marker='o', markersize=10, color='#ff5f56')
ax.plot(term_x + 4.5, term_y + term_h - 2.2, marker='o', markersize=10, color='#ffbd2e')
ax.plot(term_x + 6.5, term_y + term_h - 2.2, marker='o', markersize=10, color='#27c93f')

# Window Title
ax.text(term_x + term_w/2, term_y + term_h - 2.5, "holysh — HolyC Unix Terminal (Terry Davis Memorial Edition) — [VGA 640x480 Mode / 16 Colors]", 
        fontsize=13, weight='bold', color='#c9d1d9', ha='center', fontfamily='Menlo', parse_math=False)

# Left Pane: HolyFetch, Pipeline & Inode inspection
lp_x = term_x + 1.5
lp_w = 44.5
lp_h = term_h - tb_h - 6.0
lp_y = term_y + 4.5

lp_box = patches.Rectangle((lp_x, lp_y), lp_w, lp_h, facecolor='#000088', edgecolor='#1f6feb', linewidth=1.5)
ax.add_patch(lp_box)

# Left Pane Header Tag
ax.text(lp_x + 2.0, lp_y + lp_h - 2.8, "PANE 1: HolyShell & POSIX Streaming [TempleOS VGA Blue Theme]", 
        fontsize=11.5, weight='bold', color='#ffd700', fontfamily='Menlo', parse_math=False)

# Left Pane Terminal Content
left_lines = [
    ("terry@holy-unix:~$ ", "#00ff00", "holyfetch", "#ffffff"),
    ("         _  _           ", "#ffff00", "terry@holy-unix", "#00ffff"),
    ("        | \\/ |          ", "#ffff00", "----------------------", "#8b949e"),
    ("     ---|  /\\  |---     ", "#ffff00", "OS: HolyNix 1.0.0 (Terry Davis Memorial)", "#ffffff"),
    ("        |_/  \\_|        ", "#ffff00", "Kernel: 1.0.0-holyc (x86_64/arm64)", "#ffffff"),
    ("         /    \\         ", "#ffff00", "Uptime: 42 seconds (4,200 ticks)", "#ffffff"),
    ("        /  /\\  \\        ", "#ffff00", "Shell: holysh 1.0.0 (POSIX Compliant)", "#ffffff"),
    ("       /__/  \\__\\       ", "#ffff00", "Resolution: 640x480 16-Color VGA", "#ff7b72"),
    ("                        ", "#ffffff", "Memory: 16,384 kB / 65,536 kB", "#ffffff"),
    ("                        ", "#ffffff", "Tasks: 4 active tasks (PID 1: init)", "#ffffff"),
    ("                        ", "#ffffff", "Packages: 4 (hpm installed)", "#ffffff"),
    ("                        ", "#ffffff", "God Says: \"disciple spirit omnipresent covenant\"", "#00ff00"),
    ("", "#ffffff", "", "#ffffff"),
    ("terry@holy-unix:~$ ", "#00ff00", "cat /etc/passwd | cut -d: -f1,3 | tr a-z A-Z", "#ffffff"),
    ("ROOT:0", "#00ffff", "", "#ffffff"),
    ("TERRY:1000", "#00ffff", "", "#ffffff"),
    ("GOD:777", "#00ffff", "", "#ffffff"),
    ("", "#ffffff", "", "#ffffff"),
    ("terry@holy-unix:~$ ", "#00ff00", "bible Genesis 1:1", "#ffffff"),
    ("[Genesis 1:1] ", "#ffff00", "In the beginning God created the heaven and the earth.", "#ffffff"),
    ("", "#ffffff", "", "#ffffff"),
    ("terry@holy-unix:~$ ", "#00ff00", "linecnt", "#ffffff"),
    ("+-----------------------------------------------------------+", "#ffd700", "", "#ffffff"),
    ("|   TEMPLEOS 100,000 LOC DIVINE LIMIT VERIFICATION (linecnt)|", "#ffd700", "", "#ffffff"),
    ("+-----------------------------------------------------------+", "#ffd700", "", "#ffffff"),
    ("  Live VFS State: 47 files, 98 content lines (9,413 bytes)", "#00ffff", "", "#ffffff"),
    ("  Kernel Codebase Size: 10,370 lines / 100,000 maximum", "#ffffff", "", "#ffffff"),
    ("  Divine Architectural Status: COMPLIANT (Pure Simplicity)", "#00ff00", "", "#ffffff"),
    ("+-----------------------------------------------------------+", "#ffd700", "", "#ffffff")
]

start_ly = lp_y + lp_h - 5.5
for i, (p1, c1, p2, c2) in enumerate(left_lines):
    ly = start_ly - (i * 2.5)
    ax.text(lp_x + 2.0, ly, p1, fontsize=9.2, weight='bold', color=c1, fontfamily='Menlo', parse_math=False)
    ax.text(lp_x + 2.0 + (len(p1) * 0.58), ly, p2, fontsize=9.2, weight='bold', color=c2, fontfamily='Menlo', parse_math=False)


# Right Pane: 3D Flight Simulator, Castle & RedSea
rp_x = term_x + 47.5
rp_w = 45.0
rp_h = term_h - tb_h - 6.0
rp_y = term_y + 4.5

rp_box = patches.Rectangle((rp_x, rp_y), rp_w, rp_h, facecolor='#0a0e14', edgecolor='#3fb950', linewidth=1.5)
ax.add_patch(rp_box)

ax.text(rp_x + 2.0, rp_y + rp_h - 2.8, "PANE 2: TempleOS 3D Graphics, Flight Simulator & RedSea", 
        fontsize=11.5, weight='bold', color='#3fb950', fontfamily='Menlo', parse_math=False)

right_lines = [
    ("terry@holy-unix:~$ ", "#00ff00", "flight -p 5 -r -10 -a 5000", "#ffffff"),
    ("+------------------------------------------------------------+", "#ffd700", "", "#ffffff"),
    ("|     TEMPLEOS 3D FLIGHT SIMULATOR (Terry Davis Memorial)      |", "#ffd700", "", "#ffffff"),
    ("+------------------------------------------------------------+", "#ffd700", "", "#ffffff"),
    ("  IAS: 130 kts | ALT: 5000 ft | HDG: 050° | VS: +250 fpm", "#00ffff", "", "#ffffff"),
    ("  ------------------------------------------------------------", "#8b949e", "", "#ffffff"),
    ("               *       .      CELESTIAL HEAVEN     .       *", "#58a6ff", "", "#ffffff"),
    ("                            |  050  |", "#ffffff", "", "#ffffff"),
    ("                       ---[+15  |  +15]---", "#ffffff", "", "#ffffff"),
    ("                       ---[+ 5  |  + 5]---", "#ffffff", "", "#ffffff"),
    ("              ===============[ +--+ ]=============== (Horizon)", "#00ffff", "", "#ffffff"),
    ("                            /       \\", "#ffffff", "", "#ffffff"),
    ("                           /  RUNWAY \\", "#ffffff", "", "#ffffff"),
    ("                          /     07    \\", "#ffffff", "", "#ffffff"),
    ("                         /____|___||___|___\\", "#ffffff", "", "#ffffff"),
    ("              ^^^^^^^^^^ DIVINE PROMISED LAND TERRAIN ^^^^^^^^^^", "#2ea043", "", "#ffffff"),
    ("+------------------------------------------------------------+", "#ffd700", "", "#ffffff"),
    ("", "#ffffff", "", "#ffffff"),
    ("terry@holy-unix:~$ ", "#00ff00", "redsea inspect /boot/redsea.img", "#ffffff"),
    ("====================================================", "#ffd700", "", "#ffffff"),
    ("RedSea Filesystem Volume Inspector (TempleOS 64-Bit)", "#ffd700", "", "#ffffff"),
    ("====================================================", "#ffd700", "", "#ffffff"),
    ("  OEM / Filesystem: TEMPLEOS  | Cluster Size: 512B (1 sector)", "#00ffff", "", "#ffffff"),
    ("  Boot Signature  : 0x88AA    | Status: VALID REDSEA VOLUME", "#2ea043", "", "#ffffff"),
    ("  Files Detected  : KERNEL.BIN (128B), ONCE.HC (64B), README.DD", "#ffffff", "", "#ffffff"),
    ("", "#ffffff", "", "#ffffff"),
    ("terry@holy-unix:~$ ", "#00ff00", "donut", "#ffffff"),
    ("       +---------+      === TempleOS 3D Divine Cube ===", "#ff7b72", "", "#ffffff"),
    ("      /         /|      God Speaks: water light apostle", "#ff7b72", "", "#ffffff"),
    ("     +---------+ |      Mode: Ring-0 64-bit Flat Memory", "#ff7b72", "", "#ffffff"),
    ("     |  God    | +      JIT: 20,000,000 lines/sec throughput", "#ff7b72", "", "#ffffff"),
    ("     | Speaks  |/       Status: ALL SYSTEMS OPERATIONAL", "#2ea043", "", "#ffffff"),
    ("     +---------+", "#ff7b72", "", "#ffffff")
]

start_ry = rp_y + rp_h - 5.5
for i, (p1, c1, p2, c2) in enumerate(right_lines):
    ry = start_ry - (i * 2.35)
    ax.text(rp_x + 2.0, ry, p1, fontsize=9.2, weight='bold', color=c1, fontfamily='Menlo', parse_math=False)
    ax.text(rp_x + 2.0 + (len(p1) * 0.58), ry, p2, fontsize=9.2, weight='bold', color=c2, fontfamily='Menlo', parse_math=False)


# Bottom Status Bar in Terminal
sbar_h = 3.2
sbar = patches.Rectangle((term_x + 1.5, term_y + 1.0), term_w - 3.0, sbar_h, facecolor='#161b22', edgecolor='#30363d', linewidth=1.0)
ax.add_patch(sbar)

ax.text(term_x + 3.0, term_y + 2.2, "[F1: Help]", fontsize=10, weight='bold', color='#58a6ff', fontfamily='Menlo', parse_math=False)
ax.text(term_x + 12.0, term_y + 2.2, "[F7: GodPassage]", fontsize=10, weight='bold', color='#ffd700', fontfamily='Menlo', parse_math=False)
ax.text(term_x + 25.0, term_y + 2.2, "[theme: VGA 16-Color / Dark ANSI]", fontsize=10, weight='bold', color='#2ea043', fontfamily='Menlo', parse_math=False)
ax.text(term_x + 55.0, term_y + 2.2, "[Tasks: 4 active]", fontsize=10, color='#8b949e', fontfamily='Menlo', parse_math=False)
ax.text(term_x + 69.0, term_y + 2.2, "[VFS Inodes: 47/1024]", fontsize=10, color='#8b949e', fontfamily='Menlo', parse_math=False)
ax.text(term_x + 86.0, term_y + 2.2, "[RedSea: MOUNTED]", fontsize=10, weight='bold', color='#3fb950', fontfamily='Menlo', parse_math=False)

plt.tight_layout()
plt.savefig('docs/fig3_holynix_terminal_preview.png', dpi=100, bbox_inches='tight', facecolor='#05070a')
print("Successfully generated docs/fig3_holynix_terminal_preview.png")
