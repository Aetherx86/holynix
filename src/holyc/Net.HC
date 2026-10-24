/*
 * HolyC Unix Kernel - Simulated Network Subsystem & ICMP Diagnostics (Net.HC)
 * Virtual network interfaces (lo, eth0), network statistics, socket monitors,
 * and ICMP ping diagnostics.
 */

#ifndef NET_HC
#define NET_HC

#include "Types.HC"

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

#endif /* NET_HC */
