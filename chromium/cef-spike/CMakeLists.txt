cmake_minimum_required(VERSION 3.21)

project(LimeghostCEFSpike LANGUAGES C CXX OBJC OBJCXX)

if(NOT APPLE)
  message(FATAL_ERROR "This Limeghost CEF spike currently targets macOS only.")
endif()

set(CMAKE_CONFIGURATION_TYPES Debug Release CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS version")

if(NOT PROJECT_ARCH)
  if(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "arm64")
    set(PROJECT_ARCH "arm64")
  else()
    set(PROJECT_ARCH "x86_64")
  endif()
endif()

if(NOT PROJECT_ARCH STREQUAL "arm64" AND NOT PROJECT_ARCH STREQUAL "x86_64")
  message(FATAL_ERROR "PROJECT_ARCH must be arm64 or x86_64, got: ${PROJECT_ARCH}")
endif()

include(cmake/CEFVersion.cmake)
option(
  LIMEGHOST_CEF_VALIDATE_ONLY
  "Validate the isolated project boundary without requiring a CEF download"
  ON
)

add_library(LimeghostChromiumBridgeContract INTERFACE)
target_include_directories(
  LimeghostChromiumBridgeContract
  INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_sources(
  LimeghostChromiumBridgeContract
  INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include/LimeghostChromiumBridge.h"
)

message(STATUS "Limeghost CEF spike architecture: ${PROJECT_ARCH}")
message(STATUS "Pinned CEF version: ${LIMEGHOST_CEF_VERSION}")

if(LIMEGHOST_CEF_VALIDATE_ONLY)
  message(STATUS "Validation-only mode: CEF is not downloaded, loaded, linked, or packaged.")
  return()
endif()

if(NOT CEF_ROOT)
  message(FATAL_ERROR "Set CEF_ROOT to the extracted, verified CEF binary distribution.")
endif()

get_filename_component(CEF_ROOT "${CEF_ROOT}" ABSOLUTE)
foreach(required_path
    "include/cef_app.h"
    "cmake/FindCEF.cmake"
    "libcef_dll/CMakeLists.txt")
  if(NOT EXISTS "${CEF_ROOT}/${required_path}")
    message(FATAL_ERROR "CEF_ROOT is missing ${required_path}: ${CEF_ROOT}")
  endif()
endforeach()

if(NOT EXISTS "${CEF_ROOT}/Release/Chromium Embedded Framework.framework")
  message(FATAL_ERROR "CEF_ROOT does not contain the macOS release framework.")
endif()

list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
find_package(CEF REQUIRED)

# Building the official wrapper is the first native dependency proof. A real
# Limeghost target will be added only after the official cefsimple app works
# on this host and its helper-process bundle layout has been retained.
add_subdirectory("${CEF_LIBCEF_DLL_WRAPPER_PATH}" libcef_dll_wrapper)

PRINT_CEF_CONFIG()
