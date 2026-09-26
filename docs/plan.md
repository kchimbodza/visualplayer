# Media player build plan

**Name:** Visual Player

| Use | Name |
|---|---|
| Display name (app menu, start screen) | Visual Player |
| Package, desktop entry, config and data dirs | `visual-player` |
| Terminal command | `vplay` |

A Linux media player built on mpv, with a custom overlay UI designed for HDR video, lossless and object-based audio, and clear visibility into how media is actually being output.

---

## 1. Goals

- Play everything mpv plays, with hardware decoding by default.
- True HDR output (HDR10, HDR10+, and Dolby Vision where mpv supports it) on Wayland compositors that support it, with graceful tone-mapped SDR fallback.
- Audio passthrough (TrueHD/Atmos, DTS:X, E-AC-3) to receivers, with honest reporting when audio is downmixed.
- A clean overlay UI (see section 5) that surfaces format, output route, and playback health without clutter.
- Native packages for the two target machines.

### Non-goals (for v1)

- DRM streaming services (Widevine is not supported by mpv).
- Media library management, metadata scraping, or a server backend.
- Windows or macOS builds.
- Flatpak or AppImage (possible later, see section 10).

---

## 2. Target environments

| Machine | Base | Desktop | Package format |
|---|---|---|---|
| Nobara | Fedora | GNOME (Wayland) | RPM |
| Omarchy | Arch | Hyprland (Wayland) | PKGBUILD (pacman) |

Both are Wayland-first. X11 support is not a goal but should work incidentally through mpv.

---

## 3. Architecture decision

This is the most important decision in the project, and it changes what we discussed earlier in chat.

### The problem

Embedding mpv inside a Qt/QML window uses libmpv's render API, where mpv draws into the app's OpenGL framebuffer. Qt then presents that framebuffer to the compositor as a normal SDR surface. That means HDR video gets tone-mapped to SDR, and mpv's HDR output to the compositor (via the Wayland color-management protocol) is lost. The older `wid` embedding approach doesn't work on Wayland at all.

### Options

**Option A — Qt 6/QML app with libmpv render API.** Richest UI toolkit, easy dialogs and settings screens. HDR is tone-mapped to SDR unless Qt can present HDR surfaces on your compositors, which should not be counted on today.

**Option B — mpv owns the window, UI is an mpv script (recommended).** mpv creates its own Wayland window with `vo=gpu-next`, so HDR passthrough works exactly as it does in plain mpv. The entire UI (overlay, info panel, output popup, menus) is drawn with mpv's OSD using a Lua script. This is proven at scale by projects like uosc and ModernX, which build full modern interfaces this way.

### Decision

**Go with Option B.** HDR and format fidelity are the core of this player, and Option B is the only one that delivers them reliably on both compositors today. It also makes packaging trivial, since the app is architecture-independent scripts plus config on top of the system mpv.

Phase 0 (section 12) includes a short spike to confirm HDR output on both machines before building the full UI. If HDR passthrough turns out to be unimportant, Option A remains a valid fallback.

---

## 4. Project structure

```
visual-player/
├── bin/
│   └── vplay                  # launcher shell script
├── config/
│   ├── mpv.conf               # shipped defaults
│   └── input.conf             # key bindings
├── scripts/
│   └── visual-player/
│       ├── main.lua           # entry point, event loop, state
│       ├── state.lua          # observed mpv properties
│       ├── layout.lua         # geometry, hit testing, auto-hide
│       ├── render.lua         # ASS drawing helpers (icons, pills, bars)
│       ├── ui/
│       │   ├── top_bar.lua    # title, subtitle, clock, window buttons
│       │   ├── controls.lua   # playback row, seek bar, tools row
│       │   ├── info_panel.lua # right-edge info panel
│       │   ├── output_menu.lua# audio/display output popup
│       │   └── menus.lua      # tracks, chapters, settings
│       ├── outputs/
│       │   ├── audio.lua      # device list, bus type, BT codec
│       │   └── display.lua    # connector, mode, HDR state, USB-C
│       └── icons.lua          # icon glyph map
├── fonts/                     # icon font (bundled, see section 5.6)
├── data/
│   ├── visual-player.desktop
│   └── icons/                 # app icons, hicolor sizes
├── packaging/
│   ├── arch/PKGBUILD
│   └── fedora/visual-player.spec
├── Makefile                   # install target used by both packages
└── plan.md
```

### Launcher

`bin/vplay` starts mpv with Visual Player's files. It works both when installed (files in `/usr/share/visual-player`) and when run straight from the source folder, which makes development easy.

It passes `--no-config` so mpv doesn't load any config files on its own, then loads them explicitly in a fixed order: Visual Player's defaults (`config/mpv.conf`), then the user's personal settings (`~/.config/visual-player/mpv.conf`, created empty on first run). Loading them in this order guarantees personal settings always win. A plain `--include` of the defaults would have done the opposite, since command-line options override config files.

Interface options such as `osc` and `border` live in `config/mpv.conf` rather than on the command line, so they can be changed like any other setting. `--wayland-app-id=visual-player` stays on the command line because it must always match the desktop entry.

The window title is set in `config/mpv.conf` as `${media-title} — Visual Player`.

---

## 5. UI specification

Based on the final mockups from the design sessions. Wireframes first, then the detailed spec for each element.

### 5.0 Wireframes

Monospace sketches of the final mockups. Brackets are icon buttons; the legend follows the frames. Proportions are approximate, not pixel-exact.

**Default view (controls visible)**

