#!/bin/bash
# ============================================================
#  upgrade-to-trixie.sh
#  Debian 11 (bullseye) -> 13 (trixie) upgrade for MSM8916 dongles.
#
#  Preserves a custom kernel and disables conflicting zram services.
#  Tested on JZ01-45-@ / JZ0145_V33 / UZ801 / UFI001C.
#
#  Usage:  sudo bash upgrade-to-trixie.sh
#
#  Requirements:
#    - Running Debian 11 (bullseye)
#    - Full EDL backup already taken
#    - Inside screen/tmux if accessed over SSH
# ============================================================

set -e

# -------- config --------
CUSTOM_KERNEL_PKG="linux-image-5.15.0-handsomekernel+"
CUSTOM_HEADERS_PKG="linux-headers-5.15.0-handsomekernel+"

# -------- helpers --------
say()  { echo -e "\n\033[1;36m$*\033[0m"; }
ok()   { echo -e "  \033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "  \033[1;33m[WARN]\033[0m $*"; }
die()  { echo -e "\n\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# -------- preflight --------
[ "$EUID" -eq 0 ] || die "Run as root: sudo bash $0"

if ! grep -q "bullseye" /etc/os-release; then
    echo "Detected OS:"
    grep PRETTY_NAME /etc/os-release
    die "This script upgrades from bullseye (Debian 11). Aborting."
fi
ok "Debian bullseye detected"

# Confirm backup
say "Before continuing, confirm:"
echo "  - You have taken a full EDL backup of this device"
echo "  - You are running inside screen or tmux"
echo "  - You can recover via EDL if the device fails to boot"
echo ""
read -p "Type 'yes' to proceed: " confirm
[ "$confirm" = "yes" ] || { echo "Aborted."; exit 0; }

# -------- phase 1: prepare --------
say "Phase 1 — Preparation"

# 1. Pin custom kernel
if dpkg -l 2>/dev/null | grep -q "^ii  ${CUSTOM_KERNEL_PKG}$"; then
    apt-mark hold "$CUSTOM_KERNEL_PKG" 2>/dev/null || true
    apt-mark hold "$CUSTOM_HEADERS_PKG" 2>/dev/null || true
    ok "Custom kernel pinned: $CUSTOM_KERNEL_PKG"
else
    warn "Custom kernel package not found: $CUSTOM_KERNEL_PKG"
    echo "  Available kernel packages:"
    dpkg -l 2>/dev/null | grep -E "^ii  linux-image" | awk '{print "    "$2}'
    read -p "  Continue anyway? (yes/no): " k
    [ "$k" = "yes" ] || die "Aborted — fix the kernel package name first."
fi

# 2. Pin zram packages so autoremove doesn't take them
apt-mark manual systemd-zram-generator 2>/dev/null || true
ok "zram package pinned"

# 3. Clean package database
say "Cleaning package database..."
apt update -y
apt upgrade -y
apt --purge autoremove -y
apt autoclean
apt purge '~o' -y 2>/dev/null || true
apt purge '~c' -y 2>/dev/null || true
ok "Cleaned"

# 4. Backup sources.list
cp /etc/apt/sources.list "/etc/apt/sources.list.bullseye.$(date +%Y%m%d).bak"
ok "Saved sources.list backup"

# -------- phase 2: switch sources --------
say "Phase 2 — Switch to trixie"

cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

# Remove stale third-party repos that will break apt
rm -f /etc/apt/sources.list.d/mobian.list 2>/dev/null || true
rm -f /etc/apt/apt.conf.d/99no-check-valid-until 2>/dev/null || true

ok "Sources updated to trixie"

apt update --allow-releaseinfo-change

# -------- phase 3: upgrade --------
say "Phase 3 — Two-phase upgrade"
echo ""
echo "  Phase 3a: upgrade --without-new-pkgs (safe, minimal)"
echo "  Phase 3b: full-upgrade (installs new packages, takes 15-30 min)"
echo ""
echo "  IMPORTANT: if apt asks about removing the custom kernel,"
echo "             answer YES to abort the removal."
echo ""
read -p "Type 'go' to start the upgrade: " go
[ "$go" = "go" ] || die "Aborted."

say "Phase 3a — minimal upgrade"
DEBIAN_FRONTEND=noninteractive apt \
    -o Dpkg::Options::="--force-confold" \
    upgrade --without-new-pkgs -y

say "Phase 3b — full-upgrade"
DEBIAN_FRONTEND=noninteractive apt \
    -o Dpkg::Options::="--force-confold" \
    full-upgrade -y

# -------- phase 4: cleanup --------
say "Phase 4 — Post-upgrade cleanup"

apt --purge autoremove -y
apt autoclean

# Re-pin the kernel (in case apt lost the hold)
apt-mark hold "$CUSTOM_KERNEL_PKG" 2>/dev/null || true
apt-mark hold "$CUSTOM_HEADERS_PKG" 2>/dev/null || true
ok "Kernel re-pinned"

# Restart custom services
systemctl daemon-reload 2>/dev/null || true
for svc in led-config adb-gadget systemd-zram-setup@zram0; do
    systemctl restart "$svc" 2>/dev/null && ok "restarted $svc" || true
done

# -------- summary --------
say "Upgrade complete"
echo ""
echo "  OS:     $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo "  Kernel: $(uname -r)"
echo "  Held:   $(apt-mark showhold | grep -c .) packages"
echo ""
echo "Rebooting in 15 seconds — Ctrl-C to cancel."
sleep 15
reboot
