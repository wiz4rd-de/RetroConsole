#!/usr/bin/env bash
# Fast-tier: exercise retroconsole-seed's managed-home override policy against a
# fabricated "old /home/retro" and assert the locked M10 policy holds:
#   * managed files/keys are force-overwritten to the packaged value;
#   * es_settings.xml + user data (ROMs/savestates) are NEVER touched — a
#     deliberate user edit survives;
#   * a second run is idempotent (same content/mode/owner, no errors);
#   * the live-guard (/etc/retroconsole-live) short-circuits with no changes.
#
# DESTRUCTIVE: wipes /home/retro and /usr/share/retroconsole/skel. It is for
# throwaway Arch CI containers ONLY — hence the opt-in guard below. Run as root
# (the seed installs files as user 'retro' and re-execs via sudo when not root).
# CI runs it via docker; locally:
#   docker run --rm -v "$PWD":/build:ro -w /build archlinux:latest bash -c '
#     pacman -Sy --noconfirm --needed base-devel >/dev/null &&
#     SEED_RECONCILE_TEST=1 scripts/test-seed-reconcile.sh'
set -uo pipefail

if [[ ${SEED_RECONCILE_TEST:-} != 1 ]]; then
    echo "Refusing to run: this test WIPES /home/retro and /usr/share/retroconsole/skel." >&2
    echo "It is for throwaway Arch CI containers only. Set SEED_RECONCILE_TEST=1 to proceed." >&2
    exit 2
fi

cd "$(dirname "$0")/.."
SEED="${PWD}/packages/retroconsole-config/retroconsole-seed"
SKEL=/usr/share/retroconsole/skel/home/retro
HOME_DIR=/home/retro

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*" >&2; fail=1; }

# --- setup -----------------------------------------------------------------
id retro &>/dev/null || useradd -m retro || { echo "setup: useradd retro failed" >&2; exit 1; }
rm -rf "${HOME_DIR}" /usr/share/retroconsole/skel
mkdir -p "${HOME_DIR}"

# Packaged skel (the managed defaults), generated exactly as the build does.
scripts/gen-config-skel.sh profile/airootfs/home/retro "${SKEL}" \
    || { echo "setup: skel generation failed" >&2; exit 1; }

# Fabricate a stale/divergent "old home".
mkdir -p "${HOME_DIR}/ROMs/tools" "${HOME_DIR}/ES-DE/custom_systems" \
         "${HOME_DIR}/.config/retroarch" "${HOME_DIR}/ES-DE/settings" \
         "${HOME_DIR}/ROMs/nes"
# managed — must be force-overwritten:
printf 'STALE bash_profile - must be replaced\n'                 > "${HOME_DIR}/.bash_profile"
printf '#!/bin/bash\necho STALE shell launcher\n'                > "${HOME_DIR}/ROMs/tools/Shell.sh"
printf '<stale-systems/>\n'                                      > "${HOME_DIR}/ES-DE/custom_systems/es_systems.xml"
printf 'joypad_autoconfig_dir = "/wrong/old/path"\nvideo_fullscreen = "true"\n' \
                                                                 > "${HOME_DIR}/.config/retroarch/retroarch.cfg"
# user-reachable — must NEVER be touched:
MARK="USER_EDIT_MARKER_$$_keepme"
printf '<settings><edit>%s</edit></settings>\n' "${MARK}"        > "${HOME_DIR}/ES-DE/settings/es_settings.xml"
printf 'rom-bytes-%s\n' "${MARK}"                               > "${HOME_DIR}/ROMs/nes/MyGame.nes"
printf 'savestate-bytes-%s\n' "${MARK}"                         > "${HOME_DIR}/ROMs/nes/MyGame.state"
chown -R retro:retro "${HOME_DIR}"

# --- run #1 ----------------------------------------------------------------
echo ":: run #1 — reconcile a divergent home"
bash "${SEED}" || bad "seed exited non-zero on run #1"

cmp -s "${SKEL}/.bash_profile" "${HOME_DIR}/.bash_profile" \
    && ok ".bash_profile force-overwritten" || bad ".bash_profile not reconciled"
cmp -s "${SKEL}/ES-DE/custom_systems/es_systems.xml" "${HOME_DIR}/ES-DE/custom_systems/es_systems.xml" \
    && ok "es_systems.xml force-overwritten" || bad "es_systems.xml not reconciled"
cmp -s "${SKEL}/ROMs/tools/Shell.sh" "${HOME_DIR}/ROMs/tools/Shell.sh" \
    && ok "Shell.sh launcher force-overwritten" || bad "Shell.sh not reconciled"
meta=$(stat -c '%U:%G %a' "${HOME_DIR}/ROMs/tools/Shell.sh")
[[ ${meta} == "root:root 755" ]] && ok "Shell.sh is root:root 0755" || bad "Shell.sh meta='${meta}' (want 'root:root 755')"
grep -qx 'joypad_autoconfig_dir = "/usr/share/libretro/autoconfig"' "${HOME_DIR}/.config/retroarch/retroarch.cfg" \
    && ok "joypad_autoconfig_dir key forced" || bad "joypad_autoconfig_dir not forced"
grep -qx 'video_fullscreen = "true"' "${HOME_DIR}/.config/retroarch/retroarch.cfg" \
    && ok "unmanaged retroarch key preserved" || bad "unmanaged retroarch key lost"

grep -q "${MARK}" "${HOME_DIR}/ES-DE/settings/es_settings.xml" \
    && ok "es_settings.xml user edit survived" || bad "es_settings.xml was clobbered"
grep -q "${MARK}" "${HOME_DIR}/ROMs/nes/MyGame.nes" \
    && ok "user ROM untouched" || bad "user ROM changed"
grep -q "${MARK}" "${HOME_DIR}/ROMs/nes/MyGame.state" \
    && ok "savestate untouched" || bad "savestate changed"

# --- idempotency: run #2 leaves content/mode/owner identical ----------------
# (mtime is deliberately excluded — install(1) always rewrites it.)
manifest() {
    find "${HOME_DIR}" -exec stat -c '%n %a %U:%G %s' {} \; | sort
    ( cd "${HOME_DIR}" && find . -type f -exec sha256sum {} \; | sort )
}
before=$(manifest)
echo ":: run #2 — idempotency"
bash "${SEED}" || bad "seed exited non-zero on run #2"
after=$(manifest)
if [[ ${before} == "${after}" ]]; then
    ok "second run idempotent (content/mode/owner unchanged)"
else
    bad "second run changed the home:"
    diff <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") | head >&2
fi

# --- live guard -------------------------------------------------------------
echo ":: live-guard — must make no changes"
printf 'CORRUPT managed file\n' > "${HOME_DIR}/.bash_profile"
touch /etc/retroconsole-live
bash "${SEED}"; rc=$?
rm -f /etc/retroconsole-live
[[ ${rc} -eq 0 ]] && ok "live-guard exits 0" || bad "live-guard exit=${rc} (want 0)"
grep -qx 'CORRUPT managed file' "${HOME_DIR}/.bash_profile" \
    && ok "live-guard made NO changes" || bad "live-guard modified the home"

# --- result -----------------------------------------------------------------
if [[ ${fail} -eq 0 ]]; then
    echo ":: seed/reconcile policy OK"
else
    echo ":: seed/reconcile policy FAILED" >&2
    echo "--- /var/log/retroconsole-seed.log ---" >&2
    cat /var/log/retroconsole-seed.log >&2 2>/dev/null || true
fi
exit "${fail}"
