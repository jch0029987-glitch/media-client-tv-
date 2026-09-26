cmake_minimum_required(VERSION 3.22.1)
project("airplay_daemon")

# Define the shared library target containing our combined RTSP and mDNS server
add_library(
    airplay_daemon
    SHARED
    airplay_daemon.c
)

# Find system libraries required for logging and networking on Android
find_library(
    log-lib
    log
)

# Link our shared library against Android's liblog
target_link_libraries(
    airplay_daemon
    ${log-lib}
)
