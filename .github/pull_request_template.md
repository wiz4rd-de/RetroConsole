## Summary

<!-- What this change does and why. -->

## Issues

Refs #

<!--
Issue AUTO-CLOSE fires ONLY when a PR carrying a closing keyword (Closes /
Fixes / Resolves #NN) merges into the DEFAULT branch (main). In the
feat -> develop -> rc -> main flow that means:

  * feat -> develop  and  develop -> rc   — base is NOT main, so closing
    keywords do nothing. Use "Refs #NN" above to link the issue without
    closing it (it stays open until the release).

  * rc -> main  (the release PR)          — base IS main: replace "Refs"
    with "Closes #NN" for EVERY issue shipping in the release, so they all
    auto-close on merge. This is the ONLY PR whose keywords close issues.
    Before merging it, also finalize the CHANGELOG ([Unreleased] -> [vX.Y.Z])
    on rc — it cannot be added to main afterward (main is rc/hotfix-only).
-->
