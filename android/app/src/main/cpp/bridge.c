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
