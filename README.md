# RetroConsole

A retrogaming distro installed directly onto bare metal: flash the ISO, boot
the target PC, confirm once — the machine then always boots straight into a
gamepad-driven retro gaming UI.

- **Frontend:** [ES-DE](https://es-de.org/) running in a minimal Wayland
  kiosk session (no desktop, no login screen)
- **Emulation:** [RetroArch](https://www.retroarch.com/) with libretro cores
  for NES, SNES, Genesis/Mega Drive, Game Boy/Color/Advance, PlayStation 1
  and Nintendo 64
- **Base:** Arch Linux, built with archiso
- **Hardware:** any x86_64 PC, UEFI or legacy BIOS; Intel/AMD graphics out of
  the box (NVIDIA via nouveau)

## Install

1. Download the latest ISO from the
   [Releases page](https://github.com/wiz4rd-de/RetroConsole/releases/latest).
2. Flash it to a USB stick (`dd`, balenaEtcher, …).
3. Boot the target computer from it.
4. Type `YES` at the single confirmation prompt.

The installer picks the largest internal disk (at least 24 GiB) and splits it
into a system partition and a separate user partition for your games and
settings (`/home`).

**Careful!** A first-time install **erases the whole target disk**.
**Reinstalling or updating keeps your data:** boot the same — or a newer — ISO
on a machine that already runs RetroConsole and the installer reinstalls only
the system, keeping your games and settings on the user partition. (Machines
first installed with an older ISO that predates this split layout have no
separate user partition, so reinstalling over one still erases everything — a
one-time cost.)

After installation the machine boots directly into ES-DE.

## Adding games

The `ROMs` folder is shared on the local network (guest access, no password):
the machine shows up as `retroconsole` in macOS Finder, Windows Explorer and
Linux file managers. Drop ROMs into the matching system folder, then run
**Tools → Restart ES-DE** on the box.

Some systems need BIOS files you must provide yourself — see the note in the
share's `tools` folder neighbor `…/.config/retroarch/system/README.txt` and
`docs/HARDWARE.md`.

## Updating

**Tools → Update System** in ES-DE runs a full system upgrade.

## Building & development

See [docs/BUILDING.md](docs/BUILDING.md). Short version (macOS with Docker):

```sh
make iso         # build the ISO (in a Docker container)
make test-uefi   # boot it in QEMU with UEFI firmware
make test-bios   # boot it in QEMU with legacy BIOS
```

Hardware notes and troubleshooting: [docs/HARDWARE.md](docs/HARDWARE.md).
