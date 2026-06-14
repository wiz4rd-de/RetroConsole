#!/usr/bin/env bash
# Drop to a shell: a fullscreen foot terminal running bash inside the kiosk
# session. cage owns the display and blocks VT switching (Ctrl+Alt+F2 does
# nothing), so this Tools entry is the sanctioned way past the VT-lock for
# field debugging. ES-DE is suspended while this runs and resumes when foot exits.
exec foot --fullscreen bash
