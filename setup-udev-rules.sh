#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: setup-udev-rules.sh requires root privileges." >&2
  echo "Usage: sudo $0" >&2
  exit 1
fi

cat << 'EOF' > /etc/udev/rules.d/99-battery-charge-threshold.rules
ACTION=="add|change", SUBSYSTEM=="power_supply", ATTR{charge_control_end_threshold}!="", MODE="0666"
EOF

cat << 'EOF' > /etc/tmpfiles.d/battery-charge-threshold.conf
z /sys/class/power_supply/BAT*/charge_control_end_threshold 0666 root root -
EOF

udevadm control --reload-rules
udevadm trigger --subsystem-match=power_supply
chmod 0666 /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null || true

echo "Battery charge threshold permissions configured."
echo "Any custom percentage (e.g. 89%, 85%, 60%) can now be set without root."
