# RetroConsole ISO build container.
# Must run as linux/amd64 (under Rosetta on Apple Silicon) and --privileged,
# because mkarchiso needs chroot/mount capabilities.
FROM --platform=linux/amd64 archlinux:latest

# pacman's download sandbox (seccomp) does not work under Rosetta emulation
RUN sed -i 's/^#\?DisableSandbox.*/DisableSandbox/' /etc/pacman.conf \
    && grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

RUN pacman-key --init \
    && pacman -Sy --noconfirm archlinux-keyring \
    && pacman -Su --noconfirm \
    && pacman -S --noconfirm --needed archiso base-devel git sudo \
    && pacman -Scc --noconfirm

# Unprivileged user for makepkg (it refuses to run as root); needs sudo to
# install build dependencies.
RUN useradd -m builder \
    && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

WORKDIR /build
