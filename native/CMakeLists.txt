# SPDX-FileCopyrightText: 2026 Tag Howard <tag@jthoward.dev>
#
# SPDX-License-Identifier: GPL-3.0-only

cmake_minimum_required(VERSION 3.25)

project(
	Cloudfits
	VERSION 1.0.0
	LANGUAGES CXX
)

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

set(COMMONLIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/CommonLibF4RD")

# fixes MSVC tolerates and clang-cl rejects; a patch that already reverses cleanly is applied
file(GLOB COMMONLIB_PATCHES "${CMAKE_CURRENT_SOURCE_DIR}/patches/*.patch")
list(SORT COMMONLIB_PATCHES)
foreach(patch IN LISTS COMMONLIB_PATCHES)
	execute_process(
		COMMAND git -C "${COMMONLIB_DIR}" apply --reverse --check "${patch}"
		RESULT_VARIABLE already_applied
		OUTPUT_QUIET ERROR_QUIET
	)
	if(NOT already_applied EQUAL 0)
		execute_process(
			COMMAND git -C "${COMMONLIB_DIR}" apply "${patch}"
			RESULT_VARIABLE result
		)
		if(NOT result EQUAL 0)
			message(FATAL_ERROR "could not apply ${patch} to ${COMMONLIB_DIR}")
		endif()
	endif()
endforeach()

add_subdirectory("${COMMONLIB_DIR}/CommonLibF4" CommonLibF4 SYSTEM)

# the xwin splat on a case-sensitive filesystem has version.lib but no Version.lib
get_target_property(COMMONLIB_LINK CommonLibF4 INTERFACE_LINK_LIBRARIES)
list(TRANSFORM COMMONLIB_LINK REPLACE "^Version\\.lib$" "version.lib")
set_target_properties(CommonLibF4 PROPERTIES INTERFACE_LINK_LIBRARIES "${COMMONLIB_LINK}")

find_package(fmt REQUIRED CONFIG)
find_package(spdlog REQUIRED CONFIG)

configure_file(
	"${CMAKE_CURRENT_SOURCE_DIR}/cmake/Version.h.in"
	"${CMAKE_CURRENT_BINARY_DIR}/include/Version.h"
	@ONLY
)

add_library(
	"${PROJECT_NAME}"
	SHARED
	src/main.cpp
	src/Natives.cpp
)

target_compile_features("${PROJECT_NAME}" PRIVATE cxx_std_20)

target_include_directories(
	"${PROJECT_NAME}"
	PRIVATE
		"${CMAKE_CURRENT_BINARY_DIR}/include"
		"${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(
	"${PROJECT_NAME}"
	PRIVATE
		CommonLibF4::CommonLibF4
		fmt::fmt
		spdlog::spdlog
)

target_precompile_headers("${PROJECT_NAME}" PRIVATE src/PCH.h)

target_compile_options(
	"${PROJECT_NAME}"
	PRIVATE
		/utf-8
		/W4
		/permissive-
		/Zc:inline
)

target_link_options(
	"${PROJECT_NAME}"
	PRIVATE
		/OPT:REF
		/OPT:ICF
)
