#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <android/log.h>

#define LOG_TAG "AirPlayDaemon"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define MDNS_GROUP "224.0.0.251"
#define MDNS_PORT 5353

static int rtsp_socket = -1;
static int mdns_socket = -1;
static pthread_t rtsp_thread;
static pthread_t mdns_thread;
static volatile int daemon_running = 0;
static int server_port = 7000;
static char local_device_ip[64] = "127.0.0.1";

// Helper to get local device IPv4 address dynamically from the active interface
static void get_local_ip(char* ip_buffer, size_t max_len) {
    struct ifaddrs *ifaddr, *ifa;
    if (getifaddrs(&ifaddr) == -1) {
        snprintf(ip_buffer, max_len, "127.0.0.1");
        return;
    }
    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
        if (ifa->ifa_addr->sa_family == AF_INET) {
            struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
            char *addr = inet_ntoa(sa->sin_addr);
            // Skip loopback and point-to-point tunnel interfaces like Tailscale if present
            if (strcmp(addr, "127.0.0.1") != 0 && strncmp(addr, "100.", 4) != 0) {
                snprintf(ip_buffer, max_len, "%s", addr);
                break;
            }
        }
    }
    freeifaddrs(ifaddr);
}

// Appends a DNS name label encoded in length-prefixed format (e.g. "local" -> "\x05local\x00")
static int encode_dns_name(unsigned char* buffer, int offset, const char* domain) {
    int start = offset;
    char temp[256];
    strncpy(temp, domain, sizeof(temp));
    char* token = strtok(temp, ".");
    while (token != NULL) {
        int len = strlen(token);
        buffer[offset++] = (unsigned char)len;
        memcpy(buffer + offset, token, len);
        offset += len;
        token = strtok(NULL, ".");
    }
    buffer[offset++] = 0x00; // Null terminator for root
    return offset - start;
}

// Build standard mDNS response packet containing PTR, SRV, TXT, and A records
static int build_mdns_response(unsigned char* pkt, const char* ip_str, int port) {
    int offset = 0;

    // 1. DNS Header
    // ID (2), Flags: Standard response, Authoritative (2), QDCOUNT (2), ANCOUNT (4 answers: PTR, SRV, TXT, A)
    unsigned char header[] = {
        0x00, 0x00, // ID
        0x84, 0x00, // Flags
        0x00, 0x00, // QDCOUNT
        0x00, 0x04  // ANCOUNT (4 resource records)
    };
    memcpy(pkt + offset, header, sizeof(header));
    offset += sizeof(header);

    // --- Answer 1: PTR Record (_airplay._tcp.local) ---
    offset += encode_dns_name(pkt, offset, "_airplay._tcp.local");
    pkt[offset++] = 0x00; pkt[offset++] = 0x0c; // Type: PTR (12)
    pkt[offset++] = 0x80; pkt[offset++] = 0x01; // Class: IN with cache flush
    pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x78; // TTL: 120s
    
    int rdlen_pos_1 = offset;
    offset += 2;
    int ptr_rdata_start = offset;
    offset += encode_dns_name(pkt, offset, "MediaClientTV._airplay._tcp.local");
    int ptr_rdata_len = offset - ptr_rdata_start;
    pkt[rdlen_pos_1] = (ptr_rdata_len >> 8) & 0xFF;
    pkt[rdlen_pos_1 + 1] = ptr_rdata_len & 0xFF;

    // --- Answer 2: SRV Record (Target host details & port) ---
    offset += encode_dns_name(pkt, offset, "MediaClientTV._airplay._tcp.local");
    pkt[offset++] = 0x00; pkt[offset++] = 0x21; // Type: SRV (33)
    pkt[offset++] = 0x80; pkt[offset++] = 0x01; // Class: IN with cache flush
    pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x78; // TTL
    
    int rdlen_pos_2 = offset;
    offset += 2;
    int srv_rdata_start = offset;
    pkt[offset++] = 0x00; pkt[offset++] = 0x00; // Priority: 0
    pkt[offset++] = 0x00; pkt[offset++] = 0x00; // Weight: 0
    pkt[offset++] = (port >> 8) & 0xFF; pkt[offset++] = port & 0xFF; // Port
    offset += encode_dns_name(pkt, offset, "mediaclienttv.local"); // Target host name
    int srv_rdata_len = offset - srv_rdata_start;
    pkt[rdlen_pos_2] = (srv_rdata_len >> 8) & 0xFF;
    pkt[rdlen_pos_2 + 1] = srv_rdata_len & 0xFF;

    // --- Answer 3: TXT Record (Apple AirPlay Feature Flags & metadata) ---
    offset += encode_dns_name(pkt, offset, "MediaClientTV._airplay._tcp.local");
    pkt[offset++] = 0x00; pkt[offset++] = 0x10; // Type: TXT (16)
    pkt[offset++] = 0x80; pkt[offset++] = 0x01; // Class: IN with cache flush
    pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x78; // TTL

    int rdlen_pos_3 = offset;
    offset += 2;
    int txt_rdata_start = offset;

    // TXT record entries (Length-prefixed key=value strings required by iOS)
    const char* txt_entries[] = {
        "deviceid=AA:BB:CC:DD:EE:FF",
        "features=0x5a7ffff7,0x1e7",
        "model=AppleTV3,2",
        "pk=d41d8cd98f00b204e9800998ecf8427e",
        "vv=2"
    };
    for (int i = 0; i < 5; i++) {
        int len = strlen(txt_entries[i]);
        pkt[offset++] = (unsigned char)len;
        memcpy(pkt + offset, txt_entries[i], len);
        offset += len;
    }
    int txt_rdata_len = offset - txt_rdata_start;
    pkt[rdlen_pos_3] = (txt_rdata_len >> 8) & 0xFF;
    pkt[rdlen_pos_3 + 1] = txt_rdata_len & 0xFF;

    // --- Answer 4: A Record (IPv4 Address mapping for mediaclienttv.local) ---
    offset += encode_dns_name(pkt, offset, "mediaclienttv.local");
    pkt[offset++] = 0x00; pkt[offset++] = 0x01; // Type: A (1)
    pkt[offset++] = 0x80; pkt[offset++] = 0x01; // Class: IN with cache flush
    pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x00; pkt[offset++] = 0x78; // TTL
    
    pkt[offset++] = 0x00; pkt[offset++] = 0x04; // RDLENGTH: 4 bytes for IPv4
    in_addr_t ip_addr = inet_addr(ip_str);
    memcpy(pkt + offset, &ip_addr, 4);
    offset += 4;

    return offset;
}

