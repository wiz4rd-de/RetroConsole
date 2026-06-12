# Hardware notes

## Requirements

- x86_64 PC, UEFI or legacy BIOS (the installed disk boots on both: GPT with a
  BIOS boot partition + ESP, GRUB installed for both firmware types)
- One internal disk (the installer picks the largest internal, non-removable
  disk and asks once before wiping it)
- Intel or AMD graphics work out of the box (mesa/Vulkan). NVIDIA uses the
  open nouveau/NVK stack — fine for the bundled libretro cores; the
  proprietary driver is intentionally not included yet.

## Troubleshooting

- **Black screen instead of ES-DE**: the GPU may be too old for the GLES
  renderer. Add `retroconsole.software` to the kernel command line (press `e`
  in GRUB) to force software rendering, then report the hardware.
- **Console access**: ES-DE runs on tty1. Switch to tty2 (Ctrl+Alt+F2) and log
  in as `retro` (no password) for a shell.

## BIOS files

PSX needs user-supplied BIOS images; see
`/home/retro/.config/retroarch/system/README.txt` on the box (you can drop
files there via the ROMs network share).

## Tested machines

| Machine | GPU | Firmware | Status |
|---|---|---|---|
| _(none yet)_ | | | |
