# RetroConsole — Implementation Plan

## Context

The repo contains only a README describing the vision: a retrogaming Linux distro flashed to USB, which installs itself onto bare metal (wiping the internal drive after one confirmation) and boots straight into ES-DE with RetroArch as the emulator. Nothing is built yet — this plan bootstraps the entire project.

**Decisions made with the user:**
- Base: **Arch Linux**, ISO built with **archiso** (profile derived from stock `releng`)
- Hardware: generic **x86_64, both UEFI and legacy BIOS** boot
- Installer: unattended except **one "type YES to wipe /dev/sdX" confirmation**
- MVP scope: bootable installer ISO, controller-first UX, ROM management (Samba), system updates
- Bundled systems: **classic set** — NES, SNES, Genesis, GB/GBC/GBA, PSX, N64 (PSX gets a BIOS folder + note, user supplies the BIOS)
- Dev machine is **macOS (Apple Silicon)** — builds run in a `--platform linux/amd64` privileged Arch container (Rosetta); QEMU on the host for testing

## Key Technical Choices

| Area | Choice | Why |
|---|---|---|
| Install method | **Offline image-copy**: `unsquashfs` the ISO's `airootfs.sfs` onto the target, then a bounded cleanup list | No network needed at install time; `packages.x86_64` is the single source of truth (live == installed) |
| Disk layout | Always GPT: 1 MiB BIOS-boot (EF02) + 512 MiB ESP (EF00) + ext4 root | One layout boots both firmwares, no branching |
| Bootloader | GRUB installed **both** ways every time (`i386-pc` + `x86_64-efi --removable --no-nvram`; NVRAM entry added only when installer booted UEFI) | Disk boots on any firmware |
| Session | getty autologin on tty1 as user `retro` → `.bash_profile` dispatcher → `exec cage -- es-de` (Wayland kiosk) | No DM/desktop; getty respawns the session on crash; `retroconsole-session` is the single switch point for fallbacks (pixman renderer, gamescope) |
| AUR packages | Build `emulationstation-de`, `game-devices-udev`, `retroarch-autoconfig-udev-git` with makepkg in the container → `repo-add` into local `[retroconsole]` repo (`file:///opt/retroconsole/repo`) baked into ISO + target | pacman-native, no AUR helper on target. Verified current on AUR (ES-DE 3.4.1, maintained by ES-DE's author) |
| Graphics | mesa + vulkan-intel + vulkan-radeon + vulkan-nouveau (NVK) + intel-media-driver + libva-mesa-driver + linux-firmware | Intel/AMD out of the box; NVIDIA via nouveau/NVK for MVP (proprietary deferred) |
| ROMs | Samba guest-writable share of `/home/retro/ROMs` + avahi (macOS/Linux discovery) + wsdd (Windows) | Zero-config network drop |
| Updates | `retroconsole-update` script (`pacman -Syu`), launched from an ES-DE "tools" custom system entry, NOPASSWD sudoers scoped to that script | Simple; stretch: host `[retroconsole]` repo on GitHub Releases so ES-DE updates OTA |
| Cores | libretro from official repos: mesen + nestopia (NES), snes9x, genesis-plus-gx, gambatte (GB/GBC), mgba (GBA), beetle-psx, mupen64plus-next (N64) | All in Arch `extra`. Must include ES-DE's per-system *default* cores (nes=mesen, gb/gbc=gambatte) or game launch fails with "core file not found" |

## Repo Layout

```
RetroConsole/
├── Makefile                          # make iso / test-bios / test-uefi / clean
├── .gitignore                        # out/, work/, profile/airootfs/opt/retroconsole/repo/*
├── docker/Dockerfile                 # archlinux:latest + archiso base-devel git; 'builder' user for makepkg
├── scripts/
│   ├── build-iso.sh                  # container entrypoint: build-aur-repo.sh → mkarchiso
│   ├── build-aur-repo.sh             # clone AUR pkgs → makepkg → repo-add → into airootfs/opt/retroconsole/repo
│   └── test-qemu.sh                  # host: qemu-system-x86_64; --uefi|--bios, --fresh-disk, --boot-disk
├── profile/                          # archiso profile (copied from releng, modified)
│   ├── profiledef.sh                 # iso_name=retroconsole, dual bootmodes, zstd squashfs, installer perms 0:0:755
│   ├── packages.x86_64               # base, linux, grub, efibootmgr, networkmanager, pipewire stack, cage,
│   │                                 # retroarch + assets + cores, emulationstation-de, udev pkgs, mesa/vulkan,
│   │                                 # samba avahi wsdd, gptfdisk dosfstools e2fsprogs squashfs-tools arch-install-scripts
│   ├── pacman.conf                   # + [retroconsole] Server=file:///opt/retroconsole/repo (SigLevel Optional TrustAll for MVP)
│   ├── grub/, syslinux/, efiboot/    # ISO boot menus (from releng, retimed/rebranded)
│   └── airootfs/
│       ├── etc/retroconsole-live                         # flag file: presence = live mode (installer deletes on target)
│       ├── etc/mkinitcpio.conf.target                    # standard hooks (no archiso) — installer swaps it in
│       ├── etc/systemd/system/getty@tty1.service.d/autologin.conf
│       ├── etc/samba/smb.conf                            # [ROMs] guest ok, writable, force user=retro
│       ├── etc/sudoers.d/retroconsole                    # retro NOPASSWD: retroconsole-update, reboot, poweroff
│       ├── home/retro/.bash_profile                      # tty1 dispatcher (live → installer, installed → session)
│       ├── home/retro/ES-DE/settings/es_settings.xml     # ES-DE 3.x uses ~/ES-DE/ (not ~/.emulationstation)
│       ├── home/retro/ES-DE/custom_systems/es_systems.xml  # "tools" system launching .sh entries
│       ├── home/retro/ROMs/{nes,snes,megadrive,gb,gbc,gba,psx,n64,tools}/
│       ├── home/retro/.config/retroarch/retroarch.cfg    # udev input, ozone menu, autoconfig, Select+Start=quit
│       └── usr/local/bin/{retroconsole-install,retroconsole-session,retroconsole-update}
└── docs/{BUILDING.md,HARDWARE.md}
```

## Core Logic Sketches

**tty1 dispatcher** (`home/retro/.bash_profile`):
```bash
if [[ "$(tty)" == /dev/tty1 ]]; then
  if [[ -e /etc/retroconsole-live ]]; then
    exec sudo /usr/local/bin/retroconsole-install
  else
    exec /usr/local/bin/retroconsole-session   # exec cage -- es-de
  fi
fi
```

**Installer** (`retroconsole-install`):
1. Candidate disks via `lsblk`, excluding removable disks and the live boot medium (from `/run/archiso/bootmnt`); pick the **largest**; abort clearly if none.
2. Show model/size; the single prompt: `Type YES to ERASE /dev/sdX`.
3. `sgdisk --zap-all`; GPT: EF02 1MiB, EF00 512MiB FAT32, rest ext4.
4. `unsquashfs -f -d /mnt /run/archiso/bootmnt/arch/x86_64/airootfs.sfs`.
5. Cleanup in `arch-chroot`: rm `/etc/retroconsole-live`; swap in `mkinitcpio.conf.target` + `mkinitcpio -P`; reset machine-id; `genfstab -U`.
6. GRUB both ways (see table); `grub-mkconfig` (timeout 0, quiet).
7. `umount -R`; "remove the USB stick"; reboot.

**Build on macOS**: `make iso` → `docker run --rm --privileged --platform linux/amd64 -v $(PWD):/build -v retroconsole-pkgcache:/cache retroconsole-builder /build/scripts/build-iso.sh`. zstd squashfs (not xz) keeps Rosetta builds tolerable; package-cache volume avoids recompiling ES-DE (~5–10 min) every build. Modern mkarchiso uses mtools for the EFI image (no loop mounts) so it's container-friendly. Escape hatch if Rosetta is too slow: UTM x86_64 Arch VM, same scripts.

## Milestones (each verifiable)

- **M0 — Build pipeline** ✅ (2026-06-12): Dockerfile, Makefile, releng-derived profile, build + QEMU scripts.
  *Verify:* `make iso` on the Mac produces an ISO that boots to a root shell in QEMU under both SeaBIOS and OVMF.
- **M1 — Live ES-DE session** ✅ (2026-06-12): `[retroconsole]` repo step, full package list, `retro` user + autologin + dispatcher, session script, seeded ES-DE/RetroArch configs, "Alter Ego" homebrew NES ROM in `ROMs/nes/`. Added "Live session" / "Live session, safe graphics" ISO boot entries (`retroconsole.session` / `retroconsole.software` kernel params) so the kiosk session is reachable from live media. Added libretro-mesen + libretro-gambatte (ES-DE's default cores for nes and gb/gbc).
  *Verified:* ISO (BIOS, safe-graphics entry) boots straight into ES-DE in QEMU; Alter Ego launches in RetroArch, plays, and Esc returns to ES-DE.
- **M2 — Installer**: `retroconsole-install`, live flag, target mkinitcpio, dual GRUB.
  *Verify:* QEMU blank disk → YES prompt → reboot without ISO → ES-DE. Matrix: BIOS-install/BIOS-boot, UEFI-install/UEFI-boot; check no-eligible-disk abort and that the boot USB is never selected.
- **M3 — Controller-first polish**: udev game-device rules, RetroArch autoconfig profiles, input group, Select+Start quit hotkey.
  *Verify:* real hardware or QEMU USB passthrough — full session (boot → browse → play → quit → shutdown) without touching a keyboard.
- **M4 — ROM management**: smb.conf, avahi, wsdd, enabled units, ES-DE tools entry to restart ES-DE (rescan).
  *Verify:* macOS Finder → Network → `retroconsole` → guest copy ROM → restart from tools menu → game appears.
- **M5 — Updates**: `retroconsole-update`, sudoers, tools-menu wiring. (Stretch: host `[retroconsole]` repo on GitHub Releases for OTA ES-DE updates.)
  *Verify:* "Update System" from ES-DE runs `pacman -Syu`, logs to `/var/log/retroconsole-update.log`, system still boots into ES-DE.
- **M6 — Hardware hardening (post-MVP)**: real-hardware matrix (Intel/AMD/NVIDIA), HDMI audio, Bluetooth pads, pixman/gamescope fallbacks, docs.

## Risks / Notes

- **cage on very old GPUs** (relevant given legacy-BIOS targets): `WLR_RENDERER=pixman` software fallback; gamescope is a drop-in alternative — only `retroconsole-session` changes.
- **ES-DE 3.x config home is `~/ES-DE/`**, not `~/.emulationstation` — verify exact `es_settings.xml` keys against 3.4.x docs during M1.
- **PSX BIOS**: not distributable — create `~/.config/retroarch/system/` with a README telling the user where to drop `scph*.bin`.
- **Image-copy residue**: keep one explicit cleanup list in the installer (flag, mkinitcpio, machine-id, journal) so it stays auditable.
- **SigLevel TrustAll** on the local repo is MVP-only; sign before public distribution.
