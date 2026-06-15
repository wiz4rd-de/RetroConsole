# Hardware notes

## Requirements

- x86_64 PC, UEFI or legacy BIOS (the installed disk boots on both: GPT with a
  BIOS boot partition + ESP, GRUB installed for both firmware types)
- One internal disk, at least 24 GiB. With a single internal disk the installer
  uses it automatically; if several are present it lists them and asks which one
  to install onto (so a data drive is never wiped by mistake), then asks once
  more before writing. The chosen disk is split into a fixed 16 GiB system
  partition (`rcsys`) and a `rcuser` partition that holds `/home` — games and
  settings — and takes the rest. A first-time install wipes that disk;
  reinstalling or updating on a machine that already runs RetroConsole keeps the
  `rcuser` partition, so games and settings survive.
- Intel or AMD graphics work out of the box (mesa/Vulkan). NVIDIA uses the
  open nouveau/NVK stack — fine for the bundled libretro cores; the
  proprietary driver is intentionally not included yet.

## Troubleshooting

- **TV shows "no signal" for ~30 s during live/installed boot**: expected.
  Shortly after the boot messages the kernel's GPU driver takes over the
  display and some TVs drop the signal until ES-DE starts and sets a proper
  mode. The installer is unaffected: it boots with `nomodeset` and stays on
  the firmware framebuffer the whole time.
- **Black screen instead of ES-DE**: the GPU may be too old for the GLES
  renderer. Add `retroconsole.software` to the kernel command line (press `e`
  in GRUB) to force software rendering, then report the hardware.
- **Sound comes out of the PC instead of the TV**: HDMI outputs are ranked
  above analog via `/etc/wireplumber/wireplumber.conf.d/50-retroconsole-prefer-hdmi.conf`.
  If it still happens, switch to tty2 and run `wpctl status` — if no HDMI
  sink is listed at all, the sound card's active profile is analog-only;
  report the `wpctl status` output so a profile rule can be added.
- **Console access**: ES-DE runs on tty1. Switch to tty2 (Ctrl+Alt+F2) and log
  in as `retro` (no password) for a shell.

## In-game menu & shaders

- **Open the RetroArch menu**: while a game is running, hold **Down + Select** on
  the pad to open the in-game RetroArch menu (*Quick Menu*); **Start + Select**
  still quits back to ES-DE. A keyboard `F1` also opens the menu if one is
  attached. Use the menu for save states, fast-forward, controls, and shaders.
- **Shaders (CRT look)**: in ES-DE, highlight a game and open its *Options →
  Alternative emulators*, then pick **RetroArch — CRT** to launch with a CRT
  scanline shader applied. To tweak or turn it off live, open the RetroArch menu
  (Down + Select) and go to *Quick Menu → Shaders*. A preset you save there is
  remembered **per game**, overrides the ES-DE CRT default, and survives updates.
  The default graphics driver is `gl`, which uses the **glsl** shaders (the CRT
  variant ships the lightweight `zfast-crt` preset so it stays smooth on weaker
  GPUs); a **slang** shader pack is also installed for anyone who switches the
  driver to `glcore` from the menu.

## BIOS files

PSX needs user-supplied BIOS images; see
`/home/retro/.config/retroarch/system/README.txt` on the box (you can drop
files there via the ROMs network share).

## Tested machines

| Machine | GPU | Firmware | Status |
|---|---|---|---|
| _(none yet)_ | | | |
