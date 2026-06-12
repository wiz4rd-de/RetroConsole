#!/usr/bin/env bash
# Boot the RetroConsole ISO (or an installed test disk) in QEMU on macOS.
#
#   scripts/test-qemu.sh                 boot ISO, BIOS firmware
#   scripts/test-qemu.sh --uefi          boot ISO, UEFI firmware (OVMF/edk2)
#   scripts/test-qemu.sh --fresh-disk    recreate the virtual target disk first
#   scripts/test-qemu.sh --boot-disk     boot from the target disk (no ISO),
#                                        i.e. test the installed system
#   scripts/test-qemu.sh --gamepad[=VID:PID]
#                                        pass a host USB gamepad through to
#                                        the guest (default: ShanWan PS3/PC
#                                        pad, 2563:0523). macOS only releases
#                                        HID devices to root — run with sudo,
#                                        or the guest sees an unconfigurable
#                                        device (libusb ACCESS error).
#
# x86_64 on Apple Silicon runs under TCG emulation: expect it to be slow.
# Monitor and serial Unix sockets are exposed at /tmp/rc-mon.sock and
# /tmp/rc-serial.sock (append console=ttyS0,115200 to the kernel command
# line for a serial login shell).
set -euo pipefail

cd "$(dirname "$0")/.."

MODE=bios
FRESH=0
BOOT_DISK=0
GAMEPAD=""
for arg in "$@"; do
    case "${arg}" in
        --uefi) MODE=uefi ;;
        --bios) MODE=bios ;;
        --fresh-disk) FRESH=1 ;;
        --boot-disk) BOOT_DISK=1 ;;
        --gamepad) GAMEPAD="2563:0523" ;;
        --gamepad=*) GAMEPAD="${arg#--gamepad=}" ;;
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
    # zoom-to-fit makes the window freely resizable even in 640x480
    # text mode (QEMU's Cocoa UI otherwise locks the window size).
    -display cocoa,show-cursor=on,zoom-to-fit=on
    -device qemu-xhci
    -device usb-tablet
    -audio coreaudio,model=hda
    -nic user,model=virtio-net-pci
    -monitor unix:/tmp/rc-mon.sock,server,nowait
    -serial unix:/tmp/rc-serial.sock,server,nowait
)

if [[ -n ${GAMEPAD} ]]; then
    if [[ ${EUID} -ne 0 ]]; then
        echo "warning: --gamepad without root — macOS will not release the" >&2
        echo "         HID interface and the guest gets a dead device." >&2
    fi
    ARGS+=(-device "usb-host,vendorid=0x${GAMEPAD%%:*},productid=0x${GAMEPAD##*:}")
fi

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

# No exec: open up the control sockets once QEMU has created them, so
# they stay usable when the script runs under sudo.
qemu-system-x86_64 "${ARGS[@]}" &
QEMU_PID=$!
for _ in 1 2 3 4 5; do
    sleep 1
    chmod 666 /tmp/rc-mon.sock /tmp/rc-serial.sock 2>/dev/null && break
done
wait "${QEMU_PID}"
