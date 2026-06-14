#!/usr/bin/env bash
# Fast-tier shell lint: `shellcheck` + `bash -n` over every shell script in the
# repo. Run by CI (ci.yml fast tier, gate feat/* -> develop) and runnable
# locally:  scripts/lint-shell.sh
#
# Detection is by content/name, NOT a hardcoded list, so a newly added script
# cannot silently dodge the sweep. The tricky cases this must (and does) cover:
#   * extensionless `#!/usr/bin/env bash` tools — retroconsole-{seed,update,session}
#     (matched by the shebang scan)
#   * pacman scriptlet `*.install` and the sourced `.bash_profile` — NO shebang
#     (matched by explicit name rules)
#   * space-named ROMs/tools/*.sh launchers — "Restart ES-DE.sh" etc.
#     (matched by the .sh rule; NUL-safe iteration handles the spaces)
#
# Severity floor: shellcheck -S error by default. The existing scripts are clean
# at every level except a few style/info/warning notes (an unused loop var, a
# false-positive SC2054 on QEMU's comma-separated -device args, two ls-vs-find
# infos) — none worth silencing the installer/qemu scripts for right now. error
# still catches the class that matters most here (syntax/parse breakage), and
# `bash -n` is a second, independent parse check. Tightening to `warning` is a
# deliberate follow-up (mirrors M12's own staged-strictness rollout); override
# without editing this file via:  SHELLCHECK_SEVERITY=warning scripts/lint-shell.sh
set -uo pipefail

cd "$(dirname "$0")/.."

SEVERITY="${SHELLCHECK_SEVERITY:-error}"

# Does this tracked file want shell linting?
is_shell() {
    local f=$1 first base
    [[ -f $f ]] || return 1                      # skip dangling symlinks (systemd .wants/)
    case "$f" in
        *.sh | *.install) return 0 ;;
    esac
    base=${f##*/}
    case "$base" in
        .bash_profile | .bashrc | .profile) return 0 ;;
    esac
    IFS= read -r first < "$f" 2>/dev/null || return 1
    [[ $first =~ ^#!.*[/[:space:]](bash|sh)([[:space:]]|$) ]]
}

# Collect the file set, NUL-safe (filenames contain spaces).
FILES=()
while IFS= read -r -d '' f; do
    is_shell "$f" && FILES+=("$f")
done < <(git ls-files -z)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "lint-shell: no shell scripts found — refusing to pass vacuously" >&2
    exit 1
fi

echo ":: linting ${#FILES[@]} shell script(s) (shellcheck -S ${SEVERITY} + bash -n)"
printf '   %s\n' "${FILES[@]}"

rc=0

# bash -n: independent syntax/parse check (also covers the sourced .install /
# .bash_profile, which are valid bash even without a shebang).
for f in "${FILES[@]}"; do
    if ! bash -n "$f"; then
        echo "FAIL (bash -n): $f" >&2
        rc=1
    fi
done

# Pass --shell=bash so the shebang-less files (.install, .bash_profile,
# profiledef.sh) are checked as bash instead of being skipped / defaulting to sh.
if ! shellcheck --shell=bash --severity="${SEVERITY}" "${FILES[@]}"; then
    rc=1
fi

if [[ $rc -eq 0 ]]; then
    echo ":: shell lint passed"
fi
exit "$rc"
