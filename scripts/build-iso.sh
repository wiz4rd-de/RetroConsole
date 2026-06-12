#!/usr/bin/env bash
# Container entrypoint: build the AUR repo, then the ISO.
#
# The work directory must live on the container's own filesystem (not the
# bind-mounted macOS volume): mkarchiso creates device nodes and needs native
# Linux filesystem semantics, and squashfs creation over virtiofs is slow.
set -euo pipefail

/build/scripts/build-aur-repo.sh

# The profile's pacman.conf points at file:///opt/retroconsole/repo; make that
# path resolve inside the build container too.
mkdir -p /opt/retroconsole
ln -sfn /build/profile/airootfs/opt/retroconsole/repo /opt/retroconsole/repo

rm -rf /tmp/archiso-work
mkdir -p /build/out
mkarchiso -v -w /tmp/archiso-work -o /build/out /build/profile

echo ":: ISO ready:"
ls -lh /build/out/*.iso
