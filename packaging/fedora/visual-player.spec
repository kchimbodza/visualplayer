# Builds Visual Player for Fedora and Nobara.
#
# Don't run rpmbuild on this directly; use tools/build-rpm.sh, which
# prepares the source archive rpmbuild needs first.

Name:           visual-player
Version:        0.1.0
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
* Fri Sep 25 2026 myviewsontech - 0.1.0-1
- First package: launcher, settings, key bindings, and starter script
