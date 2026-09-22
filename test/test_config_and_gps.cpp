// Compile time tests for the GPS baudrate parameter and the config flash layout.
//
// There is no host compiler and no test framework on this machine, so the tests
// are constexpr / static_assert and the ARM compiler is the test runner: building
// this file IS the test run and a failed test is a compile error.
//
//     cmake --build build --target oXs_tests
//
// This file is not part of the firmware (CMake globs only src/).

#include <stddef.h>
#include <stdint.h>
#include "hardware/flash.h"
#include "param.h"
#include "gps.h"

// ---------------------------------------------------------------------------
// saveConfig() memcpy's the whole struct into one flash page sized stack buffer
// without checking; if CONFIG ever outgrows the page that is a silent overflow.
// ---------------------------------------------------------------------------
static_assert(sizeof(CONFIG) <= FLASH_PAGE_SIZE,
    "CONFIG no longer fits in one flash page: saveConfig() would overflow its buffer");

// ---------------------------------------------------------------------------
// Migration of a stored version 8 config.
//
// setupConfig() memcpy's the raw flash blob over the struct, so a v8 blob may
// only be reused when every field it contains still sits at the same offset.
// CONFIG_V8 below is the verbatim v8 layout; the asserts pin that down.
// ---------------------------------------------------------------------------
namespace v8 {
struct CONFIG_V8{
    uint8_t version;
    uint8_t pinChannels[16] ;
    uint8_t pinGpsTx ;
    uint8_t pinGpsRx ;
    uint8_t pinPrimIn ;
    uint8_t pinSecIn ; 
    uint8_t pinSbusOut ;
    uint8_t pinTlm ;
    uint8_t pinVolt[4] ;
    uint8_t pinSda  ;
    uint8_t pinScl ;
    uint8_t pinRpm ;
    uint8_t pinLed ;
    uint8_t protocol  ; // S = Sport, C = crossfire, J = Jeti
    uint32_t crsfBaudrate ;
    float scaleVolt1 ;
    float scaleVolt2 ;
    float scaleVolt3 ;
    float scaleVolt4 ;
    float offset1 ;
    float offset2 ;
    float offset3 ;
    float offset4 ;
    uint8_t gpsType  ;
    float rpmMultiplicator ;
    //uint8_t gpio0 = 0; // 0 mean SBUS, 1 up to 16  = a RC channel
    //uint8_t gpio1 = 1;
    //uint8_t gpio5 = 6;
    //uint8_t gpio11 = 11;
    uint8_t failsafeType ;
    crsf_channels_s failsafeChannels ;
    int16_t accOffsetX;
    int16_t accOffsetY;
    int16_t accOffsetZ;
    int16_t gyroOffsetX;
    int16_t gyroOffsetY;
    int16_t gyroOffsetZ;
    uint8_t temperature; 
    uint8_t VspeedCompChannel;
    uint8_t ledInverted;
    uint8_t pinLogger ;
    uint32_t loggerBaudrate ;
    uint8_t pinEsc;
    uint8_t escType;
    uint16_t pwmHz ;
    //                for gyro
    uint8_t gyroChanControl ; // Rc channel used to say if gyro is implemented or not and to select the mode and the general gain. Value must be in range 1/16 or 255 (no gyro)
    uint8_t gyroChan[3] ;    // Rc channel used to transmit original Ail, Elv, Rud stick position ; Value must be in range 1/16 when gyroControlChannel is not 255
    
    struct _pid_param pid_param_rate; // each structure store the Kp, Ki, Kd parameters for each of the 3 axis; here for normal mode (= rate)
    struct _pid_param pid_param_hold; // idem for hold mode
    struct _pid_param pid_param_stab;  //each structure store the Kp, Ki, Kd parameters for each of the 3 axis; here for stabilize mode (= rate)
    
