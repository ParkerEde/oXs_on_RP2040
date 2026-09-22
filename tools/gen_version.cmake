# Compose the firmware version string and write it to a generated header.
#
# The result is VERSION_BASE from src/config.h plus the state of the working tree,
# e.g. "3.0.11-rk-main-85a5014" or "3.0.11-rk-main-85a5014-dirty". That makes the
# string a board prints over USB identify exactly what was built, which a hand
# maintained version number cannot.
#
# This runs on every build rather than at configure time, so committing and
# rebuilding does not leave a stale hash behind. The header is only rewritten when
# the string actually changed, otherwise every build would recompile everything
# that includes config.h, which is all of it.
#
# Invoked with -DSRC_DIR=<repo root> -DOUT=<header to write>

if(NOT SRC_DIR OR NOT OUT)
  message(FATAL_ERROR "gen_version: SRC_DIR and OUT are required")
endif()

# ---- base version, single source of truth in src/config.h -------------------
file(STRINGS "${SRC_DIR}/src/config.h" base_lines
     REGEX "^[ \t]*#define[ \t]+VERSION_BASE[ \t]+\"")
if(NOT base_lines)
  message(FATAL_ERROR "gen_version: no '#define VERSION_BASE \"...\"' in ${SRC_DIR}/src/config.h")
endif()
list(GET base_lines 0 base_line)
string(REGEX REPLACE "[^\"]*\"([^\"]*)\".*" "\\1" base "${base_line}")

# ---- working tree state -----------------------------------------------------
set(suffix "-nogit")
find_package(Git QUIET)

if(GIT_FOUND AND IS_DIRECTORY "${SRC_DIR}/.git")
  execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
                  WORKING_DIRECTORY "${SRC_DIR}"
                  OUTPUT_VARIABLE sha OUTPUT_STRIP_TRAILING_WHITESPACE
                  RESULT_VARIABLE sha_result ERROR_QUIET)

  if(sha_result EQUAL 0 AND sha)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
                    WORKING_DIRECTORY "${SRC_DIR}"
                    OUTPUT_VARIABLE branch OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)
    if(NOT branch OR branch STREQUAL "HEAD")
      set(branch "detached")
    endif()
    # the version string ends up in C source, so keep it to harmless characters
    string(REGEX REPLACE "[^A-Za-z0-9._-]" "-" branch "${branch}")

    # untracked files count: sources are picked up with file(GLOB), so a file that
    # was never added still ends up in the image
    execute_process(COMMAND ${GIT_EXECUTABLE} status --porcelain
                    WORKING_DIRECTORY "${SRC_DIR}"
                    OUTPUT_VARIABLE dirt OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)
    set(suffix "-${branch}-${sha}")
    if(dirt)
      string(APPEND suffix "-dirty")
    endif()
  endif()
endif()

set(version "${base}${suffix}")

# ---- write, but only on a change -------------------------------------------
set(content "// Generated on every build by tools/gen_version.cmake - do not edit, do not commit.\n")
string(APPEND content "#pragma once\n")
string(APPEND content "#define VERSION \"${version}\"\n")

set(previous "")
if(EXISTS "${OUT}")
  file(READ "${OUT}" previous)
endif()

if(NOT previous STREQUAL content)
  get_filename_component(out_dir "${OUT}" DIRECTORY)
  file(MAKE_DIRECTORY "${out_dir}")
  file(WRITE "${OUT}" "${content}")
endif()

message(STATUS "oXs version ${version}")
