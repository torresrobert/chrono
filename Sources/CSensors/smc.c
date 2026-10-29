#include "CSensors.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} smc_vers_t;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} smc_plimit_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} smc_keyinfo_t;

typedef struct {
    UInt32 key;
    smc_vers_t vers;
    smc_plimit_t pLimitData;
    smc_keyinfo_t keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    unsigned char bytes[32];
} smc_param_t;

static io_connect_t smc_conn = 0;

static UInt32 fourcc(const char *s) {
    return ((UInt32)(unsigned char)s[0] << 24) | ((UInt32)(unsigned char)s[1] << 16) |
           ((UInt32)(unsigned char)s[2] << 8) | (UInt32)(unsigned char)s[3];
}

static void unfourcc(UInt32 v, char *out) {
    out[0] = (char)(v >> 24);
    out[1] = (char)(v >> 16);
    out[2] = (char)(v >> 8);
    out[3] = (char)v;
    out[4] = 0;
}

static kern_return_t smc_call(smc_param_t *in, smc_param_t *out) {
    size_t outSize = sizeof(smc_param_t);
    return IOConnectCallStructMethod(smc_conn, KERNEL_INDEX_SMC, in, sizeof(smc_param_t), out, &outSize);
}

int smc_open(void) {
    if (smc_conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &smc_conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) {
        smc_conn = 0;
        return -1;
    }
    return 0;
}

void smc_close(void) {
    if (smc_conn) {
        IOServiceClose(smc_conn);
        smc_conn = 0;
    }
}

static int smc_key_info(UInt32 key, smc_keyinfo_t *info) {
    smc_param_t in, out;
    memset(&in, 0, sizeof in);
    memset(&out, 0, sizeof out);
    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) return -1;
    *info = out.keyInfo;
    return 0;
}

// Key info never changes at runtime, so cache it (open addressing, keyed by fourcc).
#define CACHE_SIZE 8192
static struct { UInt32 key; smc_keyinfo_t info; } info_cache[CACHE_SIZE];

static int smc_key_info_cached(UInt32 key, smc_keyinfo_t *info) {
    UInt32 slot = (key * 2654435761u) & (CACHE_SIZE - 1);
    for (int probe = 0; probe < CACHE_SIZE; probe++) {
        UInt32 i = (slot + probe) & (CACHE_SIZE - 1);
        if (info_cache[i].key == key) {
            *info = info_cache[i].info;
            return 0;
        }
        if (info_cache[i].key == 0) {
            if (smc_key_info(key, info) != 0) return -1;
            info_cache[i].key = key;
            info_cache[i].info = *info;
            return 0;
        }
    }
    return smc_key_info(key, info);
}

static int smc_read_raw(const char *key, char *type, unsigned char *bytes, UInt32 *size) {
    if (!smc_conn && smc_open() != 0) return -1;
    UInt32 k = fourcc(key);
    smc_keyinfo_t info;
    if (smc_key_info_cached(k, &info) != 0) return -1;

    smc_param_t in, out;
    memset(&in, 0, sizeof in);
    memset(&out, 0, sizeof out);
    in.key = k;
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) return -1;

    unfourcc(info.dataType, type);
    *size = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(bytes, out.bytes, *size);
    return 0;
}

int smc_read_double(const char *key, double *outValue) {
    char type[5];
    unsigned char b[32];
    UInt32 size = 0;
    if (smc_read_raw(key, type, b, &size) != 0 || size == 0) return -1;

    if (strcmp(type, "flt ") == 0 && size == 4) {
        float f;
        memcpy(&f, b, 4);  // little-endian on Apple Silicon
        *outValue = f;
    } else if (strcmp(type, "fpe2") == 0 && size == 2) {
        *outValue = ((b[0] << 8) | b[1]) / 4.0;
    } else if (strcmp(type, "sp78") == 0 && size == 2) {
        *outValue = (int16_t)((b[0] << 8) | b[1]) / 256.0;
    } else if (strcmp(type, "ui8 ") == 0) {
        *outValue = b[0];
    } else if (strcmp(type, "ui16") == 0 && size == 2) {
        *outValue = (b[0] << 8) | b[1];
    } else if (strcmp(type, "ui32") == 0 && size == 4) {
        *outValue = ((UInt32)b[0] << 24) | ((UInt32)b[1] << 16) | ((UInt32)b[2] << 8) | b[3];
    } else if (strcmp(type, "si8 ") == 0) {
        *outValue = (int8_t)b[0];
    } else if (strcmp(type, "si16") == 0 && size == 2) {
        *outValue = (int16_t)((b[0] << 8) | b[1]);
    } else {
        return -1;
    }
    return 0;
}

uint32_t smc_key_count(void) {
    double v = 0;
    if (smc_read_double("#KEY", &v) != 0) return 0;
    return (uint32_t)v;
}

int smc_key_at(uint32_t index, char *key, char *type) {
    if (!smc_conn && smc_open() != 0) return -1;
    smc_param_t in, out;
    memset(&in, 0, sizeof in);
    memset(&out, 0, sizeof out);
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = index;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) return -1;
    unfourcc(out.key, key);

    smc_keyinfo_t info;
    if (smc_key_info_cached(out.key, &info) != 0) return -1;
    unfourcc(info.dataType, type);
    return 0;
}
