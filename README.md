# Visual Player

A Linux media player built on [mpv](https://mpv.io), designed for HDR video, lossless and Dolby Atmos audio, and always showing you exactly how your media is being played.

> **Status:** early development. Nothing to install yet.

## What it will do

- Play everything mpv plays, with hardware decoding by default.
- Output true HDR (HDR10, HDR10+, Dolby Vision) on Wayland desktops that support it, and fall back to good-looking SDR when they don't.
- Pass Dolby Atmos, TrueHD, and DTS:X straight through to your receiver, and tell you plainly when audio is being downmixed instead.
- Show which output you're using (HDMI, Bluetooth, USB-C DisplayPort, or built-in speakers) right next to the volume control.
- Keep the interface clean: a simple overlay that gets out of the way, with an info panel one key press away.

## Supported systems

| System | Desktop | Package |
|---|---|---|
| Nobara (Fedora-based) | GNOME | RPM |
| Omarchy (Arch-based) | Hyprland | PKGBUILD |

## How it works

Visual Player runs on top of the mpv already installed on your system. mpv handles the video and audio, and Visual Player draws the whole interface as an mpv script. This keeps HDR output intact and makes the app small and easy to package.

The full design and build plan is in [docs/plan.md](docs/plan.md).

## Contributing

The code is meant to read like plain English. Please read the code readability section of the plan before contributing. Formatting is handled by [StyLua](https://github.com/JohnnyMorganz/StyLua) and checks by [luacheck](https://github.com/lunarmodules/luacheck).

## License

MIT. See [LICENSE](LICENSE).
