# PiSky for iOS

Native **SwiftUI** port of the PiSky Android app — a read-only dashboard for a home PiAware /
Ultrafeeder ADS-B receiver. Targets **iOS 17+** (iPhone 11 Pro Max and up; universal iPhone/iPad).

This was ported from the Kotlin/Jetpack-Compose Android source (`piaware-android`, 19 modules,
~29 K LOC). See [`docs/`](docs/):

- [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the source app's architecture, data contract, screens.
- [`ANDROID_TO_IOS_MAPPING.md`](docs/ANDROID_TO_IOS_MAPPING.md) — every component's iOS equivalent + Canvas math.
- [`PORTING_NOTES.md`](docs/PORTING_NOTES.md) — what can't port 1:1 and the substitute used.

## Build (on a Mac — iOS requires Xcode)

```sh
brew install xcodegen
cd pisky-ios
xcodegen generate          # creates PiSky.xcodeproj from project.yml
open PiSky.xcodeproj
```

Then in Xcode: set your **Development Team** (Signing & Capabilities), build to the device.
Before the first build, drop in two resources (see [`PORTING_NOTES.md`](docs/PORTING_NOTES.md) §"What you must do"):
the three font families (`Resources/Fonts/`) and `us_military_aircraft.csv` (`Resources/`). The app
falls back to system fonts if the `.ttf`s are absent.

> The original Windows dev box can't compile Swift — code is authored here, generated + built on a Mac.

## Layout

```
PiSky/
  App/            app entry, AppContainer (DI), root navigation
  DesignSystem/   Hangar Luxe palette/typography/dimensions + Canvas component toolkit
  Domain/         models, enums, classifier + data tables, RF/integrity logic, repository protocols
  Network/        Codable DTOs, URLSession APIClient, DTO→domain mappers, Prometheus parser
  Data/           SwiftData persistence, preferences (UserDefaults/Keychain), repository actors, notifications
  Features/       one folder per screen-family (Atlas, Map, Aircraft, PFD, Radar, Signal, …, Settings)
  Resources/      Info.plist, assets, fonts, mil CSV
```

## Connection

Defaults to `http://192.168.1.207:8088` (the `nginx` front door for the receiver). Change it in
Settings, or use Onboarding's mDNS auto-discover. LAN-only; no cloud, no account.
