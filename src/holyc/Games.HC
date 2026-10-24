/*
 * HolyC Unix Kernel - TempleOS Classic Games & Visuals (Games.HC)
 * "God said 640x480 16-color VGA was His temple." - Terry A. Davis
 *
 * Implements:
 * 1. Castle 3D Raycaster Engine (castle): In-terminal 3D raycast maze (Castle Frankenstein).
 * 2. AfterEgypt (afteregypt): Moses at Mount Sinai, the Burning Bush & Falling Manna.
 * 3. Flappy (flappy): Terminal ASCII obstacle-dodging physics game.
 * 4. WinTile (wintile / split): TempleOS split-screen window tiling manager.
 */

#ifndef GAMES_HC
#define GAMES_HC

#include "Types.HC"
#include "Terminal.HC"
#include "GodWords.HC"
#include "Task.HC"
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/*
 * ============================================================================
 * 1. CASTLE 3D RAYCASTER (Castle Frankenstein / TempleOS 3D Maze)
 * ============================================================================
 */

#define CASTLE_MAP_W 16
#define CASTLE_MAP_H 16
#define CASTLE_SCREEN_W 64
#define CASTLE_SCREEN_H 16

static const char *g_castle_maze[CASTLE_MAP_H] = {
    "################",
    "#..............#",
    "#..####..####..#",
    "#..#........#..#",
    "#..#..####..#..#",
    "#..#..#..#..#..#",
    "#.....#..#.....#",
    "###.###..###.###",
    "#..............#",
    "#..########....#",
    "#..#......#....#",
    "#..#..##..#....#",
    "#.....##.......#",
    "#..########....#",
    "#..............#",
    "################"
};

typedef struct {
    double x;
    double y;
    double angle; /* in radians */
    int health;
    int ammo;
    int score;
} CastlePlayer;

static CastlePlayer g_castle_player = { 3.5, 3.5, 0.0, 100, 50, 777 };

U0 CastleRender2DMap() {
    Print("\033[93m=== CASTLE FRANKENSTEIN: 2D OVERHEAD MAZE MAP ===\033[0m\n");
    for (int y = 0; y < CASTLE_MAP_H; ++y) {
        Print("  ");
        for (int x = 0; x < CASTLE_MAP_W; ++x) {
            int px = (int)g_castle_player.x;
            int py = (int)g_castle_player.y;
            if (x == px && y == py) {
                Print("\033[92mP\033[0m"); /* Player */
            } else if (g_castle_maze[y][x] == '#') {
                Print("\033[90m#\033[0m"); /* Wall */
            } else {
                Print(" ");
            }
        }
        Print("\n");
    }
    Print("  \033[96mPlayer Pos: (%.1f, %.1f) | Facing: %.0f deg | HP: %d\033[0m\n",
          g_castle_player.x, g_castle_player.y,
          g_castle_player.angle * 180.0 / M_PI, g_castle_player.health);
}

