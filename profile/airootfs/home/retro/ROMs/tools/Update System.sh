#!/usr/bin/env bash
# System update: pacman -Syu in a fullscreen terminal inside the kiosk session,
# so progress is visible. ES-DE is suspended while this runs; the update script
# waits for a keypress at the end, then ES-DE resumes when foot exits.
exec foot --fullscreen /usr/local/bin/retroconsole-update
