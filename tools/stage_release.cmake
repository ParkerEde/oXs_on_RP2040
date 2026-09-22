# Stage the built UF2 under the version string it actually carries.
#
# The build target keeps a stable file name (oXs_<branch>.uf2) so ninja can track it
# and incremental builds work. What gets handed to other people is this copy, named
# oXs_<version>.uf2 with the exact string the firmware prints over USB, so a file on
# someone's disk and the version a board reports can always be matched up.
#
# The version is read from the generated header rather than recomputed from git, or
# the name could disagree with what was compiled into the binary.
#
# A dirty build is staged under its -dirty name on purpose: it makes a build that was
# never committed obvious from the file name alone, before anyone flashes it.
#
# dist/ is wiped of UF2s first, so it always holds exactly one file and there is never
# a question which one is current.
#
# Invoked with -DUF2=<built uf2> -DVERSION_HEADER=<generated header> -DDIST_DIR=<dir>

if(NOT UF2 OR NOT VERSION_HEADER OR NOT DIST_DIR)
  message(FATAL_ERROR "stage_release: UF2, VERSION_HEADER and DIST_DIR are required")
endif()

if(NOT EXISTS "${UF2}")
  message(FATAL_ERROR "stage_release: ${UF2} not found")
endif()

if(NOT EXISTS "${VERSION_HEADER}")
  message(FATAL_ERROR "stage_release: ${VERSION_HEADER} not found")
endif()

file(STRINGS "${VERSION_HEADER}" version_lines REGEX "^[ \t]*#define[ \t]+VERSION[ \t]+\"")
if(NOT version_lines)
  message(FATAL_ERROR "stage_release: no '#define VERSION \"...\"' in ${VERSION_HEADER}")
endif()
list(GET version_lines 0 version_line)
string(REGEX REPLACE "[^\"]*\"([^\"]*)\".*" "\\1" version "${version_line}")

file(GLOB stale "${DIST_DIR}/*.uf2")
if(stale)
  file(REMOVE ${stale})
endif()

file(MAKE_DIRECTORY "${DIST_DIR}")
file(COPY_FILE "${UF2}" "${DIST_DIR}/oXs_${version}.uf2")

message(STATUS "staged ${DIST_DIR}/oXs_${version}.uf2")
