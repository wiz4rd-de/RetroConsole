#!/usr/bin/env bash
# Full-tier headless QEMU smoke (CI gate rc -> main; NON-BLOCKING until #34).
#
# Boots the freshly-built ISO headless under the requested firmware and captures
# the serial log + periodic screendumps as artifacts, failing fast on a kernel
# panic. GitHub-hosted runners have NO /dev/kvm, so QEMU runs in TCG software
# emulation -- slow (a key reason this tier sits only at rc -> main). A
# self-hosted runner exposing /dev/kvm is the escape hatch (near-native speed +
# a persistent package cache); see docs/BUILDING.md.
#
# SCOPE / BAKE-IN (deliberate, see #31): today this is a boot smoke -- it proves
# the image boots in QEMU and reaches userspace without panicking, and saves
# screendumps for human review. The full tier ultimately wants more, and these
# are the planned hardening developed *against real CI runs* because this job is
# non-blocking first (#31), then promoted to required by #34:
#   * select the live ES-DE "safe graphics" entry and assert the ES-DE UI via a
#     deterministic serial sentinel (preferred over screendump OCR) -- needs the
#     boot cmdline to carry console=ttyS0, i.e. a CI boot entry or monitor
#     sendkey automation (mind the de-latin1 keymap quirk);
#   * the BIOS+UEFI install->boot matrix (install to a blank disk, boot it);
#   * the 0.2.0->latest OTA-upgrade sim (the v0.2.1 path) -- the integration
#     cousin of the #29 unit-level seed test.
#
# Usage:  scripts/test-qemu-ci.sh [--bios|--uefi] [--timeout=SECONDS] [--out=DIR]
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=bios
TIMEOUT=900
OUTDIR=out/ci-smoke
for a in "$@"; do
    case "$a" in
        --bios) MODE=bios ;;
        --uefi) MODE=uefi ;;
        --timeout=*) TIMEOUT=${a#*=} ;;
        --out=*) OUTDIR=${a#*=} ;;
        *) echo "unknown arg: $a" >&2; exit 2 ;;
    esac
done

ISO=$(ls -t out/retroconsole-*.iso 2>/dev/null | head -1 || true)
if [[ -z ${ISO} || ! -f ${ISO} ]]; then
    echo "no ISO in out/ -- run 'make iso' first" >&2
    exit 1
fi
mkdir -p "${OUTDIR}"
MON="${OUTDIR}/mon-${MODE}.sock"
SER="${OUTDIR}/serial-${MODE}.log"
rm -f "${MON}" "${SER}"

QEMU=(
    qemu-system-x86_64
    -m 4096 -smp 2 -machine q35
    -cdrom "${ISO}" -boot d
    -display none
    -device virtio-vga
    -serial "file:${SER}"
    -monitor "unix:${MON},server,nowait"
)
if [[ ${MODE} == uefi ]]; then
    OVMF=/usr/share/OVMF/OVMF_CODE.fd
    if [[ ! -r ${OVMF} ]]; then
        echo "OVMF firmware not found at ${OVMF} (apt install ovmf)" >&2
        exit 1
    fi
    QEMU+=(-drive "if=pflash,format=raw,readonly=on,file=${OVMF}")
fi

echo ":: [${MODE}] booting $(basename "${ISO}") headless (TCG, no KVM; up to ${TIMEOUT}s)"
"${QEMU[@]}" &
QPID=$!

# Wait for QEMU to create the monitor socket.
for _ in $(seq 1 15); do
    [[ -S ${MON} ]] && break
    sleep 1
done

mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:${MON}" 2>/dev/null || true; }

deadline=$((SECONDS + TIMEOUT))
shot=0
result=timeout
while ((SECONDS < deadline)); do
    if ! kill -0 "${QPID}" 2>/dev/null; then
        result=qemu-exited
        break
    fi
    sleep 20
    shot=$((shot + 1))
    mon "screendump ${OUTDIR}/screen-${MODE}-${shot}.ppm"
    if grep -qiE 'kernel panic|Oops:|Unable to mount root|Failed to start' "${SER}" 2>/dev/null; then
        result=panic
        break
    fi
done

mon "quit"
wait "${QPID}" 2>/dev/null || true
echo ":: [${MODE}] result=${result}; artifacts: ${OUTDIR}/serial-${MODE}.log, ${OUTDIR}/screen-${MODE}-*.ppm"

# Only a hard boot failure (panic) fails the smoke. The boot/UI/install/OTA
# assertions above are the bake-in work (#31 non-blocking -> #34 required), so
# a clean-but-unasserted boot does NOT fail the (currently non-required) gate.
if [[ ${result} == panic ]]; then
    echo ":: [${MODE}] BOOT FAILED (panic) -- see serial log" >&2
    exit 1
fi
exit 0
