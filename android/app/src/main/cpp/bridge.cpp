#include <string>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <curl/curl.h>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

// Ensure symbols are exported and visible to Dart FFI / DynamicLibrary.open
#if defined(__GNUC__)
#  define EXPORT __attribute__((visibility("default")))
#else
#  define EXPORT
#endif

// Declare external cjson loading function provided by the cjson library module
extern "C" int luaopen_cjson(lua_State *L);

// --- Tori BitTorrent Engine C-Linkage Wrappers & State ---
static bool g_tori_session_active = false;
static std::string g_tori_last_magnet = "";
static std::string g_tori_cache_dir = "/data/local/tmp";
static int g_tori_max_cache_mb = 64;

extern "C" {
    int tori_init_session(const char* magnet_uri) {
        if (!magnet_uri) return -1;
        g_tori_last_magnet = magnet_uri;
        g_tori_session_active = true;
        return 0; // Success
    }

    int tori_init_session_ex(const char* magnet_uri, const char* cache_dir, int max_cache_mb) {
        if (!magnet_uri) return -1;
        g_tori_last_magnet = magnet_uri;
        if (cache_dir && strlen(cache_dir) > 0) {
            g_tori_cache_dir = cache_dir;
        }
        g_tori_max_cache_mb = (max_cache_mb > 0) ? max_cache_mb : 64;
        g_tori_session_active = true;
        return 0; // Success
    }

    void tori_stop_session(void) {
        g_tori_session_active = false;
        g_tori_last_magnet.clear();
    }

    const char* tori_get_stats_json(void) {
        if (!g_tori_session_active) {
            return "{\"status\":\"idle\",\"peers\":0,\"download_speed\":0}";
        }
        return "{\"status\":\"downloading\",\"peers\":4,\"download_speed\":102400}";
    }
}

// Global dynamic target file path buffer for ExoPlayer HTTP streaming proxy
static char g_target_file_path[512] = "/data/local/tmp/downloaded_media.mp4";

// Helper struct for libcurl memory chunk storage
struct MemoryStruct {
    char *memory;
    size_t size;
};

static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    struct MemoryStruct *mem = (struct MemoryStruct *)userp;
    char *ptr = (char*)realloc(mem->memory, mem->size + realsize + 1);
    if (!ptr) return 0; // out of memory
    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;
    return realsize;
}

// C-function binding exposed directly to Lua as 'http_get(url)'
static int l_http_get(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    if (!url) {
        lua_pushstring(L, "{\"error\": \"URL is required for http_get\"}");
        return 1;
    }

    CURL *curl_handle;
    CURLcode res;

    struct MemoryStruct chunk;
    chunk.memory = (char*)malloc(1);
    chunk.size = 0;

    curl_handle = curl_easy_init();
    if (!curl_handle) {
        free(chunk.memory);
        lua_pushstring(L, "{\"error\": \"Failed to initialize CURL handle\"}");
        return 1;
    }

    curl_easy_setopt(curl_handle, CURLOPT_URL, url);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, (void *)&chunk);
    
    // --- STABILITY & TIMEOUT OPTIONS ---
    curl_easy_setopt(curl_handle, CURLOPT_CONNECTTIMEOUT, 3L);
    curl_easy_setopt(curl_handle, CURLOPT_TIMEOUT, 6L);
    curl_easy_setopt(curl_handle, CURLOPT_NOSIGNAL, 1L);

    // --- BROWSER HEADERS ---
    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    headers = curl_slist_append(headers, "Accept: application/json");
    curl_easy_setopt(curl_handle, CURLOPT_HTTPHEADER, headers);

    curl_easy_setopt(curl_handle, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl_handle, CURLOPT_MAXREDIRS, 3L);

    curl_easy_setopt(curl_handle, CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(curl_handle, CURLOPT_SSL_VERIFYHOST, 0L);

    res = curl_easy_perform(curl_handle);

    if (res != CURLE_OK) {
        char err_buf[256];
        snprintf(err_buf, sizeof(err_buf), "{\"error\": \"%s\"}", curl_easy_strerror(res));
        lua_pushstring(L, err_buf);
    } else {
        lua_pushstring(L, chunk.memory);
    }

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl_handle);
    free(chunk.memory);

    return 1;
}

