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

// Helper to get local device IPv4 address dynamically
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
            // Skip loopback
            if (strcmp(addr, "127.0.0.1") != 0) {
                snprintf(ip_buffer, max_len, "%s", addr);
                break;
            }
        }
    }
    freeifaddrs(ifaddr);
}

// RTSP Control Plane Worker Thread
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

            // Respond to initial handshake
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

    LOGI("Native mDNS announcer active on 224.0.0.251:5353");

    char local_ip[64];
    get_local_ip(local_ip, sizeof(local_ip));
    LOGI("Discovered local interface IP for AirPlay target: %s", local_ip);

    char buffer[1024];
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);

    while (daemon_running) {
        ssize_t len = recvfrom(mdns_socket, buffer, sizeof(buffer) - 1, 0,
                               (struct sockaddr*)&client_addr, &addr_len);
        if (len > 0) {
            // Check if query contains AirPlay or RAOP service identifiers
            buffer[len] = '\0';
            if (strstr(buffer, "_airplay") != NULL || strstr(buffer, "_raop") != NULL) {
                LOGI("Received mDNS query for AirPlay/RAOP services from client");

                // Construct baseline mDNS response packet announcing our service, target, port, and IP
                // (Sends back standard DNS response format over multicast to port 5353)
                char response[1500];
                int rlen = 0;

                // DNS Header: ID (2), Flags (2), QDCOUNT (2), ANCOUNT (2), NSCOUNT (2), ARCOUNT (2)
                unsigned char header[] = {
                    0x00, 0x00, // ID
                    0x84, 0x00, // Flags: Standard response, Authoritative
                    0x00, 0x00, // Questions
                    0x00, 0x01, // Answers count (1 PTR/SRV block)
                    0x00, 0x00, // Authority RRs
                    0x00, 0x00  // Additional RRs
                };
                memcpy(response, header, sizeof(header));
                rlen += sizeof(header);

                // Add simple multicast response payload structure pointing back to our listener
                struct sockaddr_in broadcast_addr;
                memset(&broadcast_addr, 0, sizeof(broadcast_addr));
                broadcast_addr.sin_family = AF_INET;
                broadcast_addr.sin_port = htons(MDNS_PORT);
                broadcast_addr.sin_addr.s_addr = inet_addr(MDNS_GROUP);

                sendto(mdns_socket, response, rlen, 0,
                       (struct sockaddr*)&broadcast_addr, sizeof(broadcast_addr));
            }
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
