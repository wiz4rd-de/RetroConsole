if [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" && "$(tty)" == /dev/tty1 ]]; then
    if [[ -e /etc/retroconsole-live ]]; then
        exec sudo /usr/local/bin/retroconsole-install
    else
        exec /usr/local/bin/retroconsole-session
    fi
fi
