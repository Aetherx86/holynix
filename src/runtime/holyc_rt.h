/*
 * HolyC Runtime Support Library (holyc_rt.h)
 * Provides HolyC primitive types, memory management, string utilities,
 * and POSIX platform integration for the HolyC Unix Kernel.
 *
 * "An idiot admires complexity, a genius admires simplicity." - Terry A. Davis
 */

#ifndef HOLYC_RT_H
#define HOLYC_RT_H

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>
#include <ctype.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <signal.h>

/* Undefine glibc stat time macros so they do not conflict with HolyC struct fields */
#ifdef st_atime
#undef st_atime
#endif
#ifdef st_mtime
#undef st_mtime
#endif
#ifdef st_ctime
#undef st_ctime
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
 * HolyC Primitive Data Types
 * ------------------------------------------------------------------------- */
typedef void            U0;
typedef int8_t          I8;
typedef uint8_t         U8;
typedef int16_t         I16;
typedef uint16_t        U16;
typedef int32_t         I32;
typedef uint32_t        U32;
typedef int64_t         I64;
typedef uint64_t        U64;
typedef double          F64;
typedef int64_t         Bool;

#ifndef TRUE
#define TRUE  1
#endif

#ifndef FALSE
#define FALSE 0
#endif

#ifndef NULL
#define NULL ((void*)0)
#endif

/* -------------------------------------------------------------------------
 * TempleOS 16-Color Palette ANSI Escape Codes
 * ------------------------------------------------------------------------- */
#define COLOR_BLACK         "\033[30m"
#define COLOR_BLUE          "\033[34m"
#define COLOR_GREEN         "\033[32m"
#define COLOR_CYAN          "\033[36m"
#define COLOR_RED           "\033[31m"
#define COLOR_PURPLE        "\033[35m"
#define COLOR_BROWN         "\033[33m"
#define COLOR_LTGRAY        "\033[37m"
#define COLOR_DKGRAY        "\033[90m"
#define COLOR_LTBLUE        "\033[94m"
#define COLOR_LTGREEN       "\033[92m"
#define COLOR_LTCYAN        "\033[96m"
#define COLOR_LTRED         "\033[91m"
#define COLOR_LTPURPLE      "\033[95m"
#define COLOR_YELLOW        "\033[93m"
#define COLOR_WHITE         "\033[97m"
#define COLOR_RESET         "\033[0m"

#define BG_BLACK            "\033[40m"
#define BG_BLUE             "\033[44m"
#define BG_GREEN            "\033[42m"
#define BG_CYAN             "\033[46m"
#define BG_RED              "\033[41m"
#define BG_PURPLE           "\033[45m"
#define BG_BROWN            "\033[43m"
#define BG_WHITE            "\033[47m"

/* -------------------------------------------------------------------------
 * Memory Allocation (HolyC MAlloc / Free)
 * ------------------------------------------------------------------------- */
static inline U0 *MAlloc(I64 size) {
    if (size <= 0) size = 1;
    U0 *ptr = malloc((size_t)size);
    if (!ptr) {
        fprintf(stderr, "[HolyC Kernel Panic] Out of Memory in MAlloc(%lld)!\n", (long long)size);
        abort();
    }
    return ptr;
}

static inline U0 *CAlloc(I64 size) {
    if (size <= 0) size = 1;
    U0 *ptr = calloc(1, (size_t)size);
    if (!ptr) {
        fprintf(stderr, "[HolyC Kernel Panic] Out of Memory in CAlloc(%lld)!\n", (long long)size);
        abort();
    }
    return ptr;
}

static inline U0 Free(U0 *ptr) {
    if (ptr) {
        free(ptr);
    }
}

static inline U0 *MemSet(U0 *dst, I64 val, I64 size) {
    if (dst && size > 0) {
        memset(dst, (int)val, (size_t)size);
    }
    return dst;
}

static inline U0 *MemCpy(U0 *dst, const U0 *src, I64 size) {
    if (dst && src && size > 0) {
        memcpy(dst, src, (size_t)size);
    }
    return dst;
}

static inline I64 MemCmp(const U0 *s1, const U0 *s2, I64 size) {
    if (!s1 || !s2 || size <= 0) return 0;
    return memcmp(s1, s2, (size_t)size);
}

