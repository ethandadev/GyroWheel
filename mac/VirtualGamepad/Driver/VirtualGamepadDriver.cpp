//
//  VirtualGamepadDriver.cpp
//

#include <string.h>
#include <os/log.h>

#include <DriverKit/IOLib.h>
#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSString.h>
#include <DriverKit/OSNumber.h>
#include <DriverKit/OSDictionary.h>

#include <HIDDriverKit/IOHIDDeviceKeys.h>

#include "VirtualGamepadDriver.h"
#include "GamepadProtocol.h"

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "VirtualGamepad: " fmt "\n", ##__VA_ARGS__)

struct VirtualGamepadDriver_IVars {
    bool started;
};

// HID report descriptor: a gamepad with 4 buttons, a 16-bit signed steering
// axis (X), and two 8-bit triggers (Z = throttle, Rz = brake). Report = 5 bytes.
static const uint8_t kReportDescriptor[] = {
    0x05, 0x01,             // Usage Page (Generic Desktop)
    0x09, 0x05,             // Usage (Game Pad)
    0xA1, 0x01,             // Collection (Application)
      0xA1, 0x00,           //   Collection (Physical)
        // --- 30 buttons (4 bytes incl. 2 padding bits) ---
        0x05, 0x09,         //     Usage Page (Button)
        0x19, 0x01,         //     Usage Minimum (Button 1)
        0x29, 0x1E,         //     Usage Maximum (Button 30)
        0x15, 0x00,         //     Logical Minimum (0)
        0x25, 0x01,         //     Logical Maximum (1)
        0x75, 0x01,         //     Report Size (1)
        0x95, 0x1E,         //     Report Count (30)
        0x81, 0x02,         //     Input (Data,Var,Abs)
        0x75, 0x01,         //     Report Size (1)   -- 2 bits padding
        0x95, 0x02,         //     Report Count (2)
        0x81, 0x03,         //     Input (Const,Var,Abs)
        // --- steering X (16-bit signed) ---
        0x05, 0x01,         //     Usage Page (Generic Desktop)
        0x09, 0x30,         //     Usage (X)
        0x16, 0x01, 0x80,   //     Logical Minimum (-32767)
        0x26, 0xFF, 0x7F,   //     Logical Maximum (32767)
        0x75, 0x10,         //     Report Size (16)
        0x95, 0x01,         //     Report Count (1)
        0x81, 0x02,         //     Input (Data,Var,Abs)
        // --- throttle (Z) + brake (Rz), 8-bit ---
        0x09, 0x32,         //     Usage (Z)
        0x09, 0x35,         //     Usage (Rz)
        0x15, 0x00,         //     Logical Minimum (0)
        0x26, 0xFF, 0x00,   //     Logical Maximum (255)
        0x75, 0x08,         //     Report Size (8)
        0x95, 0x02,         //     Report Count (2)
        0x81, 0x02,         //     Input (Data,Var,Abs)
      0xC0,                 //   End Collection
    0xC0                    // End Collection
};

bool VirtualGamepadDriver::init()
{
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(VirtualGamepadDriver_IVars, 1);
    if (!ivars) {
        return false;
    }
    return true;
}

void VirtualGamepadDriver::free()
{
    IOSafeDeleteNULL(ivars, VirtualGamepadDriver_IVars, 1);
    super::free();
}

kern_return_t
IMPL(VirtualGamepadDriver, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        LOG("super Start failed: 0x%x", ret);
        return ret;
    }

    ret = RegisterService();
    if (ret != kIOReturnSuccess) {
        LOG("RegisterService failed: 0x%x", ret);
        return ret;
    }

    if (ivars) {
        ivars->started = true;
    }
    LOG("started");
    return kIOReturnSuccess;
}

kern_return_t
IMPL(VirtualGamepadDriver, Stop)
{
    if (ivars) {
        ivars->started = false;
    }
    LOG("stopping");
    return Stop(provider, SUPERDISPATCH);
}

bool VirtualGamepadDriver::handleStart(IOService * provider)
{
    return super::handleStart(provider);
}

OSDictionary * VirtualGamepadDriver::newDeviceDescription(void)
{
    OSDictionary * desc = OSDictionary::withCapacity(10);
    if (!desc) {
        return nullptr;
    }

    OSString * transport = OSString::withCString("Virtual");
    if (transport) { desc->setObject(kIOHIDTransportKey, transport); transport->release(); }

    OSString * manufacturer = OSString::withCString("GyroWheel");
    if (manufacturer) { desc->setObject(kIOHIDManufacturerKey, manufacturer); manufacturer->release(); }

    OSString * product = OSString::withCString("GyroWheel Virtual Gamepad");
    if (product) { desc->setObject(kIOHIDProductKey, product); product->release(); }

    OSNumber * vendorID = OSNumber::withNumber((unsigned long long)0x16C0, 32);
    if (vendorID) { desc->setObject(kIOHIDVendorIDKey, vendorID); vendorID->release(); }

    OSNumber * productID = OSNumber::withNumber((unsigned long long)0x27DB, 32);
    if (productID) { desc->setObject(kIOHIDProductIDKey, productID); productID->release(); }

    OSNumber * version = OSNumber::withNumber((unsigned long long)0x0100, 32);
    if (version) { desc->setObject(kIOHIDVersionNumberKey, version); version->release(); }

    OSNumber * usagePage = OSNumber::withNumber((unsigned long long)0x01, 32); // Generic Desktop
    if (usagePage) { desc->setObject(kIOHIDPrimaryUsagePageKey, usagePage); usagePage->release(); }

    OSNumber * usage = OSNumber::withNumber((unsigned long long)0x05, 32);     // Game Pad
    if (usage) { desc->setObject(kIOHIDPrimaryUsageKey, usage); usage->release(); }

    return desc;
}

OSData * VirtualGamepadDriver::newReportDescriptor(void)
{
    return OSData::withBytes(kReportDescriptor, sizeof(kReportDescriptor));
}

kern_return_t
IMPL(VirtualGamepadDriver, NewUserClient)
{
    IOService * clientService = nullptr;
    kern_return_t ret = Create(this, "UserClientProperties", &clientService);
    if (ret != kIOReturnSuccess) {
        LOG("Create user client failed: 0x%x", ret);
        return ret;
    }

    *userClient = OSDynamicCast(IOUserClient, clientService);
    if (!*userClient) {
        if (clientService) { clientService->release(); }
        return kIOReturnError;
    }
    return kIOReturnSuccess;
}

kern_return_t VirtualGamepadDriver::postReport(const void * data, uint32_t length)
{
    if (!data || length == 0) {
        return kIOReturnBadArgument;
    }

    IOBufferMemoryDescriptor * buffer = nullptr;
    kern_return_t ret = IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut, length, 0, &buffer);
    if (ret != kIOReturnSuccess || !buffer) {
        return (ret == kIOReturnSuccess) ? kIOReturnNoMemory : ret;
    }

    IOAddressSegment segment;
    ret = buffer->GetAddressRange(&segment);
    if (ret != kIOReturnSuccess) {
        OSSafeReleaseNULL(buffer);
        return ret;
    }

    memcpy(reinterpret_cast<void *>(segment.address), data, length);

    ret = handleReport(0, buffer, length, kIOHIDReportTypeInput, 0);
    OSSafeReleaseNULL(buffer);
    return ret;
}
