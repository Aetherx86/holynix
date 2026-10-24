/*
 * HolyC Unix Kernel - DolDoc Terminal Markup Engine (DolDoc.HC)
 * Parses TempleOS DolDoc tags ($FG,RED$, $BK,1$, $TR$, $LK$, etc.)
 * and renders formatted, colored ANSI output in terminal and shell.
 *
 * "The document format is everything. Code is a document." - Terry A. Davis
 */

#ifndef DOLDOC_HC
#define DOLDOC_HC

#include "Types.HC"
#include "VFS.HC"
#include "Syscall.HC"

/* Convert a DolDoc color name to ANSI escape sequence */
static const char *DolDocColorToAnsi(const char *color_name, Bool is_bg) {
    if (!color_name) return is_bg ? "\033[49m" : "\033[39m";

    if (strcasecmp(color_name, "BLACK") == 0)   return is_bg ? "\033[40m" : "\033[30m";
    if (strcasecmp(color_name, "BLUE") == 0)    return is_bg ? "\033[44m" : "\033[94m";
    if (strcasecmp(color_name, "GREEN") == 0)   return is_bg ? "\033[42m" : "\033[92m";
    if (strcasecmp(color_name, "CYAN") == 0)    return is_bg ? "\033[46m" : "\033[96m";
    if (strcasecmp(color_name, "RED") == 0)     return is_bg ? "\033[41m" : "\033[91m";
    if (strcasecmp(color_name, "PURPLE") == 0 ||
        strcasecmp(color_name, "MAGENTA") == 0) return is_bg ? "\033[45m" : "\033[95m";
    if (strcasecmp(color_name, "BROWN") == 0 ||
        strcasecmp(color_name, "YELLOW") == 0)  return is_bg ? "\033[43m" : "\033[93m";
    if (strcasecmp(color_name, "LTGRAY") == 0)  return is_bg ? "\033[47m" : "\033[37m";
    if (strcasecmp(color_name, "DKGRAY") == 0)  return is_bg ? "\033[100m": "\033[90m";
    if (strcasecmp(color_name, "WHITE") == 0)   return is_bg ? "\033[107m": "\033[97m";
    if (strcasecmp(color_name, "DEFAULT") == 0 ||
        strcasecmp(color_name, "") == 0)        return is_bg ? "\033[49m" : "\033[0m";

    return is_bg ? "\033[49m" : "\033[0m";
}

/*
 * Translate DolDoc document text into ANSI formatted text
 */
