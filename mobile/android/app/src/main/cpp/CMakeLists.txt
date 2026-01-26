cmake_minimum_required(VERSION 3.18.0)

project("katago_mobile")

# --- Flags ---
add_definitions(-O3)
add_definitions(-DUSE_BACKEND_EIGEN)
add_definitions(-D_REENTRANT)
add_definitions(-DNO_GIT_REVISION)

# Android specific fixes
if(ANDROID)
    add_definitions(-DLITTLE_ENDIAN=1234)
    add_definitions(-DBIG_ENDIAN=4321)
    add_definitions(-DBYTE_ORDER=1234)
endif()
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
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/fake_zip)

# --- Sources ---
# Collect all KataGo sources
file(GLOB_RECURSE KATAGO_SRCS "${KATAGO_ROOT}/*.cpp")

# Exclude Main Entry Point
list(FILTER KATAGO_SRCS EXCLUDE REGEX "main\\.cpp$")

# Exclude Tests
list(FILTER KATAGO_SRCS EXCLUDE REGEX "tests/")

# Exclude OpenCL/CUDA backends (Since we use Eigen)
list(FILTER KATAGO_SRCS EXCLUDE REGEX "neuralnet/(opencl|cuda|tensorrt)")

# Exclude Distributed features (not needed for local analysis, has complex dependencies)
list(FILTER KATAGO_SRCS EXCLUDE REGEX "distributed/")

# Exclude unneeded main command entry points
list(FILTER KATAGO_SRCS EXCLUDE REGEX "command/(benchmark|contribute|evalsgf|gatekeeper|genconfig|tuner|match|selfplay|demoplay|gputest|sampleinits|sandbox|startposes|viewstartposes|checksgf|genposes|comparebooks|findbookbottlenecks|runtests|runnnlayertests|runsearchtests|runsearchtestsv3|runsearchtestsv8|runsearchtestsv9|runnnontinyboardtest|runnnsymmetriestest|runoutputtests|runselfplayinittests|runselfplayinitstattests|runsekitrainwritetests|runnnonmanyposestest|runnnbatchingtest|runownershiptests|runtinynntests|runnnevalcanarytests|runbeginsearchspeedtest|runownershipspeedtest|runsleeptest|runconfigtests)")

# --- Target ---
add_library(katago_mobile SHARED native-lib.cpp stubs.cpp ${KATAGO_SRCS})

# --- Linking ---
find_library(log-lib log)

# Link
target_link_libraries(katago_mobile ${log-lib})