    int8_t vr_gain[3];          // store the gain per axis (to combine with global gain provided by gyroChanControl)
    enum STICK_GAIN_THROW stick_gain_throw;  // this parameter allows to limit the compensation on a part of the stick travel (gain decreases more or less rapidly with stick offset)
    enum MAX_ROTATE max_rotate;              // this parameter varies from 1 up to 4 and is used to increase/decrease the gyro corrections (*2,*4,*8,*16)
    enum RATE_MODE_STICK_ROTATE rate_mode_stick_rotate;
    bool gyroAutolevel;           // true means that stabilize mode replies the Hold mode (on switch position)
    uint8_t mpuOrientationH;       // define the orientation of the mpu when plane is horizontal;
    uint8_t mpuOrientationV;       // define the orientation of the mpu when plane is vertical (nose up);
    // for Lora locator
    uint8_t pinSpiCs;
    uint8_t pinSpiSck;
    uint8_t pinSpiMosi;
    uint8_t pinSpiMiso;
    float accOffX ;
    float accOffY ;
    float accOffZ ;
    float accScaleXX ;
    float accScaleYY ;
    float accScaleZZ ;
    float accScaleXY ;
    float accScaleXZ ;
    float accScaleYZ ;
    uint8_t pinHigh ;
    uint8_t pinLow ;
    uint8_t pinE220Busy;
};
} // namespace v8

#define SAME_OFFSET(f) static_assert(offsetof(CONFIG, f) == offsetof(v8::CONFIG_V8, f), \
    "offset of " #f " moved: a stored v8 config would be misread after migration")

SAME_OFFSET(version);
SAME_OFFSET(pinChannels);
SAME_OFFSET(pinGpsTx);
SAME_OFFSET(pinGpsRx);
SAME_OFFSET(pinPrimIn);
SAME_OFFSET(pinSecIn);
SAME_OFFSET(pinSbusOut);
SAME_OFFSET(pinTlm);
SAME_OFFSET(pinVolt);
SAME_OFFSET(pinSda);
SAME_OFFSET(pinScl);
SAME_OFFSET(pinRpm);
SAME_OFFSET(pinLed);
SAME_OFFSET(protocol);
SAME_OFFSET(crsfBaudrate);
SAME_OFFSET(scaleVolt1);
SAME_OFFSET(scaleVolt2);
SAME_OFFSET(scaleVolt3);
SAME_OFFSET(scaleVolt4);
SAME_OFFSET(offset1);
SAME_OFFSET(offset2);
SAME_OFFSET(offset3);
SAME_OFFSET(offset4);
SAME_OFFSET(gpsType);
SAME_OFFSET(rpmMultiplicator);
SAME_OFFSET(failsafeType);
SAME_OFFSET(failsafeChannels);
SAME_OFFSET(accOffsetX);
SAME_OFFSET(accOffsetY);
SAME_OFFSET(accOffsetZ);
SAME_OFFSET(gyroOffsetX);
SAME_OFFSET(gyroOffsetY);
SAME_OFFSET(gyroOffsetZ);
SAME_OFFSET(temperature);
SAME_OFFSET(VspeedCompChannel);
SAME_OFFSET(ledInverted);
SAME_OFFSET(pinLogger);
SAME_OFFSET(loggerBaudrate);
SAME_OFFSET(pinEsc);
SAME_OFFSET(escType);
SAME_OFFSET(pwmHz);
SAME_OFFSET(gyroChanControl);
SAME_OFFSET(gyroChan);
SAME_OFFSET(pid_param_rate);
SAME_OFFSET(pid_param_hold);
SAME_OFFSET(pid_param_stab);
SAME_OFFSET(vr_gain);
SAME_OFFSET(stick_gain_throw);
SAME_OFFSET(max_rotate);
SAME_OFFSET(rate_mode_stick_rotate);
SAME_OFFSET(gyroAutolevel);
SAME_OFFSET(mpuOrientationH);
SAME_OFFSET(mpuOrientationV);
SAME_OFFSET(pinSpiCs);
SAME_OFFSET(pinSpiSck);
SAME_OFFSET(pinSpiMosi);
SAME_OFFSET(pinSpiMiso);
SAME_OFFSET(accOffX);
SAME_OFFSET(accOffY);
SAME_OFFSET(accOffZ);
SAME_OFFSET(accScaleXX);
SAME_OFFSET(accScaleYY);
SAME_OFFSET(accScaleZZ);
SAME_OFFSET(accScaleXY);
SAME_OFFSET(accScaleXZ);
SAME_OFFSET(accScaleYZ);
SAME_OFFSET(pinHigh);
SAME_OFFSET(pinLow);
SAME_OFFSET(pinE220Busy);

