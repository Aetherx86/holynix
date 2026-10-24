/*
 * HolyC Unix Kernel - Simulated Network Subsystem & ICMP Diagnostics (Net.HC)
 * Virtual network interfaces (lo, eth0), network statistics, socket monitors,
 * ICMP ping diagnostics, and HTTP client (curl / fetch).
 */

#ifndef NET_HC
#define NET_HC

#include "Types.HC"
#include "VFS.HC"
#include "GodWords.HC"

#define CURL_FLAG_VERBOSE   0x01
#define CURL_FLAG_HEAD_ONLY 0x02
#define CURL_FLAG_SILENT    0x04

class CNetInterface {
    char name[16];
    char ip[16];
    char netmask[16];
    char mac[18];
    I64 rx_packets;
    I64 tx_packets;
    I64 rx_bytes;
    I64 tx_bytes;
    Bool is_up;
};

static CNetInterface g_net_ifaces[] = {
    {"lo",   "127.0.0.1",     "255.0.0.0",     "00:00:00:00:00:00", 128, 128, 8192, 8192, TRUE},
    {"eth0", "192.168.1.77",  "255.255.255.0", "52:54:00:12:34:56", 1024, 896, 65536, 49152, TRUE}
};

static const I64 g_net_iface_count = sizeof(g_net_ifaces) / sizeof(g_net_ifaces[0]);

/* Execute simulated ICMP ping */
I64 NetPing(const char *target, I64 count, char *out_buf, I64 max_len) {
    if (!target || !out_buf || max_len <= 0) return -1;
    if (count <= 0) count = 4;
    if (count > 10) count = 10;

    const char *resolved_ip = target;
    if (strcmp(target, "localhost") == 0) resolved_ip = "127.0.0.1";
    else if (strcmp(target, "god.templeos.org") == 0 || strcmp(target, "templeos.org") == 0) resolved_ip = "77.77.77.77";

    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "PING %s (%s): 56 data bytes\n", target, resolved_ip);

    F64 total_time = 0.0;
    F64 min_time = 999.0;
    F64 max_time = 0.0;

    for (I64 seq = 1; seq <= count; ++seq) {
        F64 rtt = 0.035 + (F64)(RandU64() % 40) / 1000.0;
        if (strcmp(resolved_ip, "127.0.0.1") != 0) {
            rtt = 1.2 + (F64)(RandU64() % 800) / 100.0;
        }

        if (rtt < min_time) min_time = rtt;
        if (rtt > max_time) max_time = rtt;
        total_time += rtt;

        offset += snprintf(out_buf + offset, max_len - offset,
            "64 bytes from %s: icmp_seq=%lld ttl=64 time=%.3f ms\n",
            resolved_ip, (long long)seq, rtt);

        if (offset >= max_len - 256) break;
    }

    F64 avg_time = total_time / (F64)count;
    offset += snprintf(out_buf + offset, max_len - offset,
        "\n--- %s ping statistics ---\n"
        "%lld packets transmitted, %lld packets received, 0.0%% packet loss\n"
        "round-trip min/avg/max = %.3f/%.3f/%.3f ms\n",
        target, (long long)count, (long long)count, min_time, avg_time, max_time);

    return offset;
}

/* Dump network interfaces and active sockets */
I64 NetStat(char *out_buf, I64 max_len) {
    if (!out_buf || max_len <= 0) return -1;

    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "\033[93mKernel Interface Table\033[0m\n"
        "Iface   MTU  RX-OK  RX-ERR  RX-DRP  TX-OK  TX-ERR  TX-DRP Flags\n"
        "---------------------------------------------------------------\n");

    for (I64 i = 0; i < g_net_iface_count; ++i) {
        offset += snprintf(out_buf + offset, max_len - offset,
            "%-6s %5d %6lld       0       0 %6lld       0       0 %s\n",
            g_net_ifaces[i].name,
            (strcmp(g_net_ifaces[i].name, "lo") == 0) ? 65536 : 1500,
            (long long)g_net_ifaces[i].rx_packets,
            (long long)g_net_ifaces[i].tx_packets,
            g_net_ifaces[i].is_up ? "UP LOOPBACK RUNNING" : "DOWN");
    }

    offset += snprintf(out_buf + offset, max_len - offset,
        "\n\033[93mActive Internet connections (servers and established)\033[0m\n"
        "Proto Recv-Q Send-Q Local Address           Foreign Address         State\n"
        "tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN\n"
        "tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN\n"
        "tcp        0      0 0.0.0.0:7777            0.0.0.0:*               LISTEN (God-Oracle)\n"
        "tcp        0      0 127.0.0.1:7777          127.0.0.1:54321         ESTABLISHED\n");

    return offset;
}

