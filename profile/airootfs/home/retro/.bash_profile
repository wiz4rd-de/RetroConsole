if [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" && "$(tty)" == /dev/tty1 ]]; then
    # "retroconsole.session" on the kernel command line forces the kiosk
    # session even on live media (the "Live session" ISO boot entries).
    if [[ -e /etc/retroconsole-live ]] \
            && ! grep -qw 'retroconsole.session' /proc/cmdline; then
        exec sudo /usr/local/bin/retroconsole-install
    else
        exec /usr/local/bin/retroconsole-session
    fi
fi
