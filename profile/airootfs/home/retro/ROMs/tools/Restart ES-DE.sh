#!/usr/bin/env bash
# Restarting the tty1 getty tears down the session; autologin relaunches ES-DE,
# which rescans the ROM directory on startup.
exec sudo /usr/bin/systemctl restart getty@tty1
