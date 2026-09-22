# Fail the build when the program image would reach into the flash region that
# param.cpp erases and programs at runtime.
#
# param.cpp stores three blobs at fixed offsets from XIP_BASE: the config at
# FLASH_CONFIG_OFFSET, the sequencers at +4K and the gyro mixer at +8K, each one
# erased a whole 4K sector at a time. Nothing in the SDK reserves that area, so a
# firmware that grows past it still links, still boots and only destroys itself
# the first time the user types SAVE.
#
# Invoked POST_BUILD with -DBIN=<oXs.bin> -DCONFIG_OFFSET=<bytes> -DRESERVED=<bytes>

if(NOT EXISTS "${BIN}")
  message(FATAL_ERROR "check_flash_layout: ${BIN} not found")
endif()

file(SIZE "${BIN}" image_size)

math(EXPR limit_kib "${CONFIG_OFFSET} / 1024")
math(EXPR image_kib "${image_size} / 1024")

if(image_size GREATER CONFIG_OFFSET)
  math(EXPR over "${image_size} - ${CONFIG_OFFSET}")
  message(FATAL_ERROR
    "Firmware image overlaps the parameter area in flash.\n"
    "  image           : ${image_size} bytes (${image_kib} KiB)\n"
    "  parameters start: ${CONFIG_OFFSET} bytes (${limit_kib} KiB)\n"
    "  overlap         : ${over} bytes\n"
    "Flashing this would read parameters out of program code, and the first SAVE "
    "would erase a sector of the program itself and brick the board until it is "
    "re-flashed over BOOTSEL. Shrink the image or move FLASH_CONFIG_OFFSET.")
endif()

math(EXPR headroom "${CONFIG_OFFSET} - ${image_size}")
if(headroom LESS RESERVED)
  math(EXPR headroom_kib "${headroom} / 1024")
  message(WARNING
    "Only ${headroom} bytes (${headroom_kib} KiB) left below the parameter area at "
    "${limit_kib} KiB; the image is ${image_kib} KiB.")
endif()