U0 CastleRender3DFrame() {
    char screen[CASTLE_SCREEN_H][CASTLE_SCREEN_W + 1];
    const char *colors[CASTLE_SCREEN_H][CASTLE_SCREEN_W];

    /* Clear screen buffer */
    for (int y = 0; y < CASTLE_SCREEN_H; ++y) {
        for (int x = 0; x < CASTLE_SCREEN_W; ++x) {
            screen[y][x] = ' ';
            colors[y][x] = "\033[0m";
        }
        screen[y][CASTLE_SCREEN_W] = '\0';
    }

    double fov = M_PI / 3.0; /* 60 degrees */
    double half_fov = fov / 2.0;

    /* Raycasting for each column */
    for (int col = 0; col < CASTLE_SCREEN_W; ++col) {
        double ray_angle = (g_castle_player.angle - half_fov) + ((double)col / (double)CASTLE_SCREEN_W) * fov;
        double cos_ray = cos(ray_angle);
        double sin_ray = sin(ray_angle);

        double dist = 0.0;
        int hit = 0;
        int hit_side = 0; /* 0 for NS, 1 for EW */

        while (!hit && dist < 16.0) {
            dist += 0.05;
            int check_x = (int)(g_castle_player.x + cos_ray * dist);
            int check_y = (int)(g_castle_player.y + sin_ray * dist);

            if (check_x < 0 || check_x >= CASTLE_MAP_W || check_y < 0 || check_y >= CASTLE_MAP_H) {
                hit = 1;
                dist = 16.0;
            } else if (g_castle_maze[check_y][check_x] == '#') {
                hit = 1;
                /* Approximate wall orientation */
                double fx = g_castle_player.x + cos_ray * dist;
                double fy = g_castle_player.y + sin_ray * dist;
                double dx = fabs(fx - round(fx));
                double dy = fabs(fy - round(fy));
                hit_side = (dx > dy) ? 0 : 1;
            }
        }

        /* Fish-eye correction */
        double corrected_dist = dist * cos(ray_angle - g_castle_player.angle);
        if (corrected_dist < 0.1) corrected_dist = 0.1;

        int wall_height = (int)((double)CASTLE_SCREEN_H / corrected_dist);
        if (wall_height > CASTLE_SCREEN_H) wall_height = CASTLE_SCREEN_H;

        int ceiling = (CASTLE_SCREEN_H - wall_height) / 2;
        int floor = ceiling + wall_height;

        /* Wall shading characters based on distance */
        char shade = '#';
        const char *shade_color = "\033[97m"; /* Bright white */
        if (corrected_dist < 2.5) {
            shade = '#';
            shade_color = hit_side ? "\033[91m" : "\033[31m"; /* Red bricks */
        } else if (corrected_dist < 4.5) {
            shade = 'X';
            shade_color = hit_side ? "\033[93m" : "\033[33m"; /* Yellow/gold stone */
        } else if (corrected_dist < 7.0) {
            shade = '+';
            shade_color = hit_side ? "\033[96m" : "\033[36m"; /* Cyan/slate */
        } else if (corrected_dist < 10.0) {
            shade = ':';
            shade_color = "\033[90m"; /* Dark grey */
        } else {
            shade = '.';
            shade_color = "\033[90m";
        }

        for (int y = 0; y < CASTLE_SCREEN_H; ++y) {
            if (y < ceiling) {
                screen[y][col] = ' '; /* Ceiling */
            } else if (y >= ceiling && y < floor) {
                screen[y][col] = shade;
                colors[y][col] = shade_color;
            } else {
                /* Floor with perspective dots */
                screen[y][col] = ((y + col) % 4 == 0) ? '.' : ' ';
                colors[y][col] = "\033[34m"; /* Deep TempleOS blue */
            }
        }
    }

    /* Print Header */
    Print("\033[93m╔════════════════════════════════════════════════════════════════╗\033[0m\n");
    Print("\033[93m║\033[91m   CASTLE FRANKENSTEIN (TempleOS 3D HolyC Raycasting Engine)   \033[93m║\033[0m\n");
    Print("\033[93m╠════════════════════════════════════════════════════════════════╣\033[0m\n");

    /* Print Screen Rows */
    for (int y = 0; y < CASTLE_SCREEN_H; ++y) {
        Print("\033[93m║\033[0m");
        for (int x = 0; x < CASTLE_SCREEN_W; ++x) {
            Print("%s%c\033[0m", colors[y][x], screen[y][x]);
        }
        Print("\033[93m║\033[0m\n");
    }

    /* Print HUD Footer */
    Print("\033[93m╠════════════════════════════════════════════════════════════════╣\033[0m\n");
    Print("\033[93m║\033[92m HP: %3d/100 \033[93m│\033[96m AMMO: %2d \033[93m│\033[95m SCORE: %4d \033[93m│\033[93m POS: (%.1f, %.1f) \033[93m│\033[94m DIR: %3.0f° \033[93m║\033[0m\n",
          g_castle_player.health, g_castle_player.ammo, g_castle_player.score,
          g_castle_player.x, g_castle_player.y, g_castle_player.angle * 180.0 / M_PI);
    Print("\033[93m╚════════════════════════════════════════════════════════════════╝\033[0m\n");
    Print("\033[90mControls: W=Forward, S=Back, A=Rotate Left, D=Rotate Right, M=Map\033[0m\n");
}