/*
 * HTTP Network Client (curl / fetch)
 */
I64 NetCurl(const char *url, I64 flags, const char *outfile, char *out_buf, I64 max_len) {
    if (!url || !out_buf || max_len <= 0) return -1;

    char host[128] = "localhost";
    char path[128] = "/";
    int port = 80;

    /* Parse URL */
    const char *p = url;
    if (strncmp(p, "http://", 7) == 0) p += 7;
    else if (strncmp(p, "https://", 8) == 0) { p += 8; port = 443; }

    const char *slash = strchr(p, '/');
    if (slash) {
        size_t hlen = slash - p;
        if (hlen > 127) hlen = 127;
        strncpy(host, p, hlen);
        host[hlen] = '\0';
        strncpy(path, slash, sizeof(path) - 1);
        path[sizeof(path) - 1] = '\0';
    } else {
        strncpy(host, p, sizeof(host) - 1);
        host[sizeof(host) - 1] = '\0';
    }

    char *colon = strchr(host, ':');
    if (colon) {
        *colon = '\0';
        port = atoi(colon + 1);
    }

    /* Generate HTTP response content based on target host/path */
    char body[1024];
    const char *content_type = "text/plain";

    if (strstr(host, "god") != NULL || strstr(path, "god") != NULL || strstr(path, "verse") != NULL) {
        /* Divine oracle endpoint */
        char words[128];
        words[0] = '\0';
        for (int w = 0; w < 6; ++w) {
            strncat(words, (const char*)GodGetWord(), sizeof(words) - strlen(words) - 2);
            if (w + 1 < 6) strncat(words, " ", sizeof(words) - strlen(words) - 1);
        }
        snprintf(body, sizeof(body), "God Oracle Response:\n%s\n", words);
    } else if (strstr(path, "packages") != NULL || strstr(host, "hpm") != NULL) {
        snprintf(body, sizeof(body),
            "Holy Package Repository Manifest (v1.0):\n"
            "- castle (3D Labyrinth Raycaster)\n"
            "- afteregypt (Moses Sinai Quest)\n"
            "- flappy (TempleOS Bird Physics)\n"
            "- bible (KJV Scripture Search)\n");
    } else if (strstr(path, "version") != NULL || strcmp(path, "/version") == 0) {
        snprintf(body, sizeof(body), "HolyC-Unix Kernel 1.0.0 (Terry Davis Memorial Edition x86_64)\n");
    } else {
        snprintf(body, sizeof(body),
            "<!DOCTYPE html>\n<html>\n<head><title>HolyC Unix Web</title></head>\n"
            "<body><h1>Welcome to HolyC Unix HTTP Server</h1>\n"
            "<p>Host: %s:%d | Path: %s</p>\n"
            "<p>\"Simplicity is divine.\" - Terry A. Davis</p>\n</body>\n</html>\n",
            host, port, path);
        content_type = "text/html";
    }

    size_t body_len = strlen(body);
    I64 offset = 0;

    if (flags & (CURL_FLAG_VERBOSE | CURL_FLAG_HEAD_ONLY)) {
        offset += snprintf(out_buf + offset, max_len - offset,
            "HTTP/1.1 200 OK\r\n"
            "Date: Sat, 24 Oct 2026 12:00:00 GMT\r\n"
            "Server: HolyNix-HTTP/1.0 (Terry Davis Edition)\r\n"
            "Content-Type: %s\r\n"
            "Content-Length: %zu\r\n"
            "Connection: close\r\n\r\n",
            content_type, body_len);
    }

    if (!(flags & CURL_FLAG_HEAD_ONLY)) {
        offset += snprintf(out_buf + offset, max_len - offset, "%s", body);
    }

    /* Save to VFS file if requested */
    if (outfile && outfile[0] != '\0') {
        VFSCreateFile(outfile, "/", (const U8*)body, (I64)body_len);
    }

    return offset;
}

#endif /* NET_HC */
