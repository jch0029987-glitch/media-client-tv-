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
        lua_pushstring(L, "Error: URL is required for http_get");
        return 1;
    }

    CURL *curl_handle;
    CURLcode res;

    struct MemoryStruct chunk;
    chunk.memory = malloc(1);
    chunk.size = 0;

    curl_global_init(CURL_GLOBAL_ALL);
    curl_handle = curl_easy_init();
    
    if (!curl_handle) {
        free(chunk.memory);
        lua_pushstring(L, "Error: Failed to initialize CURL handle");
        return 1;
    }

    curl_easy_setopt(curl_handle, CURLOPT_URL, url);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, (void *)&chunk);
    curl_easy_setopt(curl_handle, CURLOPT_USERAGENT, "MediaClientTV-LuaAgent/1.0");
    curl_easy_setopt(curl_handle, CURLOPT_TIMEOUT, 10L);

    res = curl_easy_perform(curl_handle);

    if (res != CURLE_OK) {
        char err_buf[256];
        snprintf(err_buf, sizeof(err_buf), "{\"error\": \"%s\"}", curl_easy_strerror(res));
        lua_pushstring(L, err_buf);
    } else {
        lua_pushstring(L, chunk.memory);
    }

    curl_easy_cleanup(curl_handle);
    free(chunk.memory);
    curl_global_cleanup();

    return 1; // Number of return values pushed onto the Lua stack
}

// Original evaluator for direct script execution
EXPORT const char* eval_lua_script(const char* script_content) {
    lua_State *L = luaL_newstate();
    if (!L) {
        return "Error: Failed to allocate Lua state";
    }

    // Open standard Lua libraries & register custom libcurl http_get binding
    luaL_openlibs(L);
    lua_register(L, "http_get", l_http_get);

    // Execute the Lua script string
    if (luaL_dostring(L, script_content) != LUA_OK) {
        const char *err_msg = lua_tostring(L, -1);
        static thread_local char error_buffer[512];
        snprintf(error_buffer, sizeof(error_buffer), "Lua Execution Error: %s", err_msg ? err_msg : "unknown");
        lua_close(L);
        return error_buffer;
    }

    // Read the top of the stack as the return string (if the script returns a value)
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

    // Open standard Lua libraries & register custom libcurl http_get binding
    luaL_openlibs(L);
    lua_register(L, "http_get", l_http_get);

    // Load the script code into Lua state
    if (luaL_dostring(L, script_content) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        static thread_local char err_buf[512];
        snprintf(err_buf, sizeof(err_buf), "Lua Load Error: %s", err ? err : "unknown");
        lua_close(L);
        return err_buf;
    }

    // Look up the global 'search' function defined in the script
    lua_getglobal(L, "search");
    if (lua_isfunction(L, -1)) {
        // Push the query string argument onto the stack
        lua_pushstring(L, query_term);

        // Call search(query_term) with 1 argument and 1 return value
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

    // Read the resulting JSON return string from the top of the stack
    const char *result = lua_tostring(L, -1);
    static thread_local char res_buf[2048];
    
    if (result) {
        snprintf(res_buf, sizeof(res_buf), "%s", result);
    } else {
        snprintf(res_buf, sizeof(res_buf), "status: empty response");
    }

    lua_close(L);
    return res_buf;
}
