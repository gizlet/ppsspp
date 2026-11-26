"""Writes NOTICE.md for the package: what it contains, under which licenses,
and where the corresponding source is.
Usage: notice.py PROJECT RUNTIME SOURCES_LIST VERSION UPSTREAM TARBALL SHA256 OUTPUT"""

from pathlib import Path
import re
import sys

project, runtime, sources_list, version, upstream, tarball, sha256, output = sys.argv[1:]
runtime = Path(runtime)
sources = [line.strip() for line in Path(sources_list).read_text().splitlines() if line.strip()]
snapshot = re.search(r"^snapshot=(\S+)$", Path(project, "scripts/package.sh").read_text(), re.M).group(1)
release = f"https://github.com/gizlet/ppsspp/releases/tag/v{version}"


def licenses(package: str) -> str:
    copyright = runtime / "usr/share/doc" / package / "copyright"
    if not copyright.is_file():
        return ""
    found = []
    for match in re.finditer(r"^License:\s*(\S.*)$", copyright.read_text(errors="replace"), re.M):
        name = match.group(1).strip()
        if name not in found:
            found.append(name)
    return ", ".join(found[:6])


installed = sorted(p.name for p in (runtime / "usr/share/doc").iterdir() if p.is_dir() and p.name != "ppsspp")
lines = [
    f"# PPSSPP {version} for Gizlet: notices",
    "",
    f"This package contains PPSSPP {upstream}, built from the unmodified upstream release",
    f"`{tarball}` (SHA-256 `{sha256}`) with the configuration in `scripts/package.sh` of",
    "https://github.com/gizlet/ppsspp, and a runtime of unmodified Debian packages from",
    f"https://snapshot.debian.org/archive/debian/{snapshot}/.",
    "It contains no games, BIOS or firmware files, and no game artwork. The fonts under",
    "`assets/flash0/font` are PPSSPP's free replacements for the PSP's system fonts, which came",
    "from the JPCSP project's open-source replacement fonts and ship in every PPSSPP release;",
    "they are not the PSP's own. Users who want the originals copy them from their own PSP, as",
    "https://www.ppsspp.org/docs/getting-started/using-original-fonts/ describes.",
    "",
    "PPSSPP is free software under the GNU General Public License, version 2 or later",
    "(`licenses/PPSSPP-GPL-2.0.txt`). The libraries it bundles keep their own licenses, listed",
    "in its source. Among them, FFmpeg (LGPL 2.1 or later, `licenses/FFmpeg-LGPL-2.1.txt`) is",
    "built from the tarball's `ffmpeg/` source with its `linux_arm64.sh` and linked statically.",
    "The full copyright and",
    "license text of every Debian package is in `runtime.sqfs` under `/usr/share/doc/<package>/copyright`.",
    "",
    "## Corresponding source",
    "",
    f"The complete corresponding source is attached to the release this package comes from, {release},",
    f"as `io.gizlet.ppsspp-{version}-source.tar`: PPSSPP's upstream source tarball, every Debian",
    "source package listed below, exactly as installed, and this package's build scripts.",
    "The same Debian sources stay available from the snapshot above, and PPSSPP's from",
    f"https://github.com/hrydgard/ppsspp/releases/tag/v{upstream}.",
    "",
    "| Source package | Version |",
    "| --- | --- |",
    f"| ppsspp (upstream) | {upstream} |",
]
for entry in sources:
    name, _, ver = entry.partition("=")
    lines.append(f"| {name} | {ver} |")
lines += ["", "## Installed Debian packages and their licenses", "", "| Package | Licenses (from its copyright file) |", "| --- | --- |"]
for package in installed:
    lines.append(f"| {package} | {licenses(package) or 'see its copyright file'} |")
Path(output).write_text("\n".join(lines) + "\n", encoding="utf-8")
