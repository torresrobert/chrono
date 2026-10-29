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

#endif
