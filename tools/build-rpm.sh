#!/bin/sh
# Builds the Visual Player RPM for Fedora and Nobara.
#
# rpmbuild needs the source as an archive in ~/rpmbuild/SOURCES, so this
# script makes one from the latest commit, then runs rpmbuild.
#
# Only committed changes are included, so commit before building.
#
# Usage:
#   ./tools/build-rpm.sh

set -eu

repo_folder=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_folder"

spec_file="packaging/fedora/visual-player.spec"
version=$(sed -n 's/^Version: *//p' "$spec_file")

if ! command -v rpmbuild > /dev/null || ! command -v rpmdev-setuptree > /dev/null; then
    echo "The RPM build tools aren't installed. Install them with:"
    echo "  sudo dnf install rpm-build rpmdevtools desktop-file-utils"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Note: you have uncommitted changes. They won't be in this package."
    echo
fi

# Creates ~/rpmbuild and its folders if they don't exist yet.
rpmdev-setuptree

git archive \
    --format=tar.gz \
    --prefix="visual-player-$version/" \
    --output="$HOME/rpmbuild/SOURCES/visual-player-$version.tar.gz" \
    HEAD

rpmbuild -ba "$spec_file"

echo
echo "Built. Install it with:"
for package in "$HOME"/rpmbuild/RPMS/noarch/visual-player-"$version"-*.rpm; do
    echo "  sudo dnf install $package"
done
