# Performance Tuning for MSM8916 Debian

Every setting applied by `tune-openstick.sh`, with the reasoning.

## Overview

| Setting | Value | Reason |
|---|---|---|
| haveged | active | Entropy for headless ARM |
| vm.swappiness | 100 | zram is fast, prefer swap over cache drop |
| kernel.printk | 3 4 1 3 | Suppress noisy deprecated warnings |
| zram algorithm | zstd | Better compression than lz4 |
| zram size | 191 MB | ~50% of RAM, safe for the device |
| thermal monitor | 75°C threshold | Prevent silent overheating |
| thermal check | every 5 min | Fits in a 512 MB RAM budget |

## 1. haveged — entropy daemon

**Problem:** ARM devices in headless mode have few entropy sources.
The kernel entropy pool stays below 200 bits for minutes after boot,
causing `sshd` to hang on incoming connections and TLS handshakes to
stall.

**Solution:** `haveged` is a userspace daemon that generates entropy
from CPU timing jitter. It fills the kernel entropy pool within
seconds of boot.

```bash
sudo apt install -y haveged
sudo systemctl enable --now haveged
```

**Effect:** entropy pool goes from ~150 bits to >3000 bits within
1 second of boot. SSH and HTTPS become responsive immediately.

## 2. vm.swappiness = 100

**Problem:** default `vm.swappiness = 60` is tuned for spinning disk
swap. When the swap device is zram (RAM-backed, ~10× faster than SSD),
this is far too conservative.

**Solution:** set swappiness to 100. The kernel will aggressively swap
cold pages to zram instead of evicting page cache.

```bash
echo 'vm.swappiness=100' | sudo tee /etc/sysctl.d/99-zram.conf
sudo sysctl -p /etc/sysctl.d/99-zram.conf
```

**Effect:** on a device under memory pressure, page cache stays warm
and OOM kills become rare. The trade-off is slightly more CPU usage
for zram compression — negligible on MSM8916's 4× Cortex-A53.

## 3. kernel.printk = 3 4 1 3

**Problem:** the MSM8916 kernel prints a lot of noise:

- `adbd oom_adj is deprecated, use oom_score_adj`
- `l13 regulator: failed to enable`
- `remoteproc0: failed to load firmware`

These are expected on this hardware but flood `dmesg` and `journalctl`.

**Solution:** set the console log levels. Four numbers:

```
3  4  1  3
│  │  │  └── default for console messages
│  │  └───── default for non-console messages
│  └──────── warnings still printed
└─────────── errors still printed
```

Effectively: show errors and warnings, suppress alerts and debug.

```bash
echo 'kernel.printk=3 4 1 3' | sudo tee /etc/sysctl.d/99-printk.conf
sudo sysctl -p /etc/sysctl.d/99-printk.conf
```

**Effect:** boot log goes from ~200 lines to ~15.

## 4. zram — zstd, 191 MB

**Problem:** Debian 13 ships **two** zram packages that conflict:

- `zram-tools` (legacy, service `zramswap.service`)
- `systemd-zram-generator` (modern, service
  `systemd-zram-setup@zram0.service`)

Both try to create `/dev/zram0`. Only one wins at boot; the other
fails with `Device or resource busy`.

**Solution:** keep the modern one, remove the legacy.

```bash
sudo systemctl disable --now zramswap.service
sudo apt-mark manual systemd-zram-generator
sudo apt-mark auto zram-tools
sudo apt --purge autoremove
```

**Verify:**

```bash
zramctl
# NAME       ALGORITHM DISKSIZE  DATA COMPR TOTAL STREAMS MOUNTPOINT
# /dev/zram0 zstd          191M  4.7M  679K  1.1M       4 [SWAP]
```

**Effect:** ~6–10× compression. 12 MB of live data compresses to
4 MB of physical RAM.

## 5. Thermal monitoring

**Problem:** the dongle has no fan and a small heatsink. Under sustained
load, the SoC can reach 80–90 °C without any warning. At that
temperature, thermal throttling kicks in and performance drops silently.

**Solution:** cron script checks the temperature every 5 minutes. If
it exceeds 75 °C, sends a `wall` message that appears in all SSH
sessions.

```bash
sudo tee /root/heat_check.sh > /dev/null <<'EOF'
#!/bin/bash
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
if [ "$TEMP" -gt 75000 ]; then
    echo "CRITICAL HEAT: $((TEMP/1000))°C" | wall
fi
EOF
sudo chmod +x /root/heat_check.sh

echo "*/5 * * * * root /root/heat_check.sh" | sudo tee /etc/cron.d/heat_check
```

**Typical temps:**

| Load | Temperature |
|---|---|
| Idle | 30–40 °C |
| WiFi active | 40–50 °C |
| CPU stress test | 55–65 °C |
| Sustained >80 °C | Throttling — check cooling |

**Fix for overheating:** remove from any enclosure, add a small heatsink
to the SoC (a 15×15 mm copper pad with thermal adhesive is usually
enough).

## What NOT to do

### ❌ Don't set swappiness to 0

Some guides suggest `vm.swappiness = 0` for devices with zram. This is
wrong: 0 doesn't mean "don't swap", it means "swap only to avoid OOM".
For zram that's backwards — you want the kernel to use zram aggressively.

### ❌ Don't install zram-tools alongside systemd-zram-generator

They conflict.

### ❌ Don't modify the boot.img cmdline via abootimg

The popular MSM8916 blog uses `abootimg -u` with a hardcoded PARTUUID.
That PARTUUID is wrong for JZ0145_V33 and many other dongles. The
device won't boot. If you want to change cmdline parameters, patch
the boot.img offline and flash via EDL.

### ❌ Don't remove haveged after installing it

Some minimal systems don't need it because they use `systemd-crngd`.
This image uses neither by default — without haveged the entropy pool
stays tiny and services hang.

## Verify everything

```bash
bash verify.sh
```

Or manually:

```bash
uname -r                          # 5.15.0-handsomekernel+
cat /proc/sys/vm/swappiness       # 100
cat /proc/sys/kernel/printk       # 3	4	1	3
zramctl                           # /dev/zram0 zstd 191M
systemctl is-active haveged       # active
cat /proc/sys/kernel/random/entropy_avail   # >3000
cat /sys/class/thermal/thermal_zone0/temp   # 35000
```
