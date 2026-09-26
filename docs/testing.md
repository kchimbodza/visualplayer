# Visual Player test checklist

Run through this before each release. "Pass" means it was checked and
worked; "Not available" means the hardware doesn't have that feature;
blank means not yet tested.

Test machines:

- **Nobara:** ASUS ProArt PX13, Nobara 44 (GNOME, Wayland), AMD Radeon
  890M plus NVIDIA RTX 4050, 2880×1800 HDR touchscreen, plus a
  PX277OLEDMAX 2560×1440 240 Hz HDR monitor over DisplayPort.
- **Omarchy:** Framework 13, Omarchy (Arch, Hyprland), SDR screen.

Test files are the samples in `samples/` (not in git): Dolby Art, Dolby
Blocks, 7ENSATION Amazing Jellyfish 8, CableLabs Life Untouched, and
Barco Stinger Bees, plus `samples/test.srt` and
`samples/test-chapters.txt`.

## Picture

| Case | Nobara | Omarchy |
|---|---|---|
| HDR10 on an HDR screen: HDR output, info says HDR10 | Pass | Not available |
| HDR on an SDR screen: tone mapped, info says "Tone mapped to SDR" | Pass (HDR off) | Pass |
| HLG on an HDR screen | Pass | Not available |
| SDR on an HDR screen: looks normal, labeled SDR | Pass | Not available |
| Dolby Vision profile 5 (Blocks): correct colors, "Profile 5" | Pass | Pass |
| Dolby Vision profile 7 (Art): "HDR10 base layer" | Pass | |
| Dolby Vision profile 8 (Jellyfish): "Profile 8" | Pass | |
| 4K HEVC hardware decoding | Pass (Vulkan) | Pass (VA-API) |
| 4K AV1 hardware decoding | | Pass (VA-API, 0 dropped) |
| 8K AV1 hardware decoding (Jellyfin 8K AV1 10bit 100M, 60 fps) | Pass (Vulkan, 1 dropped in 29 s) | |
| 8K HEVC HDR10 at 150 Mb/s (Jellyfin) | Pass (Vulkan, 22 dropped in 29 s) | |
| 8K labeled "8K" in the badges and info panel | Pass | |
| Status line: smooth, dropping frames with the right cause, paused | Pass | |

## Sound

| Case | Nobara | Omarchy |
|---|---|---|
| Built-in speakers: named, "Stereo downmix from 7.1" on Art | Pass | |
| Monitor audio over DisplayPort: named PX277OLEDMAX, called DisplayPort | Pass | Not available |
| Switching outputs in the popup, also switching the system's output | | |
| Choosing an output in GNOME moves Visual Player too | | |
| Passthrough never offered to a stereo-only monitor | Pass | Not available |
| Passthrough to a soundbar: Dolby Atmos from TrueHD and E-AC-3, Dolby Digital from AC-3 (EZCOO extractor, Poseidon D80) | Pass (plain mpv, direct port) | |
| Passthrough to a soundbar through Visual Player | | |
| Bluetooth output: named, codec shown, downmix shown | | |
| Plugging in or removing an output during playback | | |
| Audio-only file (music): no video or screen rows | | |

## Screen

| Case | Nobara | Omarchy |
|---|---|---|
| Built-in screen: name, native resolution, refresh, HDR state | Pass | |
| External monitor: name from the monitor, connection, mode | Pass | Not available |
| Window across two screens: settles on one, small drop in smoothness | Pass | Not available |

## Interface

| Case | Nobara | Omarchy |
|---|---|---|
| Top bar: title, chapter subtitle, clock | Pass | Pass |
| Format badges: appear when a file starts, then fade; honest labels | | |
| Window buttons (GNOME only), dragging, double-click to maximize | Pass | Pass (no buttons) |
| Playback row, repeat, speed, time and remaining time | Pass | |
| Seek bar: chapters, hover preview, click and smooth dragging | Pass | |
| Tools row and volume slider | Pass | |
| Auto-hide and fade, pointer hides too | Pass | Pass |
| Subtitles move above the controls | Pass | |
| Info panel: all rows, updates within a second | Pass | Pass |
| Audio & subtitles menu | Pass | |
| Audio chip shows format and track number; notice appears when cycling tracks | | |
| Chapters & playlist menu, scrolling | Pass | |
| Only one popup open at a time | Pass | |
| Settings: each setting works and is remembered | Pass | |
| Remember window size | | |
| Picture-in-picture: shrinks, controls, restores | Pass | |
| Picture-in-picture: stays on top | Alt+Space | |
| Touch controls with a finger | Pass | Not available |
| Touch controls set to On, with a mouse | Pass | |

## Window

| Case | Nobara | Omarchy |
|---|---|---|
| Opens at 70% of the screen | Pass | |
| Can't be shrunk below 240p | Pass | |
| Fullscreen with F, F11, Alt+Enter, double-click | Pass | |

## Files and streams

| Case | Nobara | Omarchy |
|---|---|---|
| Playlist of several files | Pass | |
| File on a network share, opened from GNOME Files | Pass | |
| Stream (HLS or a web video): format, bitrate, buffer shown | | |
| Buffering while streaming: red "Buffering" status | | |

## Packaging

| Case | Nobara | Omarchy |
|---|---|---|
| Installs as a package, `visualplayer` works from anywhere | Pass | Pass |
| App menu entry with icon | Pass | Pass |
| Opening from the app menu with no file shows the idle screen; dropping a video plays it | | |
| Open With from the file manager | Pass | |
| Dock or taskbar shows Visual Player, not mpv | Pass | Pass |
| Upgrading from the previous version | Pass | Pass |