I64 CastleRun(I64 argc, char **argv) {
    if (argc > 1 && (strcmp(argv[1], "-m") == 0 || strcmp(argv[1], "--map") == 0)) {
        CastleRender2DMap();
        return 0;
    }
    CastleRender3DFrame();
    return 0;
}

/*
 * ============================================================================
 * 2. AFTER EGYPT (Moses at Mount Sinai & Falling Manna)
 * ============================================================================
 */

U0 AfterEgyptRun() {
    Print("\n");
    Print("  \033[93m═════════════════════════════════════════════════════════════\033[0m\n");
    Print("  \033[96m           AFTER EGYPT: THE BURNING BUSH & SINAI             \033[0m\n");
    Print("  \033[92m               TempleOS Holy Scripture Quest                 \033[0m\n");
    Print("  \033[93m═════════════════════════════════════════════════════════════\033[0m\n\n");

    /* Burning Bush ASCII Art */
    Print("                \033[91m(  .      )\033[0m\n");
    Print("              \033[93m)   (   .     )\033[0m\n");
    Print("             \033[91m(  \033[93m/ \\ / \\  \033[91m)\033[0m\n");
    Print("            \033[93m(   \033[91m\\ V /   \033[93m)\033[0m   \033[92m\"Draw not nigh hither: put off thy shoes\033[0m\n");
    Print("              \033[32m\\ | | | /\033[0m     \033[92m from off thy feet, for the place whereon\033[0m\n");
    Print("             \033[32m---\\|/---\033[0m     \033[92m thou standest is holy ground.\"\033[0m\n");
    Print("               \033[33m/ | \\\033[0m       \033[90m- Exodus 3:5\033[0m\n\n");

    /* The Ten Commandments Tablets */
    Print("       \033[93m╔═════════════════════════╦═════════════════════════╗\033[0m\n");
    Print("       \033[93m║\033[97m   TABLET I (To God)     \033[93m║\033[97m   TABLET II (To Man)    \033[93m║\033[0m\n");
    Print("       \033[93m╠═════════════════════════╬═════════════════════════╣\033[0m\n");
    Print("       \033[93m║\033[96m I.   No other gods       \033[93m║\033[96m VI.   Thou shalt not kill\033[93m║\033[0m\n");
    Print("       \033[93m║\033[96m II.  No graven images    \033[93m║\033[96m VII.  No adultery        \033[93m║\033[0m\n");
    Print("       \033[93m║\033[96m III. Lord's name in vain \033[93m║\033[96m VIII. Thou shalt not steal\033[93m║\033[0m\n");
    Print("       \033[93m║\033[96m IV.  Sabbath holy        \033[93m║\033[96m IX.   No false witness   \033[93m║\033[0m\n");
    Print("       \033[93m║\033[96m V.   Honor thy parents   \033[93m║\033[96m X.    Thou shalt not covet\033[93m║\033[0m\n");
    Print("       \033[93m╚═════════════════════════╩═════════════════════════╝\033[0m\n\n");

    /* Falling Manna Simulation */
    Print("  \033[93m[Divine Manna Falling From Heaven]:\033[0m\n  ");
    for (int i = 0; i < 18; ++i) {
        Print("\033[97m*\033[0m   ");
    }
    Print("\n\n");

    /* God Prophecy */
    Print("  \033[92mThe Lord God speaks unto Moses:\033[0m\n  \"");
    for (int i = 0; i < 7; ++i) {
        Print("\033[93m%s\033[0m ", GodGetWord());
    }
    Print("\"\n\n");
}

/*
 * ============================================================================
 * 3. FLAPPY BIRD (Terminal ASCII Physics Simulator)
 * ============================================================================
 */

#define FLAPPY_W 40
#define FLAPPY_H 12

