#!/usr/bin/env bash
# Network / Wi-Fi setup: nmtui in a fullscreen terminal inside the kiosk
# session. ES-DE is suspended while this runs and resumes when nmtui exits.
exec foot --fullscreen nmtui