```
┌────────────────────────────────────────────────────────────────────┐
│ Episode title                       Fri, Sep 5 · 9:30 AM   –  □  × │
│ S1 · E4 · Chapter 3                                                │
│                                                                    │
│                                                                    │
│                                                                    │
│                                                                    │
│                              (video)                               │
│                                                                    │
│                                                                    │
│                                                                    │
│                                                                    │
│ [▶]  [|◀]  [▶|]  [repeat]  [speed]                     0:59 / 1:45 │
│ ━━━━━━━━━━━━━ ━━━━━━━━━━━━━ ━━━━━━━━━●─── ───────────── ────────── │
│ [CC]  [menu]  [info]  [rotate]  [settings]            [HDMI] [vol] │
└────────────────────────────────────────────────────────────────────┘
```

**Info panel open** (`I` key or info button, docked flush to the right edge below the clock)

```
┌────────────────────────────────────────────────────────────────────┐
│ Episode title                       Fri, Sep 5 · 9:30 AM   –  □  × │
│ S1 · E4 · Chapter 3                                                │
│                             ┌──────────────────────────────────────│
│                             │ ▣  4K HDR10+                         │
│                             │    AV1 · 3840×2160 · 60 fps · 10-bit │
│                             │ ♪  Dolby Atmos 7.1                   │
│                             │    TrueHD · 48 kHz · English         │
│                             │ CC English                           │
│           (video)           │    SRT · track 2 of 4                │
│                             │ ●  Playing smoothly                  │
│                             │    HW decode · 0 dropped · 18 Mb/s   │
│                             └──────────────────────────────────────│
│                                                                    │
│ [▶]  [|◀]  [▶|]  [repeat]  [speed]                     0:59 / 1:45 │
│ ━━━━━━━━━━━━━ ━━━━━━━━━━━━━ ━━━━━━━━━●─── ───────────── ────────── │
│ [CC]  [menu]  [info]  [rotate]  [settings]            [HDMI] [vol] │
└────────────────────────────────────────────────────────────────────┘
```

**Output popup open** (output chip; opens above the playback row so time, seek bar, and both control rows stay visible)

```
┌────────────────────────────────────────────────────────────────────┐
│ Episode title                       Fri, Sep 5 · 9:30 AM   –  □  × │
│ S1 · E4 · Chapter 3                                                │
│                                                                    │
│                           ┌─────────────────────────────────────┐  │
│                           │ ▭  Denon AVR                        │  │
│                           │    HDMI · Atmos passthrough (green) │  │
│                           │ HDMI-A-1 · 4K 60 · HDR              │  │
│                           │ ────────────────────────────────────│  │
│                           │ ▭  Denon AVR                      ✓ │  │
│                           │ ᛒ  WH-1000XM5                       │  │
│                           │ ⌁  LG monitor                       │  │
│                           │ ▢  Speakers                         │  │
│                           └─────────────────────────────────────┘  │
│ [▶]  [|◀]  [▶|]  [repeat]  [speed]                     0:59 / 1:45 │
│ ━━━━━━━━━━━━━ ━━━━━━━━━━━━━ ━━━━━━━━━●─── ───────────── ────────── │
│ [CC]  [menu]  [info]  [rotate]  [settings]            [HDMI] [vol] │
└────────────────────────────────────────────────────────────────────┘
```

**Output popup header when on Bluetooth** (status turns amber)

```
┌────────────────────────────────────────────┐
│ ᛒ  WH-1000XM5                              │
│    Bluetooth LDAC · Stereo downmix  (amber)│
└────────────────────────────────────────────┘
```

**Volume** (slider expands to the left of the speaker icon on hover or click)

```
collapsed:  ... [settings]                    [HDMI] [vol]
expanded:   ... [settings]      [HDMI] ━━━━━━●──── [vol]
```

**Legend**

| Sketch | Control | Sketch | Control |
|---|---|---|---|
| `[▶]` | Play/pause | `[CC]` | Subtitles |
| `[\|◀]` `[▶\|]` | Previous / next | `[menu]` | Chapters, playlist |
| `[repeat]` | Repeat | `[info]` | Info panel |
| `[speed]` | Playback speed | `[rotate]` | Rotate video |
| `━━ ━━●──` | Chapter-segmented seek bar | `[settings]` | Settings |
| `–  □  ×` | Window buttons (GNOME only) | `[HDMI]` | Output chip |
| `▣ ♪ CC ●` | Info row icons: video, audio, subs, status | `[vol]` | Volume |

### 5.1 Overall

- Dark translucent overlays on top of the video, no window decorations (`--border=no`).
- All overlay UI auto-hides after 2 seconds of no mouse movement during playback, stays visible while paused or while a popup is open.
- Font: system sans for text, sized relative to window height so it scales with the window.

### 5.1a Window size

- **Smallest window: 240p** (426×240 at 16:9), measured in the screen's own scaling so it looks the same on every screen. This matches the small end of typical picture-in-picture windows.
- mpv has no setting for a smallest window size, so `window_size.lua` resizes the window back up if it stays below 240p for half a second after a resize. It leaves fullscreen and maximized windows alone.
- `autofit-smaller=426x240` in `config/mpv.conf` stops a window from opening smaller than that.
- On Hyprland, a window rule could enforce a true minimum while dragging. Optional; check the Hyprland wiki for the current syntax.

### 5.2 Top bar

