# Canyon Vigil for Mac

A native macOS app for the Canyon Vigil CND-SGM02RGB mouse with USB ID `093a:2533`.
Built from protocol information recovered from the original Windows installer.

Open **dist/Canyon Vigil.app**, click **Read mouse**, edit the settings, then click
**Apply to mouse**. It reads the device automatically at launch. No Windows drivers,
kernel extensions, or third-party runtimes are installed.

## Supported

- Four DPI profiles, 200–3200 DPI in increments of 200, and active profile selection.
- The mouse's 16 built-in color presets, lighting modes, and animation speed.
- Polling rates: 125, 250, 500, 1000 Hz.
- Top DPI button: DPI cycling, lighting switch, media actions, and several mouse actions.
- Mac shortcuts for middle and side buttons while the app runs. These affect all
  connected mice. They require Accessibility permission, requested only when you
  click Enable Mac shortcuts. Shortcuts are stored in macOS preferences.
- JSON profile import/export and a backup before every Apply.

The previous hardware profile is saved to
`~/Library/Application Support/CanyonVigilMac/before-last-apply.json`.
The first pre-Apply profile is retained as `first-connected-profile.json`.
Use Profiles → Load previous settings, then Apply, to restore the last backup.

The Apply operation updates changed documented fields, then reads the hardware
back and compares the result. If a request fails, the app reports failure; a
partial change may already have happened. Read the mouse again before retrying.

## Current limits

Hardware reading has been tested on the connected mouse. Physical write behavior
and interactive button shortcuts still need user testing. Built-in color presets
are numbered because their exact colors have not been confirmed. Arbitrary RGB,
recorded macros, launch-at-login, and per-device Mac shortcut filtering are not
implemented. The left and right buttons keep their normal behavior. Keyboard
shortcuts can vary between apps or macOS keyboard settings.

This is an experimental app, ad-hoc signed, requiring macOS 13+.
The build script targets the architecture of the Mac that builds it. Hardware
communication has been tested on an Intel Mac; Apple Silicon is not yet tested.
It is not an official Canyon app and is not notarized for distribution.

## Build

Requires Apple's Xcode command-line tools. No package dependencies for the app.

```sh
./build.sh
./dist/'Canyon Vigil.app'/Contents/MacOS/vigilctl read
```

Run the protocol tests without accessing a physical mouse:

```sh
mkdir -p .build
clang -O2 -Wall -Wextra -Wno-deprecated-declarations Sources/protocol_tests.c \
  -framework IOKit -framework CoreFoundation -o .build/protocol_tests
.build/protocol_tests
```

The USB helper uses Apple's IOKit USB device interface, without seizing HID
interfaces. A read enters the manufacturer's sensor configuration mode, reads
the known registers, returns to bank 0, enables write protection, and exits
configuration mode. It does not write DPI, lighting, or button configuration.

## Research provenance

The supplied ZIP was unpacked as a 7-Zip self-extracting archive. The nested
Setup Factory 9.1 installer was unpacked with
[sfextract](https://github.com/CybercentreCanada/sfextract). The installed .NET
application's `MyUSBControl.USBCTL` methods were inspected as CIL with `dnfile`
and `dncil`; Windows executables were not run.

See [research/PROTOCOL.md](research/PROTOCOL.md) for the recovered commands and evidence. The downloaded
[rtt3168ctl reference](https://github.com/AzaOne/rtt3168ctl) independently describes
the same USB commands. Its code is not included in the Mac application. Original
Windows files are excluded from this repository; the Mac app does not bundle
original executables, artwork, or Windows drivers. Extraction tools and the
protocol reference are research tools, not application dependencies.

## License

The original code and documentation in this repository are available under the
[MIT License](LICENSE). This license does not cover Canyon's proprietary
software or assets. Canyon and its product names belong to their respective
owners; this project is independent and unaffiliated.