I64 DolDocRender(const char *src, char *dest, I64 max_len) {
    if (!src || !dest || max_len <= 0) return 0;

    I64 s_idx = 0;
    I64 d_idx = 0;
    I64 s_len = strlen(src);
    I64 indent_level = 0;

    while (s_idx < s_len && d_idx < max_len - 1) {
        if (src[s_idx] == '$') {
            /* Check for escaped literal dollar $$ */
            if (s_idx + 1 < s_len && src[s_idx + 1] == '$') {
                dest[d_idx++] = '$';
                s_idx += 2;
                continue;
            }

            /* Scan to closing $ */
            I64 tag_start = s_idx + 1;
            I64 tag_end = tag_start;
            while (tag_end < s_len && src[tag_end] != '$' && src[tag_end] != '\n') {
                tag_end++;
            }

            if (tag_end < s_len && src[tag_end] == '$') {
                char tag[128];
                I64 tlen = tag_end - tag_start;
                if (tlen > 127) tlen = 127;
                memcpy(tag, &src[tag_start], tlen);
                tag[tlen] = '\0';
                s_idx = tag_end + 1;

                /* Parse Tag Commands */
                if (strncasecmp(tag, "FG,", 3) == 0) {
                    const char *ansi = DolDocColorToAnsi(tag + 3, FALSE);
                    I64 alen = strlen(ansi);
                    if (d_idx + alen < max_len - 1) {
                        memcpy(&dest[d_idx], ansi, alen);
                        d_idx += alen;
                    }
                } else if (strcasecmp(tag, "FG") == 0) {
                    const char *ansi = "\033[0m";
                    I64 alen = strlen(ansi);
                    if (d_idx + alen < max_len - 1) {
                        memcpy(&dest[d_idx], ansi, alen);
                        d_idx += alen;
                    }
                } else if (strncasecmp(tag, "BG,", 3) == 0) {
                    const char *ansi = DolDocColorToAnsi(tag + 3, TRUE);
                    I64 alen = strlen(ansi);
                    if (d_idx + alen < max_len - 1) {
                        memcpy(&dest[d_idx], ansi, alen);
                        d_idx += alen;
                    }
                } else if (strcasecmp(tag, "BK,1") == 0) {
                    const char *ansi = "\033[5m"; /* Blink */
                    I64 alen = strlen(ansi);
                    if (d_idx + alen < max_len - 1) {
                        memcpy(&dest[d_idx], ansi, alen);
                        d_idx += alen;
                    }
                } else if (strcasecmp(tag, "BK,0") == 0) {
                    const char *ansi = "\033[25m"; /* Blink Off */
                    I64 alen = strlen(ansi);
                    if (d_idx + alen < max_len - 1) {
                        memcpy(&dest[d_idx], ansi, alen);
                        d_idx += alen;
                    }
                } else if (strcasecmp(tag, "UL,1") == 0) {
                    const char *ansi = "\033[4m"; /* Underline */
                    I64 alen = strlen(ansi);
                    if (d_idx + alen < max_len - 1) {
                        memcpy(&dest[d_idx], ansi, alen);
                        d_idx += alen;
                    }
                } else if (strcasecmp(tag, "UL,0") == 0) {
                    const char *ansi = "\033[24m"; /* Underline Off */
                    I64 alen = strlen(ansi);
                    if (d_idx + alen < max_len - 1) {
                        memcpy(&dest[d_idx], ansi, alen);
                        d_idx += alen;
                    }
                } else if (strncasecmp(tag, "TX,", 3) == 0) {
                    /* Text Tag: $TX,"text"$ */
                    char *q1 = strchr(tag + 3, '"');
                    if (q1) {
                        char *q2 = strchr(q1 + 1, '"');
                        if (q2) {
                            *q2 = '\0';
                            const char *inner = q1 + 1;
                            I64 ilen = strlen(inner);
                            if (d_idx + ilen < max_len - 1) {
                                memcpy(&dest[d_idx], inner, ilen);
                                d_idx += ilen;
                            }
                        }
                    }
                } else if (strncasecmp(tag, "TR,", 3) == 0) {
                    /* Collapsible Tree Tag: $TR,"Title"$ */
                    char *q1 = strchr(tag + 3, '"');
                    if (q1) {
                        char *q2 = strchr(q1 + 1, '"');
                        if (q2) *q2 = '\0';
                        char tree_str[128];
                        snprintf(tree_str, sizeof(tree_str), "\n\033[93m[+] %s\033[0m\n", q1 + 1);
                        I64 tlen2 = strlen(tree_str);
                        if (d_idx + tlen2 < max_len - 1) {
                            memcpy(&dest[d_idx], tree_str, tlen2);
                            d_idx += tlen2;
                        }
                    }
                } else if (strncasecmp(tag, "LK,", 3) == 0 || strncasecmp(tag, "MA,", 3) == 0) {
                    /* Link / Macro tag: $LK,"Label",...$ */
                    char *q1 = strchr(tag + 3, '"');
                    if (q1) {
                        char *q2 = strchr(q1 + 1, '"');
                        if (q2) *q2 = '\0';
                        char link_str[128];
                        snprintf(link_str, sizeof(link_str), "\033[94m\033[4m[%s]\033[0m", q1 + 1);
                        I64 llen = strlen(link_str);
                        if (d_idx + llen < max_len - 1) {
                            memcpy(&dest[d_idx], link_str, llen);
                            d_idx += llen;
                        }
                    }
                } else if (strncasecmp(tag, "ID,", 3) == 0) {
                    /* Indentation Tag */
                    I64 id_val = atoi(tag + 3);
                    indent_level += id_val;
                    if (indent_level < 0) indent_level = 0;
                    if (indent_level > 8) indent_level = 8;
                }
                continue;
            }
        }

        /* Copy regular character */
        if (src[s_idx] == '\n') {
            dest[d_idx++] = '\n';
            s_idx++;
            /* Apply indent */
            for (I64 k = 0; k < indent_level * 2 && d_idx < max_len - 1; ++k) {
                dest[d_idx++] = ' ';
            }
            continue;
        }

        dest[d_idx++] = src[s_idx++];
    }

    /* Reset terminal styles at end of document */
    const char *reset_ansi = "\033[0m";
    I64 rlen = strlen(reset_ansi);
    if (d_idx + rlen < max_len - 1) {
        memcpy(&dest[d_idx], reset_ansi, rlen);
        d_idx += rlen;
    }

    dest[d_idx] = '\0';
    return d_idx;
}

#endif /* DOLDOC_HC */