- **Top left:** media title (`media-title`), with a subtitle line showing season/episode if parsed from the filename, plus current chapter name.
- **Top right:** clock (day, date, time).
- **Window controls:** minimize, maximize, close, shown on GNOME only (hidden on Hyprland, detected via `XDG_CURRENT_DESKTOP`).
- **Dragging:** the top bar area acts as a title bar using mpv's `begin-vo-dragging` command.

### 5.3 Bottom controls (top to bottom)

1. **Playback row:** play/pause, previous, next, repeat, speed. Elapsed/total time on the right, e.g. `0:59 / 1:45`.
2. **Seek bar:** segmented by chapters from `chapter-list`, with a circular scrubber handle. Hover shows the timestamp and chapter name.
3. **Tools row:** CC, menu (chapters/playlist), info, rotate, settings on the left. Audio output chip and volume on the right.

All icon buttons share one size.

### 5.4 Volume

- Speaker icon at the far right of the tools row.
- Click or hover expands a slider to the left; double-click toggles mute.
- Icon reflects level (muted, low, high).
- Scroll wheel and up/down arrows also change volume.

### 5.5 Info panel (design 1, grouped rows)

Docked flush to the right edge, below the clock. Toggled by the info button or the `I` key. Four groups, each a bold headline with a muted technical line underneath:

| Row | Headline | Technical line |
|---|---|---|
| Video | `4K HDR10+` | `AV1 · 3840×2160 · 60 fps · 10-bit` |
| Audio | `Dolby Atmos 7.1` | `TrueHD · 48 kHz · English` |
| Subtitles | `English` | `SRT · track 2 of 4` |
| Status | `Playing smoothly` (green dot) | `HW decode · 0 dropped · 18 Mb/s` |

Rules:

- Omit a row when not applicable (no subtitles, audio-only file).
- Status states: green "Playing smoothly", amber "Dropping frames", red "Buffering". The technical line explains why.
- For local files, replace bitrate with the container format.
- Refresh once per second to avoid flicker.

### 5.6 Output chip and popup (slim design 1)

**Chip:** next to the volume icon, showing an icon plus a short label (`HDMI`, `LDAC`, `DP`, `Speakers`).

**Popup:** opens above the playback row so the time display, seek bar, and both control rows remain visible. Right-aligned, roughly half the window width.

- **Header:** device icon, device name, and a line with connection type and audio mode. Mode is green "Atmos passthrough" (or the actual passthrough format) or amber "Stereo downmix".
- **Display line:** connector, mode, HDR state, e.g. `HDMI-A-1 · 4K 60 · HDR`.
- **Device list:** icon, name, and check mark for the active device. Selecting a device switches `audio-device` immediately.

### 5.7 Icons

Bundle an icon font (Tabler Icons, MIT licensed, matches the mockups) and render glyphs through ASS with `\fn`.

- `tools/update-icon-font.py` downloads a Tabler release from npm, reads each icon's character code from its stylesheet, trims the font to only the icons listed in `NEEDED_ICONS` (when fontTools is installed), and writes `scripts/visual-player/icons.lua`. The font and `icons.lua` are committed, so building the app never needs the internet.
- The launcher passes `--osd-fonts-dir` so the on-screen display finds the bundled font without installing it system-wide, where it would clutter font menus.
- To add an icon: add its name to `NEEDED_ICONS` and run the script again.

### 5.8 Rotation

Rotate button cycles `video-rotate` through 0, 90, 180, 270 and shows a brief centered confirmation.

---

## 6. Data sources

Almost all UI data comes from observed mpv properties.

| UI element | mpv property / source |
|---|---|
| Title | `media-title` |
| Chapter segments, current chapter | `chapter-list`, `chapter` |
| Time | `time-pos`, `duration` |
| Resolution, HDR format, bit depth | `video-params` (`w`, `h`, `gamma`, `primaries`, `pixelformat`) |
| Dolby Vision / HDR10+ detection | `video-params`, `track-list` metadata |
| Frame rate | `estimated-vf-fps`, `container-fps` |
| Video codec | `current-tracks/video/codec` |
| Audio codec, channels, sample rate | `current-tracks/audio`, `audio-params` |
| Passthrough active | `audio-codec-name` vs `audio-params/format` (spdif formats) |
| Subtitles | `current-tracks/sub` |
| Hardware decoding | `hwdec-current` |
| Dropped frames | `frame-drop-count`, `decoder-frame-drop-count` |
| Buffer, bitrate | `demuxer-cache-duration`, `video-bitrate`, `audio-bitrate` |
| Volume, mute | `volume`, `mute` |
| Audio devices | `audio-device-list`, `audio-device` |
| Display connector | `display-names` |
| Display refresh | `display-fps` |
| HDR output active | `video-target-params` |
| Frame timing health | `vo-delayed-frame-count`, `mistimed-frame-count`, `vsync-jitter` |
| Measured vs specified refresh | `estimated-display-fps`, `display-fps` |

---

## 7. Output detection

### Audio

1. `audio-device-list` gives PipeWire device names and descriptions.
2. Run `pw-dump` via `mp.command_native({name = "subprocess", ...})` when the device list changes (not on a timer) to read each node's `device.bus` (`bluetooth`, `pci`, `usb`) and, for Bluetooth, `api.bluez5.codec` (SBC, AAC, aptX, LDAC).
3. Classify: `bluetooth` → Bluetooth, `usb` → USB audio, a digital display output → match it to the display connector (`HDMI-A-*` → HDMI, `DP-*` → DisplayPort or USB-C), otherwise built-in. Linux audio labels DisplayPort audio as "HDMI", so never use the audio name to decide the connection type.
4. Fall back to name matching (`bluez` for Bluetooth) if `pw-dump` is unavailable.

