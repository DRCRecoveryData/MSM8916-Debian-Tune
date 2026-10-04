# Upgrading to Debian 13 (Trixie)

Direct bullseye → trixie upgrade. Preserves the custom kernel.

## Why direct works

Debian officially recommends going through bookworm, but APT resolves
package dependencies at install time — a direct jump works for most
systems. The two things that can break it on MSM8916 hardware are:

1. **The custom kernel getting removed** by apt. Prevented by pinning.
2. **Sshd_config being replaced** by the maintainer's version, disabling
   root login. Prevented by `--force-confold` in the upgrade script.

Everything else is standard Debian.

## Before you start

1. **Full EDL backup.** This is your recovery path if the boot fails.
2. **`screen` or `tmux`.** SSH will drop during the upgrade.
3. **Internet access from the device.**

## The upgrade

```bash
sudo bash upgrade-to-trixie.sh
```

The script:

1. Verifies Debian 11
2. Pins the custom kernel package
3. Cleans the package database
4. Backs up `sources.list`
5. Switches to trixie sources
6. Runs `upgrade --without-new-pkgs`
7. Runs `full-upgrade` with `--force-confold` (keeps local configs)
8. Re-pins the kernel
9. Restarts custom services
10. Reboots

Total time: **20–40 minutes** depending on download speed.

## What to watch for

### "Do you want to abort removal now? [yes/no]" — the kernel

If apt tries to remove `linux-image-5.15.0-handsomekernel+`, **answer
`yes`** to abort the removal. The script pins it, but this prompt can
still appear if a dependency chain bypasses the hold.

### "A new version of /etc/ssh/sshd_config is available"

The script passes `--force-confold`, so this prompt shouldn't appear.
If it does (running manually), **choose option 2 (keep local)**.

The same applies to:

- `/etc/default/*`
- `/etc/dnsmasq.conf`
- `/etc/systemd/*` custom services

**Rule:** if you customized it, keep local. If unsure, keep local.

### SSH disconnects

Expected. Wait 10 seconds, then reconnect:

```bash
ssh root@<device-ip>
```

The upgrade continues on the device regardless of your session.

## After the upgrade

Verify:

```bash
bash verify.sh
```

Expected:

```
Kernel:      5.15.0-handsomekernel+
OS:          Debian GNU/Linux 13 (trixie)
Swappiness:  100
zram:        /dev/zram0 zstd 191M
```

If the LEDs / ADB / other services stopped:

```bash
sudo systemctl restart led-config adb-gadget
```

## If the device fails to boot

Signs:

- Ping to device fails after 2+ minutes
- USB doesn't enumerate as ADB or RNDIS

**Recovery via EDL:**

From a Windows host with the OpenStick installer repo:

```bat
cd /d C:\jz01-openstick

REM Enter EDL: unplug, hold reset, plug USB, release after 5s
edl\venv\Scripts\python edl\edl.py ^
  --loader edl\Loaders\custom\prog_emmc_firehose_8916.mbn ^
  wf backup_before_upgrade.bin --memory=eMMC
```

20 minutes and the device is back to bullseye exactly as it was.

## Rolling back to bullseye (if upgrade succeeds but something's broken)

You can downgrade, but it's messy. Easier to restore from the EDL
backup. Save the backup file for at least a month after the upgrade.

## Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Boot loops to fastboot | Kernel was removed | Restore EDL backup |
| SSH refused after reboot | sshd_config replaced | Reboot to ADB, re-add `PermitRootLogin yes` |
| zram not active | zram-tools vs systemd-zram-generator conflict | Run `tune-openstick.sh` |
| `apt update` errors | Stale third-party repo | Remove `/etc/apt/sources.list.d/*.list` |
| LEDs dead | DTB was replaced | Re-run `fix_dtb_inplace.py` from OpenStick repo |
