# Omarchy Power & Hardware Monitor

A high-performance Quickshell panel and top-bar widget for Omarchy Linux that extends the default battery indicator with live hardware telemetry, power profiles, and btop-style dynamic resource graphs.

---

## Overview

The standard Omarchy battery widget only reports state of charge and power profile buttons. When tuning performance or diagnosing thermal throttling on laptops and handhelds, users had to launch external terminals running `btop` or `htop`.

**Omarchy Power Monitor** replaces the stock widget with a complete system health HUD:
- **Instant System Pulse**: View battery charge percentage, charging rate, and power profile at a glance.
- **CPU Telemetry**: Track real-time CPU load (`%`), package temperature (`°C`), and socket wattage (`W`).
- **Memory Metrics**: Monitor Total RAM, Used RAM, and Free/Available RAM in GiB.
- **Btop-Style Dynamic Graphs**: Watch smooth, auto-scaling 30-sample historical canvas graphs for both CPU and Memory.
- **Zero Overhead**: Samples directly from `/proc` and `/sys/class/hwmon` every 5 seconds only while the flyout panel is open.

---

## Visual Behavior & UX

### Top Bar Indicator
- Shows the current battery glyph reflecting state (charging, discharging, threshold, full).
- Displays battery percentage next to the glyph when enabled.
- Highlights charging with an active accent tint.

### Flyout Panel Layout
When clicked or triggered via IPC (`quickshell ipc call omarchy.power open`):

| Section | Content | Behavior |
| :--- | :--- | :--- |
| **Hero Card** | Large battery icon, status phrase, charge percentage | Rotates status phrasing smoothly during charge/discharge. |
| **Charge Bar** | Visual charge progress bar | Pulses gently while charging is active. |
| **Battery Details** | Time remaining, power draw, health condition | Only displays when battery hardware reports valid data. |
| **Power Profiles** | Performance, Balanced, Power Saver buttons | Highlights active profile; clicks invoke `power-profiles-daemon`. |
| **CPU Telemetry** | Load %, Temperature (°C), Package Power (W) | Live 30-sample historical line graph, fixed 0–100% scale. |
| **Memory Telemetry**| Total, Used, Available RAM (GiB), Used % | Dynamic auto-scaled line graph showing consumption trends. |

---

## Prerequisites

- **OS**: Arch Linux or Arch-based distributions running Omarchy (`omarchy-shell` / `quickshell`).
- **Python**: Python 3.8+ (standard library only; no pip dependencies required).
- **Sensors**: Kernel hwmon support (`k10temp`, `zenpower`, `coretemp`, `amdgpu`, or generic ACPI).
- **Services**: `upower`, `power-profiles-daemon` (standard on Omarchy).

---

## Installation

### 1. Clone into Omarchy Plugin Directory
Clone this repository directly into your user plugin path:

```bash
git clone https://github.com/<your-username>/omarchy-power-monitor.git ~/.config/omarchy/plugins/kinara.power
chmod +x ~/.config/omarchy/plugins/kinara.power/hardware-stats
```

### 2. Enable in Omarchy Shell Configuration
Open `~/.config/omarchy/shell.json` in your editor and locate the `bar` items array. Replace `omarchy.power` with `kinara.power`:

```json
{
  "plugins": {
    "bar": [
      "omarchy.workspace-switcher",
      "omarchy.media-player",
      "kinara.power",
      "omarchy.clock"
    ]
  }
}
```

### 3. Reload the Shell
Reload Quickshell to apply the plugin:

```bash
quickshell ipc -p /usr/share/omarchy/shell call omarchy.power open
```

Or restart the quickshell service:

```bash
systemctl --user restart quickshell
```

---

## Technical Details

### Sensor Resolution Logic
`hardware-stats` executes non-privileged queries without external daemons:
- **CPU Utilization**: Calculated from two snapshots of `/proc/stat` across a 250ms sampling window.
- **CPU Temperature**: Discovers labeled hwmon sensor nodes (`k10temp Tctl`, `coretemp Package id 0`, or fallback `temp*_input`).
- **Power Draw**: Detects socket package power (`amdgpu PPT`, `BAT0/BAT1 power_input`, or ACPI power meter).
- **Memory**: Parsed from `/proc/meminfo` (`MemTotal`, `MemAvailable`). Free memory calculation uses available memory to reflect real headroom rather than unallocated pages.

---

## Verification & Health Check

Test telemetry collection manually in terminal:

```bash
~/.config/omarchy/plugins/kinara.power/hardware-stats
```

Expected output:
```text
cpu_percent=3%
cpu_temp=48 °C
cpu_watt=12.4 W
ram_total=14.4 GiB
ram_used=9.8 GiB
ram_free=4.6 GiB
ram_percent=68.1
```

Inspect Quickshell logs if the panel does not open:

```bash
journalctl --user -u quickshell -n 50 --no-pager
```

---

## Uninstallation

To revert to the stock Omarchy power widget:

1. Restore `omarchy.power` in `~/.config/omarchy/shell.json`.
2. Remove the plugin directory:
   ```bash
   rm -rf ~/.config/omarchy/plugins/kinara.power
   ```
3. Restart Quickshell:
   ```bash
   systemctl --user restart quickshell
   ```

---

## License

MIT License.
