//
//  VirtualGamepadUserClient.cpp
//

#include <os/log.h>

#include <DriverKit/IOLib.h>
#include <DriverKit/IOUserServer.h>
#include <DriverKit/OSData.h>

#include "VirtualGamepadUserClient.h"
#include "VirtualGamepadDriver.h"
#include "GamepadProtocol.h"

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "VirtualGamepadUC: " fmt "\n", ##__VA_ARGS__)

struct VirtualGamepadUserClient_IVars {
    VirtualGamepadDriver * driver;
};

bool VirtualGamepadUserClient::init()
{
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(VirtualGamepadUserClient_IVars, 1);
    if (!ivars) {
        return false;
    }
    return true;
}

void VirtualGamepadUserClient::free()
{
    IOSafeDeleteNULL(ivars, VirtualGamepadUserClient_IVars, 1);
    super::free();
}

kern_return_t
IMPL(VirtualGamepadUserClient, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    ivars->driver = OSDynamicCast(VirtualGamepadDriver, provider);
    if (!ivars->driver) {
        LOG("provider is not VirtualGamepadDriver");
        return kIOReturnError;
    }
    LOG("user client started");
    return kIOReturnSuccess;
}

kern_return_t
IMPL(VirtualGamepadUserClient, Stop)
{
    if (ivars) {
        ivars->driver = nullptr;
    }
    return Stop(provider, SUPERDISPATCH);
}

kern_return_t VirtualGamepadUserClient::ExternalMethod(uint64_t selector,
                                                       IOUserClientMethodArguments * arguments,
                                                       const IOUserClientMethodDispatch * dispatch,
                                                       OSObject * target,
                                                       void * reference)
{
    switch (selector) {
        case kGamepadUserClientPostReport: {
            if (!ivars || !ivars->driver) {
                return kIOReturnNotReady;
            }
            if (!arguments || !arguments->structureInput) {
                return kIOReturnBadArgument;
            }
            OSData * input = arguments->structureInput;
            const void * bytes = input->getBytesNoCopy();
            uint32_t length = static_cast<uint32_t>(input->getLength());
            if (!bytes || length == 0) {
                return kIOReturnBadArgument;
            }
            return ivars->driver->postReport(bytes, length);
        }
        default:
            return super::ExternalMethod(selector, arguments, dispatch, target, reference);
    }
}
