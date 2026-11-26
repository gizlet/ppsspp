#!/bin/sh
# Builds PPSSPP from its upstream release source in a Debian build root,
# assembles its runtime from the same Debian snapshot, runs upstream's CPU
# tests headlessly and writes the .gzl and its corresponding source under
# dist/ (or $GIZLET_DIST).
set -eu

project=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dist=${GIZLET_DIST:-$project/dist}
if [ "$(id -u)" -ne 0 ] || [ "$(uname -m)" != aarch64 ]; then
    echo 'Build on ARM64 Linux as root.' >&2
    exit 1
fi
build_dir=$(mktemp -d)
cleanup() {
    for root in "$build_dir/build" "$build_dir/runtime"; do
        umount -R "$root/dev" 2>/dev/null || true
        umount "$root/proc" 2>/dev/null || true
    done
    rm -rf --one-file-system "$build_dir"
}
trap cleanup EXIT

snapshot=20261124T000000Z
mirror=https://snapshot.debian.org/archive/debian/$snapshot/
suite=forky
upstream=1.20.4
tarball=ppsspp-$upstream.tar.xz
tarball_url=https://github.com/hrydgard/ppsspp/releases/download/v$upstream/$tarball
tarball_sha256=4de21db3105d9d81a465a8a7e78c68ee3c0e0bf6597d1c1d530f7555f3ad8b31
build_packages="ca-certificates,build-essential,cmake,pkgconf,python3,libsdl2-dev,libsdl2-ttf-dev,libfontconfig-dev,libgles-dev,libegl-dev,libgbm-dev,libdrm-dev,zlib1g-dev,libpng-dev,libzstd-dev"
# Loaded at run time rather than linked: SDL's KMS/DRM video, ALSA sound and
# udev controllers, Mesa's drivers, fontconfig's fonts and the launch tools.
runtime_extra="libasound2t64,libasound2-data,libudev1,libdrm2,libgbm1,libegl1,libegl-mesa0,libgles2,libgl1-mesa-dri,mesa-libgallium,fontconfig,fonts-droid-fallback,mount,util-linux"

# snapshot.debian.org is slow and drops connections: retry, and give up on a
# stalled one instead of waiting forever.
apt_options='-o Acquire::Check-Valid-Until=false -o Acquire::Retries=8 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60'

# Debian's archive key, on the build host and then in each chroot. Ubuntu does
# not trust it by default, so the sources name it.
keyring=/usr/share/keyrings/debian-archive-keyring.gpg

bootstrap() {
    mmdebstrap --mode=root --variant=minbase --architectures=arm64 \
        --aptopt='Acquire::Check-Valid-Until "false"' \
        --aptopt='Acquire::Retries "8"' \
        --aptopt='Acquire::http::Timeout "60"' \
        --aptopt='Acquire::https::Timeout "60"' \
        --aptopt='APT::Install-Recommends "false"' \
        --include="$1" --format=directory "$suite" "$2" \
        "deb [signed-by=$keyring] $mirror $suite main" "deb-src [signed-by=$keyring] $mirror $suite main"
}

# in_chroot DIR SCRIPT: runs SCRIPT in DIR with the host's /dev and a /proc,
# which apt's TLS and the build tools need.
in_chroot() {
    find "$1/dev" -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system {} +
    mount --rbind /dev "$1/dev"
    mount --make-rslave "$1/dev"
    mount -t proc proc "$1/proc"
    status=0
    chroot "$1" /bin/sh -ec "$2" || status=$?
    umount -R "$1/dev"
    umount "$1/proc"
    return "$status"
}

curl -fsSL --retry 5 -o "$build_dir/$tarball" "$tarball_url"
echo "$tarball_sha256  $build_dir/$tarball" | sha256sum -c --quiet

# PPSSPP with SDL2 on KMS/DRM and OpenGL ES and no Discord, UPnP, X11 or
# Wayland. FFmpeg is the one PPSSPP bundles for video and audio playback, as
# its own Linux builds use: built here from the tarball's ffmpeg/ source with
# upstream's own linux_arm64.sh, which enables only the decoders PSP games use.
bootstrap "$build_packages" "$build_dir/build"
cp "$build_dir/$tarball" "$project/app/launch.c" "$build_dir/build/root/"
in_chroot "$build_dir/build" "
    cd /root
    tar -xf $tarball
    cc -Wall -Wextra -Werror -std=c17 -O2 -static -s launch.c -o launch
    (cd ppsspp-$upstream/ffmpeg && bash linux_arm64.sh >/root/ffmpeg.log 2>&1) ||
        { tail -40 /root/ffmpeg.log; exit 1; }
    cmake -S ppsspp-$upstream -B build -DCMAKE_BUILD_TYPE=Release \
        -DUSING_GLES2=ON -DUSING_EGL=OFF -DUSING_X11_VULKAN=OFF -DUSE_WAYLAND_WSI=OFF \
        -DUSE_VULKAN_DISPLAY_KHR=OFF -DUSE_DISCORD=OFF -DUSE_MINIUPNPC=OFF \
        -DUSE_SYSTEM_FFMPEG=OFF -DUSE_SYSTEM_LIBSDL2=ON -DUSE_SYSTEM_ZSTD=ON -DUSE_SYSTEM_LIBPNG=ON \
        -DHEADLESS=ON -DUNITTEST=OFF -DATLAS_TOOL=OFF -DUSE_CCACHE=OFF -DGOLD=OFF >/root/cmake.log 2>&1 ||
        { tail -60 /root/cmake.log; exit 1; }
    cmake --build build -j\$(nproc) --target PPSSPPSDL PPSSPPHeadless >/root/build.log 2>&1 ||
        { grep -B5 -A20 -m3 'error' /root/build.log | head -120; exit 1; }
    strip build/PPSSPPSDL build/PPSSPPHeadless
    for binary in build/PPSSPPSDL build/PPSSPPHeadless; do
        ldd \$binary | awk '/=>/ { print \$3 }' | xargs -r readlink -f
    done | sort -u | xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | sort -u > /root/linked.txt
