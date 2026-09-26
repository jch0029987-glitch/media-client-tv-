#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <curl/curl.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

// Ensure the symbol is exported and visible to Dart FFI / DynamicLibrary.open
#if defined(__GNUC__)
#  define EXPORT __attribute__((visibility("default")))
#else
#  define EXPORT
#endif

// Declare the external cjson loading function provided by the cjson library module
int luaopen_cjson(lua_State *L);

// Declare external C++ functions from the Tori BitTorrent engine (libtori.a)
#ifdef __cplusplus
extern "C" {
#endif
    int tori_init_session(const char* magnet_uri);
    void tori_stop_session(void);
    const char* tori_get_stats_json(void);
#ifdef __cplusplus
}
#endif

// Helper struct for libcurl memory chunk storage
struct MemoryStruct {
    char *memory;
    size_t size;
};

static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    struct MemoryStruct *mem = (struct MemoryStruct *)userp;
    char *ptr = realloc(mem->memory, mem->size + realsize + 1);
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
    chunk.memory = malloc(1);
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
EXPORT const char* eval_lua_script(const char* script_content) {
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
EXPORT const char* call_lua_search(const char* script_content, const char* query_term) {
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

// --- Torrents FFI Export Bindings ---

EXPORT int bridge_start_torrent(const char* magnet_uri) {
    if (!magnet_uri) return -1;
    return tori_init_session(magnet_uri);
}

EXPORT void bridge_stop_torrent(void) {
    tori_stop_session();
}

EXPORT const char* bridge_get_torrent_stats(void) {
    const char* stats = tori_get_stats_json();
    if (!stats) {
        return "{\"status\":\"idle\",\"peers\":0,\"download_speed\":0}";
    }
    return stats;
}