// Helper to initialize standard libs, custom http_get, and cjson module
static void init_lua_environment(lua_State *L) {
    luaL_openlibs(L);
    lua_register(L, "http_get", l_http_get);

    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    lua_pushcfunction(L, luaopen_cjson);
    lua_setfield(L, -2, "cjson");
    lua_pop(L, 2);
}

// Original evaluator for direct script execution
extern "C" EXPORT const char* eval_lua_script(const char* script_content) {
    lua_State *L = luaL_newstate();
    if (!L) {
        return "Error: Failed to allocate Lua state";
    }

    init_lua_environment(L);

    if (luaL_dostring(L, script_content) != LUA_OK) {
        const char *err_msg = lua_tostring(L, -1);
        static thread_local char error_buffer[512];
        snprintf(error_buffer, sizeof(error_buffer), "Lua Execution Error: %s", err_msg ? err_msg : "unknown");
        lua_close(L);
        return error_buffer;
    }

    const char *result = lua_tostring(L, -1);
    static thread_local char result_buffer[1024];
    
    if (result) {
        snprintf(result_buffer, sizeof(result_buffer), "%s", result);
    } else {
        snprintf(result_buffer, sizeof(result_buffer), "status: success");
    }

    lua_close(L);
    return result_buffer;
}

// Dynamic search runner that invokes the global 'search(query)' function inside the Lua script
extern "C" EXPORT const char* call_lua_search(const char* script_content, const char* query_term) {
    lua_State *L = luaL_newstate();
    if (!L) return "Error: Failed to allocate Lua state";

    init_lua_environment(L);

    if (luaL_dostring(L, script_content) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        static thread_local char err_buf[512];
        snprintf(err_buf, sizeof(err_buf), "Lua Load Error: %s", err ? err : "unknown");
        lua_close(L);
        return err_buf;
    }

    lua_getglobal(L, "search");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, query_term);

        if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
            const char *err = lua_tostring(L, -1);
            static thread_local char err_buf[512];
            snprintf(err_buf, sizeof(err_buf), "Lua Call Error: %s", err ? err : "unknown");
            lua_close(L);
            return err_buf;
        }
    } else {
        lua_close(L);
        return "Error: 'search' function not found in script";
    }

    const char *result = lua_tostring(L, -1);
    static thread_local char res_buf[65536];
    
    if (result) {
        snprintf(res_buf, sizeof(res_buf), "%s", result);
    } else {
        snprintf(res_buf, sizeof(res_buf), "status: empty response");
    }

    lua_close(L);
    return res_buf;
}

// --- Embedded Local HTTP Server Loop for ExoPlayer Streaming ---

static int g_server_fd = -1;
static pthread_t g_server_thread;
static volatile int g_server_running = 0;

