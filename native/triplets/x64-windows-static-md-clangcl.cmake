# SPDX-FileCopyrightText: 2026 Tag Howard <tag@jthoward.dev>
#
# SPDX-License-Identifier: GPL-3.0-only

# x64-windows-static-md, cross-built on Linux with clang-cl against an xwin splat
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Windows)
# the splat carries no debug CRT
set(VCPKG_BUILD_TYPE release)
set(VCPKG_ENV_PASSTHROUGH CLOUDFITS_TOOLCHAINS)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "$ENV{CLOUDFITS_TOOLCHAINS}/fo4-mcp-msvc/clang-cl-win64.cmake")
