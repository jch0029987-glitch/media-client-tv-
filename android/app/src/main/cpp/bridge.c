#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

// Ensure the symbol is exported and visible to Dart FFI / DynamicLibrary.open
#if defined(__GNUC__)
#  define EXPORT __attribute__((visibility("default")))
#else
#  define EXPORT
#endif

// Original evaluator for direct script execution
EXPORT const char* eval_lua_script(const char* script_content) {
    lua_State *L = luaL_newstate();
    if (!L) {
        return "Error: Failed to allocate Lua state";
    }

    // Open standard Lua libraries (string, table, math, etc.)
    luaL_openlibs(L);

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

    luaL_openlibs(L);

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
