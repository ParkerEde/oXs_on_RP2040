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
add_executable(oXs)

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


# Optionally copy the built UF2 somewhere after each build. Empty (the default)
# copies nothing, so a build never touches anything outside the build directory.
#   -DOXS_COPY_UF2_TO=.      refresh the oXs.uf2 committed in the repo root
#   -DOXS_COPY_UF2_TO=E:/    drop it straight onto a mounted RPI-RP2 drive to flash
set(OXS_COPY_UF2_TO "" CACHE STRING "Directory to copy oXs.uf2 to after a build (empty = do not copy)")

if(OXS_COPY_UF2_TO)
  add_custom_command(TARGET oXs POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
            $<TARGET_FILE_DIR:oXs>/oXs.uf2
            ${OXS_COPY_UF2_TO}
    COMMENT "Copying oXs.uf2 to ${OXS_COPY_UF2_TO}"
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
