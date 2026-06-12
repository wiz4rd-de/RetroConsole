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
- **M2 — Installer** ✅ (2026-06-12): `retroconsole-install`, live flag, target mkinitcpio, dual GRUB.
  *Verified:* full matrix in QEMU — BIOS-install/BIOS-boot and UEFI-install/UEFI-boot both end in ES-DE after rebooting from the bare disk (no ISO). `grub-mkconfig` picked up kernel + both ucode images (the pacman-hook stash works); the UEFI run executed the extra NVRAM `grub-install` and the disk booted via the `--removable` fallback path. No-disk boot aborts with "No suitable internal disk found" and drops to a shell; the boot medium was never selected as target. Notably the installed system runs cage/ES-DE under plain virtio-vga without `retroconsole.software`.
- **M3 — Controller-first polish** ✅ (2026-06-12): udev game-device rules and autoconfig profiles were already in the package list — the milestone turned out to be about making RetroArch actually *use* them. Three root causes found via USB passthrough (ShanWan PS3/PC pad, 2563:0523):
  1. RetroArch never loaded the 437 `retroarch-autoconfig-udev` profiles because its compiled-in `joypad_autoconfig_dir` default is the empty per-user dir (`/etc/retroarch.cfg` ships the key commented out, and our user-level config shadows `/etc/retroarch.cfg` entirely). Pad showed "not configured" → no Start/Select binds → no quit combo. Fix: `joypad_autoconfig_dir = "/usr/share/libretro/autoconfig"` in the shipped `retroarch.cfg` (must be in the shipped file — RetroArch honors the first occurrence and rewrites the full config on exit).
  2. The matching profile ("Spartan Gear Oplon Dinput") ships with the d-pad unbound (upstream comments the binds out; this pad reports the d-pad as HAT0, verified by decoding evdev). Fix: pacman hook `zz02-retroconsole-shanwan-dpad.hook` appends the four hat binds after the package installs (an airootfs file override is impossible — mkarchiso copies airootfs *before* pacstrap and pacman aborts on the file conflict; the hook stays in the image so upgrades re-apply it).
  3. ES-DE's quit menu only contained "QUIT ES-DE" (which the kiosk respawns) — Reboot/Power Off entries are gated behind `ShowQuitMenu`. Fix: `<bool name="ShowQuitMenu" value="true" />` in the shipped `es_settings.xml`; "POWER OFF SYSTEM" (runs `shutdown --poweroff now`) verified to shut the VM down as user `retro` (polkit allows the active seat session).
  The `input` group turned out unnecessary: logind's uaccess ACL on `/dev/input/event*` covers the seat session (verified: `crw-rw----+ root input` and reading evdev as `retro` works).
  *Verified in QEMU* (USB passthrough; requires root QEMU on macOS: `sudo scripts/test-qemu.sh --gamepad`): full keyboard-free session on the final ISO — boot to ES-DE, browse (d-pad), launch Alter Ego (Start at title), play (d-pad), Select+Start quits to ES-DE, Quit → Power Off System shuts the machine down. RetroArch log shows "Spartan Gear Oplon (DInput) configured in port 1". *Open (needs real hardware):* untested pad models, Bluetooth pairing flow (M6).
- **M4 — ROM management** ✅ (2026-06-12): smb.conf, avahi, wsdd, enabled units, ES-DE tools entries (Restart ES-DE, Update System, **Wi-Fi Setup** — `foot --fullscreen nmtui` inside cage). Fixes found during verification: ROM dirs must be 0777 (Samba guest-token ACL check ignores `force user`), `tools/` veto'd from the share (network guests must not tamper with scripts ES-DE executes).
  *Verified in QEMU:* NetworkManager DHCP + smb/nmb/wsdd/avahi all active on live boot; share mounted from macOS via `hostfwd` port-forward as guest, "Lan Master" homebrew copied in, Tools → Restart ES-DE → NES shows 2 games; Wi-Fi Setup opens nmtui fullscreen and returns to ES-DE on exit. *Open (needs real LAN/hardware):* Finder/avahi network discovery, actual Wi-Fi association, Bluetooth (unit active but conditioned on hardware).
- **M5 — Updates** ✅ (2026-06-12): `retroconsole-update`, sudoers, tools-menu wiring. The pieces existed since M4 but the UX was broken: launched from ES-DE the old script redirected *all* output to the log, so the user saw a blank, blocking screen with no progress or completion signal. Reworked into the M4 `foot --fullscreen` pattern: "Update System.sh" now opens `foot --fullscreen /usr/local/bin/retroconsole-update`; the script `tee`s `pacman -Syu` to both the terminal and `/var/log/retroconsole-update.log` (live *and* logged), captures pacman's real exit via `PIPESTATUS[0]`, prints "Update complete"/"FAILED", and gates on a final "Press Enter to return to ES-DE" keypress so the user controls when the session resumes. Added a live-USB guard (`/etc/retroconsole-live`): on live media an update would write to the tmpfs overlay and be lost on reboot, so it refuses with a short explanation instead of running. Also shipped `~/.config/foot/foot.ini` (`Terminus:size=20`, the largest bitmap in the only shipped font `terminus-font`) so the update/Wi-Fi text is legible from a couch — the default foot font is tiny on a TV. (Stretch, deferred: host `[retroconsole]` repo on GitHub Releases for OTA ES-DE updates.)
  *Verified in QEMU* (BIOS path): fresh install onto a blank disk → installed disk boots to ES-DE on its own → Tools system lists Restart ES-DE / Update System / Wi-Fi Setup → "Update System" opens foot fullscreen, `pacman -Syu` runs visibly, "update successful, press Enter" returns to ES-DE on keypress. The on-disk log (`/var/log/retroconsole-update.log`, read back from the qcow2) contains two full runs, each syncing core/extra/retroconsole and finishing "status 0" — pacman's own output is tee'd in alongside the start/finish markers, proving the log path (`there is nothing to do` because the image is freshly built). ES-DE relaunches cleanly after each run (the "Restart ES-DE" tool also verified to respawn the session), so the system stays in ES-DE post-update. `foot --check-config` accepts the new foot.ini (exit 0) and `fc-match "Terminus:size=20"` resolves to `ter-u20n.otb`, so the enlarged font renders. *Open (needs real hardware/LAN):* an update with an actual package delta (the VM's freshly-built mirror had nothing to upgrade).
- **M6 — Hardware hardening (post-MVP)**: real-hardware matrix (Intel/AMD/NVIDIA), HDMI audio, Bluetooth pads, pixman/gamescope fallbacks, docs.

## Risks / Notes

- **cage on very old GPUs** (relevant given legacy-BIOS targets): `WLR_RENDERER=pixman` software fallback; gamescope is a drop-in alternative — only `retroconsole-session` changes.
- **ES-DE 3.x config home is `~/ES-DE/`**, not `~/.emulationstation` — verify exact `es_settings.xml` keys against 3.4.x docs during M1.
- **PSX BIOS**: not distributable — create `~/.config/retroarch/system/` with a README telling the user where to drop `scph*.bin`.
- **Image-copy residue**: keep one explicit cleanup list in the installer (flag, mkinitcpio, machine-id, journal) so it stays auditable.
- **SigLevel TrustAll** on the local repo is MVP-only; sign before public distribution.
