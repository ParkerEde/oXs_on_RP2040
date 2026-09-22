# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.1.0)
set(toolchainVersion 13_3_Rel1)
set(picotoolVersion 2.1.0)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================
set(PICO_BOARD pico CACHE STRING "Board type")


cmake_minimum_required(VERSION 3.13)

add_compile_definitions(PICO_XOSC_STARTUP_DELAY_MULTIPLIER=128)

# initialize the SDK based on PICO_SDK_PATH
# note: this must happen before project()
include(pico_sdk_import.cmake)

project(my_project LANGUAGES C CXX)

# initialize the Raspberry Pi Pico SDK
pico_sdk_init()
#add_compile_options(-Werror -Wall -Wextra -Wnull-dereference)
#add_compile_options(-Wall)

# The SDK defaults a Release build to -O3, which puts this firmware at ~260 KiB and thus
# straight into the parameter area that param.cpp erases at 256 KiB (see the check further
# down). -O2 builds the same code at ~245 KiB and is the usual choice for embedded anyway,
# so the upstream flash layout can be kept unchanged.
set(CMAKE_C_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "" FORCE)

add_executable(oXs)

# Name the artifacts after the branch (oXs_rk-main.uf2) so it stays obvious which build is
# on a board. Pass -DOXS_UF2_NAME=oXs to get the plain name back, which is what refreshing
# the oXs.uf2 committed in the repo root needs.
execute_process(COMMAND git rev-parse --abbrev-ref HEAD
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
        OUTPUT_VARIABLE OXS_GIT_BRANCH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
if(NOT OXS_GIT_BRANCH OR OXS_GIT_BRANCH STREQUAL "HEAD")
    set(OXS_GIT_BRANCH "nobranch")
endif()
string(REGEX REPLACE "[^A-Za-z0-9._-]" "-" OXS_GIT_BRANCH "${OXS_GIT_BRANCH}")
set(OXS_UF2_NAME "oXs_${OXS_GIT_BRANCH}" CACHE STRING "Base name of the built artifacts")
set_target_properties(oXs PROPERTIES OUTPUT_NAME "${OXS_UF2_NAME}")
# re-run cmake when the checked out branch changes, so the name follows along
if(EXISTS ${CMAKE_CURRENT_LIST_DIR}/.git/HEAD)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${CMAKE_CURRENT_LIST_DIR}/.git/HEAD)
endif()

#pico_generate_pio_header(oXs ${CMAKE_CURRENT_LIST_DIR}/src/uart_crsf_rx.pio )
pico_generate_pio_header(oXs ${CMAKE_CURRENT_LIST_DIR}/src/uart_crsf_tx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_gps_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_gps_tx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_hott_tx_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_ibus_tx_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_jeti_tx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_mpx_tx_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_sbus_tx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_sport_tx_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_srxl2_tx_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_exbus_tx_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_logger_tx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_esc_rx.pio )
pico_generate_pio_header(oXs  ${CMAKE_CURRENT_LIST_DIR}/src/uart_frsky_hub_tx.pio)

file(GLOB oXs_SRC CONFIGURE_DEPENDS "src/*.h" "src/*.cpp")

target_sources(oXs PRIVATE ${oXs_SRC}  )

# VERSION carries the branch and the commit (3.0.11-rk-main-85a5014, plus -dirty for an
# uncommitted tree), so what a board prints identifies exactly what was built. Regenerated
# on every build rather than at configure time, so a fresh commit cannot leave a stale hash
# behind; the header is only rewritten when the string changed.
set(OXS_VERSION_HEADER ${CMAKE_BINARY_DIR}/generated/oxs_version.h)
add_custom_target(oXs_version ALL
  COMMAND ${CMAKE_COMMAND}
          -DSRC_DIR=${CMAKE_CURRENT_LIST_DIR}
          -DOUT=${OXS_VERSION_HEADER}
          -P ${CMAKE_CURRENT_LIST_DIR}/tools/gen_version.cmake
  BYPRODUCTS ${OXS_VERSION_HEADER}
  COMMENT "Generating the version string from git"
  VERBATIM
)
add_dependencies(oXs oXs_version)
target_include_directories(oXs PRIVATE ${CMAKE_BINARY_DIR}/generated)

target_link_libraries(oXs PRIVATE
        pico_stdlib
        pico_multicore
        hardware_pio
        hardware_i2c
        hardware_watchdog
        hardware_timer
        hardware_dma
        hardware_irq
        hardware_adc
        hardware_pwm
        hardware_spi
        )

#enable printf on usb
pico_enable_stdio_usb(oXs 1)
pico_enable_stdio_uart(oXs 0)


# create map/bin/hex/uf2 file in addition to ELF.
pico_add_extra_outputs(oXs)

# The parameter area that param.cpp erases/programs at runtime is NOT reserved by the
# linker, so a firmware that grows into it links and boots fine and only destroys
# itself on the first SAVE. Keep these two values in sync with param.cpp.
set(OXS_FLASH_CONFIG_OFFSET 262144 CACHE STRING "FLASH_CONFIG_OFFSET from param.cpp, in bytes")
set(OXS_FLASH_HEADROOM_WARN 8192 CACHE STRING "Warn when less than this many bytes are left below it")

add_custom_command(TARGET oXs POST_BUILD
  COMMAND ${CMAKE_COMMAND}
          -DBIN=$<TARGET_FILE_DIR:oXs>/$<TARGET_FILE_BASE_NAME:oXs>.bin
          -DCONFIG_OFFSET=${OXS_FLASH_CONFIG_OFFSET}
          -DRESERVED=${OXS_FLASH_HEADROOM_WARN}
          -P ${CMAKE_CURRENT_LIST_DIR}/tools/check_flash_layout.cmake
  COMMENT "Checking that the image stays below the parameter area in flash"
  VERBATIM
)


# Optionally copy the built UF2 somewhere after each build. Empty (the default)
# copies nothing, so a build never touches anything outside the build directory.
#   -DOXS_COPY_UF2_TO=E:/                     drop it on a mounted RPI-RP2 drive to flash
#   -DOXS_UF2_NAME=oXs -DOXS_COPY_UF2_TO=.    refresh the oXs.uf2 committed in the repo root
set(OXS_COPY_UF2_TO "" CACHE STRING "Directory to copy the UF2 to after a build (empty = do not copy)")

if(OXS_COPY_UF2_TO)
  add_custom_command(TARGET oXs POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
            $<TARGET_FILE_DIR:oXs>/$<TARGET_FILE_BASE_NAME:oXs>.uf2
            ${OXS_COPY_UF2_TO}
    COMMENT "Copying ${OXS_UF2_NAME}.uf2 to ${OXS_COPY_UF2_TO}"
  )
endif()


# Compile time tests (constexpr / static_assert). There is no host compiler and
# no test framework here, so building this target is the test run: a failed test
# is a compile error. It is built together with the firmware so a regression in
# the config flash layout cannot pass unnoticed.
#   cmake --build build --target oXs_tests
add_library(oXs_tests OBJECT test/test_config_and_gps.cpp)
# reuse the firmware's include paths and defines without pulling in the SDK sources
target_include_directories(oXs_tests PRIVATE
        src
        $<TARGET_PROPERTY:oXs,INCLUDE_DIRECTORIES>
        )
target_compile_definitions(oXs_tests PRIVATE $<TARGET_PROPERTY:oXs,COMPILE_DEFINITIONS>)
add_dependencies(oXs_tests oXs_version)
