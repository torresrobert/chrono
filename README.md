# Vitals

A native macOS menu bar system monitor (Swift + SwiftUI, no dependencies). Each module gets its own
menu bar item; clicking one opens a detail panel.

| Module   | Menu bar               | Panel |
|----------|------------------------|-------|
| CPU      | history graph + %      | user/system/idle, load averages, per-core bars grouped by cluster, top processes, uptime |
| GPU      | history graph + %      | device/renderer utilization, memory in use, temperature |
| Memory   | ring + %               | app/wired/compressed/cached breakdown, swap, pressure, history, top processes |
| Disk     | read/write rates       | throughput history, capacity of every mounted volume |
| Network  | up/down rates          | throughput history, peaks, primary interface + local IP, totals since boot |
| Sensors  | CPU temperature        | CPU/GPU/memory/SSD/airflow temperatures (avg + max), fan speeds, total system power |
| Battery  | level                  | charge state, time remaining, health (hidden on desktops) |

CPU, Memory, Network and Sensors are on by default; toggle modules, captions, update interval,
°C/°F and launch-at-login in Settings (gear icon in any panel). ⌘-drag items to reorder them.

## Build & install

```sh
./scripts/bundle.sh            # builds build/Vitals.app (release, ad-hoc signed)
./scripts/bundle.sh --install  # also copies to /Applications and launches it
```

Requires macOS 14+ and Xcode / Swift 6 toolchain. Apple Silicon only (the build is arm64).

## Diagnostics

```sh
swift run Vitals --dump            # print every reading once
swift run Vitals --snapshot DIR    # render each panel (light + dark) and the menu bar to PNGs
swift run Vitals --selftest        # launch for real, open each panel, report geometry, quit
```

## Where the numbers come from

- **CPU**: `host_processor_info` tick deltas; clusters from `hw.perflevelN.*` sysctls.
- **Memory**: `host_statistics64` (same accounting as Activity Monitor), `vm.swapusage`,
  `kern.memorystatus_vm_pressure_level`.
- **Processes**: `proc_pid_rusage` (CPU time deltas, physical footprint). Only sampled while a
  CPU/Memory panel is open; processes owned by other users (root daemons) aren't readable without root.
- **GPU**: `IOAccelerator` → `PerformanceStatistics`.
- **Disk**: `IOBlockStorageDriver` statistics; capacity uses "available for important usage" like Finder.
- **Network**: 64-bit counters from `NET_RT_IFLIST2`, summed over `en*` interfaces.
- **Sensors**: AppleSMC (`Sources/CSensors/smc.c`) for temperatures, fans (`F*Ac/Mn/Mx`) and system
  power (`PSTR`); HID temperature sensors (`hid.c`) as a CPU fallback. SMC key layouts differ per chip,
  so groups are discovered at launch by key prefix (`Tp/Te` CPU, `Tg` GPU, `Tm` memory, `TN` SSD,
  `TaF/TaR` airflow) and up to 6 keys per group are sampled each tick.
