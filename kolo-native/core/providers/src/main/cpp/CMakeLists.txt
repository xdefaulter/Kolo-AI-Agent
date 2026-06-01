cmake_minimum_required(VERSION 3.22.1)

project(kolo_llama_bridge)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED true)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED true)

set(LLAMA_SRC ${CMAKE_CURRENT_LIST_DIR}/../../../../../third_party/llama.cpp)
set(LLAMA_BUILD_SRC ${LLAMA_SRC})
set(VULKAN_HEADERS_SRC ${CMAKE_CURRENT_LIST_DIR}/../../../../../third_party/Vulkan-Headers)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)

set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN ON CACHE BOOL "" FORCE)
set(GGML_VULKAN_CHECK_RESULTS OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN_DEBUG OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN_RUN_TESTS OFF CACHE BOOL "" FORCE)

if(ANDROID AND NOT Vulkan_GLSLC_EXECUTABLE)
    file(GLOB _ANDROID_GLSLC
        "$ENV{ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}/shader-tools/*/glslc"
        "$ENV{ANDROID_SDK_ROOT}/ndk/${ANDROID_NDK_VERSION}/shader-tools/*/glslc"
        "${ANDROID_NDK}/shader-tools/*/glslc"
    )
    list(LENGTH _ANDROID_GLSLC _ANDROID_GLSLC_COUNT)
    if(_ANDROID_GLSLC_COUNT GREATER 0)
        list(GET _ANDROID_GLSLC 0 Vulkan_GLSLC_EXECUTABLE)
        set(Vulkan_GLSLC_EXECUTABLE "${Vulkan_GLSLC_EXECUTABLE}" CACHE FILEPATH "glslc from Android NDK" FORCE)
    endif()
endif()

if(ANDROID)
    if(EXISTS "${VULKAN_HEADERS_SRC}/include/vulkan/vulkan.hpp")
        include_directories(SYSTEM "${VULKAN_HEADERS_SRC}/include")
    endif()

    set(_ANDROID_SPIRV_HEADERS "${ANDROID_NDK}/sources/third_party/shaderc/third_party/spirv-tools/external/spirv-headers")
    if(EXISTS "${_ANDROID_SPIRV_HEADERS}/include/spirv/unified1/spirv.hpp")
        set(_SPIRV_HEADERS_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/cmake/SPIRV-Headers")
        file(MAKE_DIRECTORY "${_SPIRV_HEADERS_CONFIG_DIR}")
        file(WRITE "${_SPIRV_HEADERS_CONFIG_DIR}/SPIRV-HeadersConfig.cmake"
            "set(SPIRV-Headers_FOUND TRUE)\n"
            "if(NOT TARGET SPIRV-Headers::SPIRV-Headers)\n"
            "  add_library(SPIRV-Headers::SPIRV-Headers INTERFACE IMPORTED)\n"
            "  set_target_properties(SPIRV-Headers::SPIRV-Headers PROPERTIES INTERFACE_INCLUDE_DIRECTORIES \"${_ANDROID_SPIRV_HEADERS}/include\")\n"
            "endif()\n"
            "include_directories(SYSTEM \"${_ANDROID_SPIRV_HEADERS}/include\")\n"
        )
        set("SPIRV-Headers_DIR" "${_SPIRV_HEADERS_CONFIG_DIR}" CACHE PATH "SPIR-V headers package shim" FORCE)
        include_directories(SYSTEM "${_ANDROID_SPIRV_HEADERS}/include")
    endif()
endif()

if(ANDROID)
    set(LLAMA_BUILD_SRC "${CMAKE_CURRENT_BINARY_DIR}/llama.cpp-patched")
    file(REMOVE_RECURSE "${LLAMA_BUILD_SRC}")
    file(COPY "${LLAMA_SRC}/" DESTINATION "${LLAMA_BUILD_SRC}" PATTERN ".git" EXCLUDE)

    set(_GGML_VULKAN_CMAKE "${LLAMA_BUILD_SRC}/ggml/src/ggml-vulkan/CMakeLists.txt")
    file(READ "${_GGML_VULKAN_CMAKE}" _GGML_VULKAN_CMAKE_CONTENT)
    if(NOT _GGML_VULKAN_CMAKE_CONTENT MATCHES "CMAKE_MAKE_PROGRAM=\\$\\{CMAKE_MAKE_PROGRAM\\}")
        string(REPLACE
            "                   -DCMAKE_BUILD_TYPE=$<CONFIG>\n                   \${VULKAN_SHADER_GEN_CMAKE_ARGS}"
            "                   -DCMAKE_BUILD_TYPE=$<CONFIG>\n                   -DCMAKE_MAKE_PROGRAM=\${CMAKE_MAKE_PROGRAM}\n                   \${VULKAN_SHADER_GEN_CMAKE_ARGS}"
            _GGML_VULKAN_CMAKE_PATCHED
            "${_GGML_VULKAN_CMAKE_CONTENT}"
        )
        if(_GGML_VULKAN_CMAKE_PATCHED STREQUAL _GGML_VULKAN_CMAKE_CONTENT)
            message(FATAL_ERROR "Unable to patch llama.cpp Vulkan shader generator CMake arguments.")
        endif()
        file(WRITE "${_GGML_VULKAN_CMAKE}" "${_GGML_VULKAN_CMAKE_PATCHED}")
    endif()
endif()

add_subdirectory(${LLAMA_BUILD_SRC} build-llama)

add_library(
    kolo_llama_bridge
    SHARED
    llama_bridge.cpp
)

target_include_directories(
    kolo_llama_bridge
    PRIVATE
    ${LLAMA_BUILD_SRC}
    ${LLAMA_BUILD_SRC}/common
    ${LLAMA_BUILD_SRC}/include
    ${LLAMA_BUILD_SRC}/ggml/include
    ${LLAMA_BUILD_SRC}/ggml/src
)

find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(
    kolo_llama_bridge
    llama
    llama-common
    ${android-lib}
    ${log-lib}
)
