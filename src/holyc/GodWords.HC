/*
 * HolyC Unix Kernel - TempleOS God Oracle Dictionary (GodWords.HC)
 * "God says: ... A genuine 64-bit TempleOS divine oracle." - Terry A. Davis
 */

#ifndef GODWORDS_HC
#define GODWORDS_HC

#include "Types.HC"

/* Authentic TempleOS Divine Vocabulary Sample */
static const U8 *g_god_words[] = {
    "prophet", "tabernacle", "righteousness", "covenant", "chariot",
    "psalm", "cherubim", "sanctuary", "firmament", "anoint",
    "rejoice", "altar", "glory", "behold", "faith",
    "ark", "cloud", "commandment", "elect", "providence",
    "wisdom", "trinity", "seraphim", "everlasting", "amen",
    "grace", "hosanna", "hallelujah", "salvation", "blessing",
    "epistle", "disciple", "apostle", "gospel", "parable",
    "redeemer", "temple", "revelation", "testament", "genesis",
    "exodus", "zion", "jerusalem", "sinai", "manna",
    "mercy", "peace", "light", "living", "water",
    "bread", "spirit", "holy", "infinite", "celestial",
    "eternal", "divine", "voice", "heaven", "stars",
    "firmament", "throne", "crown", "scepter", "majesty",
    "praise", "worship", "shepherd", "pasture", "flock",
    "alpha", "omega", "first", "last", "beginning",
    "lamb", "lion", "judah", "olive", "branch",
    "vine", "vineyard", "harvest", "dew", "morning",
    "counsel", "judgment", "truth", "justice", "habitation",
    "covenant", "statute", "ordinance", "testimony", "precept",
    "compassion", "kindness", "gentleness", "patience", "longsuffering",
    "simplicity", "purity", "innocence", "unsearchable", "marvelous",
    "omnipotent", "omnipresent", "omniscient", "sovereign", "hallowed"
};

#define GOD_WORDS_COUNT ((I64)(sizeof(g_god_words) / sizeof(g_god_words[0])))

const U8 *GodGetWord() {
    I64 idx = RandRange(0, GOD_WORDS_COUNT - 1);
    return g_god_words[idx];
}

U0 GodSpeak(I64 count) {
    if (count <= 0) count = 7;
    "God says: \033[93m";
    for (I64 i = 0; i < count; ++i) {
        "%s%s", GodGetWord(), (i + 1 < count) ? " " : "";
    }
    "\033[0m\n";
}

I64 GodStreamRead(U8 *buf, I64 count) {
    if (!buf || count <= 0) return 0;
    I64 written = 0;
    while (written < count) {
        const U8 *w = GodGetWord();
        I64 wlen = StrLen(w);
        for (I64 i = 0; i < wlen && written < count; ++i) {
            buf[written++] = w[i];
        }
        if (written < count) {
            buf[written++] = ' ';
        }
    }
    return written;
}

#endif /* GODWORDS_HC */
