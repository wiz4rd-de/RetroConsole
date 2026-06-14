#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="retroconsole"
iso_label="RETROCONSOLE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="RetroConsole"
iso_application="RetroConsole Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd instead of releng's xz: emulated x86_64 builds on Apple Silicon would
# take hours with xz, and ISO size is not a priority for a USB installer.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/retroconsole-live"]="0:0:440"
  ["/usr/local/bin/retroconsole-install"]="0:0:755"
  ["/home/retro/ROMs/tools/Update System.sh"]="0:0:755"
  ["/home/retro/ROMs/tools/Restart ES-DE.sh"]="0:0:755"
  ["/home/retro/ROMs/tools/Wi-Fi Setup.sh"]="0:0:755"
  ["/home/retro/ROMs/tools/Shell.sh"]="0:0:755"
  # 0777: Samba guest sessions are access-checked against the POSIX mode
  # (not the forced user), so the ROM drop dirs must be world-writable.
  ["/home/retro/ROMs/nes"]="1000:1000:0777"
  ["/home/retro/ROMs/snes"]="1000:1000:0777"
  ["/home/retro/ROMs/megadrive"]="1000:1000:0777"
  ["/home/retro/ROMs/gb"]="1000:1000:0777"
  ["/home/retro/ROMs/gbc"]="1000:1000:0777"
  ["/home/retro/ROMs/gba"]="1000:1000:0777"
  ["/home/retro/ROMs/psx"]="1000:1000:0777"
  ["/home/retro/ROMs/n64"]="1000:1000:0777"
)
