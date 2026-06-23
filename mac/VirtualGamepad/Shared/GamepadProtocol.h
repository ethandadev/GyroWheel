//
//  GamepadProtocol.h
//  Shared between the DriverKit extension (C++) and the host app (Swift).
//
//  Defines the user-client method selectors and the binary input report that
//  the host pushes to the driver. The struct layout matches the HID report
//  descriptor byte-for-byte (5 bytes): buttons, steer(int16 LE), throttle, brake.
//

#ifndef GamepadProtocol_h
#define GamepadProtocol_h

#include <stdint.h>

#define kVirtualGamepadReportLength 8

// External method selectors (host -> driver user client).
enum {
    kGamepadUserClientPostReport = 0,
    kGamepadUserClientMethodCount
};

// One HID input report. `packed` so sizeof == 5 and it maps directly onto the
// report descriptor with no padding.
typedef struct __attribute__((packed)) {
    uint8_t  buttons;   // bit0..bit3 = btn1..btn4
    int16_t  steer;     // -32767 (full left) .. 32767 (full right)
    uint8_t  throttle;  // 0 .. 255
    uint8_t  brake;     // 0 .. 255
} GamepadInputReport;

#endif /* GamepadProtocol_h */
