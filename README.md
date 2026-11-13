<img src="data/icons/visual-player.svg" width="72" alt="Visual Player icon">

# Visual Player

A Linux media player built on [mpv](https://mpv.io), designed for HDR video, lossless and Dolby Atmos audio, and always showing you exactly how your media is being played.

> **Status:** early development, version 0.6.13. It builds and installs as a local package on both test machines (RPM on Nobara, PKGBUILD on Omarchy). No published package yet; AUR and COPR are planned.

## What it does

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

## Architecture

<p align="center"><img src="docs/architecture.svg" width="100%" alt="The visualplayer launcher starts the system mpv 0.41 or newer with Visual Player's config. mpv owns the Wayland window and decodes in hardware (Vulkan or VA-API). Visual Player's interface is Lua scripts inside mpv that read mpv properties and system facts (pw-dump, ALSA ELD, DRM EDID) and draw on mpv's on-screen display. Video goes through gpu-next with a colour hint: real HDR on an HDR screen, tone mapped on an SDR screen. Audio: if passthrough is on for the output, the bitstream goes straight to the ALSA HDMI port so the soundbar decodes Atmos; otherwise it is decoded and played through PipeWire, with any downmix reported."></p>

Visual Player runs on top of the mpv already installed on your system. mpv handles the video and audio, and Visual Player draws the whole interface as an mpv script. This keeps HDR output intact and makes the app small and easy to package.

**Why this architecture**

| Choice | Why |
|---|---|
| mpv owns the window; the interface is a Lua script (not a Qt app embedding libmpv) | Qt presents mpv's picture as a normal SDR surface, so HDR would be tone mapped. With mpv's own Wayland window and `gpu-next`, HDR works exactly as in plain mpv. |
| Built on the system's mpv | The app is only scripts, config and fonts, so both packages are `noarch`/`any` with no build step. |
| Launcher with `--no-config`, then defaults, then personal settings | Personal settings always win, and a personal `~/.config/mpv` setup never mixes in. |
| Output details from PipeWire, ELD and EDID, not just mpv | mpv reported 7.1 on stereo laptop speakers because PipeWire downmixes after it, and Linux names DisplayPort audio "HDMI". |
| Passthrough on the direct ALSA HDMI port, chosen at startup | Through PipeWire only AC-3 got through; the direct port carried TrueHD and E-AC-3 Atmos. Taking the port over mid-playback failed ("Device or resource busy"). |
| `video-sync=audio` (mpv's default) | `display-resample` dropped 237 frames in 59 s on a 240 Hz monitor with uneven refresh timing, against 1 in 74 s with the default. |

The full design, build plan and findings from every phase are in [docs/plan.md](docs/plan.md).

## Results

From the release checklist [docs/testing.md](docs/testing.md), filled in by hand on two machines: an ASUS ProArt PX13 (Nobara 44, GNOME, HDR screen plus a 240 Hz HDR OLED monitor) and a Framework 13 (Omarchy, Hyprland, SDR screen).

| | Cases |
|---|---|
| Checklist cases | 67 |
| Passed on at least one machine | 55 (Nobara 53, Omarchy 13) |
| Failed | 0 recorded |
| Not tested yet | 11 (e.g. Bluetooth output, streams, hot-plugging an output) |
| Works with a workaround | 1 (picture-in-picture on top: GNOME needs Alt+Space) |

Measured playback (from `docs/testing.md` and `docs/plan.md`):

| Test | Result |
|---|---|
| 8K AV1, 10-bit, 100 Mb/s, 60 fps (Nobara, Vulkan) | 1 dropped frame in 29 s |
| 8K HEVC HDR10 at 150 Mb/s (Nobara, Vulkan) | 22 dropped frames in 29 s |
| 4K AV1 (Omarchy, VA-API) | 0 dropped |
| SDR test folder, all ten files (Nobara) | Hardware decoding, correct badges, 0 dropped |
| Dolby Vision profiles 5, 7, 8.1, 8.4, 10 and an iPhone clip | All labelled correctly |
| Passthrough to a Poseidon D80 soundbar (via an EZCOO extractor) | Dolby Atmos from TrueHD and E-AC-3, Dolby Digital from AC-3 |
| DTS-HD MA 7.1 decoded on the direct route | 7.1 PCM, every speaker in the right place |
| Redraws while resizing, before and after the redraw limiter | 141–227 dropped frames per clip, down to about 28 |

Code checks, run 13 Nov 2026 on Arch Linux: `luacheck scripts` (luacheck 1.2.0, the repo's `.luacheckrc`) gives **0 errors, 1 warning in 37 files** (an unused value in `bottom_controls.lua`); all 37 Lua files compile with LuaJIT 2.1. There are no automated tests or CI; testing is the manual checklist above.

## What worked and what didn't

| | What | Detail |
|---|---|---|
| ✅ | HDR on GNOME | mpv sent PQ with BT.2020 for every HDR file, on the laptop screen and the external monitor. |
| ✅ | Tone mapping on SDR | On the Framework 13, HDR files, including Dolby Vision profile 5, looked correct as SDR. |
| ✅ | Atmos passthrough | TrueHD and E-AC-3 Atmos reached the soundbar once passthrough used the direct HDMI port. |
| ❌ → ✅ | Passthrough through PipeWire | Only AC-3 got through; DTS gave silence ("no target node available"). Moved to the direct port. |
| ❌ → ✅ | DTS to the Poseidon D80 | The extractor lists DTS, but the soundbar can't decode it: silence. Formats can now be switched off per device and are decoded instead. |
| ❌ → ✅ | Surround decoded on the direct port | Came out as stereo because the extractor advertises only FL FR. Fixed with `audio-channels=7.1,5.1,stereo` and `alsa-ignore-chmap=yes`. |
| ❌ → ✅ | Settings saved in the wrong folder | mpv's `~~/` path saved settings wherever the player was started, and they ended up on GitHub. Now built from `$XDG_CONFIG_HOME` (0.6.10). |
| ❌ → ✅ | Second window on double-click | A second video opened a new window. The launcher now sends files to the open one over a socket (0.6.13). |
| ⚠️ | Dolby Vision profile 7 | mpv plays only its HDR10 base layer, so it is labelled that way. |
| ⚠️ | HDR10+ | mpv doesn't report it, so HDR10+ files show as HDR10. |
| ⚠️ | Wayland limits | Windows can't raise or place themselves, and GNOME apps can't set always-on-top. |
| ⚠️ | Not yet tested | Bluetooth output, streams and buffering, hot-plugging outputs, audio-only files. |

## Build and install

While in development, both packages build from the source folder:

- **Omarchy:** `cd packaging/arch && makepkg -si`
- **Nobara:** `./tools/build-rpm.sh`, which prints the `sudo dnf install ...` command for the built RPM

Needs mpv 0.41 or newer. Then run `visualplayer [file]`, or open it from the app menu.

## Contributing

The code is meant to read like plain English. Please read the code readability section of the plan before contributing. Formatting is handled by [StyLua](https://github.com/JohnnyMorganz/StyLua) and checks by [luacheck](https://github.com/lunarmodules/luacheck).

## License

MIT. See [LICENSE](LICENSE).
