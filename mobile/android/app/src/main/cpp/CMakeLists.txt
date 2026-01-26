cmake_minimum_required(VERSION 3.18.0)

project("katago_mobile")

# --- Flags ---
add_definitions(-O3)
add_definitions(-DUSE_BACKEND_EIGEN)
add_definitions(-DNO_GIT_REVISION)
# Enable C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Includes ---
# Eigen (Header-only)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/eigen)

# KataGo
set(KATAGO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/katago/cpp)
include_directories(${KATAGO_ROOT})
# Include sub-modules explicitly if needed, but root usually suffices relative inputs.
# However, KataGo code uses include "core/..." so root is fine.
# But some externals might need includes.
include_directories(${KATAGO_ROOT}/external)
include_directories(${KATAGO_ROOT}/external/tclap-1.2.5/include)
include_directories(${KATAGO_ROOT}/external/nlohmann_json)
include_directories(${KATAGO_ROOT}/external/filesystem-1.5.8/include)

# --- Sources ---
# Collect all KataGo sources
file(GLOB_RECURSE KATAGO_SRCS "${KATAGO_ROOT}/*.cpp")

# Exclude Main Entry Point (We have our own JNI entry)
list(FILTER KATAGO_SRCS EXCLUDE REGEX ".*/main\\.cpp$")

# Exclude Tests
list(FILTER KATAGO_SRCS EXCLUDE REGEX ".*/tests/.*")

# Exclude OpenCL/CUDA backends (Since we use Eigen)
list(FILTER KATAGO_SRCS EXCLUDE REGEX ".*/neuralnet/opencl.*")
list(FILTER KATAGO_SRCS EXCLUDE REGEX ".*/neuralnet/cuda.*")
list(FILTER KATAGO_SRCS EXCLUDE REGEX ".*/neuralnet/tensorrt.*")

# --- Target ---
add_library(katago_mobile SHARED native-lib.cpp ${KATAGO_SRCS})

# --- Linking ---
find_library(log-lib log)

# Link
target_link_libraries(katago_mobile ${log-lib})
