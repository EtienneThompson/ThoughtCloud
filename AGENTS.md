# Agent notes for ThoughtCloud

A personal iPhone app: the owner is the only user. See `README.md` for the layout and how to run and test.

## UI copy

- **No helper or explanatory text.** Don't add footers, captions, tips, onboarding sentences or "how this works" lines (e.g. "Everything is stored only on this iPhone…", "Tap + to…", "First line is the title…"). The user knows how the app works.
- Labels, titles, values and short placeholders are fine. Empty states get an icon and a short title only.
- This applies to every screen, sheet, settings page, empty state, and to App Intent descriptions.

## Interaction

- Controls must respond instantly. Buttons get a full-size hit area (`.contentShape`), and button actions like zoom apply immediately rather than through an animation loop.
- Show every option at once rather than in a horizontal scroller when the user must pick from it (e.g. category pills wrap onto rows with `FlowLayout`).
- The tab bar is symmetrical: Cloud, Todos, Events | + | Thoughts, Review, Settings. Keep the same number of tabs on each side of +.
- The capture + button starts with the current tab's kind (Todos → todo, Events → event, Thoughts → thought, Review → review card); on Cloud and Settings the kind is auto-guessed.

## Engineering

- Test-driven: write a failing Swift Testing test in `Packages/ThoughtCloudKit` first, then implement.
- All logic lives in the package behind small protocols (persistence, date provider, date detection). The SwiftUI layer stays thin: it reads models and forwards actions.
- Data stays on the device. No server or cloud sync.
- Don't commit unless asked.
