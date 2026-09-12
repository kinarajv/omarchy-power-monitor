# Omarchy Power & Hardware Monitor

A high-performance Quickshell panel and top-bar widget for Omarchy Linux that extends the default battery indicator with live hardware telemetry, power profiles, and btop-style dynamic resource graphs.

---

## Overview

The standard Omarchy battery widget only reports state of charge and power profile buttons. When tuning performance or diagnosing thermal throttling on laptops and handhelds, users had to launch external terminals running `btop` or `htop`.

**Omarchy Power Monitor** replaces the stock widget with a complete system health HUD:
- **Instant System Pulse**: View battery charge percentage, charging rate, and power profile at a glance.
- **CPU Telemetry**: Track real-time CPU load (`%`), package temperature (`°C`), and socket wattage (`W`).
- **Memory Metrics**: Monitor Total RAM, Used RAM, and Free/Available RAM in GiB.
- **Btop-Style Dynamic Graphs**: Watch smooth, auto-scaling historical canvas graphs for both CPU and Memory.
- **Zero Overhead**: Samples directly from `/proc` and `/sys/class/hwmon` every 5 seconds only while the flyout panel is open.
- **Fully Configurable**: Easily configure sensor sources, polling intervals, sample limits, and display options via JSON or environment variables.

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
| **CPU Telemetry** | Load %, Temperature (°C), Package Power (W) | Live historical line graph, fixed 0–100% scale. |
| **Memory Telemetry**| Total, Used, Available RAM (GiB), Used % | Dynamic auto-scaled line graph showing consumption trends. |

---

## Configuration Guide

The widget works automatically out of the box with intelligent sensor auto-detection (AMD Ryzen, Intel Core, and ACPI). You can customize behavior using `config.json`, global configuration, or environment variables.

### Configuration File Locations

Settings are loaded in this priority:
1. Environment variables
2. Plugin config: `~/.config/omarchy/plugins/kinara.power/config.json`
3. Global config: `~/.config/omarchy/power-monitor.json`

To customize, copy `config.example.json`:

```bash
cp config.example.json config.json
```

### Configuration Options Reference

| Key | Environment Variable | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `tempSensorName` | `POWER_TEMP_NAME` | `"k10temp"` | Name of hwmon device for CPU temperature (`k10temp`, `coretemp`, `zenpower`) |
| `tempSensorLabel` | `POWER_TEMP_LABEL` | `"Tctl"` | Labeled sensor input (`Tctl`, `Package id 0`, `Tdie`) |
| `powerSensorName` | `POWER_NAME` | `"amdgpu"` | Name of hwmon device for package power (`amdgpu`, `BAT0`, `power_meter`) |
| `powerSensorLabel` | `POWER_LABEL` | `"PPT"` | Labeled power input (`PPT`, `power1_input`) |
| `sampleDelaySeconds` | `POWER_SAMPLE_DELAY` | `0.25` | Duration (seconds) between `/proc/stat` reads for CPU delta calculation |
| `refreshIntervalMs` | — | `5000` | Quickshell UI refresh timer while panel is open (milliseconds) |
| `historySampleLimit`| — | `30` | Number of historical samples retained for the dynamic canvas graphs |

---

### Hardware Configuration Examples

#### AMD Ryzen Laptop / APU (Default)
```json
{
  "tempSensorName": "k10temp",
  "tempSensorLabel": "Tctl",
  "powerSensorName": "amdgpu",
  "powerSensorLabel": "PPT",
  "sampleDelaySeconds": 0.25
}
```

#### Intel Core Laptop
```json
{
  "tempSensorName": "coretemp",
  "tempSensorLabel": "Package id 0",
  "powerSensorName": "BAT0",
  "powerSensorLabel": "power",
  "sampleDelaySeconds": 0.25
}
```

#### Finding Your Available Sensors
Run this one-liner in your terminal to inspect all recognized sensors on your system:

```bash
for n in /sys/class/hwmon/hwmon*/name; do echo "Device: $(cat $n) in $(dirname $n)"; ls -l $(dirname $n)/*_label 2>/dev/null; done
```

---

## Installation

### Method 1: Using the Omarchy Plugin Manager (Recommended)
Install and enable the plugin directly from GitHub using the Omarchy CLI:

```bash
omarchy plugin add https://github.com/kinarajv/omarchy-power-monitor.git --enable
```

### Method 2: Manual Installation
Clone this repository directly into your user plugin path:

```bash
git clone https://github.com/kinarajv/omarchy-power-monitor.git ~/.config/omarchy/plugins/kinarajv.power-monitor
chmod +x ~/.config/omarchy/plugins/kinarajv.power-monitor/hardware-stats
```

Optional sensor customization:
```bash
cd ~/.config/omarchy/plugins/kinarajv.power-monitor
cp config.example.json config.json
```

Enable the plugin in `~/.config/omarchy/shell.json` by adding `"kinarajv.power-monitor"` to the `bar` list, then reload:

```bash
omarchy plugin enable kinarajv.power-monitor
```

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
 
### Using the Plugin Manager:
```bash
omarchy plugin disable kinarajv.power-monitor
omarchy plugin remove kinarajv.power-monitor --yes
```

### Manual Removal:
1. Remove `kinarajv.power-monitor` from `~/.config/omarchy/shell.json`.
2. Delete the plugin directory:
   ```bash
   rm -rf ~/.config/omarchy/plugins/kinarajv.power-monitor
   ```
3. Restart Quickshell:
   ```bash
   systemctl --user restart quickshell
   ```

---

## License

MIT License.