### Display

1. `display-names` gives the connector the window is on (`HDMI-A-1`, `DP-2`, `eDP-1`).
2. USB-C detection: check `/sys/class/typec/*/` for a partner with an active DisplayPort alt mode. If found and the connector is `DP-*`, label it USB-C. Otherwise label it DisplayPort. This is a best-effort heuristic.
3. HDR state from `video-target-params` (transfer function PQ or HLG means HDR output is active).

---

## 8. Default mpv configuration

```ini
# config/mpv.conf
vo=gpu-next
gpu-api=vulkan
hwdec=auto-safe
target-colorspace-hint=yes
tone-mapping=auto

# Time video to the audio clock (mpv's default). Phase 0 showed
# display-resample badly hurts smoothness on screens with unsteady refresh
# timing: 237 dropped frames in 59 seconds versus 1 in 74 seconds.
video-sync=audio

# audio
audio-channels=auto
# audio-spdif is set per device by the output menu, not globally

# behavior
keep-open=yes
save-position-on-quit=yes
osd-bar=no
```

Passthrough: when the user selects a receiver or other device that supports it, set `audio-spdif=ac3,eac3,dts,dts-hd,truehd`. For Bluetooth and built-in devices, clear it. Persist per-device choices in `~/.config/visual-player/devices.json`.

---

## 9. Key bindings

| Key | Action |
|---|---|
| Space | Play/pause |
| Left / Right | Seek 5s |
| Up / Down | Volume |
| M | Menu (chapters, playlist) |
| I | Toggle info panel |
| C | Cycle subtitles |
| A | Cycle audio tracks |
| O | Open output popup |
| R | Rotate video |
| F, F11, Alt+Enter, double-click | Fullscreen |
| Esc | Close popup, then exit fullscreen |

---

## 10. Packaging

The app is architecture-independent (Lua, config, fonts, desktop file), so both packages are `noarch`/`any` and depend on the system mpv.

### Shared install layout (Makefile `install` target)

| Path | Contents |
|---|---|
| `/usr/bin/vplay` | launcher |
| `/usr/share/visual-player/config/` | `mpv.conf`, `input.conf` |
| `/usr/share/visual-player/scripts/visual-player/` | the Lua script (`main.lua` and modules) |
| `/usr/share/visual-player/fonts/` | icon font (from Phase 2) |
| `/usr/share/applications/visual-player.desktop` | desktop entry with video MIME types |
| `/usr/share/icons/hicolor/scalable/apps/visual-player.svg` | app icon |

### Building locally

While the project is in development, both packages build from the source folder rather than downloading a release:

- **Omarchy:** `cd packaging/arch && makepkg -si`
- **Nobara:** `./tools/build-rpm.sh`, which creates the source archive `rpmbuild` needs from the latest commit, then builds the RPM. Only committed changes are included.

The version number currently lives in three places that must match: `main.lua`, the PKGBUILD, and the spec.

### Omarchy (Arch)

`packaging/arch/PKGBUILD`:

- `arch=('any')`
- `depends=('mpv' 'pipewire')`
- `optdepends=('wireplumber: output device detection')`
- Build and install with `makepkg -si`.
- Later: publish to the AUR.

### Nobara (Fedora)

`packaging/fedora/visual-player.spec`:

- `BuildArch: noarch`
- `Requires: mpv, pipewire-utils`
- Build with `rpmbuild -ba`, install with `sudo dnf install ./visual-player-*.noarch.rpm`.
- Later: Fedora COPR repo for automatic updates.

### Minimum mpv version

**mpv 0.41 or newer.** Confirmed in Phase 0 on Nobara 44, where 0.41 provides HDR output on GNOME and the `begin-vo-dragging` command. Omarchy (Arch) also ships 0.41, confirmed in Phase 0.

### Future options

Flatpak (for sharing with others) once the core is stable. Expect extra work for HDR, PipeWire passthrough, and NVIDIA GL extensions inside the sandbox.

---

## 11. Code readability

The code should read like plain English. Someone opening any file, including you months from now, should understand what it does and why without having to decode it. Readability wins over cleverness and brevity every time.

### Naming

- Use full, descriptive words. `is_passthrough_active`, not `pt` or `isPT`.
- Name functions for what they do, as a verb phrase: `show_info_panel()`, `switch_audio_device(device)`, `format_time_remaining(seconds)`.
- Name booleans as yes/no questions: `is_paused`, `has_subtitles`, `should_show_controls`.
- Name values with their units: `hide_delay_seconds`, `panel_width_pixels`, `refresh_interval_ms`.
- No single-letter names except loop counters, and prefer `for index, device in ipairs(devices)` over `for i, d`.
- Avoid abbreviations unless they are the everyday term (`hdr`, `hdmi`, `url` are fine; `dev`, `cfg`, `btn` are not).

### Structure

- Keep functions short and focused on one job. If a function needs a comment explaining a section inside it, that section should probably be its own well-named function.
- Prefer simple, flat logic. Use early returns instead of deeply nested `if` blocks.
- No magic numbers. Put them in named constants at the top of the file:

```lua
-- How long the controls stay visible after the mouse stops moving.
local HIDE_CONTROLS_AFTER_SECONDS = 2

-- How often the info panel refreshes. Faster makes numbers flicker.
local INFO_PANEL_REFRESH_SECONDS = 1
```

