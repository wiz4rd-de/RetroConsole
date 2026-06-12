IMAGE := retroconsole-builder

.PHONY: iso builder test-bios test-uefi test-installed-bios test-installed-uefi clean aur-clean

iso: builder
	docker run --rm --privileged --platform linux/amd64 \
		-v "$(CURDIR)":/build \
		-v retroconsole-pkgcache:/var/cache/pacman/pkg \
		$(IMAGE) /build/scripts/build-iso.sh

builder:
	docker build --platform linux/amd64 -t $(IMAGE) docker

test-bios:
	scripts/test-qemu.sh --bios --fresh-disk

test-uefi:
	scripts/test-qemu.sh --uefi --fresh-disk

# Boot the disk an installer test wrote to, without the ISO attached
test-installed-bios:
	scripts/test-qemu.sh --bios --boot-disk

test-installed-uefi:
	scripts/test-qemu.sh --uefi --boot-disk

clean:
	rm -rf out

aur-clean:
	rm -f profile/airootfs/opt/retroconsole/repo/*.pkg.tar.zst \
	      profile/airootfs/opt/retroconsole/repo/retroconsole.db* \
	      profile/airootfs/opt/retroconsole/repo/retroconsole.files*
