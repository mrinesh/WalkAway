<div align="center">

# WalkAway

**A gentle break reminder that lives in your macOS menu bar.**

Every so often, WalkAway takes over your screens with a calm countdown and a nudge to stand up, stretch, hydrate, or rest your eyes. The rest of the time it stays out of your way: it pauses itself during meetings, resets when you've been away, and pauses your video when a break begins.

![macOS](https://img.shields.io/badge/macOS-15.2%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![SwiftUI + AppKit](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0A84FF)
![Menu bar app](https://img.shields.io/badge/type-menu%20bar%20app-5E5CE6)

</div>

---

## Why WalkAway

Long, unbroken stretches at a screen lead to eye strain, stiff shoulders, and slipping focus. Most break timers are easy to ignore, or they interrupt you at the worst moment. WalkAway is built to be hard to ignore when a break is due and invisible when it shouldn't bother you.

## Features

### A real break, not a notification
- **Full-screen overlay on every display** with an animated night-sky background, a large countdown, and a rotating motivational message.
- **30-second heads-up** toast before every break, so you can wrap up your thought.
- **Short and long breaks.** Short breaks can be skipped. Every **3rd break is a long one and can't be skipped**.
- **A soft chime** when the break ends.

### Smart enough to stay out of your way
- **Pauses for meetings.** Detects active **Zoom**, **Microsoft Teams**, and **Webex** calls, pauses the timer, and resumes automatically when the call ends.
- **Pauses your media.** When a break starts, whatever is playing (a YouTube video in Safari, Music, Spotify, …) is paused, so it doesn't keep running behind the overlay. Media that's already paused stays paused.
- **Resets after you've been away.** If you've been idle longer than your threshold, the cycle starts fresh when you come back, so you don't get a break the moment you sit down.
- **Handles sleep and wake.** Timers pause when your Mac sleeps and pick up where they left off.

### Comfortable to live with
- Lives in the menu bar only: no Dock icon, no windows.
- See time until the next break at a glance; pause or resume at any time.
- Optional **Launch at Login**.

## Settings

Click the walking-figure icon in the menu bar to open settings.

| Setting | Default | Range |
| --- | --- | --- |
| Break frequency | 30 min | 30–120 min |
| Short break | 30 sec | 30–180 sec |
| Long break (every 3rd break) | 5 min | 5–30 min |
| Reset after inactivity | 10 min | 5–60 min |
| Pause for meeting apps | Off | On / Off |
| Launch at Login | Off | On / Off |

## How a break cycle works

```mermaid
flowchart LR
    A[Working] -->|frequency − 30 s| B[Heads-up toast]
    B -->|30 s| C[Break overlay<br/>media paused]
    C -->|countdown ends<br/>or Skip| D[Chime]
    D --> A
    A -.->|meeting detected| P[Paused]
    P -.->|meeting ends| A
    A -.->|idle past threshold,<br/>then activity| A
```

## Getting started

### Requirements
- macOS 15.2 or later
- Xcode 16 or later

### Run from Xcode
```bash
git clone https://github.com/mrinesh/WalkAway.git
cd WalkAway
open WalkAway.xcodeproj
```
Press **⌘R**. The project is set to *Sign to Run Locally*, so you don't need an Apple Developer account.

### Install a Release build
```bash
xcodebuild -project WalkAway.xcodeproj -scheme WalkAway \
  -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/WalkAway.app /Applications/
open /Applications/WalkAway.app
```

To quit, open the menu bar popover and click **Quit WalkAway** (or press **⌘Q** while it's open).

## Privacy

- **Nothing leaves your Mac.** No network access, no analytics, no accounts.
- Settings are stored locally in `UserDefaults`.
- Meeting detection only looks at which apps are running, their window titles, and CPU usage. It never accesses your camera, microphone, or meeting content.

## Under the hood

| File | Responsibility |
| --- | --- |
| [`WalkAwayApp.swift`](WalkAway/WalkAwayApp.swift) | App entry point and `AppDelegate`: break timers, pause/resume, meeting detection, inactivity tracking, sleep/wake, Launch at Login, the settings popover, and the heads-up toast. |
| [`OverlayWindowController.swift`](WalkAway/OverlayWindowController.swift) | The full-screen break window, one per display, with its animated background and Skip button. |
| [`MediaController.swift`](WalkAway/MediaController.swift) | Pauses system-wide “Now Playing” media when a break starts. |
| [`welcome.mp3`](WalkAway/welcome.mp3) | The end-of-break chime. |

### Meeting detection
Every 2 seconds, while the option is on, WalkAway checks each meeting app in turn:

| App | Signal |
| --- | --- |
| Zoom | The in-meeting helper process (`CptHost`) is running |
| Webex | The meeting host process (`washost`) is running |
| Teams | Average CPU use stays above 10% for about 10 seconds |

### Pausing media
macOS has no public API to control another app's playback. Since macOS 15.4, the private `MediaRemote` framework also refuses requests from third-party apps. WalkAway gets around this by running a short script with Apple's own `/usr/bin/perl`, which macOS still allows to use `MediaRemote`. The script checks whether anything is playing and, if it is, sends an explicit **Pause** command. It never sends a play/pause toggle, so it can't accidentally resume something. If the script fails, WalkAway sends the Pause command directly as a fallback.

This approach needs the app to run **outside the App Sandbox**, which is why WalkAway isn't distributed through the Mac App Store.

### Testing tip
Waiting 30 minutes for a break gets old. In `WalkAwayApp.swift`, set:
```swift
private let testingBreakFrequencyMinutes: Int? = 1
```
to get a break every minute. Set it back to `nil` before committing.

## Known limitations

- **Media pausing relies on private macOS behavior** and could break in a future macOS update.
- Only the app macOS considers “Now Playing” is paused, which is usually the one you used most recently.
- Teams detection is a heuristic and can occasionally misfire.
- Browser-based meetings (Google Meet, Teams on the web) aren't detected.

## Contributing

Issues and pull requests are welcome. If you're adding support for a new meeting app, implement the `MeetingDetector` protocol in `WalkAwayApp.swift` and register it in `MeetingMonitor`.

## Acknowledgements

The Perl-based `MediaRemote` workaround is inspired by [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter).
