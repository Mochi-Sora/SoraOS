#!/usr/bin/env bash
# Regenerate the committed PNG branding assets from their SVG sources.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v rsvg-convert >/dev/null 2>&1 || {
    echo "error: rsvg-convert not found; install librsvg" >&2
    exit 1
}

wall_dir="iso/airootfs/usr/share/wallpapers/SoraOS/contents/images"
icon_dir="iso/airootfs/usr/share/icons/hicolor/scalable/apps"
pixmap_dir="iso/airootfs/usr/share/pixmaps"

install -d "$wall_dir" "$icon_dir" "$pixmap_dir" iso/syslinux
install -Dm644 branding/sora-mark.svg "$icon_dir/soraos.svg"
install -Dm644 branding/sora-mark.svg "$pixmap_dir/soraos.svg"

rsvg-convert -w 3840 -h 2160 branding/wallpaper.svg -o "$wall_dir/3840x2160.png"
rsvg-convert -w 1920 -h 1080 branding/wallpaper.svg -o "$wall_dir/1920x1080.png"
rsvg-convert -w 640  -h 480  branding/splash.svg    -o iso/syslinux/splash.png
rsvg-convert -w 256  -h 256  branding/sora-mark.svg -o iso/airootfs/etc/skel/.face.icon

echo "Regenerated:"
find "$wall_dir" iso/syslinux/splash.png iso/airootfs/etc/skel/.face.icon -type f -printf '  %p\n'
