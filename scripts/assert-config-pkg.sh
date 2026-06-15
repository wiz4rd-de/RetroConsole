#!/usr/bin/env bash
# Fast-tier assertion: build the retroconsole-config package (data-only makepkg,
# NOT a full `make iso`) and assert the built .pkg.tar.zst ships every package()
# target at the expected path AND mode, with a NON-EMPTY generated skel.
#
# retroconsole-config is how every appliance fix reaches installed boxes over
# OTA, so a dropped managed file, a wrong mode, or an empty skel is a
# high-impact, easy-to-miss regression. This catches that class by building the
# package and inspecting the result, without installing it.
#
# Runs inside an Arch container (root); makepkg refuses root, so it builds as an
# unprivileged 'builder' user. CI runs it via docker; locally:
#   docker run --rm -v "$PWD":/build:ro -w /build archlinux:latest bash -c '
#     pacman -Sy --noconfirm --needed base-devel git >/dev/null && scripts/assert-config-pkg.sh'
set -euo pipefail

cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
BUILD="${WORK}/retroconsole-config"
cp -r packages/retroconsole-config "${BUILD}"

# Generate the skel exactly as the ISO build does (shared code path, #28).
scripts/gen-config-skel.sh profile/airootfs/home/retro "${BUILD}/skel/home/retro"
skelfiles=$(find "${BUILD}/skel" -type f | wc -l)
echo ":: generated skel: ${skelfiles} file(s)"
if [[ ${skelfiles} -eq 0 ]]; then
    echo "FAIL: generated skel is EMPTY (the empty-skel regression class)" >&2
    exit 1
fi

# makepkg won't run as root; build as 'builder'. --nodeps: skip the openssh
# runtime dep (we only inspect the package, never install it). --force: overwrite.
if [[ ${EUID} -eq 0 ]]; then
    id builder &>/dev/null || useradd -m builder
    chown -R builder "${WORK}"
    sudo -u builder bash -c "cd '${BUILD}' && makepkg --noconfirm --force --nodeps"
else
    ( cd "${BUILD}" && makepkg --noconfirm --force --nodeps )
fi

PKG=$(ls "${BUILD}"/retroconsole-config-*.pkg.tar.zst 2>/dev/null | head -1)
if [[ ! -f ${PKG} ]]; then
    echo "FAIL: makepkg produced no package" >&2
    exit 1
fi
echo ":: built $(basename "${PKG}")"

# Normalize the archive listing to "<symbolic-mode>\t<path>" lines. Paths can
# contain spaces (the ROMs/tools/*.sh launchers), so reconstruct from field 6+.
listing=$(tar tvf "${PKG}" | awk '{m=$1; n=$6; for(i=7;i<=NF;i++) n=n" "$i; print m"\t"n}')

fail=0
check() {  # check <path> <expected-symbolic-mode>
    local p=$1 want=$2 got
    got=$(awk -F'\t' -v p="$p" '$2==p{print $1; f=1} END{if(!f) exit 1}' <<<"${listing}") \
        || { echo "FAIL missing: ${p}" >&2; fail=1; return; }
    if [[ ${got} != "${want}" ]]; then
        echo "FAIL mode ${p}: want ${want} got ${got}" >&2; fail=1; return
    fi
    echo "  ok ${p} (${got})"
}

# Static package() targets — paths + modes from the PKGBUILD.
check usr/local/bin/retroconsole-session -rwxr-xr-x
check usr/local/bin/retroconsole-launch  -rwxr-xr-x
check usr/local/bin/retroconsole-update  -rwxr-xr-x
check usr/local/bin/retroconsole-seed    -rwxr-xr-x
check etc/systemd/system/retroconsole-seed.service                       -rw-r--r--
check etc/sudoers.d/retroconsole                                         -r--r-----
check etc/polkit-1/rules.d/50-retroconsole-network.rules                 -rw-r--r--
check etc/wireplumber/wireplumber.conf.d/50-retroconsole-prefer-hdmi.conf -rw-r--r--
check etc/vconsole.conf                                                   -rw-r--r--
check usr/share/libretro/autoconfig/udev/retrobit-genesis-saturn-8button.cfg -rw-r--r--

# Named skel members (the non-launcher managed files), all 0644.
SKEL=usr/share/retroconsole/skel/home/retro
check "${SKEL}/.bash_profile"                          -rw-r--r--
check "${SKEL}/.config/foot/foot.ini"                  -rw-r--r--
check "${SKEL}/ES-DE/custom_systems/es_systems.xml"    -rw-r--r--

# Every skel tool launcher (.sh, names contain spaces) must be 0755; >=1 present.
toolcount=0
while IFS=$'\t' read -r m n; do
    case "${n}" in
        "${SKEL}"/ROMs/tools/*.sh)
            toolcount=$((toolcount + 1))
            [[ ${m} == -rwxr-xr-x ]] || { echo "FAIL tool mode ${n}: ${m} (want -rwxr-xr-x)" >&2; fail=1; }
            ;;
    esac
done <<<"${listing}"
if [[ ${toolcount} -ge 1 ]]; then
    echo "  ok ${toolcount} skel tool launcher(s) at 0755"
else
    echo "FAIL: package ships no skel tool launchers" >&2; fail=1
fi

# Any other packaged skel file (not a .sh launcher, not a dir) must be 0644 —
# mirrors the PKGBUILD's install -Dm644 branch, so a mode slip is caught.
while IFS=$'\t' read -r m n; do
    [[ ${m} == d* ]] && continue
    case "${n}" in
        "usr/share/retroconsole/skel/"*.sh) ;;            # launcher, checked above
        "usr/share/retroconsole/skel/"*)
            [[ ${m} == -rw-r--r-- ]] || { echo "FAIL skel mode ${n}: ${m} (want -rw-r--r--)" >&2; fail=1; }
            ;;
    esac
done <<<"${listing}"

if [[ ${fail} -eq 0 ]]; then
    echo ":: package assertions passed"
else
    echo ":: package assertions FAILED" >&2
fi
exit "${fail}"