- One file per UI element or concern, matching the project structure in section 4.

### Comments

- Every file starts with a short plain-English summary of what it is responsible for.
- Every function has a one-line comment describing what it does, in a sentence, if the name alone doesn't make it obvious.
- Comments explain **why**, not **what**. The code already says what it does.

```lua
-- Bad: set spdif
mp.set_property("audio-spdif", "truehd,eac3,dts-hd")

-- Good: Receivers decode Atmos themselves, so send the untouched
-- bitstream over HDMI instead of decoding it here.
mp.set_property("audio-spdif", "truehd,eac3,dts-hd")
```

- Explain anything surprising: workarounds, platform differences between GNOME and Hyprland, and mpv quirks, with a link to the relevant mpv documentation or issue where possible.
- Write comments as full sentences with normal capitalization and punctuation.

### Example of the target style

```lua
-- Works out a friendly label for the audio output chip,
-- such as "HDMI", "LDAC", or "Speakers".
local function describe_audio_output(device)
    if device.connection == "bluetooth" then
        -- Showing the codec tells the user how good the sound is.
        return device.bluetooth_codec or "Bluetooth"
    end

    if device.connection == "hdmi" then
        return "HDMI"
    end

    return "Speakers"
end
```

### Messages shown to the user

- Write in plain language, not jargon: "Stereo downmix" rather than "PCM 2.0 via ao_pipewire."
- Error messages say what happened and what to do next: "Couldn't find your receiver. Check that it's turned on and connected over HDMI."

### Consistency

- Format all Lua with StyLua using one shared config, so every file looks the same.
- Lint with luacheck to catch unused variables and typos.
- Keep the README, this plan, and code comments in the same plain, friendly tone.

---

## 12. Milestones

### Phase 0 — Spike (validate the architecture)

- [x] Confirm mpv version on Nobara (0.41.0).
- [x] Confirm mpv version on Omarchy (0.41.0).
- [x] Enable HDR in GNOME display settings.
- [x] Hyprland HDR: not applicable, the Framework 13 screen is SDR. Test later with an external HDR monitor.
- [x] Nobara: HDR output engages for HDR10, HLG, and Dolby Vision (with and without HDR10 fallback).
- [x] Omarchy: HDR files tone-map to SDR correctly and look great, including Dolby Vision profile 5.
- [ ] Test TrueHD, E-AC-3, and DTS-HD passthrough to a receiver with `audio-spdif` (untested: no receiver connected yet).
- [x] Nobara: `display-names` returns connector names (`eDP-1`).
- [x] Omarchy: `display-names` returns connector names (`eDP-1`).
- [x] Draw a test button via ASS and confirm hover, click hit-testing, and window dragging work on both machines. (Icon font deferred to Phase 2.)

### Phase 0 findings (Nobara)

Tested on Nobara 44 GNOME (Wayland), kernel 7.2, mpv 0.41.0, on a hybrid laptop with an NVIDIA RTX 4050 and an AMD Radeon 890M. Test files: Dolby Art, CableLabs Life Untouched, 7ENSATION Amazing Jellyfish 8, Dolby Blocks, and Barco Stinger Bees.

- **HDR works on GNOME.** mpv sent a PQ signal with BT.2020 primaries for every HDR file, and pictures looked correct, including Dolby Vision profile 5 (Blocks) with no HDR10 fallback. The biggest architectural risk is cleared.
- **Hardware decoding works** through Vulkan video decoding (`hwdec-current = vulkan`) for 4K HEVC 10-bit.
- **SDR content is sent inside an HDR signal when GNOME's HDR mode is on**, and it looked normal. So the info panel must label the file's format from `video-params` (the source), never from `video-target-params` (the output), or every SDR file would read as HDR.
- **mpv can't see PipeWire downmixing.** On stereo laptop speakers, `audio-out-params` still reported 7.1 because PipeWire downmixes after mpv. The "Stereo downmix" warning must come from the PipeWire sink's channel count (via `pw-dump`), not from mpv.
- **Friendlier HDMI names are available.** One device list names the port "Radeon High Definition Audio Controller Digital Stereo (HDMI 4)", while ALSA reports the connected monitor's own name ("PX277OLEDMAX") from its EDID/ELD data. The output popup should prefer the monitor or receiver's name.
- **Dolby Vision isn't visible in `video-params`**, which only describes the HDR10 base layer. Detect Dolby Vision from the track metadata in `track-list` instead (Phase 3).
- **A few dropped frames at startup are normal** (2 on the first file). Only a count that keeps rising should turn the status line amber.
- **Hybrid graphics:** decoding worked, but the info panel's Decode row should eventually show which GPU is in use, since that can differ between the laptop screen and external monitors.

### Phase 0 findings (button test, both machines)

- **Drawing, hover, clicks, and dragging all work** on GNOME and Hyprland, using an `ass-events` overlay sized to `osd-dimensions` and mouse coordinates from `mouse-pos`. Hover lined up exactly with the pointer, so no scaling correction is needed.
- **Dolby Vision profile 7 plays as its HDR10 base layer.** mpv reports that the enhancement layer isn't supported. The info panel should say "Dolby Vision (HDR10 base layer)" for profile 7 files rather than claiming full Dolby Vision.
- **Files often carry several audio tracks** (Art has TrueHD 7.1, E-AC-3 7.1, and AC-3 5.1). Idea for Phase 4: when the current output can't pass the default track through, offer or automatically pick the best track it can.
- **People expect Alt+Enter and double-click for fullscreen**, not only `f`.

