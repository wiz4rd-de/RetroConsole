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

A release is the `rc → main` promotion followed by a semver tag cut from
`main`. Because `main` only accepts `rc`/`hotfix` commits and the tag inherits
whatever `main` has at merge time, two things **must be in place before the
`rc → main` PR merges** — neither can be added to `main` afterward:

1. **Finalize the CHANGELOG on `rc` first.** Rename `[Unreleased]` to a dated
   `[vX.Y.Z]` block, open a fresh empty `[Unreleased]`, and bump the compare
   links. Commit it on `rc` so it rides into `main` with the release PR, then
   back-sync `develop` to `rc` (e.g. cherry-pick the finalize) so the next
   `develop → rc` doesn't conflict.
2. **List `Closes #NN` for every issue in the release** in the `rc → main` PR
   body. `main` is the default branch, so this is the **only** PR whose closing
   keywords auto-close issues on merge — keywords in `feat → develop` PRs do
   nothing (use `Refs #NN` there). The repo's pull-request template
   (`.github/pull_request_template.md`) spells this out per branch.

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

## Adding a curated system

ES-DE only knows the systems defined in
`profile/airootfs/home/retro/ES-DE/custom_systems/es_systems.xml` — its bundled
~190-system list is force-emptied at runtime (see the design note below). So
adding a console is additive and self-contained:

1. **Copy the canonical entry from ES-DE.** From ES-DE's bundled
   `resources/systems/linux/es_systems.xml` (pin the version you build against —
   currently **3.4.1**), copy the system's `<name>` **verbatim** (the canonical
   name is what makes the theme supply artwork), plus its `<fullname>`, `<path>`,
   `<extension>`, `<platform>`, `<theme>`, and the **bundled DEFAULT** `<command>`
   (the first one — ES-DE's pick for that system).
2. **Add a `<system>` block** to `custom_systems/es_systems.xml` with two
   commands: the bundled default first (so a normal launch is byte-for-byte
   ES-DE's behavior), then the `RetroArch — CRT` variant — the **same core** with
   `--appendconfig /usr/share/retroconsole/retroarch/crt.cfg` appended. Drop the
   other bundled alt-emulators (M11 locked decision #3). Mirror an existing
   console's block.
3. **Ship the default core.** Add its libretro package to
   `profile/packages.x86_64`. It **must** be ES-DE's default core file for that
   system — if that `.so` is missing the launch fails with "core file not found"
   even when another core is installed (see the design note on per-system
   defaults). If the default core already ships for another system (e.g. Genesis
   Plus GX also drives Master System), no change is needed here.
4. **Create the ROM dir.** Add `["/home/retro/ROMs/<dir>"]="1000:1000:0777"` to
   `profile/profiledef.sh` (0777 so Samba guests can drop ROMs — see the Samba
   note below) and create `profile/airootfs/home/retro/ROMs/<dir>/.gitkeep` so
   the empty dir is tracked and ships in the image.
5. **Rebuild** (`make iso`). Fresh installs get the system and dir directly;
   existing boxes get both via `retroconsole-seed` on the next *Tools → Update
   System* (the seed materializes the curated dir at 0777 and the new
   `es_systems.xml` reaches the box over OTA).
6. **BIOS-dependent systems** (e.g. PlayStation-class, some Sega CD): we can't
   redistribute BIOS files, so the system will list but games won't launch until
   the user supplies the BIOS. Call this out in `docs/HARDWARE.md` and the
   share's RetroArch `system/README.txt` rather than shipping anything.

Master System (Genesis Plus GX, no extra core, no BIOS) is the worked example —
see its block in `es_systems.xml` and its `mastersystem` entries in
`profiledef.sh` and `ROMs/`.

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
- **`custom_systems` is the sole source of truth; the bundled list is emptied**
  (#62/#63). ES-DE merges its ~190-system bundled
  `/usr/share/es-de/resources/systems/linux/es_systems.xml` *under*
  `custom_systems/es_systems.xml`, which only **overrides by `<name>`** — so even
  with a curated `custom_systems`, ES-DE still *knows* ~190 systems.
  *Utilities → Create/update system directories* then creates a folder for every
  one of them in `/home/retro/ROMs` (the Samba share), most at 0755 — not
  guest-writable, so the share floods with unusable dirs; the same gap bites a
  curated dir a user deletes and recreates from the menu. The fix: ship an empty
  `<systemList/>` stub at the neutral path
  `/usr/share/retroconsole/es-de/es_systems-empty.xml` (a real
  `/usr/share/es-de/...` path would collide with `emulationstation-de` and abort
  pacstrap) and have `retroconsole-seed` force-overwrite the bundled file with it
  on every boot and after every *Update System* (a `pacman -Syu` reverts it to
  stock). ES-DE then knows **only** the curated set, so that menu can only ever
  (re)create curated dirs — and the menu stays fully visible (no Kiosk mode). The
  seed also reconciles each curated ROM dir to 0777 (directory only, never
  recursing into ROMs) and sweeps empty non-curated leftovers — a dir holding
  nothing but ES-DE's generated `systeminfo.txt` — to tidy already-flooded boxes,
  while preserving any dir that holds a real ROM. This is a deliberate, narrow
  exception to "seed never touches ROMs": top-level dir modes/existence only,
  and it skips any symlinked ROM dir so it can never chmod or delete through a
  link to a target outside the curated tree. One accepted side effect: because
  the seed force-replaces a package-owned file, `pacman -Qkk emulationstation-de`
  will report the bundled `es_systems.xml` as modified — that is the seed owning
  its runtime state by design, not corruption.
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