"
linked=$(tr '\n' ',' < "$build_dir/build/root/linked.txt" | sed 's/,$//')

runtime=$build_dir/runtime
bootstrap "$linked,$runtime_extra" "$runtime"
mkdir -p "$runtime/usr/lib/ppsspp" "$runtime/usr/share/gizlet-ppsspp" "$runtime/usr/share/doc/ppsspp"
src=$build_dir/build/root/ppsspp-$upstream
install -m 0755 "$build_dir/build/root/build/PPSSPPSDL" "$runtime/usr/lib/ppsspp/PPSSPPSDL"
cp -R "$src/assets" "$runtime/usr/lib/ppsspp/assets"
# The PSP font files in flash0 come without license terms; PPSSPP draws
# its own text without them, and users can add their own.
rm -f "$runtime/usr/lib/ppsspp/assets/flash0/font/"*.pgf
install -m 0644 "$src/LICENSE.TXT" "$runtime/usr/share/doc/ppsspp/LICENSE.TXT"
install -m 0644 "$src/README.md" "$runtime/usr/share/doc/ppsspp/README.md"
install -m 0644 "$project/config/ppsspp.ini" "$runtime/usr/share/gizlet-ppsspp/ppsspp.ini"
install -m 0755 "$project/config/set-ini" "$runtime/usr/share/gizlet-ppsspp/set-ini"
mkdir -p "$runtime/save" "$runtime/media" "$runtime/mnt" "$runtime/home" \
    "$runtime/proc" "$runtime/sys" "$runtime/run" "$runtime/dev" "$runtime/tmp"
touch "$runtime/etc/asound.conf"

# Smoke tests in the runtime: PPSSPP starts, and the headless build passes
# upstream's CPU tests from pspautotests, test programs that ship with
# PPSSPP's source.
install -m 0755 "$build_dir/build/root/build/PPSSPPHeadless" "$runtime/tmp/PPSSPPHeadless"
install -m 0755 "$(readlink -f "$(command -v qemu-aarch64-static || command -v qemu-aarch64)")" "$runtime/tmp/qemu-aarch64"
mkdir -p "$runtime/tmp/tests"
cp -R "$src/pspautotests/tests/cpu" "$runtime/tmp/tests/"
install -m 0755 "$project/tests/smoke.sh" "$runtime/tmp/smoke.sh"
in_chroot "$runtime" "/bin/sh /tmp/smoke.sh /tmp/tests"
rm -rf "$runtime/tmp/"* "$runtime/tmp/".[!.]* 2>/dev/null || true

# Corresponding source: PPSSPP's upstream tarball, every Debian source
# package in the runtime, and this package's scripts.
chroot "$runtime" dpkg-query -W -f '${source:Package}=${source:Version}\n' | sort -u > "$build_dir/sources.list"
mkdir -p "$build_dir/build/root/sources"
cp "$build_dir/sources.list" "$build_dir/build/root/sources.list"
in_chroot "$build_dir/build" "
    apt-get $apt_options update -qq
    cd /root/sources
    xargs apt-get $apt_options source -qq --download-only < /root/sources.list >/dev/null
"

rm -f "$runtime/etc/resolv.conf"
rm -rf "$runtime/var/lib/apt/lists/"* "$runtime/var/cache/apt/"* "$runtime/var/log/"*
find "$runtime/dev" -mindepth 1 -delete

app=$build_dir/app
mkdir -p "$app/bin" "$app/licenses" "$dist/sources"
install -m 0755 "$build_dir/build/root/launch" "$app/bin/launch"
install -m 0755 "$project/app/launch.sh" "$app/bin/launch.sh"
install -m 0755 "$project/app/session" "$app/bin/session"
install -m 0755 "$project/app/find-games" "$app/bin/find-games"
python3 "$project/scripts/manifest.py" "$project/gizlet.toml" "$app/manifest.json"
version=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$app/manifest.json")
python3 "$project/scripts/notice.py" "$project" "$runtime" "$build_dir/sources.list" "$version" "$upstream" "$tarball" "$tarball_sha256" "$app/NOTICE.md"
install -m 0644 "$project/LICENSE" "$app/licenses/gizlet-ppsspp-packaging-MIT.txt"
install -m 0644 "$src/LICENSE.TXT" "$app/licenses/PPSSPP-GPL-2.0.txt"
install -m 0644 "$src/ffmpeg/COPYING.LGPLv2.1" "$app/licenses/FFmpeg-LGPL-2.1.txt"
cp "$app/NOTICE.md" "$dist/sources/io.gizlet.ppsspp-$version-NOTICE.md"
mksquashfs "$runtime" "$app/runtime.sqfs" -comp zstd -noappend -no-progress -quiet
python3 "$project/scripts/pack.py" "$app" "$dist"

mkdir "$build_dir/build/root/packaging"
tar -C "$project" --exclude=./dist --exclude=./.git -cf - . | tar -C "$build_dir/build/root/packaging" -xf -
cp "$build_dir/$tarball" "$build_dir/build/root/sources/"
tar --format=ustar -cf "$dist/sources/io.gizlet.ppsspp-$version-source.tar" \
    -C "$build_dir/build/root" sources.list sources packaging
ls -l "$dist" "$dist/sources"
