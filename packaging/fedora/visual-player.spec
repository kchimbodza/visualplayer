# Builds Visual Player for Fedora and Nobara.
#
# Don't run rpmbuild on this directly; use tools/build-rpm.sh, which
# prepares the source archive rpmbuild needs first.

Name:           visual-player
Version:        0.6.0
Release:        1%{?dist}
Summary:        Media player for HDR video and Dolby Atmos audio, built on mpv

License:        MIT
URL:            https://github.com/kchimbodza/visualplayer
Source0:        %{name}-%{version}.tar.gz

# Visual Player is scripts and settings, so one package works on every
# processor type.
BuildArch:      noarch

BuildRequires:  make
BuildRequires:  desktop-file-utils
Requires:       mpv >= 0.41
Requires:       hicolor-icon-theme
# pw-dump, used from Phase 4 to detect audio outputs and Bluetooth codecs.
Recommends:     pipewire-utils

%description
Visual Player is a media player built on mpv. It outputs true HDR on
screens that support it, tone maps beautifully on screens that don't,
passes Dolby Atmos and DTS:X through to receivers, and always shows
plainly how your media is being played.

%prep
%autosetup

%build
# Nothing to build: Visual Player is scripts and settings.

%install
%make_install PREFIX=%{_prefix}

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{name}.desktop

%files
%license LICENSE licenses/tabler-icons.txt licenses/inter.txt
%doc README.md
%{_bindir}/vplay
%{_datadir}/%{name}/
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg

%changelog
* Sat Sep 26 2026 myviewsontech - 0.6.0-1
- Passthrough straight to the HDMI port, chosen at startup, for Dolby
  TrueHD and E-AC-3 Atmos on receivers and soundbars
- Format badges when a file starts
- Audio chip with the current track, and a notice when it changes
- Choosing an output switches the system's output too
- Volume next to the speed control
- Exact text measuring, HDMI screen names, and mpv's own seek bar
  switched off

* Sat Sep 26 2026 myviewsontech - 0.5.0-1
- Menus for audio and subtitle tracks, and for chapters and the playlist
- Settings menu with saved settings, including interface size
- Picture-in-picture
- Touch screen support, detected automatically

* Sat Sep 26 2026 myviewsontech - 0.4.0-1
- Outputs: sound and screen detection with real device names, HDMI and
  DisplayPort told apart, downmix reporting, an output popup for
  switching devices, and passthrough offered only where it works

* Sat Sep 26 2026 myviewsontech - 0.3.0-1
- Info panel: video, audio, subtitles, and a plain-language status line,
  with Dolby Vision profiles, tone mapping, and source details

* Sat Sep 26 2026 myviewsontech - 0.2.0-1
- Visual Player's own interface: top bar, playback row, chapter seek bar,
  tools row with volume slider, and auto-hide

* Fri Sep 25 2026 myviewsontech - 0.1.0-1
- First package: launcher, settings, key bindings, and starter script
