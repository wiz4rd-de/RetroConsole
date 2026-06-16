# Changelog

All notable changes to RetroConsole are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Each release corresponds to a milestone; `(#NN)` references the GitHub issue.
Changes accumulate under **[Unreleased]** as they merge to `develop` and are
finalized into a version block when the release tag is cut.

## [Unreleased]

### Added
- **Four selectable shader looks per system.** Each console's *Alternative
  emulators* list now offers, beside the bundled default (no shader), four
  intensity-ordered tiers — **RetroArch — Smooth** (bilinear, smooth scaling),
  **RetroArch — CRT** (`zfast-crt`, the recommended CRT), **RetroArch — CRT Sharp**
  (`crt-easymode`) and **RetroArch — CRT Sharp+Glow** (`crt-easymode-halation`) —
  so players pick a look from smooth scaling up to a glowing CRT. The two heavier
  *Sharp* looks are opt-in, so the low-end box and the recommended CRT never
  regress. Set per game (*Options → Alternative emulators*) or for everything
  (*Other Settings → Alternative emulators*). (#79)
- **Saved per-game shader presets now win over the chosen look.** A preset saved
  from *Quick Menu → Shaders → Save Game Preset* applies on every launch of that
  game through any tier, overriding the tier's preset (precedence: per-game saved
  preset → chosen tier → per-core → global). A new `retroconsole-crt-launch`
  wrapper implements this; deleting the saved preset restores the tier's look.
  (#79)

### Changed
- **RetroArch — CRT** is now one of four shader tiers and launches through
  `retroconsole-crt-launch` — its label is unchanged, so existing per-game CRT
  selections keep working. The shader subsystem is now enabled globally
  (`video_shader_enable` / `auto_shaders_enable` / `rgui_config_directory` ship in
  `retroarch.cfg` and are forced over OTA by `retroconsole-seed`), and the
  per-launch `crt.cfg` overlay is retired (`--appendconfig` is gone; pacman removes
  the orphaned file on upgrade). The default (no-shader) launch is unchanged.
  Supersedes #76. (#79)

## [0.3.2] - 2026-06-16

### Fixed
- **RetroArch — CRT** now actually applies its shader. The alternative emulator
  set the preset by appending a `video_shader = …` line to RetroArch's config, but
  RetroArch removed that config key in 1.7.8 and silently ignores it — so the CRT
  variant enabled the shader subsystem yet selected nothing, launching with no
  visible effect even though the glsl pack and `zfast-crt` preset were on disk.
  (The 0.3.1 fix made the shader *files* reach OTA boxes but did not address this:
  the file was present and still nothing loaded.) The CRT command now selects the
  preset on the RetroArch command line with `--set-shader …/crt/zfast-crt.glslp`,
  the launch-time mechanism RetroArch honors, and `crt.cfg` is trimmed to the one
  key it still needs (`video_shader_enable`). The default (non-CRT) launch is
  unchanged. Reaches existing boxes over OTA. (#20)

## [0.3.1] - 2026-06-15

Shader delivery fix (M11 follow-up): the glsl/slang packs now reach existing
boxes over OTA, so *Quick Menu → Shaders* is populated and the **RetroArch — CRT**
emulator actually applies its shader — both without an Online Updater download.

### Fixed
- Shaders now actually reach existing boxes over OTA. The glsl/slang packs were
  listed only in the ISO build manifest, so an *Update System* (`pacman -Syu`)
  never installed them — leaving *Quick Menu → Shaders* empty and the
  **RetroArch — CRT** emulator with no visible effect (its overlay pointed at a
  shader file that wasn't on disk). `retroconsole-config` now depends on both
  packs, so OTA pulls them in. (#19, #20)
- *Quick Menu → Shaders → Load Shader Preset* now opens at the bundled pack
  (`video_shader_dir`), so shaders are browsable without first running the Online
  Updater. Forced onto existing boxes by the seed. (#19)

## [0.3.0] - 2026-06-15

In-game RetroArch menu + selectable shaders (M11) and ES-DE system curation
(the create-system-directories ROM-flood fix + Sega Master System).

### Added
- In-game RetroArch menu from the controller: hold **Down + Select** while a game
  is running to open it (Start + Select still quits to ES-DE; keyboard `F1` still
  works). Reaches fresh installs and existing boxes over OTA. (#18)
- Shader presets now ship, so *Quick Menu → Shaders* is no longer empty: the
  **glsl** pack (used by the default `gl` driver) and the **slang** pack (for
  users who switch the driver to `glcore`). (#19)
- Selectable CRT shader, surfaced in ES-DE as a **RetroArch — CRT** alternative
  emulator per system — launching a game with it applies a CRT scanline shader
  (the lightweight `zfast-crt` preset, chosen to stay smooth on weak GPUs). A
  preset saved from the in-game menu overrides it per game and persists across
  updates. (#20)
- Hardware docs for the menu combo and shader selection. (#21)
- **Sega Master System** added to the curated systems — default emulator Genesis
  Plus GX plus the **RetroArch — CRT** variant. Reaches existing boxes (folder +
  system) over OTA on the next *Update System*. (#65)
- *Adding a curated system* recipe and the empty-bundled-list design note in
  `docs/BUILDING.md`. (#66)

### Changed
- Systems launched through ES-DE (NES, SNES, Genesis, Mega Drive, GB, GBC, GBA,
  N64, PSX) now list the default emulator plus the new **RetroArch — CRT** variant
  only; other bundled libretro cores are no longer selectable from the ES-DE
  alternative-emulators menu for those systems. The default launch is unchanged,
  and per-game tweaks remain available from the in-game RetroArch menu. (#20)

### Fixed
- *Utilities → Create/update system directories* no longer floods the ROMs share
  with ~190 folders. ES-DE's bundled ~190-system list is force-emptied at runtime
  so `custom_systems` is the sole source of truth — ES-DE knows only the curated
  set, so that menu can only ever (re)create curated dirs. (#62, #63)
- ROM folders stay guest-writable: `retroconsole-seed` reconciles each curated
  dir to 0777 (directory only, never touching ROMs) and sweeps empty non-curated
  leftovers — tidying boxes already flooded before the fix — while preserving any
  folder that holds a real ROM. Reaches existing boxes over OTA. (#62, #64)

## [0.2.2] - 2026-06-15

Field fixes (M13).

### Fixed
- Sega-lookalike 8-button pad (Retro-Bit / 8BitDo-M30 class) now enumerates
  correctly, with a working d-pad and the right face buttons. (#47)
- Sound is no longer quiet out of the box — the default audio sink is pinned to
  full volume (WirePlumber starts new routes at 40%). (#13)
- Audio buzz/stutter on 50 Hz (PAL) panels fixed by pinning RetroArch's refresh
  to the panel's actual rate instead of assuming 60 Hz. (#14)
- *Update System* now returns to ES-DE on its own after finishing (timed
  auto-return), so no keyboard is needed to dismiss it. (#45)

### Added
- Boot splash screen and a project logo in the README.

### Changed
- CI: the `main` branch edge is protected — releases can only reach `main` from
  `rc`/`hotfix` branches, keeping the release history linear.

## [0.2.1] - 2026-06-14

OTA managed-home + field debugging (M10) and the CI/branch-flow groundwork (M12).

### Added
- Over-the-air home reconciliation: appliance home defaults (controller configs,
  ES-DE systems, session files) now reach already-installed boxes through
  *Update System* without a reflash, while user data (games, saves, settings) is
  never touched. (#8, #9, #10, #11)
- Field debugging on installed boxes: SSH access (openssh, enabled on install)
  and a fullscreen shell tool in the ES-DE Tools menu. (#12, #15)
- Installed disks now show a brief GRUB boot menu instead of booting silently. (#16)

### Changed
- Development workflow: tiered pull-request CI (fast/medium/full by branch) and a
  documented `feat → develop → rc → main` git-flow. (#25–#33)

## [0.2.0] - 2026-06-13

Disk safety and data persistence.

### Added
- When several internal disks are present, the installer now asks which one to
  install onto (with a confirmation) instead of auto-wiping the largest, so a
  data drive is never erased by mistake. (#5)
- A separate `/home` partition (`rcuser`) holds games and settings, so a reinstall
  or update on an existing RetroConsole box preserves them. (#5)

### Fixed
- Incremental ISO builds no longer corrupt the local package repo (dropped the
  `repo-add --new` that skipped re-checksumming rebuilt packages).

## [0.1.0] - 2026-06-13

First release — a self-installing, controller-first retro console (M0–M8).

### Added
- Bootable installer ISO (archiso) that installs RetroConsole to an internal disk
  (GPT, boots on both UEFI and legacy BIOS) and boots straight into ES-DE with
  RetroArch as the emulator.
- Controller-first kiosk session (cage/Wayland, autologin): gamepads work in
  RetroArch out of the box, with a controller-only Start+Select quit and on-screen
  power-off.
- On-screen system updates launched from the ES-DE Tools menu (`pacman -Syu`).
- Wi-Fi setup tool and a guest-writable Samba share for dropping ROMs over the
  network.
- HDMI-preferred audio routing and a German console/keyboard layout.
- Appliance configuration packaged so later fixes ship over OTA, and a tag-driven
  release pipeline that builds the ISO and publishes the OTA channel.

[Unreleased]: https://github.com/wiz4rd-de/RetroConsole/compare/v0.3.2...develop
[0.3.2]: https://github.com/wiz4rd-de/RetroConsole/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/wiz4rd-de/RetroConsole/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/wiz4rd-de/RetroConsole/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/wiz4rd-de/RetroConsole/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/wiz4rd-de/RetroConsole/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/wiz4rd-de/RetroConsole/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/wiz4rd-de/RetroConsole/releases/tag/v0.1.0
