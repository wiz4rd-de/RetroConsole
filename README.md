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

1. Flash the ISO to a USB stick (`dd`, balenaEtcher, …).
2. Boot the target computer from it.
3. Type `YES` at the single confirmation prompt.

**Careful!** This erases the computer's internal drive (the installer picks
the largest internal disk).

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