### Phase 0 findings (frame timing, Nobara)

Investigated dropped frames on Art (4K, 60 fps) using mpv's stats overlay.

| Screen | Timing mode | Output drops | VSync jitter |
|---|---|---|---|
| Built-in 60 Hz (eDP-1) | default | 17 in 40 s | about 0.15 |
| Built-in 60 Hz (eDP-1) | display-resample | 17 in 74 s | 0.147 |
| Built-in 60 Hz (eDP-1) | display-resample, fast profile | 19 in 37 s | not measured |
| External 240 Hz OLED (DP-3), VRR off | display-resample | 237 in 59 s | 0.546 |
| External 240 Hz OLED (DP-3) | default | 1 in 74 s | not applicable |

- **The GPU is not the bottleneck.** Frames rendered in 1.3 to 3.6 ms on average, well under the time available, decoding had zero drops, and the lighter `fast` profile didn't help.
- **Drops come from unsteady refresh timing** reported by the compositor. The 240 Hz monitor measured about 219 Hz instead of 240, with high jitter even with VRR off.
- **Decision: use mpv's default timing (`video-sync=audio`).** `display-resample` depends on steady refresh timing and made things far worse where timing was unsteady. Possible later improvement: switch to `display-resample` automatically only when jitter is low.
- **The status line can explain drops accurately.** High render times mean "GPU can't keep up"; low render times with rising mistimed or delayed counts mean "screen timing is uneven". The plain-language message should say which.
- **The built-in 60 Hz panel drops about one frame every two seconds** on 60 fps content. That's a trait of the panel's timing, not the player.
- **DisplayPort audio is named "HDMI" by Linux audio.** The PX277OLEDMAX on `DP-3` appears as an "HDMI" audio device. The output chip must take the connection type from the display connector, never from the audio device name.
- **HDR works on the external monitor too** (PQ output on DP-3).
- **People also press F11 for fullscreen.**

### Phase 0 findings (Omarchy)

Tested on Omarchy (Arch, Hyprland on Wayland) with mpv 0.41.0 on a Framework 13 with an SDR screen, using the same five test files.

- **Tone mapping works well.** With no HDR display, mpv converted every HDR file to SDR, and the picture looked excellent. Dolby Vision profile 5 (Blocks) had correct colors, so Dolby Vision is handled properly even without HDR output.
- **Hardware decoding works, through VA-API** rather than Vulkan as on Nobara. The player must not assume a particular decoding method; the info panel should report whatever `hwdec-current` says.
- **Display names and window dragging work under Hyprland**, so the drag-to-move title bar works on both desktops.
- **"HDR output active: NO" is the correct result on an SDR screen.** In the app, this should read as "Tone mapped to SDR", not as a warning.

### Phase 1 — Skeleton

- [x] StyLua and luacheck configs added; readability rules from section 11 apply from the first commit.
- [x] Repo layout, launcher, shipped config, key bindings, desktop file, placeholder icon.
- [ ] PKGBUILD and spec file installing the skeleton, via a shared Makefile.
- [x] Script loads, observes properties, logs state.

### Phase 1 findings

- **Properties are empty or half-filled before a file finishes loading.** The script ignores changes until `file-loaded`, then reads every value once, since mpv only reports changes and some values were set earlier.
- **mpv reports the transfer as `auto` until it knows it,** which briefly looked like "SDR" on HDR files. Unknown values are now skipped, not guessed.
- **Dragging a window between screens fires hundreds of screen changes** (284 in one drag). Anything that reacts to the current screen must wait for it to settle, currently for 1 second.
- **A window left spanning two screens drops frames** (11 in 55 seconds versus 1 when fully on one screen). This likely explains part of the earlier 240 Hz timing trouble. Idea for later: a gentle hint when the window straddles two screens.
- **Cycling audio tracks includes "no audio".** The track picker should show this clearly as "Off".

### Phase 2 — Core controls

- [x] Step 1: drawing toolkit (`draw.lua`), screen scaling (`screen.lua`), redraw limiting (`redraw.lua`), icon and text fonts, temporary test card.
- [x] Step 2: top bar (`top_bar.lua`, `pointer.lua`) with title, subtitle, clock, drag-to-move, double-click to maximize, GNOME window buttons. Smallest window size of 240p (`window_size.lua`). Required on GNOME: Nobara's mpv is built without libdecor, so mpv draws no title bar there.
- [x] Step 3: playback row (`playback_row.lua`) inside the bottom area (`bottom_controls.lua`), with shared click handling (`click_area.lua`) and shared colors (`style.lua`). mpv's own controls turned off (`osc=no`).
- [x] Step 4: seek bar (`seek_bar.lua`) with chapter sections, scrubber, click and drag seeking (fast keyframe seeks while dragging, an exact seek on release, at most 20 a second), and a hover preview of the time and chapter.
- [x] Step 5: tools row (`tools_row.lua`): subtitles, menu, info, rotate, settings, output chip, and volume with a slider that expands on hover. Menu, settings, and the output chip show a note until their panels arrive; info shows mpv's stats overlay until Phase 3.
- [x] Step 6: auto-hide and fade (`visibility.lua`), `border=no`, pointer hiding in step with the controls, temporary test card removed. Version 0.2.0.

Phase 2 complete: version 0.2.0 installed as a package and confirmed on both Nobara (GNOME) and Omarchy (Hyprland).

### Phase 2 findings

