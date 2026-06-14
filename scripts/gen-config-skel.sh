#!/usr/bin/env bash
# Generate the retroconsole-config package skel from the airootfs /home/retro
# tree. This is the single source of truth for the managed-home allowlist — the
# "unreachable" files retroconsole-seed force-overwrites on installed boxes
# (tool launchers, es_systems.xml, .bash_profile, foot.ini). User-reachable
# state (es_settings.xml, ROMs, savestates, scraped media, gamelists) is
# deliberately NOT listed, so an update never clobbers it.
#
#   gen-config-skel.sh <airootfs_home_retro> <skel_dest>
#
# Both the ISO build (scripts/build-aur-repo.sh) and the fast-tier package
# assertion (scripts/assert-config-pkg.sh) call this, so the CI gate exercises
# the exact code path that ships the release — a drifted/empty skel can't pass
# the test yet ship broken. The empty-skel bug class lived here once (a relative
# "skel" path silently producing nothing); keep generation and verification on
# one implementation.
set -euo pipefail

SKEL_SRC=${1:?usage: gen-config-skel.sh <airootfs_home_retro> <skel_dest>}
SKEL_DST=${2:?usage: gen-config-skel.sh <airootfs_home_retro> <skel_dest>}

SKEL_ALLOWLIST=(
    "ROMs/tools/*.sh"                       # tool launchers (root:root 0755)
    "ES-DE/custom_systems/es_systems.xml"   # systems definition
    ".bash_profile"                         # kiosk session bootstrap
    ".config/foot/foot.ini"                 # terminal config
)

rm -rf "${SKEL_DST}"
for pattern in "${SKEL_ALLOWLIST[@]}"; do
    for src in "${SKEL_SRC}"/${pattern}; do
        [[ -e ${src} ]] || continue
        rel="${src#"${SKEL_SRC}/"}"
        mkdir -p "${SKEL_DST}/$(dirname "${rel}")"
        cp "${src}" "${SKEL_DST}/${rel}"
    done
done
