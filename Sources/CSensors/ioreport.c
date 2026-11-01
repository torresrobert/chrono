// GPU clock and power on Apple Silicon, from IOReport (libIOReport, the interface powermetrics
// uses). It's private API, but needs no privileges; if the channels aren't there, nothing is reported.

#include "CSensors.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct IOReportSubscription *IOReportSubscriptionRef;

extern CFMutableDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a,
                                                          uint64_t b, uint64_t c);
extern void IOReportMergeChannels(CFMutableDictionaryRef into, CFMutableDictionaryRef from, CFTypeRef unused);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *unused, CFMutableDictionaryRef channels,
                                                          CFMutableDictionaryRef *subscribed, uint64_t id,
                                                          CFTypeRef options);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef subscription, CFMutableDictionaryRef channels,
                                             CFTypeRef unused);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef previous, CFDictionaryRef current, CFTypeRef unused);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef channel);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef channel);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef channel);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index);
extern int32_t IOReportStateGetCount(CFDictionaryRef channel);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef channel, int32_t index);
extern int64_t IOReportStateGetResidency(CFDictionaryRef channel, int32_t index);

#define MAX_STATES 32

static IOReportSubscriptionRef subscription;
static CFMutableDictionaryRef subscribed;
static CFDictionaryRef previous;
static uint64_t previous_time;
static double clocks[MAX_STATES];  // MHz of P1, P2, …
static int clock_count;

/// The GPU's DVFS table: pairs of (frequency, voltage) as little-endian UInt32 in pmgr's
/// "voltage-states9". Frequencies are Hz on most chips and kHz on some; zero entries are "off".
static void read_clock_table(void) {
    io_service_t pmgr = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"));
    if (!pmgr) return;
    CFTypeRef data = IORegistryEntryCreateCFProperty(pmgr, CFSTR("voltage-states9"), kCFAllocatorDefault, 0);
    IOObjectRelease(pmgr);
    if (!data) return;
    if (CFGetTypeID(data) == CFDataGetTypeID()) {
        const uint8_t *bytes = CFDataGetBytePtr(data);
        CFIndex length = CFDataGetLength(data);
        double max = 0;
        for (CFIndex offset = 0; offset + 8 <= length && clock_count < MAX_STATES; offset += 8) {
            uint32_t frequency;
            memcpy(&frequency, bytes + offset, 4);
            if (frequency == 0) continue;
            clocks[clock_count++] = frequency;
            if (frequency > max) max = frequency;
        }
        double scale = max < 1e7 ? 1e-3 : 1e-6;  // kHz or Hz, to MHz
        for (int i = 0; i < clock_count; i++) clocks[i] *= scale;
    }
    CFRelease(data);
}

static int string_equals(CFStringRef string, const char *expected) {
    char buffer[64];
    return string && CFStringGetCString(string, buffer, sizeof buffer, kCFStringEncodingUTF8)
        && strcmp(buffer, expected) == 0;
}

int gpu_perf_open(void) {
    if (subscription) return 0;
    read_clock_table();
    CFMutableDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("GPU Stats"), CFSTR("GPU Performance States"), 0, 0, 0);
    CFMutableDictionaryRef energy = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    if (!channels || !energy) {
        if (channels) CFRelease(channels);
        if (energy) CFRelease(energy);
        return -1;
    }
    // The energy group has hundreds of channels and sampling all of them costs ~5 ms; keep the GPU's.
    CFArrayRef all = CFDictionaryGetValue(energy, CFSTR("IOReportChannels"));
    if (all && CFGetTypeID(all) == CFArrayGetTypeID()) {
        CFMutableArrayRef gpu = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        for (CFIndex i = 0; i < CFArrayGetCount(all); i++) {
            CFDictionaryRef channel = CFArrayGetValueAtIndex(all, i);
            if (string_equals(IOReportChannelGetChannelName(channel), "GPU Energy")) CFArrayAppendValue(gpu, channel);
        }
        CFDictionarySetValue(energy, CFSTR("IOReportChannels"), gpu);
        CFRelease(gpu);
    }
    IOReportMergeChannels(channels, energy, NULL);
    CFRelease(energy);
    subscription = IOReportCreateSubscription(NULL, channels, &subscribed, 0, NULL);
    CFRelease(channels);
    if (!subscription) return -1;
    previous = IOReportCreateSamples(subscription, subscribed, NULL);
    previous_time = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    return previous ? 0 : -1;
}

double gpu_perf_max_megahertz(void) {
    return clock_count > 0 ? clocks[clock_count - 1] : 0;
}

int gpu_perf_sample(gpu_perf_t *out) {
    if (!subscription || !previous) return -1;
    CFDictionaryRef current = IOReportCreateSamples(subscription, subscribed, NULL);
    if (!current) return -1;
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    double seconds = (now - previous_time) / 1e9;
    CFDictionaryRef delta = IOReportCreateSamplesDelta(previous, current, NULL);
    CFRelease(previous);
    previous = current;
    previous_time = now;
    if (!delta) return -1;

    out->active = 0;
    out->megahertz = 0;
    out->watts = -1;
    int found = 0;
    CFArrayRef list = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        CFDictionaryRef channel = CFArrayGetValueAtIndex(list, i);
        CFStringRef name = IOReportChannelGetChannelName(channel);
        if (string_equals(name, "GPUPH")) {
            // States are OFF (and on some chips IDLE/DOWN), then P1…Pn from slowest to fastest.
            double total = 0, active = 0, weighted = 0;
            for (int32_t s = 0; s < IOReportStateGetCount(channel); s++) {
                double residency = (double)IOReportStateGetResidency(channel, s);
                total += residency;
                char state[16] = "";
                CFStringRef stateName = IOReportStateGetNameForIndex(channel, s);
                if (!stateName || !CFStringGetCString(stateName, state, sizeof state, kCFStringEncodingUTF8)) continue;
                if (state[0] != 'P' || state[1] < '1' || state[1] > '9') continue;
                active += residency;
                int index = atoi(state + 1) - 1;
                if (index >= 0 && index < clock_count) weighted += residency * clocks[index];
            }
            if (total > 0) {
                out->active = active / total;
                out->megahertz = active > 0 && clock_count > 0 ? weighted / active : 0;
                found = 1;
            }
        } else if (string_equals(name, "GPU Energy") && string_equals(IOReportChannelGetGroup(channel), "Energy Model")
                   && seconds > 0) {
            double value = (double)IOReportSimpleGetIntegerValue(channel, 0);
            CFStringRef unit = IOReportChannelGetUnitLabel(channel);
            double joules = string_equals(unit, "mJ") ? value / 1e3
                : string_equals(unit, "uJ") ? value / 1e6 : value / 1e9;
            out->watts = joules / seconds;
            found = 1;
        }
    }
    CFRelease(delta);
    return found ? 0 : -1;
}