- **Redraw through the limiter, never directly.** Redrawing a detailed overlay on every window-size change dropped 141 to 227 frames per clip during resizes, because it kept mpv's main thread busy. GPU render time stayed low (about 3 ms), so the cost was on the CPU side. Combining redraw requests to at most 30 a second (`redraw.lua`) cut this to about 28 frames even while resizing continuously.
- **Only redraw when something visible changes.** Mouse movement fires constantly, so interface parts compare their new state with the old before asking for a redraw.
- **Bundle fonts; don't rely on system defaults.** Nobara's default font is a variable Noto Sans, which mpv's text renderer drew with oddly small digits. Visual Player now ships Inter (regular and bold, OFL licensed) as `osd-font`, downloaded by `tools/update-text-font.py`.
- **Keep licenses out of `fonts/`.** mpv tries to load every file in the fonts folder as a font, so licenses live in `licenses/`.
- **For fades, blur one shape instead of stacking strips.** Stacked strips show thin seams where they meet, however many there are. A single rectangle with a blurred bottom edge fades smoothly and cost no noticeable extra.
- **The interface scales with the window's height,** relative to 1080 pixels, like mpv's own controls. Scaling only by the desktop's HiDPI setting left everything tiny in large windows.
- **Hover highlights must be strong (45% white).** In HDR, mpv draws the interface at "paper white" brightness while the video can be far brighter, so 15% and even 28% nearly vanished over bright scenes. Shared colors and strengths now live in `style.lua`.
- **Icons need per-icon centering.** mpv's text renderer centers a character by its spacing and line height, not its visible shape, so icons sat slightly off-center in their hover circles. `tools/update-icon-font.py` now measures each icon's shape with fontTools and stores a correction in `icons.lua`, which `draw.icon` applies.
- **Turn off mpv's `window-dragging`.** By default, pressing and dragging anywhere on the window moves it, which grabs the mouse before Visual Player's controls see the movement, so seek bar dragging didn't work. Anything draggable (seek bar, volume slider) depends on `window-dragging=no`. The top bar moves the window itself with `begin-vo-dragging`.
- **While dragging, draw the handle at the pointer, not at playback.** Playback only catches up after each seek, and keyframe seeks land up to a couple of seconds away, so a handle that followed playback jumped and lagged.
- **For smooth scrubbing, send the next seek only when the last one finishes** (mpv's `playback-restart` event), always to the pointer's latest position. Seeking on a fixed timer made mpv discard half-decoded 4K frames. While dragging, redraws run at up to 60 a second.
- **Keep expensive, rarely changing drawings on their own layer.** The blurred background sits on a canvas underneath (`layer = -1`) and only redraws when the window size changes, so frequent redraws of the controls on top stay cheap.
- **Lift subtitles above the controls while they're showing.** mpv doesn't know about Visual Player's controls, so subtitles sat behind them. `bottom_controls.lua` sets `sub-pos` to just above the controls while they're visible and puts it back when they hide, never lower than the person's own setting.
- **Never loop over a list that might have gaps.** Lua's `ipairs` stops at the first missing value. It blanked details lines, and showed a stereo monitor as "Full 7.1" when mpv briefly had no channel count while switching outputs. Check optional values one by one, or loop to `table.maxn`.
- **The output popup is only about sound.** A screen line under the sound device's name read as if it described that device, so it was removed; the info panel's Screen row covers the picture.
- **Move subtitles above the controls while they show.** mpv places subtitles near the bottom, right where the controls are. `bottom_controls.lua` sets `sub-pos` to just above the playback row while the controls are visible, and restores the original value when they hide.
- **mpv has no minimum window size setting.** `autofit-smaller` only applies when a window opens, so shrinking below 240p is undone by a script instead.
- **mpv draws a stand-in title bar when a window has no border** (its `windowcontrols` feature). Visual Player turns it off with `script-opts-append=osc-windowcontrols=no` once its own top bar is in place.

### Phase 3 — Info panel

Findings (step 2): the video track in `track-list` reports `dolby-vision-profile` and `dolby-vision-level` (Jellyfish 8, Art 7, Blocks 5). Profile 8's variant comes from the base layer's transfer (PQ is 8.1, HLG is 8.4, SDR is 8.2), but only while mpv isn't applying Dolby Vision: when it is, `video-params` shows `colormatrix dolbyvision` and PQ, so the original curve is gone and the panel says just "Profile 8" (found in Phase 4, step 2). mpv reports nothing about HDR10+, so HDR10+ files honestly show as HDR10 until it does. Most MKV files carry an average bitrate in their track metadata (`BPS`, from mkvmerge's statistics), usable for local files in step 4.

- [x] Step 1: panel shell (`info_panel.lua`, with the wording in `info_details.lua`), docked to the right edge below the clock, toggled by the info button and the `I` key, with the four grouped rows from section 5.5 filled from mpv properties. Replaces the temporary stats overlay on the info button.
- [x] Step 2: HDR format detection: HDR10, HDR10+, HLG, and Dolby Vision, including its profile, described honestly (profile 7 as "Dolby Vision (HDR10 base layer)"). Always from the source, never the output.
- [x] Step 3: status line with plain-language states: green "Playing smoothly", amber when frames drop, red when buffering, with the technical line telling apart "graphics can't keep up" (high render times) from "screen timing is uneven" (low render times, rising mistimed or delayed frames).
- [x] Step 4: rows adapt to the file (local files show container and recorded bitrate; streams show format, live bitrate, and buffer): hide rows that don't apply (no subtitles, audio only), show container instead of bitrate for local files, "Tone mapped to SDR" as a normal state on SDR screens, and refresh at most once a second.

