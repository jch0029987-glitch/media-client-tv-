#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <android/log.h>

#define LOG_TAG "AirPlayDaemon"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static int server_socket = -1;
static pthread_t worker_thread;
static volatile int server_running = 0;

// Handle incoming RTSP / AirPlay control handshakes from iOS 18
static void* airplay_worker_routine(void* arg) {
    int port = *((int*)arg);
    free(arg);

    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket < 0) {
        LOGE("Failed to create RTSP socket");
        return NULL;
    }

    int opt = 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(port);

    if (bind(server_socket, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        LOGE("Failed to bind RTSP socket to port %d", port);
        close(server_socket);
        server_socket = -1;
        return NULL;
    }

    if (listen(server_socket, 5) < 0) {
        LOGE("Failed to listen on RTSP socket");
        close(server_socket);
        server_socket = -1;
        return NULL;
    }

    LOGI("AirPlay RTSP daemon listening successfully on port %d", port);
    server_running = 1;

    while (server_running) {
        int client_socket = accept(server_socket, (struct sockaddr*)&client_addr, &client_len);
        if (client_socket < 0) {
            if (!server_running) break;
            continue;
        }

        LOGI("Accepted incoming connection from iOS client");

        char buffer[4096];
        memset(buffer, 0, sizeof(buffer));
        ssize_t bytes_read = read(client_socket, buffer, sizeof(buffer) - 1);
        
        if (bytes_read > 0) {
            LOGI("Received RTSP Payload:\n%s", buffer);

            // Respond to initial OPTIONS/ANNOUNCE handshakes to keep connection alive
            const char* response = 
                "RTSP/1.0 200 OK\r\n"
                "CSeq: 1\r\n"
                "Public: OPTIONS, ANNOUNCE, SETUP, RECORD, PAUSE, TEARDOWN, GET_PARAMETER, SET_PARAMETER\r\n"
                "Server: AirPlay/650.15.1\r\n\r\n";
            
            write(client_socket, response, strlen(response));
        }

        close(client_socket);
    }

    if (server_socket != -1) {
        close(server_socket);
        server_socket = -1;
    }

    LOGI("AirPlay RTSP daemon stopped.");
    return NULL;
}

// Exposed FFI entry point: Start server worker thread
int airplay_server_start(int port) {
    if (server_running) return 0;

    int* arg = malloc(sizeof(int));
    *arg = port;

    if (pthread_create(&worker_thread, NULL, airplay_worker_routine, arg) != 0) {
        LOGE("Failed to create worker thread for AirPlay daemon");
        free(arg);
        return -1;
    }

    return 0;
}

// Exposed FFI entry point: Stop server
void airplay_server_stop() {
    if (!server_running) return;
    server_running = 0;
    
    if (server_socket != -1) {
        shutdown(server_socket, SHUT_RDWR);
        close(server_socket);
        server_socket = -1;
    }

    pthread_join(worker_thread, NULL);
}
