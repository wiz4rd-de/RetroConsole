#!/usr/bin/env bash
# Apply the desired classic branch-protection state for `main` from the IaC
# artifact .github/branch-protection/main.json (strips _comment keys first).
#
# Requires: gh (authenticated), python3. Idempotent — re-running re-asserts state.
#
# Sequencing: `release-source-guard` must have produced at least one check run
# on a PR into main before it can be marked required without wedging PRs. The
# workflow reaches `main`'s incoming PRs once .github/workflows/release-guard.yml
# is present on `rc` (it flows develop -> rc -> main like any change). Apply this
# after the guard has run once on a real rc -> main PR, OR accept that the first
# rc -> main PR will wait for the guard's first run (fine — it runs in seconds).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=.github/branch-protection/main.json
[[ -f ${CONFIG} ]] || { echo "missing ${CONFIG}" >&2; exit 1; }

# Drop documentation-only _comment keys before sending to the API.
BODY=$(python3 -c "import json,sys; d=json.load(open('${CONFIG}')); d.pop('_comment',None); json.dump(d,sys.stdout,indent=2)")

echo "Applying branch protection to main:"
echo "${BODY}"

echo "${BODY}" | gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  repos/:owner/:repo/branches/main/protection \
  --input -

echo "Done. Current required checks on main:"
gh api repos/:owner/:repo/branches/main/protection/required_status_checks \
  --jq '.contexts' 2>/dev/null || echo "(none / not protected)"
