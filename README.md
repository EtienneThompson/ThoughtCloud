# ThoughtCloud

An iPhone app for everything you need to remember: **todos**, **thoughts**, **review** cards (things to go over again at growing intervals) and **events** (things coming up, mirrored to the iPhone Calendar), tied together by **categories** and shown as an interactive graph (the **Cloud**).

All data stays on the device (one JSON file in Application Support, previous version kept as a backup). There is no server. Events are also written to the default iPhone calendar via EventKit.

## Layout

```
ThoughtCloud.xcodeproj         App project (folder-synced groups: new files are picked up automatically)
ThoughtCloud/                  SwiftUI app layer: views only, thin
Packages/ThoughtCloudKit/      All logic, fully unit tested (Swift Testing)
design/                        HTML mockups from the design phase
```

### ThoughtCloudKit seams

| Area | Type | Responsibility |
|---|---|---|
| Domain | `Item`, `Subtask`, `ItemCategory`, `ItemLink`, `LibrarySnapshot` | Plain `Codable` values |
| Persistence | `LibraryPersisting` (protocol) → `JSONFilePersistence`, `InMemoryPersistence` | Load/save a snapshot |
| Time | `DateProviding` (protocol) | "Now", injectable in tests |
| Capture | `CaptureParser` + `DateDetecting` (protocol) → `SystemDateDetector` | Text → title/body/#tags/date/kind guess |
| Capture UI state | `CaptureModel` | Live draft, kind override, category chips, `#` autocomplete |
| Review | `ReviewScheduler` | 1·3·7·14·30·60-day ladder, remember-until capping and expiry |
| Review UI state | `ReviewSession` | Swipe queue, undo, browse mode |
| Todos | `TodoSectioner` | Today / Upcoming / Someday / Done, overdue rules |
| Events | `EventInfo`, `EventReviewScheduler`, `EventSectioner` | Start/end/all-day; review checkpoints 14·7·3·1·0 days before, archived the day after; This week / Later this month / month groups |
| Calendar | `CalendarSyncing` (protocol) → `EventKitCalendar` (app) | Create/update/remove the Calendar copy; missing permission is retried later |
| Presentation rules | `BodyFormatter`, `CategoryStyle` | `- ` lists and `Label: value` lines; 0/1/2/3+ category colours |
| Graph | `GraphBuilder`, `ForceLayout`, `GraphCamera`, `CloudModel` | Data → nodes/edges, force layout, pan/zoom maths, Cloud interaction |
| Orchestration | `Library` (`@Observable`) | The single store the UI talks to; every command persists |

## Running

- **App:** open `ThoughtCloud.xcodeproj`, pick your iPhone, Run. Signing uses automatic signing for team `72P754F3H3`.
- **Tests:** `⌘U` in Xcode (runs the package tests on the simulator), or from the terminal:
  ```sh
  cd Packages/ThoughtCloudKit && swift test
  ```
- **Demo data (simulator, Debug only):** add launch argument `-tcSampleData` (in-memory, nothing saved, never touches the calendar). `-tcTab todos|events|thoughts|review|settings` opens a tab; `-tcCapture` opens the capture sheet.

## Siri / Shortcuts

- "Add to ThoughtCloud": Siri asks what to capture, then files it without opening the app.
- "Open ThoughtCloud capture": opens straight to the capture sheet (assign it to the Action button).
- "Review my ThoughtCloud cards": opens Review.
