#!/usr/bin/env bash
# Boot the RetroConsole ISO (or an installed test disk) in QEMU on macOS.
#
#   scripts/test-qemu.sh                 boot ISO, BIOS firmware
#   scripts/test-qemu.sh --uefi          boot ISO, UEFI firmware (OVMF/edk2)
#   scripts/test-qemu.sh --fresh-disk    recreate the virtual target disk first
#   scripts/test-qemu.sh --boot-disk     boot from the target disk (no ISO),
#                                        i.e. test the installed system
#
# x86_64 on Apple Silicon runs under TCG emulation: expect it to be slow.
set -euo pipefail

cd "$(dirname "$0")/.."

MODE=bios
FRESH=0
BOOT_DISK=0
for arg in "$@"; do
    case "${arg}" in
        --uefi) MODE=uefi ;;
        --bios) MODE=bios ;;
        --fresh-disk) FRESH=1 ;;
        --boot-disk) BOOT_DISK=1 ;;
        *) echo "Unknown argument: ${arg}" >&2; exit 1 ;;
    esac
done

DISK="out/test-disk-${MODE}.qcow2"
if [[ ${FRESH} -eq 1 ]]; then
    rm -f "${DISK}"
fi
if [[ ! -e ${DISK} ]]; then
    mkdir -p out
    qemu-img create -f qcow2 "${DISK}" 32G
fi

ARGS=(
    -machine q35
    -m 4096
    -smp 4
    -drive "file=${DISK},if=virtio,format=qcow2"
    -device virtio-vga
    -display default,show-cursor=on
    -device qemu-xhci
    -device usb-tablet
    -audio coreaudio,model=hda
    -nic user,model=virtio-net-pci
)

if [[ ${MODE} == uefi ]]; then
    EDK2="$(brew --prefix qemu)/share/qemu/edk2-x86_64-code.fd"
    [[ -r ${EDK2} ]] || { echo "edk2 firmware not found at ${EDK2}" >&2; exit 1; }
    ARGS+=(-drive "if=pflash,format=raw,readonly=on,file=${EDK2}")
fi

if [[ ${BOOT_DISK} -eq 0 ]]; then
    ISO=$(ls -t out/retroconsole-*.iso 2>/dev/null | head -1) \
        || { echo "No ISO in out/ — run 'make iso' first." >&2; exit 1; }
    ARGS+=(-cdrom "${ISO}" -boot d)
fi

exec qemu-system-x86_64 "${ARGS[@]}"
