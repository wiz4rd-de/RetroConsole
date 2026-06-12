# Building RetroConsole

The ISO is built with [archiso](https://gitlab.archlinux.org/archlinux/archiso),
which only runs on Arch Linux. On macOS the build runs inside a privileged
`linux/amd64` Docker container (Rosetta emulation on Apple Silicon — slow but
reliable).

## Prerequisites (macOS)

- Docker Desktop (or another Docker engine)
- QEMU for testing: `brew install qemu`

## Build

```sh
make iso
```

This:
1. Builds the `retroconsole-builder` image (Arch + archiso + base-devel).
2. Builds the AUR packages (`emulationstation-de`, `game-devices-udev`,
   `retroarch-autoconfig-udev-git`) with `makepkg` and publishes them into the
   local `[retroconsole]` pacman repo at
   `profile/airootfs/opt/retroconsole/repo/` (gitignored). Already-built
   packages are reused; force a rebuild with `make aur-clean`.
3. Runs `mkarchiso` against `profile/`. The ISO lands in `out/`.

The first build compiles ES-DE under emulation and downloads every package —
expect well over an hour. Subsequent builds reuse the AUR packages and the
pacman package cache (Docker volume `retroconsole-pkgcache`) and are much
faster.

## Test in QEMU

```sh
make test-bios     # boot the ISO with legacy BIOS firmware, fresh target disk
make test-uefi     # boot the ISO with UEFI (edk2) firmware, fresh target disk
```

Run the installer inside the VM (type `YES`), then verify the installed
system boots on its own:

```sh
make test-installed-bios
make test-installed-uefi
```

x86_64 on Apple Silicon uses TCG (full CPU emulation): boot takes minutes and
ES-DE renders via llvmpipe. That is fine for verification; judge performance
on real hardware only.

## Flash to USB

```sh
# find the disk with: diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=out/retroconsole-*.iso of=/dev/rdiskN bs=4m status=progress
```

## Design notes

- **One package list**: the installer copies the live squashfs onto the disk,
  so `profile/packages.x86_64` defines both the live ISO and the installed
  system.
- **Live vs installed** is decided by the flag file `/etc/retroconsole-live`:
  present on the ISO, removed by the installer. tty1 autologins user `retro`,
  whose `~/.bash_profile` either starts the installer (live) or the
  cage + ES-DE kiosk session (installed).
- **AUR packages** are real pacman packages in the `[retroconsole]` repo; the
  repo directory ships in the image, so the installed system can reinstall
  them offline. The repo is unsigned (`SigLevel = Optional TrustAll`) — sign
  it before distributing ISOs publicly.
