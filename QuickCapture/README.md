# Quick Capture

Talk, and your to-do list updates itself. Say something like *"remind me to call Sam tomorrow at 3, and buy
milk and eggs for groceries, oh and the tax thing is urgent"*. When you stop talking, you get three tasks with
dates, lists and priorities, sent to **Apple Reminders**, **Todoist** and/or **Notion**.

| Device | How to trigger | How it ends |
|---|---|---|
| **Mac** (menu bar app, no Dock icon) | Tap **⌥ ⌥ ⌥** · **swirl the pointer** twice quickly · click the menu bar icon | Stop talking (auto) · tap ⌥ once · **Esc** discards |
| **iPhone** | **Action Button** · **Control Center / Lock Screen control** · Lock Screen widget · "Hey Siri, capture with Quick Capture" · Back Tap (via Shortcuts) · **swirl a finger** twice in the app | Stop talking (auto) · tap the orb |
| **Apple Watch** | Open the app or tap the **complication**: it's already listening · **Double Tap** gesture | Stop talking (auto) · tap / Double Tap |

## Why it's fast and light

- **Nothing runs in the background.** On the Mac there are no timers or polling, just two passive `NSEvent`
  monitors. A modifier change or mouse move costs a few comparisons; the swirl check works on a window of about
  150 points.
- **Speech-to-text runs on the device** (`SFSpeechRecognizer` with `requiresOnDeviceRecognition`), with partial
  results so you see words as you speak. It stops by itself after about 1.8 s of silence (you can change this).
- **The AI step also runs on the device when it can.** On Apple Intelligence hardware (iOS/macOS 26) the
  *Auto* setting uses Apple's Foundation Models: free, private, no network. Otherwise it uses one Claude call
  with a JSON-schema output (no retries, no agent loop). If that fails or you're offline, it makes one task per
  sentence, so a note is never lost.
- **All destinations are sent to in parallel**, and every task is also sent in parallel.
- **The Watch does very little.** It records 16 kHz mono AAC (a few KB per second) and hands the file to the
  iPhone with `WCSession.transferFile`. The file is queued and delivered even if the phone is asleep.
- **No third-party dependencies.**

## Layout

```
QuickCapture/
├── project.yml                 XcodeGen spec (5 targets)
├── Packages/CaptureKit/        Foundation-only core, unit-tested (swift test)
│   ├── CaptureTask.swift       model + TaskExtractor / TaskDestination protocols
│   ├── ExtractionPrompt.swift  shared prompt + JSON schema + offline fallback
│   ├── ClaudeExtractor.swift   Messages API call (structured output)
│   ├── RemoteDestinations.swift Todoist + Notion
│   └── GestureDetectors.swift  ⌥⌥⌥ tap detector + swirl detector
├── Shared/                     iOS + macOS: speech, on-device model, Reminders, pipeline, settings
├── macOS/                      menu bar app, global trigger monitor, floating HUD
├── iOS/                        app, App Intents (Action Button/Siri/Shortcuts), Watch receiver
├── iOSWidgets/                 Control Center control + Lock Screen / Home widget
├── watchOS/                    recorder + phone hand-off
└── watchWidgets/               watch face complication
```

## Build

Requires Xcode 26 (iOS 18 / macOS 15 / watchOS 11 minimum; Apple Intelligence extraction on 26+).

```sh
brew install xcodegen
cd QuickCapture
xcodegen                       # creates QuickCapture.xcodeproj
open QuickCapture.xcodeproj
```

1. Set your team in each target's *Signing & Capabilities*, and change `com.example.quickcapture` to your own
   prefix. Search for it in `project.yml`, which also holds the Watch's `WKCompanionAppBundleIdentifier`.
2. Run **QuickCaptureMac**. Grant Microphone, Speech Recognition and **Accessibility** (needed for the global ⌥
   trigger). The app picks up Accessibility permission as soon as you grant it.
3. Run **QuickCapture** on your iPhone; the Watch app installs with it.
4. Run the core tests with `cd Packages/CaptureKit && swift test`.

## Setup

Open **Settings** (menu bar → Settings… on the Mac, the gear icon on iPhone). Settings are stored per device, and
the Watch uses the iPhone's.

- **Convert with:** *Auto* (on-device, then Claude), Apple Intelligence, Claude, or no AI.
- **Anthropic API key:** from console.anthropic.com. It's stored in the Keychain. The model defaults to
  `claude-opus-5` at `low` effort; you can change it in the *Claude model* field. `claude-haiku-4-5` is the
  lowest-latency option (the app leaves out the parameters Haiku doesn't support).
- **Reminders:** on by default. You can pick a default list; if you say a list's name ("…to groceries"), the task
  goes to that list.
- **Todoist:** API token from *Settings → Integrations → Developer*. Project ID is optional. If you name a
  project in the note, the task goes there.
- **Notion:** create an integration, share your tasks database with it, and paste the token and the database
  ID. You can also set the title property name (default `Name`) and a date property (e.g. `Due`).

### iPhone trigger ideas

- **Action Button:** Settings → Action Button → Controls → *Quick Capture*.
- **Control Center / Lock Screen:** add the *Quick Capture* control.
- **Back Tap:** create a Shortcut that runs *Quick Capture*, then Settings → Accessibility → Touch → Back Tap.
- **Capture without opening the app:** a Shortcut with *Dictate Text* followed by *Capture Text as Tasks*.

## Privacy

Audio never leaves your devices. The transcript goes only to the model you chose (it stays on the device with
Apple Intelligence) and the resulting tasks go only to the destinations you turned on. The last 30 notes are
kept locally in the app's history.
