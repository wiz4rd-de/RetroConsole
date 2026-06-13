#!/usr/bin/env bash
# Publish the [retroconsole] pacman repository to GitHub Releases.
#
# Uploads the package files and repo database from the local repo dir to a
# rolling release tagged "repo". Installed systems have
#   Server = https://github.com/wiz4rd-de/RetroConsole/releases/download/repo
# as their primary [retroconsole] server, so "Update System" (pacman -Syu)
# picks up whatever is published here.
#
# Run after a build that refreshed the repo (scripts/build-aur-repo.sh runs
# as part of `make iso` and rebuilds retroconsole-config every time).
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_DIR=profile/airootfs/opt/retroconsole/repo
TAG=repo

[[ -r ${REPO_DIR}/retroconsole.db.tar.gz ]] \
    || { echo "No repo database in ${REPO_DIR} — run 'make iso' first." >&2; exit 1; }

if ! gh release view "${TAG}" >/dev/null 2>&1; then
    gh release create "${TAG}" \
        --title "Package repository" \
        --notes "Rolling [retroconsole] pacman repository. Do not delete: installed systems update from these assets." \
        --latest=false
fi

# pacman fetches retroconsole.db / retroconsole.files; locally those are
# symlinks to the .tar.gz files. Upload real copies under the plain names.
STAGE=$(mktemp -d)
trap 'rm -rf "${STAGE}"' EXIT
cp "${REPO_DIR}"/*.pkg.tar.zst "${STAGE}/"
cp -L "${REPO_DIR}/retroconsole.db.tar.gz" "${STAGE}/retroconsole.db.tar.gz"
cp -L "${REPO_DIR}/retroconsole.files.tar.gz" "${STAGE}/retroconsole.files.tar.gz"
cp -L "${REPO_DIR}/retroconsole.db.tar.gz" "${STAGE}/retroconsole.db"
cp -L "${REPO_DIR}/retroconsole.files.tar.gz" "${STAGE}/retroconsole.files"

echo ":: Uploading $(ls "${STAGE}" | wc -l | tr -d ' ') assets to release '${TAG}'..."
gh release upload "${TAG}" "${STAGE}"/* --clobber

# Drop stale assets (old package versions) no longer present locally.
local_files=$(ls "${STAGE}")
for asset in $(gh release view "${TAG}" --json assets -q '.assets[].name'); do
    if ! grep -qx "${asset}" <<< "${local_files}"; then
        echo ":: Deleting stale asset ${asset}"
        gh release delete-asset "${TAG}" "${asset}" --yes
    fi
done

echo ":: Published. Installed systems will pick this up on their next update."
