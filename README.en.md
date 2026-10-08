<p align="center">
  <img src="icon.png" width="128" height="128" alt="SoundPin icon">
</p>

<h1 align="center">SoundPin</h1>

<p align="center">
  Keep your Mac on the audio devices you chose.<br>
  A menu bar utility that prevents unwanted default device switches.
</p>

<p align="center">
  <a href="https://github.com/realruian/SoundPin/releases/latest"><img src="https://img.shields.io/github/v/release/realruian/SoundPin?style=flat&color=blue" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%26%20Intel)-brightgreen" alt="Universal Architecture">
  <img src="https://img.shields.io/badge/Swift-5-orange?logo=swift" alt="Swift 5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

<p align="center">
  <a href="README.md">简体中文</a> · English
</p>

<p align="center">
  <img src="screenshot-en.png" width="364" alt="SoundPin Panel Screenshot">
</p>

---

## Why

macOS does not offer a way to lock default audio input and output devices. When AirPods connect, the system automatically redirects the microphone to the headset. Connecting an external monitor or a dock often redirects audio output to monitor speakers unexpectedly.

SoundPin maintains priority lists for speakers, headphones, and microphones. Whenever a device connects or disconnects, or when macOS or another app changes the default device, SoundPin automatically switches back to the highest-ranked available device.

## Features

- **Priority-based switching**: Automatically routes audio to the highest-ranked connected device, and restores it when changed by other apps.
- **Separate headphone and speaker lists**: Routes to headphones when connected, and returns to desktop speakers when disconnected. Display audio (HDMI/DisplayPort) is filtered so it is never mistaken for headphones.
- **Click to promote**: Clicking any connected device selects it immediately and moves it to the top of its priority list.
- **Scroll wheel volume control**: Hover over the volume slider and scroll to adjust the volume.
- **System-style panel**: Designed after the macOS Sound menu. The menu bar icon reflects volume level, mute state, and connected headphone models.
- **Offline device memory**: Disconnected devices remain in the list with last-seen timestamps, allowing you to organize priorities ahead of time.
- **Lightweight and private**: Driven by CoreAudio hardware event notifications with no polling. Requires no microphone recording permissions, makes no network requests, and collects no telemetry.
- **Keyboard and VoiceOver support**: Full VoiceOver support for reading device states and actions, plus Tab/Space navigation on macOS 14+.
- **Bilingual interface**: Supports English and Simplified Chinese, matching the system language by default.

## Installation

Compatible with Apple Silicon and Intel Macs running macOS 13 or later.

### Download

1. Download the latest `.dmg` from [Releases](https://github.com/realruian/SoundPin/releases/latest).
2. Open the disk image and drag `SoundPin` into Applications.
3. On first launch, if macOS warns that the developer cannot be verified, open System Settings > Privacy & Security and click Open Anyway. You can also remove the quarantine attribute via Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/SoundPin.app
   ```

**Upgrading from 2.1 or earlier (Audio Priority Bar)**:  
The app was renamed to SoundPin in version 2.2 with a new bundle identifier. Remove the old `AudioPriorityBar` from Applications after installing. Settings and priority orders migrate automatically on first launch; Open at Login should be re-enabled from the menu.

### Build from source

Requires Xcode Command Line Tools:

```bash
git clone https://github.com/realruian/SoundPin.git
cd SoundPin
./install.sh
```

`install.sh` builds a universal binary, installs it to `/Applications/SoundPin.app`, and opens it.

## Usage

SoundPin runs in the menu bar as a speaker icon:

| Action | Result |
|---|---|
| Click a device | Selects it and moves it to the top of its category |
| Drag a device | Reorders priorities |
| Scroll on volume slider | Adjusts output volume |
| Keyboard (macOS 14+) | With Keyboard Navigation on, press Tab to focus and Space/Return to select |
| Device ⋯ menu | Ignore device, never auto-select, or move between headphones and speakers |
| Top-right ⋯ menu | Toggle auto-switching, open at login, edit device list, switch language, quit |
| Edit Device List | Displays disconnected devices for reordering or removing |
| Sound Settings… | Opens macOS Sound settings |

When automatic switching is paused, an "Auto-Switch Paused" indicator appears in the header. Click it to resume.

## How it works

- **Device observation**: Uses CoreAudio C APIs (`AudioObjectAddPropertyListenerBlock`) to observe hardware changes and default device changes without polling.
- **Persistent storage**: Priorities are saved by device hardware UID in local preferences (`io.github.realruian.SoundPin`), preserving order across reconnects and reboots.
- **Device categorization**: Uses hardware transport types (`kAudioDevicePropertyTransportType`) and brand keywords to distinguish headphones from speakers.

Read local preferences:
```bash
defaults read io.github.realruian.SoundPin
```

## Known limitations

- **Less common Bluetooth headphones**: Earbuds not matching the built-in keyword database may land in the speakers list initially. Select "Move to Headphones" from the device menu to fix this permanently.
- **AirPlay**: Disconnected AirPlay destinations do not appear in the list.
- **Bluetooth pairing**: Manages already-connected audio devices and does not initiate Bluetooth discovery or connection.

## Uninstall

Quit the app from the menu, then run:

```bash
rm -rf /Applications/SoundPin.app
defaults delete io.github.realruian.SoundPin
```

## Development

The repository includes helper scripts:

- `tools/render-preview.sh [output.png] [--demo] [--lang en|zh-Hans]`: Renders offline panel previews via SwiftUI without physical device changes.
- `tools/check-devices.sh`: Tests device classification and icon rules against sample devices.
- `tools/check-settings.sh`: Checks how devices are remembered and marked "never select automatically", in a settings domain of its own.
- `tools/check-events.sh`: Checks that a burst of device notifications is handled once, using test devices only this process sees.
- `tools/check-voiceover.sh [--lang en|zh-Hans]`: Reads the panel's accessibility information without turning VoiceOver on and runs one row action (the terminal needs Accessibility permission).
- `tools/make-dmg.sh`: Builds a universal release binary and packages a DMG.

## Credits

Based on [tobi/AudioPriorityBar](https://github.com/tobi/AudioPriorityBar). Versions up to 2.1 retained the original name; the project was renamed to SoundPin starting in version 2.2.

Changes from the original:
- Redesigned interface following the macOS Sound menu;
- Clicking a device selects and promotes it to the top (original ignored clicks during auto mode);
- Scroll wheel support on the volume slider;
- Native bilingual interface (English and Simplified Chinese);
- Dynamic menu bar icon reflecting volume, mute, and headphone model;
- Transport type filtering preventing HDMI and DisplayPort from being classified as headphones;
- Offline device caching with recency timestamps;
- Full VoiceOver and keyboard navigation support;
- Layout fixes for modern macOS releases.

## License

[MIT](LICENSE)