Phase 3 complete: version 0.3.0, info panel confirmed on Nobara.

### Phase 4 — Outputs

Findings (step 1, Nobara): PipeWire reports each output's `audio.channels` (2 for both the laptop speakers and the monitor's port, whose profile is "Digital Stereo"), `device.api`, and `device.bus`. A connected screen's own report in `/proc/asound/card1/eld#0.3` gives `monitor_name PX277OLEDMAX` and `connection_type DisplayPort`, matching PipeWire's `hdmi-stereo-extra3` (card 1, port 3). This is how DisplayPort audio is told apart from HDMI, despite Linux naming both "HDMI". mpv's "auto" output is resolved through PipeWire's `default.audio.sink` metadata.

- [x] Step 1: audio output detection (`outputs/audio.lua`): kind (Bluetooth, HDMI, DisplayPort, USB, speakers), name from the screen's report, Bluetooth codec, and channel count, via `pw-dump` in the background when outputs change. Feeds the output chip.
- [x] Step 2: downmix and passthrough reporting, comparing the file's channels with the fewest along the way (what mpv sends and what the output accepts), shown on a new Output row in the info panel.
- [x] Step 3: display details (`outputs/display.lua`) on a new Screen row: the screen's name from its EDID, connection (HDMI, DisplayPort, or USB-C DisplayPort when confirmed), resolution, refresh rate, and HDR state.

  Findings (step 3, Nobara): EDID files in `/sys/class/drm/card1-DP-3/edid` report a size of 0 but contain 384 readable bytes. mpv provides `display-width` and `display-height`, but they gave 3340×3240 on the 2880×1620 laptop screen, so the native resolution is read from the connector's `modes` file instead (first line). Also, with `window-dragging=no`, mpv ignores `begin-vo-dragging` too, so the top bar switches `window-dragging` on only while the pointer is over it. The laptop's USB-C port 1 has a partner connected but lists no alternate modes, so USB-C DisplayPort can't be confirmed there; the Screen row then says just "DisplayPort" rather than guessing.
- [ ] Step 4: output popup (`output_popup.lua`, slim design above the playback row): current output with a colored sound-path line, and every output with a check on the current one; clicking one switches to it. Opened from the chip or `o`; closed by clicking outside, the chip, or Esc.
- [ ] Step 5: passthrough per device, remembered between sessions. Needs a receiver to test.

### Phase 5 — Menus and polish

- [ ] Picture-in-picture: one key or button shrinks the window to about a quarter of the screen's width in a corner and keeps it on top (mpv's `ontop`), with a minimal interface of play/pause, return to full size, and close. The 240p minimum still applies.

- [ ] Subtitle and audio track pickers.
- [ ] Chapters and playlist menu.
- [ ] Settings menu (hwdec, passthrough formats, auto-hide delay, UI scale).
- [ ] Rotation with confirmation.
- [ ] Animations (fade in/out) kept subtle.

### Phase 6 — Release

- [ ] Test matrix (section 13) passes on both machines.
- [ ] Publish AUR package and COPR repo.
- [ ] README with screenshots and install instructions.

---

## 13. Test matrix

| Case | Nobara (GNOME) | Omarchy (Hyprland) |
|---|---|---|
| HDR10 file, HDR display | Pass | Not available (SDR screen) |
| HDR10 file, SDR display (tone mapping) | | Pass |
| HLG file, HDR display | Pass | Not available (SDR screen) |
| HLG file, SDR display (tone mapping) | | Pass |
| SDR file, HDR display (looks normal) | Pass | Not available (SDR screen) |
| Dolby Vision profile 5 and 8 | Pass | Pass |
| 4K AV1 hardware decode | | |
| TrueHD Atmos passthrough over HDMI | | |
| Bluetooth headphones (codec shown, downmix shown) | | |
| USB-C DisplayPort monitor | | |
| External 240 Hz HDR monitor (DP) | Pass (HDR, 1 drop in 74 s) | |
| Built-in display and speakers | Pass | Pass |
| Device hot-plug during playback | | |
| Window drag, resize, fullscreen | | |
| Audio-only file (rows hidden) | | |
| HLS stream (buffer and bitrate shown) | | |

---

## 14. Risks and open questions

- **HDR on GNOME:** resolved. Confirmed working on Nobara 44 with mpv 0.41 in Phase 0.
- **Passthrough through PipeWire:** can be device-dependent. Keep an ALSA direct-output option in settings as a fallback.
- **Dolby Vision:** mpv handles profiles 5 and 8 well. Profile 7 (dual-layer) plays its HDR10 base layer only, confirmed in Phase 0. Label accurately rather than overpromise.
- **OSD UI complexity:** building menus with ASS is more manual than a GUI toolkit. Mitigate by studying uosc's rendering and hit-testing approach.
- **USB-C detection:** heuristic only. Fall back to "DisplayPort" when uncertain.
- **Hybrid graphics (NVIDIA plus AMD):** Vulkan decoding works on Nobara. Still to test: playback on an external monitor wired to the NVIDIA GPU, where a different GPU may handle decoding.
- **Passthrough is untested** until a receiver or soundbar is connected. Sending Atmos to a monitor that can't decode it produces silence or noise, so the app should only offer passthrough for devices that report support for those formats.
- **Name:** "Visual Player" is a common phrase, so search visibility will be limited. Before publishing, check the AUR, Fedora packages, and Flathub for existing `visual-player` or `vplay` packages or commands.
