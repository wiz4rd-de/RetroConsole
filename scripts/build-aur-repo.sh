#!/usr/bin/env bash
# Build the AUR packages RetroConsole needs and publish them into the local
# [retroconsole] pacman repository inside the airootfs, so pacstrap can
# install them like any repo package.
#
# Packages are built in order and the repo database is refreshed after each
# one, so later packages can depend on earlier ones (emulationstation-de
# needs freeimage, which is itself AUR-only these days).
#
# Runs as root inside the build container. Set FORCE_AUR=1 to rebuild
# packages that are already in the repo.
set -euo pipefail

REPO_DIR=/build/profile/airootfs/opt/retroconsole/repo
BUILD_DIR=/tmp/aur-build
AUR_PACKAGES=(
    freeimage
    game-devices-udev
    retroarch-autoconfig-udev-git
    emulationstation-de
)

mkdir -p "${REPO_DIR}" "${BUILD_DIR}"
chown builder "${BUILD_DIR}"

# Make [retroconsole] resolvable for the container's own pacman, so makepkg
# can pull build/runtime deps that we built ourselves.
mkdir -p /opt/retroconsole
ln -sfn "${REPO_DIR}" /opt/retroconsole/repo
if ! grep -q '^\[retroconsole\]' /etc/pacman.conf; then
    printf '\n[retroconsole]\nSigLevel = Optional TrustAll\nServer = file:///opt/retroconsole/repo\n' >> /etc/pacman.conf
fi

refresh_repo() {
    # No --new: retroconsole-config is rebuilt every run with the same version
    # string but different bytes, so repo-add MUST update (re-checksum) the
    # existing entry. With --new it would skip the update, leaving the db
    # checksum pointing at the old file and pacstrap rejecting it as corrupt.
    (cd "${REPO_DIR}" && repo-add --remove retroconsole.db.tar.gz ./*.pkg.tar.zst)
    pacman -Sy --noconfirm
}

if compgen -G "${REPO_DIR}/*.pkg.tar.zst" >/dev/null; then
    refresh_repo
else
    # Bootstrap an empty database so pacman -Sy succeeds before the first build
    tar -czf "${REPO_DIR}/retroconsole.db.tar.gz" --files-from /dev/null
    ln -sf retroconsole.db.tar.gz "${REPO_DIR}/retroconsole.db"
    pacman -Sy --noconfirm
fi

for pkg in "${AUR_PACKAGES[@]}"; do
    if [[ -z ${FORCE_AUR:-} ]] && compgen -G "${REPO_DIR}/${pkg}-[0-9]*.pkg.tar.zst" >/dev/null; then
        echo ":: ${pkg}: already built, skipping (FORCE_AUR=1 to rebuild)"
        continue
    fi
    echo ":: Building ${pkg} from AUR..."
    rm -rf "${BUILD_DIR:?}/${pkg}"
    sudo -u builder git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "${BUILD_DIR}/${pkg}"
    # --skippgpcheck: the throwaway container has no gpg keyring for AUR
    # maintainer keys; source integrity is still covered by the checksums.
    (cd "${BUILD_DIR}/${pkg}" && sudo -u builder env MAKEFLAGS="-j$(nproc)" makepkg --syncdeps --noconfirm --skippgpcheck)
    cp "${BUILD_DIR}/${pkg}"/*.pkg.tar.zst "${REPO_DIR}/"
    refresh_repo
done

# Our own config package: always rebuilt (cheap — no compilation) so file
# edits and pkgver bumps are picked up by every build.
echo ":: Building retroconsole-config..."
rm -rf "${BUILD_DIR}/retroconsole-config"
cp -r /build/packages/retroconsole-config "${BUILD_DIR}/retroconsole-config"

# Generate the package skel from the airootfs /home/retro tree so the two can
# never drift: airootfs stays the single source of truth, retroconsole-seed
# reconciles installed boxes from the packaged copy at the neutral path
# /usr/share/retroconsole/skel/home/retro/ (A1/#8, A3/#10). The allowlist (only
# the "unreachable" managed files the override policy force-overwrites) lives in
# scripts/gen-config-skel.sh — shared with the fast-tier package assertion
# (#28) so CI exercises this exact generation step.
echo ":: Generating retroconsole-config skel from airootfs allowlist..."
/build/scripts/gen-config-skel.sh \
    /build/profile/airootfs/home/retro \
    "${BUILD_DIR}/retroconsole-config/skel/home/retro"

chown -R builder "${BUILD_DIR}/retroconsole-config"
(cd "${BUILD_DIR}/retroconsole-config" && sudo -u builder makepkg --noconfirm --force)
rm -f "${REPO_DIR}"/retroconsole-config-*.pkg.tar.zst
cp "${BUILD_DIR}/retroconsole-config"/retroconsole-config-*.pkg.tar.zst "${REPO_DIR}/"
refresh_repo

echo ":: Done. Repo contents:"
ls -lh "${REPO_DIR}"