// RTSP Control Plane Worker Thread (Handles Apple AirPlay Protocol handshakes)
static void* rtsp_worker_routine(void* arg) {
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    rtsp_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (rtsp_socket < 0) {
        LOGE("Failed to create RTSP socket");
        return NULL;
    }

    int opt = 1;
    setsockopt(rtsp_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(server_port);

    if (bind(rtsp_socket, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        LOGE("Failed to bind RTSP socket to port %d", server_port);
        close(rtsp_socket);
        rtsp_socket = -1;
        return NULL;
    }

    if (listen(rtsp_socket, 5) < 0) {
        LOGE("Failed to listen on RTSP socket");
        close(rtsp_socket);
        rtsp_socket = -1;
        return NULL;
    }

    LOGI("AirPlay RTSP daemon listening on port %d", server_port);

    while (daemon_running) {
        int client_socket = accept(rtsp_socket, (struct sockaddr*)&client_addr, &client_len);
        if (client_socket < 0) {
            if (!daemon_running) break;
            continue;
        }

        LOGI("Accepted incoming RTSP connection from iOS client");

        char buffer[4096];
        memset(buffer, 0, sizeof(buffer));
        ssize_t bytes_read = read(client_socket, buffer, sizeof(buffer) - 1);
        
        if (bytes_read > 0) {
            LOGI("Received RTSP Payload:\n%s", buffer);

            // Respond to initial Apple AirPlay RTSP handshake
            const char* response = 
                "RTSP/1.0 200 OK\r\n"
                "CSeq: 1\r\n"
                "Public: OPTIONS, ANNOUNCE, SETUP, RECORD, PAUSE, TEARDOWN, GET_PARAMETER, SET_PARAMETER\r\n"
                "Server: AirPlay/650.15.1\r\n\r\n";
            
            write(client_socket, response, strlen(response));
        }

        close(client_socket);
    }

    if (rtsp_socket != -1) {
        close(rtsp_socket);
        rtsp_socket = -1;
    }
    return NULL;
}

// Native mDNS Multicast Announcer & Responder Thread
static void* mdns_worker_routine(void* arg) {
    struct sockaddr_in saddr;
    struct ip_mreq mreq;

    mdns_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (mdns_socket < 0) {
        LOGE("Failed to create mDNS UDP socket");
        return NULL;
    }

    int reuse = 1;
    setsockopt(mdns_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
#ifdef SO_REUSEPORT
    setsockopt(mdns_socket, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse));
#endif

    memset(&saddr, 0, sizeof(saddr));
    saddr.sin_family = AF_INET;
    saddr.sin_port = htons(MDNS_PORT);
    saddr.sin_addr.s_addr = INADDR_ANY;

    if (bind(mdns_socket, (struct sockaddr*)&saddr, sizeof(saddr)) < 0) {
        LOGE("Failed to bind mDNS socket to port 5353");
        close(mdns_socket);
        mdns_socket = -1;
        return NULL;
    }

    // Join multicast group 224.0.0.251
    mreq.imr_multiaddr.s_addr = inet_addr(MDNS_GROUP);
    mreq.imr_interface.s_addr = htonl(INADDR_ANY);
    if (setsockopt(mdns_socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, sizeof(mreq)) < 0) {
        LOGE("Failed to join mDNS multicast group");
    }

    get_local_ip(local_device_ip, sizeof(local_device_ip));
    LOGI("Native mDNS announcer active on 224.0.0.251:5353. Local IP: %s", local_device_ip);

    // Setup broadcast address destination for mDNS responses
    struct sockaddr_in broadcast_addr;
    memset(&broadcast_addr, 0, sizeof(broadcast_addr));
    broadcast_addr.sin_family = AF_INET;
    broadcast_addr.sin_port = htons(MDNS_PORT);
    broadcast_addr.sin_addr.s_addr = inet_addr(MDNS_GROUP);

    // Send initial unsolicited announcement packet immediately so iOS detects it on startup
    unsigned char ann_pkt[1024];
    int ann_len = build_mdns_response(ann_pkt, local_device_ip, server_port);
    sendto(mdns_socket, ann_pkt, ann_len, 0, (struct sockaddr*)&broadcast_addr, sizeof(broadcast_addr));

    char buffer[1024];
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);

    // Set receive timeout so we can periodically push keep-alive announcements
    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    setsockopt(mdns_socket, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));

    while (daemon_running) {
        ssize_t len = recvfrom(mdns_socket, buffer, sizeof(buffer) - 1, 0,
                               (struct sockaddr*)&client_addr, &addr_len);
        if (len > 0) {
            buffer[len] = '\0';
            // If an iOS device queries for AirPlay or RAOP services, reply with our full mDNS record set
            if (strstr(buffer, "_airplay") != NULL || strstr(buffer, "_raop") != NULL || client_addr.sin_port != 0) {
                LOGI("Received mDNS query from client, sending AirPlay service response");
                unsigned char resp_pkt[1024];
                int resp_len = build_mdns_response(resp_pkt, local_device_ip, server_port);
                sendto(mdns_socket, resp_pkt, resp_len, 0, (struct sockaddr*)&broadcast_addr, sizeof(broadcast_addr));
            }
        } else {
            // Periodic keep-alive announcement broadcast
            unsigned char keep_pkt[1024];
            int keep_len = build_mdns_response(keep_pkt, local_device_ip, server_port);
            sendto(mdns_socket, keep_pkt, keep_len, 0, (struct sockaddr*)&broadcast_addr, sizeof(broadcast_addr));
        }
    }

    if (mdns_socket != -1) {
        close(mdns_socket);
        mdns_socket = -1;
    }
    return NULL;
}

// Exposed FFI: Start daemon services
int airplay_server_start(int port) {
    if (daemon_running) return 0;
    server_port = port;
    daemon_running = 1;

    if (pthread_create(&rtsp_thread, NULL, rtsp_worker_routine, NULL) != 0) {
        LOGE("Failed to start RTSP thread");
        daemon_running = 0;
        return -1;
    }

    if (pthread_create(&mdns_thread, NULL, mdns_worker_routine, NULL) != 0) {
        LOGE("Failed to start mDNS thread");
        daemon_running = 0;
        return -1;
    }

    return 0;
}

// Exposed FFI: Stop daemon services
void airplay_server_stop() {
    if (!daemon_running) return;
    daemon_running = 0;

    if (rtsp_socket != -1) {
        shutdown(rtsp_socket, SHUT_RDWR);
        close(rtsp_socket);
        rtsp_socket = -1;
    }
    if (mdns_socket != -1) {
        shutdown(mdns_socket, SHUT_RDWR);
        close(mdns_socket);
        mdns_socket = -1;
    }

    pthread_join(rtsp_thread, NULL);
    pthread_join(mdns_thread, NULL);
    LOGI("AirPlay daemon fully stopped.");
}
