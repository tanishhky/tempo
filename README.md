# Tempo

A minimal study timer that lives in the macOS menu bar. No account, no network, no ads.

- Focus / Break modes with presets (25 · 50 · 90 and 5 · 10 · 20 min), adjustable in 5-minute steps
- Live countdown in the menu bar; Glass chime and a notification when a session ends
- Optional topic per session; today and 7-day focus totals
- Sessions logged locally to `~/Library/Application Support/Tempo/sessions.jsonl` (focus sessions stopped early count once they pass a minute)

## Build

```
./build.sh            # builds build/Tempo.app (ad-hoc signed)
./build.sh --install  # copies it to /Applications and launches it
tools/make-icon.sh    # regenerates Resources/AppIcon.icns from AppIcon.svg
```

Needs the Xcode Command Line Tools and macOS 14 or later (Apple silicon).

## Keyboard and URL control

In the panel: Return starts or pauses, ⌘R resets, ⌘Q quits.

From anywhere (e.g. a Raycast Quicklink with a hotkey): `tempo://toggle`, `tempo://start`, `tempo://pause`, `tempo://reset`, `tempo://skip`.
