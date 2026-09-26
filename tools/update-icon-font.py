#!/usr/bin/env python3
"""Downloads the icon font and writes the icon list Visual Player uses.

Visual Player draws its icons with Tabler Icons (MIT licensed). This script:

  1. downloads a Tabler Icons release from npm,
  2. finds the character code of each icon listed in NEEDED_ICONS,
  3. saves the font into fonts/ and its license into licenses/, and
  4. measures where each icon's visible shape sits, so it can be centered
     exactly, and
  5. writes scripts/visual-player/icons.lua, which the Lua code reads.

This needs Python's fontTools (python3-fonttools). It's used to trim the
font down to only the icons Visual Player uses, shrinking it from
megabytes to kilobytes, and to measure each icon.

Run it again after adding a name to NEEDED_ICONS.

Usage:
    ./tools/update-icon-font.py            use the latest Tabler Icons
    ./tools/update-icon-font.py 3.30.0     use a specific version
"""

import io
import json
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

# Every icon the interface uses. Names come from https://tabler.io/icons
NEEDED_ICONS = [
    # Playback row
    "player-play",
    "player-pause",
    "player-skip-back",
    "player-skip-forward",
    "repeat",
    "repeat-once",
    "gauge",
    # Tools row
    "badge-cc",
    "list",
    "info-circle",
    "rotate-clockwise",
    "settings",
    "volume",
    "volume-2",
    "volume-3",
    # Output popup
    "device-tv",
    "device-desktop",
    "device-laptop",
    "bluetooth",
    "usb",
    "check",
    # Info panel
    "movie",
    # Window buttons (GNOME only)
    "minus",
    "square",
    "x",
    # General
    "chevron-down",
    "chevron-up",
    "eye",
    "eye-off",
    "folder-open",
]

REPO_FOLDER = Path(__file__).resolve().parent.parent
FONT_FOLDER = REPO_FOLDER / "fonts"
FONT_FILE = FONT_FOLDER / "tabler-icons.ttf"
# Licenses live outside fonts/, because mpv tries to load every file in
# the fonts folder as a font.
LICENSE_FOLDER = REPO_FOLDER / "licenses"
LICENSE_FILE = LICENSE_FOLDER / "tabler-icons.txt"
ICON_LIST_FILE = REPO_FOLDER / "scripts" / "visual-player" / "icons.lua"

PACKAGE_URL = "https://registry.npmjs.org/@tabler/icons-webfont/{version}"

# Newer releases ship separate outline and filled fonts; older ones ship
# a single font. We want the outline style, so try that first.
FONT_VARIANTS = ["tabler-icons-outline", "tabler-icons"]


def download(url):
    with urllib.request.urlopen(url) as response:
        return response.read()


def download_release(version):
    """Returns the exact version downloaded and the release archive."""
    package_info = json.loads(download(PACKAGE_URL.format(version=version)))
    exact_version = package_info["version"]
    print(f"Downloading Tabler Icons {exact_version}...")

    archive_bytes = download(package_info["dist"]["tarball"])
    archive = tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz")
    return exact_version, archive


def read_file_from_archive(archive, file_name):
    """Returns the contents of the file with this name, wherever it is in
    the archive, or None if there isn't one."""
    for member_name in archive.getnames():
        if member_name.endswith("/" + file_name):
            return archive.extractfile(member_name).read()
    return None


def find_font_and_css(archive):
    """Returns the font and its matching stylesheet, which lists the
    character code of every icon."""
    for variant in FONT_VARIANTS:
        font = read_file_from_archive(archive, variant + ".ttf")
        css = read_file_from_archive(archive, variant + ".css")
        if css is None:
            css = read_file_from_archive(archive, variant + ".min.css")

        if font is not None and css is not None:
            return font, css.decode("utf-8")

    sys.exit("Couldn't find the font in this Tabler Icons release.")


def find_character_codes(css):
    """Reads lines like .ti-player-play:before { content: "\\ed46"; }
    and returns a dictionary of icon names to character codes."""
    pattern = re.compile(r'\.ti-([a-z0-9-]+):+before\s*\{\s*content:\s*"\\([0-9a-fA-F]+)"')
    return {name: int(code, 16) for name, code in pattern.findall(css)}


def trim_font(font_bytes, character_codes):
    """Keeps only the icons we use, if fontTools is available."""
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
    except ImportError:
        print("fontTools isn't installed, so the full font is kept (a few MB).")
        print("To trim it to a few KB, install python3-fonttools and run this again.")
        return font_bytes

    font = TTFont(io.BytesIO(font_bytes))
    subsetter = subset.Subsetter(subset.Options())
    subsetter.populate(unicodes=character_codes)
    subsetter.subset(font)

    trimmed = io.BytesIO()
    font.save(trimmed)
    return trimmed.getvalue()


