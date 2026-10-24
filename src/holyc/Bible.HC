/*
 * HolyC Unix Kernel - King James Bible Concordance & Divine Scripture Oracle (Bible.HC)
 * Embedded scripture passages from the King James Version (KJV)
 * providing text search, book/chapter/verse lookup, and random divine oracle passages.
 *
 * "The Bible is the word of God. God's official temple is 640x480 16 color." - Terry A. Davis
 */

#ifndef BIBLE_HC
#define BIBLE_HC

#include "Types.HC"

class CBibleVerse {
    const char *book;
    I64 chapter;
    I64 verse;
    const char *text;
};

static const CBibleVerse g_bible_verses[] = {
    {"Genesis", 1, 1, "In the beginning God created the heaven and the earth."},
    {"Genesis", 1, 2, "And the earth was without form, and void; and darkness was upon the face of the deep. And the Spirit of God moved upon the face of the waters."},
    {"Genesis", 1, 3, "And God said, Let there be light: and there was light."},
    {"Genesis", 1, 4, "And God saw the light, that it was good: and God divided the light from the darkness."},
    {"Genesis", 1, 31, "And God saw every thing that he had made, and, behold, it was very good."},
    {"Exodus", 20, 2, "I am the LORD thy God, which have brought thee out of the land of Egypt, out of the house of bondage."},
    {"Exodus", 20, 3, "Thou shalt have no other gods before me."},
    {"Exodus", 20, 8, "Remember the sabbath day, to keep it holy."},
    {"1 Samuel", 16, 7, "For the LORD seeth not as man seeth; for man looketh on the outward appearance, but the LORD looketh on the heart."},
    {"1 Kings", 19, 12, "And after the earthquake a fire; but the LORD was not in the fire: and after the fire a still small voice."},
    {"Job", 38, 4, "Where wast thou when I laid the foundations of the earth? declare, if thou hast understanding."},
    {"Psalm", 19, 1, "The heavens declare the glory of God; and the firmament sheweth his handywork."},
    {"Psalm", 23, 1, "The LORD is my shepherd; I shall not want."},
    {"Psalm", 23, 2, "He maketh me to lie down in green pastures: he leadeth me beside the still waters."},
    {"Psalm", 23, 4, "Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me."},
    {"Psalm", 91, 1, "He that dwelleth in the secret place of the most High shall abide under the shadow of the Almighty."},
    {"Psalm", 119, 105, "Thy word is a lamp unto my feet, and a light unto my path."},
    {"Proverbs", 3, 5, "Trust in the LORD with all thine heart; and lean not unto thine own understanding."},
    {"Proverbs", 3, 6, "In all thy ways acknowledge him, and he shall direct thy paths."},
    {"Proverbs", 16, 3, "Commit thy works unto the LORD, and thy thoughts shall be established."},
    {"Ecclesiastes", 3, 1, "To every thing there is a season, and a time to every purpose under the heaven:"},
    {"Ecclesiastes", 3, 11, "He hath made every thing beautiful in his time:"},
    {"Isaiah", 40, 31, "But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint."},
    {"Micah", 6, 8, "He hath shewed thee, O man, what is good; and what doth the LORD require of thee, but to do justly, and to love mercy, and to walk humbly with thy God?"},
    {"Matthew", 5, 3, "Blessed are the poor in spirit: for theirs is the kingdom of heaven."},
    {"Matthew", 5, 14, "Ye are the light of the world. A city that is set on an hill cannot be hid."},
    {"Matthew", 6, 9, "After this manner therefore pray ye: Our Father which art in heaven, Hallowed be thy name."},
    {"Matthew", 6, 33, "But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you."},
    {"John", 1, 1, "In the beginning was the Word, and the Word was with God, and the Word was God."},
    {"John", 1, 5, "And the light shineth in darkness; and the darkness comprehended it not."},
    {"John", 3, 16, "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."},
    {"John", 14, 6, "Jesus saith unto him, I am the way, the truth, and the life: no man cometh unto the Father, but by me."},
    {"Romans", 8, 28, "And we know that all things work together for good to them that love God, to them who are the called according to his purpose."},
    {"1 Corinthians", 13, 13, "And now abideth faith, hope, charity, these three; but the greatest of these is charity."},
    {"Philippians", 4, 13, "I can do all things through Christ which strengtheneth me."},
    {"Revelation", 21, 4, "And God shall wipe away all tears from their eyes; and there shall be no more death, neither sorrow, nor crying, neither shall there be any more pain:"},
    {"Revelation", 22, 13, "I am Alpha and Omega, the beginning and the end, the first and the last."}
};

static const I64 g_bible_verse_count = sizeof(g_bible_verses) / sizeof(g_bible_verses[0]);

/* Lookup a verse by Book name, Chapter, and Verse */
const CBibleVerse *BibleLookup(const char *book, I64 chapter, I64 verse) {
    if (!book) return NULL;
    for (I64 i = 0; i < g_bible_verse_count; ++i) {
        if (strcasecmp(g_bible_verses[i].book, book) == 0 &&
            (chapter <= 0 || g_bible_verses[i].chapter == chapter) &&
            (verse <= 0 || g_bible_verses[i].verse == verse)) {
            return &g_bible_verses[i];
        }
    }
    return NULL;
}

/* Pick a random divine scripture passage using entropy */
const CBibleVerse *BibleGodPassage() {
    I64 idx = (I64)(RandU64() % (U64)g_bible_verse_count);
    return &g_bible_verses[idx];
}

/* Full-text keyword search across scriptures */
I64 BibleSearch(const char *query, char *out_buf, I64 max_len) {
    if (!query || !out_buf || max_len <= 0) return 0;

    I64 count = 0;
    I64 offset = 0;
    out_buf[0] = '\0';

    for (I64 i = 0; i < g_bible_verse_count; ++i) {
        if (strcasestr(g_bible_verses[i].text, query) != NULL ||
            strcasestr(g_bible_verses[i].book, query) != NULL) {
            count++;
            offset += snprintf(out_buf + offset, max_len - offset,
                               "\033[93m[%s %lld:%lld]\033[0m %s\n",
                               g_bible_verses[i].book,
                               (long long)g_bible_verses[i].chapter,
                               (long long)g_bible_verses[i].verse,
                               g_bible_verses[i].text);
            if (offset >= max_len - 256) break;
        }
    }

    return count;
}

#endif /* BIBLE_HC */
