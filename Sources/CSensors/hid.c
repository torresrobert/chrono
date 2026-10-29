#include "CSensors.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <string.h>

// Private IOKit HID event API (exported by IOKit.framework, not in public headers).
typedef struct __IOHIDEvent *IOHIDEventRef;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kIOHIDEventTypeTemperature 15
#define IOHIDEventFieldBase(type) ((type) << 16)

static IOHIDEventSystemClientRef client = NULL;

static void ensure_client(void) {
    if (client) return;
    client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return;

    int page = 0xff00, usage = 5;  // AppleVendor / TemperatureSensor
    CFNumberRef pageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *vals[] = {pageNum, usageNum};
    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
                                               &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(client, match);
    CFRelease(match);
    CFRelease(pageNum);
    CFRelease(usageNum);
}

int hid_read_temperatures(hid_temperature_t *out, int max) {
    ensure_client();
    if (!client) return 0;

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) return 0;

    int n = 0;
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count && n < max; i++) {
        IOHIDServiceClientRef svc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        CFStringRef name = IOHIDServiceClientCopyProperty(svc, CFSTR("Product"));
        if (!name) continue;

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0);
        if (event) {
            double t = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(kIOHIDEventTypeTemperature));
            if (t > 0 && t < 150 && CFStringGetCString(name, out[n].name, sizeof out[n].name, kCFStringEncodingUTF8)) {
                out[n].celsius = t;
                n++;
            }
            CFRelease(event);
        }
        CFRelease(name);
    }
    CFRelease(services);
    return n;
}
