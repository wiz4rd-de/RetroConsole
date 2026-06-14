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

### USB gamepad passthrough

```sh
sudo scripts/test-qemu.sh --gamepad             # ShanWan PS3/PC pad (2563:0523)
sudo scripts/test-qemu.sh --gamepad=dead:beef   # any other VID:PID
```

`sudo` is required: macOS only lets libusb capture a HID device from the
kernel driver as root. Without it QEMU attaches a husk the guest cannot
configure (`libusb_detach_kernel_driver: -3 [ACCESS]` on the terminal, the
device stays at 1.5 Mb/s with no product string and binds no input driver).
Once captured, QEMU periodically prints
`libusb_kernel_driver_active: -5 [NOT_FOUND]` — that is harmless noise
("no macOS driver attached", which is exactly the captured state).

The script always exposes a QEMU monitor socket at `/tmp/rc-mon.sock` and a
serial socket at `/tmp/rc-serial.sock`; append `console=ttyS0,115200` to the
kernel command line (Tab in the boot menu) to get a serial login shell.
When booted into the installer entry, cage is not running, so
Ctrl+Alt+F2 also gives a tty2 login — handy for poking at the live system.

## Flash to USB

```sh
# find the disk with: diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=out/retroconsole-*.iso of=/dev/rdiskN bs=4m status=progress
```

## Branching & CI gates

Changes flow through four branches, left to right — a merge is only ever made
in this direction:

```
feat/* ──▶ develop ──▶ rc ──▶ main
```

- **`feat/*`** — one branch per change, cut from `develop`.
- **`develop`** — integration branch; where day-to-day work lands.
- **`rc`** — **long-lived** staging branch (not recreated per release). It
  exists for one reason: so the slow tests gate only the infrequent
  `rc → main` promotion instead of every `feat → develop` merge.
- **`main`** — stable branch; release tags are cut from here.

CI (`.github/workflows/ci.yml`) runs a different **tier** of tests depending on
which branch a pull request targets — cheap-and-broad near `develop`,
slow-and-thorough near `main`:

| PR base | Tier | What runs | ~time |
|---------|------|-----------|-------|
| `develop` | **fast** | `shellcheck` + `bash -n` sweep; build `retroconsole-config` and assert its contents; `retroconsole-seed` override-policy (seed/reconcile) test | seconds–~2 min |
| `rc` | **medium** | full `make iso` (proves the image assembles) | ~30+ min |
| `main` | **full** | `make iso` + QEMU smoke (boot-to-ES-DE; BIOS+UEFI install→boot matrix; OTA-upgrade sim) | ~1 h+ |

The full tier runs QEMU in **TCG software emulation** — GitHub-hosted runners
have no `/dev/kvm` — which is the second reason (after wall-clock) it sits only
at the `rc → main` edge. A self-hosted runner with `/dev/kvm` is the escape
hatch if that tier's runtime becomes a problem.

**Staged strictness.** The gate tightens in two steps, not all at once:

1. **Lean gate first** — branch protection requires only the **fast** checks on
   `develop` and the **medium** `make iso` on `rc`/`main`. The full QEMU tier
   runs **non-blocking** (it reports but cannot block a merge) while it earns a
   track record.
2. **Tighten later** — once the full tier has proven reliable, its
   `full-qemu-smoke` check is promoted to a required check on `rc → main`.

A release is the far end of this pipe: work reaches `main` through the gates
above, then a tag cut from `main` runs `release.yml` (below).

## Releasing

Releases are cut by CI (`.github/workflows/release.yml`), not by hand — no
manual ISO uploads, no manual `publish-repo.sh`. Push a semver tag and the
workflow does everything:

```sh
git tag v0.1.0
git push origin v0.1.0
```

On a native amd64 runner it builds the ISO (same Docker image and scripts as
`make iso`), then:

- creates the GitHub Release `v0.1.0` with the ISO and its `.sha256`
  attached — this is the fresh-install medium; and
- republishes the rolling `repo` pacman repository, the OTA channel that
  *Tools → Update System* pulls from.

Versioning starts at `v0.1.0`. No secrets to configure: the workflow uses the
built-in `GITHUB_TOKEN` (needs `contents: write`, which it requests). Expect
~30–60 min — the AUR packages compile from source on every release (no
cross-run caching, so each release's artifacts are reproducible from the tag).

## Ship a fix to installed systems (OTA)

System-level appliance files (session/update scripts, polkit rule,
WirePlumber/keymap config, sudoers) are owned by the `retroconsole-config`
package (`packages/retroconsole-config/`), not by loose airootfs files, so
installed systems receive fixes through *Tools → Update System* without
reflashing:

1. Edit the file under `packages/retroconsole-config/` and bump `pkgver`
   (or `pkgrel` for a packaging-only change) in the `PKGBUILD`.
2. Merge to `main` and cut a release (see *Releasing* above). CI rebuilds the
   package and republishes the rolling `repo` GitHub Release that installed
   systems have as their primary pacman server (with the baked-in
   `file:///opt/retroconsole/repo` as offline fallback). The OTA repo is
   refreshed only when a release is cut, so a fix ships the moment you tag.

To try the package before releasing, run `make iso` (rebuilds it into the
local `[retroconsole]` repo) and optionally `scripts/publish-repo.sh` to push
it to the `repo` release by hand.

Files seeded under `/home/retro` (ES-DE settings, retroarch.cfg, foot.ini)
are runtime-mutable user state: they live in airootfs and are written to the
`rcuser` (`/home`) partition only when that path does not already exist — a
fresh install, or a new default added in a later ISO (see the system/user
split note below). A reinstall does **not** overwrite a user's existing copy,
so fixes to these never reach machines already in the field — keep product
logic out of them (the ROMs tools scripts are one-line wrappers for that
reason; ship behavioural fixes through the package above).

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
- **System / user split**: the installer creates two ext4 partitions —
  `rcsys` (a fixed 16 GiB system root) and `rcuser` (the rest, mounted at
  `/home`). Partitions are found by GPT name (PARTLABELs `rcbios`, `rcesp`,
  `rcsys`, `rcuser`), not by device path, so nvme and sd\* disks and reinstalls
  behave identically. On a disk that already carries this layout the installer
  runs in *preserve* mode: it reformats only `rcsys` (and the ESP) and keeps
  `rcuser`, so a reinstall/update never loses games or settings. The `/home`
  skeleton from the image is seeded onto `rcuser` with `cp -an` — new default
  entries (e.g. a ROM folder for a newly added emulator) appear, existing user
  files are never overwritten. Disks with no (or an incomplete) RetroConsole
  layout get a full wipe.
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