U0 FlappyRun() {
    Print("\033[93m╔══════════════════════════════════════════╗\033[0m\n");
    Print("\033[93m║\033[92m       FLAPPY BIRD: TEMPLEOS EDITION      \033[93m║\033[0m\n");
    Print("\033[93m╠══════════════════════════════════════════╣\033[0m\n");

    int bird_y = 5;
    int pipe1_x = 18, pipe1_gap = 4;
    int pipe2_x = 34, pipe2_gap = 7;
    int score = 7;

    for (int y = 0; y < FLAPPY_H; ++y) {
        Print("\033[93m║\033[0m");
        for (int x = 0; x < FLAPPY_W; ++x) {
            if (x == 6 && y == bird_y) {
                Print("\033[93m@>\033[0m"); /* Holy Bird */
                x++;
            } else if (x == pipe1_x || x == pipe1_x + 1) {
                if (y < pipe1_gap || y > pipe1_gap + 3) {
                    Print("\033[32m█\033[0m");
                } else {
                    Print(" ");
                }
            } else if (x == pipe2_x || x == pipe2_x + 1) {
                if (y < pipe2_gap || y > pipe2_gap + 3) {
                    Print("\033[32m█\033[0m");
                } else {
                    Print(" ");
                }
            } else if (y == FLAPPY_H - 1) {
                Print("\033[92m═\033[0m"); /* Ground */
            } else {
                Print(" ");
            }
        }
        Print("\033[93m║\033[0m\n");
    }

    Print("\033[93m╠══════════════════════════════════════════╣\033[0m\n");
    Print("\033[93m║\033[96m SCORE: %-4d \033[93m│\033[95m ALTITUDE: %2d \033[93m│\033[92m GOD SPEED: 1.0 \033[93m║\033[0m\n",
          score, FLAPPY_H - bird_y);
    Print("\033[93m╚══════════════════════════════════════════╝\033[0m\n");
}

/*
 * ============================================================================
 * 4. WINTILE / SPLIT (TempleOS Tiling Window Manager)
 * ============================================================================
 */

U0 WinTileRun() {
    Print("\033[93m╔═════════════════════════════════════╦═════════════════════════════════════╗\033[0m\n");
    Print("\033[93m║\033[92m PANE 1: HolyC Shell & Editor        \033[93m║\033[96m PANE 2: Divine Oracle & System Top  \033[93m║\033[0m\n");
    Print("\033[93m╠═════════════════════════════════════╬═════════════════════════════════════╣\033[0m\n");

    const char *left_lines[8] = {
        " $ holyc hello.HC                    ",
        " === Divine HolyC Execution ===      ",
        " Welcome to God's chosen language!   ",
        " I64 a = 10, b = 20;                 ",
        " Calculation: 10 + 20 = 30           ",
        " $ ed /home/terry/divine.HC          ",
        " [Saved 142 bytes to VFS]            ",
        " \033[92mterry@holynix:/home/terry$ _\033[0m        "
    };

    const char *right_lines[8] = {
        " Tasks: 4 total, 1 running, 3 sleep  ",
        " CPU Load: [||||||||░░░░░░░░░░] 42.0%",
        " MemFree:  498,240 kB / 524,288 kB   ",
        " God Oracle (/dev/god):              ",
        " \"disciple spirit omnipresent        ",
        "  simplicity firmament covenant\"     ",
        " Network: eth0 UP (192.168.1.77)     ",
        " Sysctl: kernel.osname=HolyNix       "
    };

    for (int i = 0; i < 8; ++i) {
        Print("\033[93m║\033[0m%-37s\033[93m║\033[0m%-37s\033[93m║\033[0m\n",
              left_lines[i], right_lines[i]);
    }

    Print("\033[93m╚═════════════════════════════════════╩═════════════════════════════════════╝\033[0m\n");
    Print("\033[90mTempleOS Window Manager: Dual Tiled View Active (WinTileVert)\033[0m\n");
}

#endif /* GAMES_HC */