static_assert(sizeof(v8::CONFIG_V8) == CONFIG_V8_SIZE,
    "CONFIG_V8_SIZE does not match the v8 layout: migration would copy the wrong length");
static_assert(CONFIG_V8_SIZE == offsetof(CONFIG, gpsBaudrate),
    "gpsBaudrate must be appended behind the v8 layout so a v8 blob stays a prefix");
static_assert(CONFIG_VERSION == 9, "adding a field to CONFIG requires a version bump");

// ---------------------------------------------------------------------------
// Accepted baudrates
// ---------------------------------------------------------------------------
static_assert(gpsBaudrateIsValid(9600),   "9600 is a ublox baudrate");
static_assert(gpsBaudrateIsValid(38400),  "38400 is the default");
static_assert(gpsBaudrateIsValid(115200), "115200 is what a recent Beitian BE-250 ships with");
static_assert(gpsBaudrateIsValid(460800), "460800 is a ublox baudrate");
static_assert(!gpsBaudrateIsValid(0),     "0 is not a baudrate");
static_assert(!gpsBaudrateIsValid(38401), "an arbitrary value must be rejected");
static_assert(!gpsBaudrateIsValid(100000),"a plausible but non standard value must be rejected");

// ---------------------------------------------------------------------------
// Patching the baudrate into the UBX-CFG-PRT frame.
//
// Expected bytes were produced independently of the implementation; the 38400
// case must reproduce the hand written table that shipped before this change.
// ---------------------------------------------------------------------------
struct CfgPrt { uint8_t b[UBX_CFG_PRT_LEN]; };

static constexpr CfgPrt patched(uint32_t baud) {
    CfgPrt f = { { 0xB5,0x62,0x06,0x00, 0x14,0x00,
                   0x01,0x00,0x00,0x00,0xD0,0x08,0x00,0x00,0x00,0x96,
                   0x00,0x00,0x07,0x00,0x01,0x00,0x00,0x00,0x00,0x00,
                   0x91,0x84 } };
    ubxPatchCfgPrtBaudrate(f.b, baud);
    return f;
}

static constexpr bool frameIs(uint32_t baud, uint8_t b0, uint8_t b1, uint8_t b2, uint8_t b3,
                              uint8_t ckA, uint8_t ckB) {
    CfgPrt f = patched(baud);
    return f.b[14] == b0 && f.b[15] == b1 && f.b[16] == b2 && f.b[17] == b3
        && f.b[26] == ckA && f.b[27] == ckB;
}

static_assert(UBX_CFG_PRT_LEN == 28, "UBX-CFG-PRT is 6 header + 20 payload + 2 checksum bytes");
static_assert(frameIs(  9600, 0x80,0x25,0x00,0x00, 0xA0,0xA9), "9600 frame wrong");
static_assert(frameIs( 19200, 0x00,0x4B,0x00,0x00, 0x46,0x4B), "19200 frame wrong");
static_assert(frameIs( 38400, 0x00,0x96,0x00,0x00, 0x91,0x84), "38400 must reproduce the original table");
static_assert(frameIs( 57600, 0x00,0xE1,0x00,0x00, 0xDC,0xBD), "57600 frame wrong");
static_assert(frameIs(115200, 0x00,0xC2,0x01,0x00, 0xBE,0x72), "115200 frame wrong");
static_assert(frameIs(230400, 0x00,0x84,0x03,0x00, 0x82,0xDC), "230400 frame wrong");
static_assert(frameIs(460800, 0x00,0x08,0x07,0x00, 0x0A,0xB0), "460800 frame wrong");

// the patch must leave everything outside the baudrate and checksum untouched
static constexpr bool restUnchanged() {
    CfgPrt f = patched(115200);
    const uint8_t orig[] = { 0xB5,0x62,0x06,0x00, 0x14,0x00,
                             0x01,0x00,0x00,0x00,0xD0,0x08,0x00,0x00 };
    for (unsigned i = 0; i < sizeof(orig); i++) if (f.b[i] != orig[i]) return false;
    const uint8_t tail[] = { 0x07,0x00,0x01,0x00,0x00,0x00,0x00,0x00 };
    for (unsigned i = 0; i < sizeof(tail); i++) if (f.b[18 + i] != tail[i]) return false;
    return true;
}
static_assert(restUnchanged(), "patching the baudrate must not disturb the rest of the frame");
