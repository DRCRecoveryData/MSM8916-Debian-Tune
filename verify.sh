#!/bin/bash
# ============================================================
#  verify.sh
#  Print a snapshot of the current MSM8916 Debian system state.
#
#  Usage:  bash verify.sh        (no root needed)
# ============================================================

set -e

line() { printf "%-20s %s\n" "$1:" "$2"; }
sep()  { echo "----------------------------------------"; }

echo "============================================================"
echo "  MSM8916 Debian — System Verification"
echo "  $(date)"
echo "============================================================"
echo ""

sep; echo "OS"; sep
line "Hostname"    "$(hostname)"
line "Kernel"      "$(uname -r)"
line "Arch"        "$(uname -m)"
line "OS"          "$(grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2)"
line "Uptime"      "$(uptime -p)"
echo ""

sep; echo "Memory"; sep
line "RAM total"   "$(free -h | awk '/^Mem:/ {print $2}')"
line "RAM used"    "$(free -h | awk '/^Mem:/ {print $3}')"
line "Swap total"  "$(free -h | awk '/^Swap:/ {print $2}')"
line "Swap used"   "$(free -h | awk '/^Swap:/ {print $3}')"
echo ""

sep; echo "CPU / Thermal"; sep
TEMP=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1)
if [ -n "$TEMP" ]; then
    line "SoC temp"  "$((TEMP/1000))°C"
fi
line "Load"  "$(uptime | awk -F'load average:' '{print $2}')"
echo ""

sep; echo "Network"; sep
for iface in $(ls /sys/class/net | grep -v lo); do
    IP=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | head -1)
    line "$iface" "${IP:-(no IPv4)}"
done
echo ""

sep; echo "Storage"; sep
df -h / /boot 2>/dev/null | awk 'NR>1 {printf "%-20s %s used / %s (%s)\n", $6":", $3, $2, $5}'
echo ""

sep; echo "Tuning"; sep
line "swappiness"   "$(cat /proc/sys/vm/swappiness)"
line "printk"       "$(cat /proc/sys/kernel/printk)"
line "entropy"      "$(cat /proc/sys/kernel/random/entropy_avail) bits"
line "zram"         "$(zramctl --noheadings 2>/dev/null | awk '{print $1, $2, $3}' | head -1)"
echo ""

sep; echo "Services"; sep
for svc in haveged ssh led-config adb-gadget systemd-zram-setup@zram0 reset-listener; do
    state=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
    printf "%-20s %s\n" "$svc:" "$state"
done
echo ""

sep; echo "Kernel packages held"; sep
apt-mark showhold 2>/dev/null | grep -E "linux-(image|headers)" || echo "(none)"
echo ""

sep; echo "LEDs (GPIO assignment)"; sep
for c in wifi internet os; do
    P="/proc/device-tree/leds/$c/gpios"
    if [ -r "$P" ]; then
        # bytes 4-7 = GPIO number
        G=$(od -A n -t x1 "$P" | tr -d ' \n' | cut -c9-16)
        line "$c" "GPIO 0x$G"
    else
        line "$c" "(not in device tree)"
    fi
done
echo ""

sep; echo "LED triggers (current)"; sep
for led in blue:wifi green:internet red:os; do
    T="/sys/class/leds/$led/trigger"
    if [ -r "$T" ]; then
        cur=$(cat "$T" | tr ' ' '\n' | grep '\[' | tr -d '[]')
        line "$led" "$cur"
    fi
done
echo ""

echo "============================================================"
