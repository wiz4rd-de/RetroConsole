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

## Build log warnings that are safe to ignore

`mkinitcpio` prints `WARNING: Possibly missing firmware for module: ...` for
`aic94xx`, `ast`, `bfa`, `qed`, `qla1280`, `qla2xxx`, `wd719x` and
`xhci_pci_renesas`. The fallback initramfs packs every storage/display
driver in the kernel and flags optional firmware that is not installed —
these modules are 90s SCSI controllers, fibre-channel SAN HBAs and server
BMC graphics. No hardware a retro console can use is affected (consumer
Wi-Fi/GPU/ethernet firmware is all in `linux-firmware`, which we ship);
several of these firmware files are not even redistributable. The same
warnings appear on any stock Arch install.

## Design notes

- **One package list**: the installer copies the live squashfs onto the disk,
  so `profile/packages.x86_64` defines both the live ISO and the installed
  system.
- **Live vs installed** is decided by the flag file `/etc/retroconsole-live`:
  present on the ISO, removed by the installer. tty1 autologins user `retro`,
  whose `~/.bash_profile` either starts the installer (live) or the
  cage + ES-DE kiosk session (installed).
- **Live session boot entries**: the ISO menu also offers "Live session"
  (kernel parameter `retroconsole.session`, forces the kiosk session on live
  media) and "Live session, safe graphics" (additionally
  `retroconsole.software`, which makes cage/ES-DE/RetroArch render in
  software — use this in VMs and on GPUs the GLES renderer cannot drive).
- **Bundled libretro cores must include ES-DE's per-system defaults** (see
  the comment in `packages.x86_64`). ES-DE launches the first emulator entry
  from its bundled `es_systems.xml`; if that core file is missing the launch
  fails with "core file not found" even when an alternative core (e.g.
  Nestopia) is installed.
- **Test game**: `ROMs/nes/` ships "Alter Ego" (Shiru & Denis Grachev, 2011,
  free/open-source homebrew) so the gamelist is never empty and game launch
  can be verified without copying ROMs in.
- **Samba guest writes need 0777 ROM dirs**: guest sessions are
  access-checked against the NT ACL synthesized from the POSIX mode, not the
  `force user` identity — with 0755 dirs, guests can read but every write
  fails with ACCESS_DENIED. The system ROM dirs ship 0777 (see
  `profiledef.sh`); the open share is by design, filesystem modes are not the
  security boundary on this appliance. `tools/` is veto'd from the share so
  network guests cannot tamper with scripts that ES-DE executes.
- **Verify Samba from the Mac without a LAN**: forward the guest's SMB port
  (`-nic user,...,hostfwd=tcp:127.0.0.1:4455-:445`), then
  `mount_smbfs -N //guest@127.0.0.1:4455/ROMs /tmp/mnt`. Use `cp -X` — macOS
  quarantine xattrs cannot be copied to the share.
- **AUR packages** are real pacman packages in the `[retroconsole]` repo; the
  repo directory ships in the image, so the installed system can reinstall
  them offline. The repo is unsigned (`SigLevel = Optional TrustAll`) — sign
  it before distributing ISOs publicly.
