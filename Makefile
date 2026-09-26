# Installs Visual Player into the system folders.
#
# Both packages (the Arch PKGBUILD and the Fedora spec) use this, so they
# always install the same files in the same places. Normally you'd install
# a package instead of running this directly, but it also works by hand:
#
#   make install PREFIX=$HOME/.local     Install just for you
#   sudo make install                    Install for everyone
#   make check                           Check the Lua code's style

PREFIX ?= /usr/local
DESTDIR ?=

bin_folder = $(DESTDIR)$(PREFIX)/bin
share_folder = $(DESTDIR)$(PREFIX)/share
app_folder = $(share_folder)/visual-player

.PHONY: install uninstall check

install:
	install -Dm755 bin/vplay "$(bin_folder)/vplay"
	install -Dm644 -t "$(app_folder)/config" config/mpv.conf config/input.conf
	install -Dm644 -t "$(app_folder)/scripts/visual-player" scripts/visual-player/*.lua
	install -Dm644 -t "$(app_folder)/fonts" fonts/*.ttf
	install -Dm644 -t "$(app_folder)/licenses" licenses/*.txt
	install -Dm644 data/visual-player.desktop "$(share_folder)/applications/visual-player.desktop"
	install -Dm644 data/icons/visual-player.svg \
		"$(share_folder)/icons/hicolor/scalable/apps/visual-player.svg"

uninstall:
	rm -f "$(bin_folder)/vplay"
	rm -rf "$(app_folder)"
	rm -f "$(share_folder)/applications/visual-player.desktop"
	rm -f "$(share_folder)/icons/hicolor/scalable/apps/visual-player.svg"

# Runs the style tools from docs/plan.md, section 11, if they're installed.
check:
	@if command -v stylua > /dev/null; then stylua --check scripts; \
	else echo "stylua isn't installed, skipping the formatting check"; fi
	@if command -v luacheck > /dev/null; then luacheck scripts; \
	else echo "luacheck isn't installed, skipping the lint check"; fi
