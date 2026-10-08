<p align="center">
  <img src="icon.png" width="128" height="128" alt="Audio Priority Bar icon">
</p>

<h1 align="center">Audio Priority Bar</h1>

<p align="center">
  Keep your Mac on the microphone and speakers you chose, even when AirPods connect.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

<p align="center">
  <a href="README.md">简体中文</a> · English
</p>

<p align="center">
  <img src="screenshot-en.png" width="364" alt="The Audio Priority Bar panel">
</p>

## Why

macOS has no setting that pins the input device. When AirPods connect, the system moves the microphone to them, even if a better USB microphone is plugged in. Connecting a display or a dock moves the sound output the same way.

Audio Priority Bar keeps a ranked list for speakers, headphones and microphones, and always uses the highest-ranked device that is connected. When the system or another app switches away, it switches back.

## Features

- **Priority-based switching**: when a device connects or disconnects, the highest-ranked connected device is used.
- **Switches back**: a default device changed by the system or another app is restored at once.
- **Separate lists for headphones and speakers**: headphones take over when they connect, and the top speaker returns when they leave.
- **A panel in the system's style**: laid out after the macOS Sound menu, with an icon for each kind of device.
- **A menu bar icon that follows the state**: mute, volume level, and the headphones in use.
- **Runs locally**: no network access, no recording, no microphone permission, no analytics.
- **English and Chinese**: the interface follows the system language, or the one you pick in the menu.

## Install

Runs on Apple silicon and Intel Macs with macOS 13 or later (developed and tested on macOS 27).

### Download

1. Get the latest `.dmg` from [Releases](https://github.com/realruian/AudioPriorityBar/releases/latest).
2. Open it and drag AudioPriorityBar onto Applications.
3. On first launch macOS says it cannot verify the developer, because the download is not notarized by Apple. Open System Settings > Privacy & Security and click Open Anyway near the bottom.

Instead of step 3, this command in Terminal does the same:

```bash
xattr -dr com.apple.quarantine /Applications/AudioPriorityBar.app
```

### Build from source

Requires Xcode. A build made on your own Mac is not blocked by the system.

```bash
git clone https://github.com/realruian/AudioPriorityBar.git
cd AudioPriorityBar
./install.sh
```

`install.sh` builds the app, installs it to `/Applications/AudioPriorityBar.app` and launches it. Run it again after updating the code.

The app has no window and no Dock icon, only a speaker icon in the menu bar.

## Usage

On first use, open the panel, move the devices you want to the top of each list, and turn on Open at Login in the ⋯ menu at the top right.

| Action | Result |
|---|---|
| Click a device | Selects it and moves it to the top of its list |
| Drag a device | Changes the priority order |
| Hover a device and click its ⋯ | Ignore the device, never pick it automatically, or move it between headphones and speakers |
| The ⋯ menu next to the title | Automatic switching on or off, open at login, edit the device list, language, quit |
| Edit the device list | Shows disconnected devices, to rank them ahead of time or forget old ones |
| Sound Settings… | Opens Sound in System Settings |

With automatic switching off, the app leaves the devices alone, and an orange notice next to the title says so. Click the notice to turn switching back on.

## How it works

- **Device discovery**: CoreAudio lists the audio devices and reports when devices or the default devices change.
- **Stored order**: priorities are saved in the local preferences by device UID, so they survive reconnects.
- **Switching**: on every change, the default input and output are set to the highest-ranked connected device.
- **Categories**: outputs are split into speakers and headphones, each with its own order. Headphones are recognised by brand keywords in the device name, and can be moved by hand.

Settings live in the `app.audioprioritybar` preferences domain:

```bash
defaults read app.audioprioritybar
```

## Known limitations

- **Less common Bluetooth headphones**: headphones that are not on the keyword list land under speakers and are not switched to when they connect. Click them once in the panel.
- **AirPlay**: AirPlay devices that are not connected do not appear in the list.
- **No connecting**: the app manages devices already connected to the Mac and cannot connect Bluetooth headphones for you.
- **Not included**: a mute button and AirPods noise control. Use Control Center for those.

## Uninstall

Quit the app from the ⋯ menu, then remove the app and its settings:

```bash
rm -rf /Applications/AudioPriorityBar.app
defaults delete app.audioprioritybar
```

## Development

The menu bar panel cannot be captured from outside, so the repository carries two tools for checking changes:

- `tools/render-preview.sh [output.png] [--manual-look] [--edit-look] [--demo] [--lang en|zh-Hans]` renders the panel to an image. It does not change the audio devices.
- `tools/check-devices.sh` prints which list and which icon a table of sample devices gets.

The download is made by `tools/make-dmg.sh`, which builds a universal app and packs it into a `.dmg` under `dist/`.

## Credits

This project is based on [tobi/AudioPriorityBar](https://github.com/tobi/AudioPriorityBar). The priority-switching logic is the original author's. Changes made here:

- The panel is restyled after the macOS Sound menu
- The interface is in English and Chinese, following the system language by default
- Clicking a device selects it and moves it to the top (the original ignores clicks while switching is automatic)
- The menu bar icon follows mute, volume and headphone state
- The device list no longer collapses in the menu bar panel on macOS 27
- Icons are chosen by device model and connection type
- Devices on HDMI or DisplayPort are no longer mistaken for headphones

## License

[MIT](LICENSE)
