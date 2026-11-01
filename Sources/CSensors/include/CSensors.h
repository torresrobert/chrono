#ifndef CSENSORS_H
#define CSENSORS_H

#include <stdint.h>

// MARK: - SMC (System Management Controller)

/// Opens a connection to AppleSMC. Returns 0 on success.
int smc_open(void);
void smc_close(void);

/// Reads a key and decodes it to a double (flt, fpe2, sp78, ui8/16/32, si8/16).
/// Returns 0 on success.
int smc_read_double(const char *key, double *out);

/// Number of keys exposed by the SMC (0 if unavailable).
uint32_t smc_key_count(void);

/// Fills `key` (5 bytes incl. NUL) and `type` (5 bytes incl. NUL) for the key at `index`.
/// Returns 0 on success.
int smc_key_at(uint32_t index, char *key, char *type);

// MARK: - HID temperature sensors (Apple Silicon)

typedef struct {
    char name[64];
    double celsius;
} hid_temperature_t;

/// Reads all HID temperature sensors. Returns the number written (<= max).
int hid_read_temperatures(hid_temperature_t *out, int max);

// MARK: - GPU clock and power (IOReport, Apple Silicon)

typedef struct {
    double active;     // fraction of the interval the GPU spent in a performance state
    double megahertz;  // average clock while active; 0 if it was never active or the table is unknown
    double watts;      // GPU power over the interval; negative if unknown
} gpu_perf_t;

/// Subscribes to the GPU performance-state and energy channels. Returns 0 on success.
int gpu_perf_open(void);

/// Fills `out` with readings since the previous call. Returns 0 on success.
int gpu_perf_sample(gpu_perf_t *out);

/// The GPU's highest clock in MHz, or 0 if unknown.
double gpu_perf_max_megahertz(void);

#endif