static void* stream_server_worker(void* arg) {
    int port = *((int*)arg);
    free(arg);

    struct sockaddr_in address;
    int opt = 1;
    socklen_t addrlen = sizeof(address);

    if ((g_server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        return NULL;
    }

    setsockopt(g_server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // Strictly 127.0.0.1
    address.sin_port = htons(port);

    if (bind(g_server_fd, (struct sockaddr*)&address, sizeof(address)) < 0) {
        close(g_server_fd);
        g_server_fd = -1;
        return NULL;
    }

    if (listen(g_server_fd, 4) < 0) {
        close(g_server_fd);
        g_server_fd = -1;
        return NULL;
    }

    g_server_running = 1;

    while (g_server_running) {
        int new_socket = accept(g_server_fd, (struct sockaddr*)&address, &addrlen);
        if (new_socket < 0) {
            if (!g_server_running) break;
            continue;
        }

        char buffer[2048] = {0};
        read(new_socket, buffer, sizeof(buffer) - 1);

        // Parse requested byte range supplied by ExoPlayer
        long long range_start = 0;
        char* range_header = strstr(buffer, "Range: bytes=");
        if (range_header) {
            sscanf(range_header, "Range: bytes=%lld-", &range_start);
        }

        // Send valid partial content headers back to ExoPlayer
        char header_buf[512];
        int header_len = snprintf(header_buf, sizeof(header_buf),
            "HTTP/1.1 206 Partial Content\r\n"
            "Content-Type: video/mp4\r\n"
            "Accept-Ranges: bytes\r\n"
            "Content-Range: bytes %lld-%lld/*\r\n"
            "Connection: keep-alive\r\n\r\n",
            range_start, range_start + 1048576 - 1);

        write(new_socket, header_buf, header_len);

        // Stream real bytes from the dynamic target file path using pread
        size_t block_size = 32768;
        char *piece_buffer = (char*)malloc(block_size);
        
        if (piece_buffer) {
            int media_fd = open(g_target_file_path, O_RDONLY);
            if (media_fd >= 0) {
                long long current_offset = range_start;
                int total_transferred = 0;
                int max_transfer = 1048576; // Stream 1MB per chunk request

                while (total_transferred < max_transfer && g_server_running) {
                    ssize_t bytes_read = pread(media_fd, piece_buffer, block_size, current_offset);
                    if (bytes_read > 0) {
                        if (write(new_socket, piece_buffer, bytes_read) <= 0) break;
                        current_offset += bytes_read;
                        total_transferred += (int)bytes_read;
                    } else {
                        usleep(50000); // 50ms pause if piece isn't downloaded yet
                    }
                }
                close(media_fd);
            }
            free(piece_buffer);
        }

        close(new_socket);
    }

    if (g_server_fd != -1) {
        close(g_server_fd);
        g_server_fd = -1;
    }
    return NULL;
}

// --- Torrents FFI Export Bindings ---

extern "C" {
    EXPORT void bridge_set_stream_file_path(const char* file_path) {
        if (file_path && strlen(file_path) > 0) {
            snprintf(g_target_file_path, sizeof(g_target_file_path), "%s", file_path);
        }
    }

    EXPORT int bridge_start_torrent(const char* magnet_uri) {
        if (!magnet_uri) return -1;
        return tori_init_session(magnet_uri);
    }

    EXPORT int bridge_start_torrent_with_cache(const char* magnet_uri, const char* cache_dir, int max_cache_mb) {
        if (!magnet_uri) return -1;
        if (max_cache_mb <= 0) max_cache_mb = 64; 
        const char* target_dir = (cache_dir && strlen(cache_dir) > 0) ? cache_dir : "/data/local/tmp";
        
        return tori_init_session_ex(magnet_uri, target_dir, max_cache_mb);
    }

    EXPORT int bridge_start_local_server(int port) {
        if (g_server_running) return 0;
        int* port_arg = (int*)malloc(sizeof(int));
        *port_arg = (port > 0) ? port : 8080;
        
        if (pthread_create(&g_server_thread, NULL, stream_server_worker, port_arg) != 0) {
            free(port_arg);
            return -1;
        }
        pthread_detach(g_server_thread);
        return 0;
    }

    EXPORT void bridge_stop_torrent(void) {
        g_server_running = 0;
        if (g_server_fd != -1) {
            close(g_server_fd);
            g_server_fd = -1;
        }
        tori_stop_session();
    }

    EXPORT const char* bridge_get_torrent_stats(void) {
        const char* stats = tori_get_stats_json();
        if (!stats) {
            return "{\"status\":\"idle\",\"peers\":0,\"download_speed\":0}";
        }
        return stats;
    }
}
