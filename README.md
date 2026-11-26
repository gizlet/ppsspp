# PPSSPP for Gizlet

PPSSPP 1.20.4, built from its upstream source and packaged as a Gizlet app for the R36S. Emulation Center ([gizlet/emulation-center](https://github.com/gizlet/emulation-center)) installs, updates and opens it, and it also runs on its own from the launcher. The package contains no games, BIOS files or game artwork; players open games they already have in PPSSPP's own game browser.

## What is in the package

| Part | Source |
| --- | --- |
| `/usr/lib/ppsspp/PPSSPPSDL` and `assets/` in `runtime.sqfs` | The upstream release tarball `ppsspp-1.20.4.tar.xz`, checked by SHA-256 and built in [`scripts/package.sh`](scripts/package.sh) with SDL2 on KMS/DRM and OpenGL ES. Discord, UPnP, X11 and Wayland are off. `assets/flash0/font` holds PPSSPP's free replacements for the PSP's system fonts, from the JPCSP project's open-source fonts, as in every PPSSPP release; they are not the PSP's own, and users can [use their PSP's original fonts](https://www.ppsspp.org/docs/getting-started/using-original-fonts/) instead. |
| FFmpeg | PPSSPP's bundled FFmpeg, built from the tarball's `ffmpeg/` with upstream's `linux_arm64.sh`, which enables only the decoders PSP games use, and linked statically |
| Runtime | SDL2, SDL2_ttf, fontconfig with Droid Sans Fallback, Mesa, ALSA, udev and the other libraries PPSSPP needs, unmodified from Debian's snapshot `20261124T000000Z` (forky) |
| `bin/launch`, `bin/launch.sh`, `bin/session`, `bin/find-games` | The entry ([`app/`](app)): a static launcher, because the Gizlet Store requires an ELF entry, and the scripts it runs |
| Configuration | [`config/`](config): first-launch `ppsspp.ini`, the helper that sets keys in it, and `start`, which prepares the memory stick and starts PPSSPP |

## How it runs

`gizlet run io.gizlet.ppsspp [--games DIR]` runs `bin/launch.sh` as root. It mounts `runtime.sqfs` as the root of a private mount and PID namespace, makes the display, controls, sound, `/home`, `/media`, `/mnt` and the app's save folder (as `/save`) visible, and starts PPSSPP as `nobody` with the device groups it needs, on SDL's `kmsdrm` video and `alsa` audio. Mounts propagate into the namespace, so a TF2 card inserted while PPSSPP runs appears in it.

PPSSPP's memory stick is `/save/config/ppsspp`, in the save folder `/opt/gizlet/saves/io.gizlet.ppsspp`. Root only hands that folder to `nobody`. After privileges are dropped, [`config/start`](config/start) creates `ppsspp.ini` on the first launch and sets `CurrentDirectory` to `DIR`, which Emulation Center passes and the launch script resolves. Without it, the game browser starts in the TF2 card where it is mounted ([`app/find-games`](app/find-games)), else in `/home`. A folder outside `/home`, `/media` and `/mnt` is shown at `/run/games`. `start` also turns off PPSSPP's own update check and sets its language from the launcher's. The user's folders are bound read-only, and the host's resolver configuration is bound in for PPSSPP's ad hoc servers.

Stopping the app (holding FN, or Select and Start) sends SIGTERM to PPSSPP. `unshare` ignores it while waiting, so the launch script forwards it to the session, and kills `unshare`, which kills the session, if PPSSPP is still running three seconds later.

SDL maps the R36S's controls as a standard gamepad. In PPSSPP's default bindings, A is Circle and B is Cross, and L2 or a short press of FN opens the menu. Holding FN, or Select and Start for two seconds, is Gizlet OS's way back to the launcher.

## Build and test

On ARM64 Linux, install `mmdebstrap`, `squashfs-tools`, `debian-archive-keyring`, `qemu-user-static` and Python 3.11 or newer, then run `sudo ./scripts/package.sh`. It writes `dist/io.gizlet.ppsspp-<version>-aarch64-unknown-linux-gnu-lite.gzl` and, under `dist/sources/`, the notices and the corresponding source archive. `GIZLET_DIST` chooses another output folder.

The smoke test ([`tests/smoke.sh`](tests/smoke.sh)) checks that PPSSPP's libraries resolve in the runtime and that its assets and replacement fonts are there. It also runs the headless build on upstream's CPU tests (`pspautotests`: ALU, FPU and load/store, test programs that ship with PPSSPP's source), with the JIT and the IR interpreter, comparing their output with the expected output. They run under QEMU as a Cortex-A35, the R36S's CPU, so the JIT is tested on that instruction set.

Display, sound and the physical controls need an R36S to verify.

## Release

Change `version` in [`gizlet.toml`](gizlet.toml) and merge to `main`. The version is PPSSPP's plus a package revision (`1.20.4.1`). CI builds and tests on GitHub's ARM64 runner, publishes the GitHub Release and the Gizlet Store listing, then attaches `NOTICE.md` and the corresponding source archive to the release.

## Licenses and corresponding source

PPSSPP is under the GNU GPL, version 2 or later, and its bundled FFmpeg under the GNU LGPL, version 2.1 or later. Each Debian library keeps its own license, with its copyright file in `runtime.sqfs` under `/usr/share/doc`. The package's `NOTICE.md` lists every Debian source package and version. Each release attaches `io.gizlet.ppsspp-<version>-source.tar`, with the upstream tarball, those Debian source packages and this repository's scripts. The packaging scripts in this repository are under the MIT License. The Store icon is PPSSPP's own (`icons/hicolor/512x512/apps`, GPL-2.0-or-later).
