#!/bin/bash
# ============================================================
#  tune-openstick.sh
#  Performance tuning for MSM8916 Debian (JZ0145_V33 / UZ801 / UFI001C).
#
#  Applies:
#    - haveged entropy daemon
#    - vm.swappiness = 100 for zram
#    - kernel.printk = 3 4 1 3 (quieter dmesg)
#    - thermal monitoring via cron every 5 min
#    - zram package conflict resolution
#
#  Idempotent — safe to re-run.
#
#  Usage:  sudo bash tune-openstick.sh
# ============================================================

set -e

# -------- helpers --------
say()  { echo -e "\n\033[1;36m$*\033[0m"; }
ok()   { echo -e "  \033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "  \033[1;33m[WARN]\033[0m $*"; }
die()  { echo -e "\n\033[1;31m[ERROR]\033[0m $*"; exit 1; }

[ "$EUID" -eq 0 ] || die "Run as root: sudo bash $0"

echo "============================================================"
echo "  MSM8916 Debian Tuning"
echo "============================================================"

# -------- 1. haveged --------
say "[1/6] Installing haveged entropy daemon"
apt install -y haveged
systemctl enable --now haveged
ok "haveged active"

# -------- 2. swappiness --------
say "[2/6] Setting vm.swappiness=100"
cat > /etc/sysctl.d/99-zram.conf <<'EOF'
# Aggressive swap for zram-backed device with small RAM.
# zram is fast (RAM-backed), so swapping is cheaper than dropping cache.
vm.swappiness=100
EOF
sysctl -p /etc/sysctl.d/99-zram.conf >/dev/null
ok "swappiness = $(cat /proc/sys/vm/swappiness)"

# -------- 3. printk --------
say "[3/6] Reducing kernel console noise"
cat > /etc/sysctl.d/99-printk.conf <<'EOF'
# Quiet console: keep errors (3) and warnings (4), drop alerts and debug.
kernel.printk=3 4 1 3
EOF
sysctl -p /etc/sysctl.d/99-printk.conf >/dev/null
ok "printk = $(cat /proc/sys/kernel/printk)"

# -------- 4. thermal monitor --------
say "[4/6] Setting up thermal monitor"

# Detect a valid thermal zone
TZ=""
for z in /sys/class/thermal/thermal_zone*; do
    if [ -r "$z/temp" ]; then
        TZ="$z"
        break
    fi
done

if [ -n "$TZ" ]; then
    cat > /root/heat_check.sh <<EOF
#!/bin/bash
# Warn if SoC temperature exceeds 75°C
TEMP=\$(cat ${TZ}/temp)
if [ "\$TEMP" -gt 75000 ]; then
    echo "CRITICAL HEAT: \$((TEMP/1000))°C" | wall
fi
EOF
    chmod +x /root/heat_check.sh

    cat > /etc/cron.d/heat_check <<'EOF'
*/5 * * * * root /root/heat_check.sh
EOF
    ok "Thermal monitor installed (zone: $TZ)"
else
    warn "No readable thermal zone — skipping thermal monitor"
fi

# -------- 5. zram conflict --------
say "[5/6] Resolving zram package conflict"

has_generator=0
has_tools=0
dpkg -l 2>/dev/null | grep -q "^ii  systemd-zram-generator" && has_generator=1
dpkg -l 2>/dev/null | grep -q "^ii  zram-tools" && has_tools=1

if [ "$has_generator" = "1" ] && [ "$has_tools" = "1" ]; then
    systemctl disable --now zramswap.service 2>/dev/null || true
    apt-mark manual systemd-zram-generator
    apt-mark auto zram-tools 2>/dev/null || true
    apt --purge autoremove -y
    ok "Removed zram-tools, kept systemd-zram-generator"
elif [ "$has_generator" = "1" ]; then
    ok "Only systemd-zram-generator installed (correct)"
elif [ "$has_tools" = "1" ]; then
    warn "Only zram-tools installed — consider switching to systemd-zram-generator"
else
    warn "No zram package installed — installing systemd-zram-generator"
    apt install -y systemd-zram-generator
fi

# -------- 6. verify --------
say "[6/6] Verification"

check() {
    printf "  %-22s " "$1:"
    eval "$2" 2>/dev/null || echo "(failed)"
}

check "Kernel"          "uname -r"
check "OS"              "grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2"
check "Swappiness"      "cat /proc/sys/vm/swappiness"
check "Printk"          "cat /proc/sys/kernel/printk"
check "haveged"         "systemctl is-active haveged"
check "Entropy (bits)"  "cat /proc/sys/kernel/random/entropy_avail"
check "zram"            "zramctl --noheadings 2>/dev/null | awk '{print \$1, \$2, \$3}'"
check "Temperature"     "echo \$((\$(cat ${TZ:-/sys/class/thermal/thermal_zone0}/temp)/1000))°C"

echo ""
echo "============================================================"
echo "  TUNING COMPLETE"
echo "============================================================"
echo ""
echo "See docs/TUNING.md for details on each setting."