def measure_centering(font_path, codes_by_name):
    """Works out how far each icon's visible shape is from the center of
    the box mpv's text renderer centers it by.

    The renderer centers a character using its spacing and the font's line
    height, not the visible shape, so icons can land slightly off-center.
    For each icon this returns how far the shape's middle is from the
    box's middle, as a fraction of the font size: positive x means it sits
    too far right, positive y too far down. draw.lua shifts each icon back
    by that amount.
    """
    try:
        from fontTools.pens.boundsPen import BoundsPen
        from fontTools.ttLib import TTFont
    except ImportError:
        print("fontTools isn't installed, so icons can't be measured for centering.")
        return {}

    font = TTFont(font_path)
    character_map = font.getBestCmap()
    glyphs = font.getGlyphSet()

    # mpv's text renderer sizes text by the font's "Windows" line height
    # when a font has one, the way older subtitle software did.
    os2 = font["OS/2"] if "OS/2" in font else None
    if os2 is not None and os2.usWinAscent + os2.usWinDescent > 0:
        ascent, descent = os2.usWinAscent, os2.usWinDescent
    else:
        ascent, descent = font["hhea"].ascent, -font["hhea"].descent
    line_height = ascent + descent

    offsets = {}
    for name, code in codes_by_name.items():
        glyph_name = character_map.get(code)
        if glyph_name is None:
            continue

        pen = BoundsPen(glyphs)
        glyphs[glyph_name].draw(pen)
        if pen.bounds is None:
            continue
        left, bottom, right, top = pen.bounds
        advance_width = font["hmtx"][glyph_name][0]

        shape_middle_x = (left + right) / 2
        box_middle_x = advance_width / 2

        # Font units count upwards from the baseline; screen positions
        # count downwards from the top of the line.
        shape_middle_from_top = ascent - (bottom + top) / 2
        box_middle_from_top = line_height / 2

        offsets[name] = (
            (shape_middle_x - box_middle_x) / line_height,
            (shape_middle_from_top - box_middle_from_top) / line_height,
        )

    return offsets


def read_font_family_name(font_path):
    """Returns the font's family name, which ASS uses to pick the font."""
    try:
        from fontTools.ttLib import TTFont

        return TTFont(font_path)["name"].getDebugName(1)
    except ImportError:
        pass

    if shutil.which("fc-scan"):
        result = subprocess.run(
            ["fc-scan", "--format", "%{family}", str(font_path)],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.split(",")[0].strip()

    return "tabler-icons"


def write_icon_list(font_family, version, codes_by_name, offsets):
    lines = [
        "-- The icons Visual Player uses, and where to find each one in the icon font.",
        "--",
        f"-- Generated by tools/update-icon-font.py from Tabler Icons {version}.",
        "-- Don't edit this by hand: add names to NEEDED_ICONS in that script",
        "-- and run it again.",
        "",
        "return {",
        f'    font_family = "{font_family}",',
        f'    font_version = "{version}",',
        "    codepoints = {",
    ]
    for name in sorted(codes_by_name):
        lines.append(f'        ["{name}"] = 0x{codes_by_name[name]:X},')
    lines += [
        "    },",
        "",
        "    -- How far each icon's visible shape sits from the middle of its box,",
        "    -- as a fraction of the font size. Positive x is too far right,",
        "    -- positive y too far down. draw.lua shifts icons back by this much.",
        "    offsets = {",
    ]
    for name in sorted(offsets):
        x, y = offsets[name]
        lines.append(f'        ["{name}"] = {{ x = {x:.4f}, y = {y:.4f} }},')
    lines += ["    },", "}", ""]

    ICON_LIST_FILE.write_text("\n".join(lines))


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "latest"
    exact_version, archive = download_release(version)

    font_bytes, css = find_font_and_css(archive)
    all_codes = find_character_codes(css)

    missing = [name for name in NEEDED_ICONS if name not in all_codes]
    if missing:
        print("These icons aren't in this release, so they're left out:")
        for name in missing:
            print(f"  {name}")

    needed_codes = {name: all_codes[name] for name in NEEDED_ICONS if name in all_codes}

    FONT_FOLDER.mkdir(exist_ok=True)
    FONT_FILE.write_bytes(trim_font(font_bytes, list(needed_codes.values())))

    license_text = read_file_from_archive(archive, "LICENSE")
    if license_text is not None:
        LICENSE_FOLDER.mkdir(exist_ok=True)
        LICENSE_FILE.write_bytes(license_text)

    font_family = read_font_family_name(FONT_FILE)
    offsets = measure_centering(FONT_FILE, needed_codes)
    write_icon_list(font_family, exact_version, needed_codes, offsets)

    size_in_kb = FONT_FILE.stat().st_size / 1024
    print(f"Saved {len(needed_codes)} icons ({size_in_kb:.0f} KB), font family '{font_family}'.")
    print(f"Updated {ICON_LIST_FILE.relative_to(REPO_FOLDER)}.")


if __name__ == "__main__":
    main()
