# MSM8916 Debian Tune

Upgrade and tune Debian on **MSM8916-based 4G dongles** (JZ01-45-@,
JZ0145_V33, UZ801, UFI001C, and similar).

**Three scripts, no installer, no flashing.** Point it at a working
OpenStick/Debian install and it upgrades + tunes in place.

---

## What this does

| Script | Purpose |
|---|---|
| [`upgrade-to-trixie.sh`](upgrade-to-trixie.sh) | Debian 11 (bullseye) → 13 (trixie), preserving a custom kernel |
| [`tune-openstick.sh`](tune-openstick.sh) | Apply performance tuning (haveged, swappiness, zram, thermal) |
| [`verify.sh`](verify.sh) | Print a snapshot of the current system state |

---

## Who this is for

You already have a **working** Debian system on your dongle — likely
running **OpenStick** (based on bullseye) with a **custom kernel**
(`handsomekernel` or similar). You want to:

- Upgrade to **Debian 13 (trixie)** without losing the custom kernel
- Apply **performance tuning** that fits a 512 MB–1 GB ARM device
- Keep everything reproducible in scripts

**This repo does not flash anything.** No EDL, no fastboot, no boot
image patching. If you don't have a working Debian install yet, get that
first (see the [OpenStick project](https://github.com/OpenStick/OpenStick)).

---

## ⚠️ Before you start

1. **Take a full EDL backup** of the running device. The upgrade can
   brick the boot if something goes wrong, and EDL is the only recovery.
2. **Run inside `screen` or `tmux`** — the upgrade restarts `sshd` and
   your SSH session will drop.
3. **Pin your custom kernel** — the scripts do this automatically, but
   never remove it manually.

See [`docs/UPGRADE.md`](docs/UPGRADE.md) for the full procedure.

---

## Quick start

```bash
# On the device (over SSH)
sudo apt install -y screen
screen -S upgrade

# 1. Clone or copy the scripts to /root
cd /root
git clone https://github.com/DRCRecoveryData/MSM8916-Debian-Tune.git

# 2. Take an EDL backup first (see docs/UPGRADE.md)
# ...

# 3. Run the upgrade
cd MSM8916-Debian-Tune
sudo bash upgrade-to-trixie.sh

# 4. After reboot, apply tuning
sudo bash tune-openstick.sh

# 5. Verify
bash verify.sh
```

---

## Requirements

- Debian 11 (bullseye) installed and bootable
- Root SSH access (or physical console)
- ~500 MB free on `/` for the upgrade
- Internet access from the device

---

## What's tested

- **JZ01-45-@ / JZ0145_V33** (MSM8916, OpenStick base) — full test
- **UZ801 / UFI001C** — same instructions, same scripts; minor thermal
  zone naming differences possible
- Custom kernels — `handsomekernel` is pinned automatically; adapt the
  package name in `upgrade-to-trixie.sh` if yours differs

---

## Docs

- [docs/UPGRADE.md](docs/UPGRADE.md) — bullseye → trixie walkthrough
- [docs/TUNING.md](docs/TUNING.md) — every tuning setting explained

---

## What NOT to do

- Don't run `abootimg -u` on the boot partition (wrong PARTUUID on most
  MSM8916 dongles — this bricks the boot)
- Don't remove the custom kernel with `apt autoremove`
- Don't install `zram-tools` alongside `systemd-zram-generator`
  (they conflict over `/dev/zram0`)

---

## License

MIT — see [`LICENSE`](LICENSE).
