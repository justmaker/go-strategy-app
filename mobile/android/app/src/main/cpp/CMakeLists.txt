cmake_minimum_required(VERSION 3.18.0)

project("katago_mobile")

# Define the shared library
add_library(katago_mobile SHARED native-lib.cpp)

# Search for the log library
find_library(log-lib log)

# Link libraries
target_link_libraries(katago_mobile ${log-lib})
