#!/usr/bin/env python3
"""Downloads Inter, the font Visual Player uses for its on-screen text.

Visual Player bundles its own text font so the interface looks the same on
every system, instead of depending on each system's default. Inter is made
for screens, has clear, evenly sized numbers (important for timestamps and
bitrates), and is free under the SIL Open Font License.

It also avoids a problem found in Phase 2: some systems' default font is a
"variable" font, which mpv's text renderer drew with oddly small numbers.
This script saves Inter's regular, non-variable files.

Usage:
    ./tools/update-text-font.py            use the latest Inter release
    ./tools/update-text-font.py v4.1       use a specific release
"""

import io
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

# The styles the interface uses: regular text, and bold for headings.
NEEDED_STYLES = ["Inter-Regular.ttf", "Inter-Bold.ttf"]

REPO_FOLDER = Path(__file__).resolve().parent.parent
FONT_FOLDER = REPO_FOLDER / "fonts"
LICENSE_FOLDER = REPO_FOLDER / "licenses"

RELEASE_URL = "https://api.github.com/repos/rsms/inter/releases/{which}"


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "visual-player"})
    with urllib.request.urlopen(request) as response:
        return response.read()


def find_release_zip(version):
    """Returns the release name and the download address of its zip file."""
    which = "latest" if version == "latest" else f"tags/{version}"
    release = json.loads(download(RELEASE_URL.format(which=which)))

    for asset in release["assets"]:
        if asset["name"].endswith(".zip"):
            return release["tag_name"], asset["browser_download_url"]

    sys.exit(f"Inter release {release['tag_name']} has no zip file to download.")


def read_file_from_zip(archive, file_name):
    """Returns the file with this name, preferring the copy in a ttf folder,
    since some releases include the same name in several formats."""
    matches = [name for name in archive.namelist() if name.endswith("/" + file_name)
               or name == file_name]
    matches.sort(key=lambda name: "ttf/" not in name)

    if not matches:
        return None
    return archive.read(matches[0])


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "latest"
    release_name, zip_url = find_release_zip(version)
    print(f"Downloading Inter {release_name}...")

    archive = zipfile.ZipFile(io.BytesIO(download(zip_url)))
    FONT_FOLDER.mkdir(exist_ok=True)

    for style in NEEDED_STYLES:
        font = read_file_from_zip(archive, style)
        if font is None:
            sys.exit(f"Couldn't find {style} in this Inter release.")
        (FONT_FOLDER / style).write_bytes(font)
        print(f"Saved fonts/{style} ({len(font) / 1024:.0f} KB)")

    license_text = read_file_from_zip(archive, "LICENSE.txt")
    if license_text is not None:
        LICENSE_FOLDER.mkdir(exist_ok=True)
        (LICENSE_FOLDER / "inter.txt").write_bytes(license_text)
        print("Saved licenses/inter.txt")


if __name__ == "__main__":
    main()
