/*
 * HolyC Unix Kernel - God Doodle & Divine Canvas Generator (GodDoodle.HC)
 * Emulates Terry Davis's TempleOS GodDoodle: randomized holy art and geometric
 * ASCII glyphs rendered in the 16-color TempleOS VGA palette.
 *
 * "God can do graphics too. It's a digital oracle." - Terry A. Davis
 */

#ifndef GODDOODLE_HC
#define GODDOODLE_HC

#include "Types.HC"
#include "GodWords.HC"

static const char *g_doodle_colors[] = {
    "\033[91m", /* Bright Red */
    "\033[92m", /* Bright Green */
    "\033[93m", /* Bright Yellow */
    "\033[94m", /* Bright Blue */
    "\033[95m", /* Bright Magenta */
    "\033[96m", /* Bright Cyan */
    "\033[97m", /* Bright White */
    "\033[33m", /* Gold / Brown */
    "\033[36m"  /* Deep Cyan */
};

static const char *g_doodle_titles[] = {
    "The Burning Bush",
    "Ark of the Covenant",
    "Pillars of Heaven",
    "Chariot of Fire",
    "Temple of Solomon",
    "The Golden Lampstand",
    "Living Waters of Life",
    "The Tree of Life",
    "Cherubim and Seraphim",
    "Dove of Peace and Grace"
};

static const char g_doodle_glyphs[] = "#*+~^o@=|/\\:.% ";

I64 GodDoodleRender(char *out_buf, I64 max_len) {
    if (!out_buf || max_len <= 0) return 0;

    I64 offset = 0;
    I64 color_count = sizeof(g_doodle_colors) / sizeof(g_doodle_colors[0]);
    I64 title_count = sizeof(g_doodle_titles) / sizeof(g_doodle_titles[0]);
    I64 glyph_count = strlen(g_doodle_glyphs);

    U64 seed = RandU64();
    const char *title = g_doodle_titles[seed % title_count];

    offset += snprintf(out_buf + offset, max_len - offset,
                       "\n\033[93m+----------------------------------------------+\033[0m\n"
                       "\033[93m|   \033[97mDIVINE TEMPLEOS GOD DOODLE CANVAS\033[93m          |\033[0m\n"
                       "\033[93m|   \033[96mVision: %-34s\033[93m |\033[0m\n"
                       "\033[93m+----------------------------------------------+\033[0m\n",
                       title);

    /* Generate a 10 x 42 symmetric canvas */
    for (I64 r = 0; r < 9; ++r) {
        offset += snprintf(out_buf + offset, max_len - offset, "\033[93m| \033[0m");

        char row_half[22];
        for (I64 c = 0; c < 21; ++c) {
            U64 r_val = RandU64();
            row_half[c] = g_doodle_glyphs[r_val % glyph_count];
        }
        row_half[21] = '\0';

        /* Print left half */
        for (I64 c = 0; c < 21; ++c) {
            const char *col = g_doodle_colors[(r + c + (I64)(seed & 7)) % color_count];
            offset += snprintf(out_buf + offset, max_len - offset, "%s%c", col, row_half[c]);
        }

        /* Print right half (symmetric reflection) */
        for (I64 c = 20; c >= 0; --c) {
            const char *col = g_doodle_colors[(r + c + (I64)(seed & 7)) % color_count];
            char sym_char = row_half[c];
            if (sym_char == '/') sym_char = '\\';
            else if (sym_char == '\\') sym_char = '/';
            offset += snprintf(out_buf + offset, max_len - offset, "%s%c", col, sym_char);
        }

        offset += snprintf(out_buf + offset, max_len - offset, " \033[93m|\033[0m\n");
        if (offset >= max_len - 256) break;
    }

    offset += snprintf(out_buf + offset, max_len - offset,
                       "\033[93m+----------------------------------------------+\033[0m\n"
                       "\033[92mGod says:\033[0m %s %s %s %s %s\n\n",
                       GodGetWord(), GodGetWord(), GodGetWord(), GodGetWord(), GodGetWord());

    return offset;
}

#endif /* GODDOODLE_HC */