/* -------------------------------------------------------------------------
 * String Handling Utilities (HolyC standard naming)
 * ------------------------------------------------------------------------- */
static inline I64 StrLen(const U8 *str) {
    if (!str) return 0;
    return (I64)strlen((const char*)str);
}

static inline I64 StrCmp(const U8 *s1, const U8 *s2) {
    if (!s1 && !s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    return (I64)strcmp((const char*)s1, (const char*)s2);
}

static inline I64 StrNCmp(const U8 *s1, const U8 *s2, I64 n) {
    if (n <= 0) return 0;
    if (!s1 && !s2) return 0;
    if (!s1) return -1;
    if (!s2) return 1;
    return (I64)strncmp((const char*)s1, (const char*)s2, (size_t)n);
}

static inline U8 *StrCpy(U8 *dst, const U8 *src) {
    if (!dst || !src) return dst;
    return (U8*)strcpy((char*)dst, (const char*)src);
}

static inline U8 *StrNCpy(U8 *dst, const U8 *src, I64 n) {
    if (!dst || !src || n <= 0) return dst;
    return (U8*)strncpy((char*)dst, (const char*)src, (size_t)n);
}

static inline U8 *StrCat(U8 *dst, const U8 *src) {
    if (!dst || !src) return dst;
    return (U8*)strcat((char*)dst, (const char*)src);
}

static inline U8 *StrNew(const U8 *src) {
    if (!src) {
        U8 *empty = (U8*)MAlloc(1);
        empty[0] = '\0';
        return empty;
    }
    I64 len = StrLen(src);
    U8 *dup = (U8*)MAlloc(len + 1);
    MemCpy(dup, src, len + 1);
    return dup;
}

static inline U8 *StrFind(const U8 *haystack, const U8 *needle) {
    if (!haystack || !needle) return NULL;
    return (U8*)strstr((const char*)haystack, (const char*)needle);
}

static inline U8 *StrChr(const U8 *s, I64 c) {
    if (!s) return NULL;
    return (U8*)strchr((const char*)s, (int)c);
}

/* -------------------------------------------------------------------------
 * Math & Randomness
 * ------------------------------------------------------------------------- */
static inline I64 Abs(I64 v) {
    return (v < 0) ? -v : v;
}

static inline I64 Min(I64 a, I64 b) {
    return (a < b) ? a : b;
}

static inline I64 Max(I64 a, I64 b) {
    return (a > b) ? a : b;
}

static inline I64 Clamp(I64 v, I64 min_val, I64 max_val) {
    if (v < min_val) return min_val;
    if (v > max_val) return max_val;
    return v;
}

static uint64_t g_holyc_rng_state = 0x853c49e6748fea9bULL;

static inline U64 RandU64(U0) {
    /* 64-bit xorshift* */
    g_holyc_rng_state ^= g_holyc_rng_state >> 12;
    g_holyc_rng_state ^= g_holyc_rng_state << 25;
    g_holyc_rng_state ^= g_holyc_rng_state >> 27;
    return g_holyc_rng_state * 0x2545F4914F6CDD1DULL;
}

static inline I64 RandRange(I64 min_val, I64 max_val) {
    if (min_val >= max_val) return min_val;
    U64 r = RandU64();
    return min_val + (I64)(r % (U64)(max_val - min_val + 1));
}

/* -------------------------------------------------------------------------
 * Time Utilities
 * ------------------------------------------------------------------------- */
static inline I64 GetTimestampMs(U0) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((I64)tv.tv_sec * 1000LL) + ((I64)tv.tv_usec / 1000LL);
}

static inline U0 SleepMs(I64 ms) {
    if (ms <= 0) return;
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000;
    nanosleep(&ts, NULL);
}

/* -------------------------------------------------------------------------
 * Console / Printing
 * ------------------------------------------------------------------------- */
static inline U0 Print(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    fflush(stdout);
}

static inline U0 PutChars(I64 ch) {
    putchar((int)ch);
    fflush(stdout);
}

#ifdef __cplusplus
}
#endif

#endif /* HOLYC_RT_H */
