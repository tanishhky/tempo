<p align="center">
  <img src="docs/icon.png" width="128" alt="Tempo icon">
</p>

<h1 align="center">Tempo</h1>

<p align="center">
  A minimal study timer for the macOS menu bar.<br>
  No account, no ads, no analytics, no cloud.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/SwiftUI-native-F05138?logo=swift&logoColor=white" alt="Native SwiftUI">
  <img src="https://img.shields.io/badge/network-your%20own%20phone%20only-6366F1" alt="Network: your own phone only">
  <img src="https://img.shields.io/badge/dependencies-0-16A34A" alt="No dependencies">
</p>

![Tempo counting down a focus session from the menu bar](docs/hero.jpg)

## Why

Most focus timers want an account, show ads, or sync your sessions to a server you don't control.
Tempo counts down a study block from the menu bar, keeps a permanent ledger of everything you study, and silences your Mac and your Android phone while you work.
Your history lives in one file on your Mac and nowhere else.

## Features

- **Live menu bar countdown.** The label shows the phase and the time left, in monospaced digits so it never jitters.
- **Any length.** Presets of 25, 50 and 90 minutes for focus and 5, 10 and 20 for breaks, plus any whole number of minutes you type or step through.
- **Activities.** Track whatever you do: Study, Quiz, Reading, Rest, or your own. Each one counts as focus or rest, has a colour, and keeps its own history.
- **A permanent ledger.** Every focus block and every break, kept forever, with totals for 7 days, 30 days, 90 days, a year or all time.
- **Habits.** A daily focus goal, a streak of days you hit it, and a per-activity trend with its own streak and heatmap.
- **A journal.** Daily checklists per activity, with a GitHub-style progress grid for each one.
- **An AI assistant can help.** A small MCP server lets an assistant log time, add activities and tick journal items for you.
- **Do Not Disturb that follows the timer.** Focus on your Mac and Do Not Disturb on your Android phone switch on when a session starts and off when it ends.
- **A topic per session.** Note what you're studying and see time per topic.
- **End-of-session alert.** A chime plays even when a Focus mode silences notifications, a banner appears, and Tempo moves to the next phase.
- **Accurate.** The countdown runs against a fixed end time, so App Nap or a busy CPU can't make it drift.
- **Scriptable.** A `tempo://` URL scheme controls it from Raycast, Alfred, Shortcuts or the terminal.
- **Light and dark.** Follows the system appearance.

![Ready, paused and break states in dark mode](docs/states.png)

### Menu bar states

![The menu bar label while idle, focusing, paused and on a break](docs/menubar.png)

| Label | Meaning |
|---|---|
| Timer | Idle. Click to open the panel. |
| Brain and time left | Focus session running |
| Pause and time left | Paused |
| Cup and time left | Break running |

## The ledger and your streak

Open **Ledger** from the panel (or `tempo://ledger`) for the long view.

![The ledger: totals, hours per day, a year heatmap, time by topic and recent sessions](docs/ledger.png)

- **Totals** for focus time, rest time, completed sessions and active days over the range you pick.
- **Time by activity** as stacked bars per day, each segment one activity, with your daily goal as a dashed line.
- **Habits** for any one activity: its total, the days you logged it, the run of days logged in a row, a daily bar chart and a year heatmap. Pick the activity from the dropdown.
- **Consistency** is a year of days, one square each, shaded by how close you got to your goal. Hover a square for that day's numbers.
- **Streak** counts consecutive days you reached your goal. Today never breaks it until the day is over.
- **By topic** and **Recent sessions** show where the time went.
- **Export** every session as CSV from the button in the corner.

Set your daily goal (default 2 hours) in **Settings**.
Rest counts too: a break you stop early still logs once it passes a minute, the same as a focus block.

<details>
<summary>Dark mode</summary>

![The ledger in dark mode](docs/ledger-dark.png)

</details>

> The ledger and heatmap images use generated sample history, not real study data.

## Do Not Disturb

Tempo switches Do Not Disturb on when a focus block starts and off when it ends, pauses, is reset or skipped, or when you quit.
It can also keep it on through breaks.
Tempo switches back whatever it switched on, including when you quit, and never touches a device you did not turn on in **Settings**.
If Tempo or the Mac crashes mid-session, the phone reverts by itself when the session's time is up; Focus on the Mac stays on until you turn it off.

### On your Mac

macOS has no public switch for Do Not Disturb, so Tempo runs two Shortcuts that you create once:

1. Open the Shortcuts app and create a shortcut named **Tempo Focus On**.
2. Add the action **Set Focus**: Do Not Disturb, Turn On, Until Turned Off.
3. Create a second shortcut named **Tempo Focus Off** with **Set Focus** set to Turn Off.
4. In Tempo's **Settings**, turn on *Turn on Focus while a session runs*. It shows whether it found both shortcuts, and has **Test on** and **Test off** buttons.

You can pick any Focus in those shortcuts, not only Do Not Disturb.

### On your Android phone

The **Tempo Companion** app in [`android/`](android) listens on your local network and switches the phone's Do Not Disturb when your Mac asks.
Everything stays between the two devices on your own Wi-Fi.

![Tempo Settings with Do Not Disturb options for the Mac and an Android phone](docs/settings.png)

1. **Build it.** You need JDK 17 or later and the Android SDK (platform 35).

   ```sh
   cd android
   export ANDROID_HOME=/path/to/your/android-sdk
   ./gradlew assembleDebug
   ```

   The APK is `app/build/outputs/apk/debug/app-debug.apk`.
2. **Install it.** Copy the APK to the phone and open it, or run `adb install app/build/outputs/apk/debug/app-debug.apk` with the phone connected.
   Android will ask you to allow installing from your file manager or browser.
3. **Grant three permissions** on the phone's screen, each with a button that opens the right Settings page:
   - **Do Not Disturb access**, required. Android only lets an app change Do Not Disturb after you switch it on yourself.
   - **Notifications**, so Android can show the "listening" notification that background listeners must have.
   - **Unrestricted battery use**, recommended. Without it Android may delay the Mac's request while the phone sleeps.
4. **Tap Start listening.** The app shows the phone's address, the port and a token.
5. **Enter them in Tempo.** In **Settings**, turn on *Also silence the phone*, type the address, port and token, and press **Test connection**.
   The first time, macOS asks to allow Tempo to find devices on your local network. Allow it.

How it behaves:

- The phone is set to **Priority only**, so your own allowed contacts and alarms still get through, and the mode you had before is restored afterwards.
- Every request carries a secret token, and only two requests exist: read status, and switch Do Not Disturb.
- Tempo tells the phone how long the session lasts, so the phone switches itself back if the Mac never says "off" (a crash, a closed lid, a dropped connection).
- Traffic is plain HTTP on your local network. The token stops other devices on the network from using it, but it is not encrypted. Do not use this on a network you do not trust.
- Tempo only talks to the one address you enter, and only while the phone toggle is on.
- If the phone's address changes, update it in Settings. Reserving the phone's address in your router keeps it fixed.

**Status:** the phone's request handling has 11 automated tests and the Mac side has been exercised against a stand-in phone that speaks the same protocol, including a wrong token, missing Do Not Disturb access, an app that isn't running and a phone that never answers.
It has not yet been tried on a physical Android device, so treat the phone side as experimental and please report anything odd.

## Install

Tempo is built from source on your own Mac, which takes about a minute.

### Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel
- Xcode Command Line Tools (`xcode-select --install`); the full Xcode app is not needed

### Build and install

```sh
git clone https://github.com/tanishhky/tempo.git
cd tempo
./build.sh --install
```

`build.sh` compiles the app, signs it ad hoc, copies it to `/Applications/Tempo.app` and launches it.
The timer icon appears in your menu bar.
Because the app is built locally rather than downloaded, Gatekeeper does not quarantine it.

### First launch

- macOS asks whether Tempo may send notifications. Allow it to get the end-of-session banner; the chime plays either way.
- If you use the Android companion, macOS also asks once for local network access.
- To start Tempo with your Mac, tick **Open at login** in the panel. macOS may ask you to approve it under System Settings → General → Login Items.

### Update

```sh
cd tempo
./tools/update.sh
```

The script copies your session log, activities, journal and settings into a timestamped folder under `~/Library/Application Support/Tempo/backups` first. It then fetches the new version (fast-forward only, so it never merges silently), runs the tests, builds and installs. It never moves or rewrites your data, and it stops before installing if anything fails. The newest ten backups are kept.

If an update ever goes wrong, quit Tempo and copy the files back from the backup folder. The backup also holds a `settings.plist`, which you can restore with `defaults import me.tanishkyadav.tempo settings.plist`.

No conversion is needed from an older version. Sessions logged before activities existed still count as Study or Rest, and the app reads them as they are.

### Uninstall

```sh
pkill -x Tempo
rm -rf /Applications/Tempo.app "$HOME/Library/Application Support/Tempo"
defaults delete me.tanishkyadav.tempo
```

## Usage

1. Click the timer icon in the menu bar.
2. Pick an activity, a length and, optionally, type what you're studying.
3. Press Return to start.

When the block ends, Tempo chimes, logs the session and switches to a break.
If Do Not Disturb is set up, it was on for the whole block and is off again now.
Start the break when you're ready; it hands back to focus the same way.
If you reset or skip a focus block after at least a minute, the minutes you put in still count.

| Shortcut (panel open) | Action |
|---|---|
| <kbd>Return</kbd> | Start, pause or resume |
| <kbd>⌘</kbd> <kbd>R</kbd> | Reset the current session |
| <kbd>⌘</kbd> <kbd>Q</kbd> | Quit Tempo |

## Activities and the journal

Open **Settings** and find **Activities** to add, rename, recolour or remove them.

- **Counts as** sets whether an activity is *Focus* (it counts toward your daily goal and turns Do Not Disturb on) or *Rest* (it doesn't).
- **Journal checklist** lists the items that appear every day for that activity, such as "MCQ 1-20" for a Quiz.

The panel shows a chip for each activity of the current kind. Pick one before you press Start, and the block is logged under it.
Removing an activity never changes past sessions: they keep its name in the ledger.

The **Journal** (`tempo://journal`, or the button in the panel) shows each activity's checklist for the day you pick. Tick items off, add one-off items, and leave a note. Each activity also gets a progress grid, one square per day, shaded by how much of its checklist you finished.

## Letting an AI assistant log for you

`tools/tempo_mcp.py` is a [Model Context Protocol](https://modelcontextprotocol.io) server with no dependencies. It reads and writes the same files as the app, so anything it logs appears in the ledger and journal once Tempo is active again.

Register it with Claude Code, using the absolute path to your clone:

```sh
claude mcp add tempo -- python3 /absolute/path/to/tempo/tools/tempo_mcp.py
```

It offers these tools:

| Tool | What it does |
|---|---|
| `tempo_list_activities` | Lists activities, with their ids, kinds and default checklists |
| `tempo_add_activity` | Adds an activity, as focus or rest, with an optional checklist |
| `tempo_log_session` | Logs minutes against an activity, for today or a past date |
| `tempo_set_journal` | Sets the checklist and note for one activity on one day |
| `tempo_get_journal` | Reads every checklist saved for a day |
| `tempo_summary` | Time per activity over the last N days, with days logged and runs |

Set `TEMPO_DATA_DIR` to point it at a different data folder. Its tests run without touching your data:

```sh
python3 -m unittest discover -s tools -p "test_*.py"
```

## Raycast, Shortcuts and the terminal

Tempo registers the `tempo://` URL scheme, so anything that can open a URL can control it.

| URL | Action |
|---|---|
| `tempo://toggle` | Start or pause |
| `tempo://start` | Start, or resume if paused |
| `tempo://pause` | Pause |
| `tempo://reset` | Reset the current session |
| `tempo://skip` | Skip to the next phase |
| `tempo://ledger` | Open the ledger |
| `tempo://journal` | Open the journal |
| `tempo://settings` | Open Settings |

From a terminal:

```sh
open tempo://toggle
```

**Global hotkey with Raycast:** run *Create Quicklink*, set the link to `tempo://toggle` and save it.
Then assign it a hotkey in Raycast Settings → Extensions.

## Your data

Everything stays on your Mac.
The only network use is the optional phone feature above: a request to the one phone address you enter, while its toggle is on.
Tempo has no accounts, analytics, update checks or servers of its own.

| What | Where |
|---|---|
| Sessions | `~/Library/Application Support/Tempo/sessions.jsonl` |
| Activities | `~/Library/Application Support/Tempo/activities.json` |
| Journal checklists | `~/Library/Application Support/Tempo/journal.jsonl` |
| Backups, made by `tools/update.sh` | `~/Library/Application Support/Tempo/backups/` |
| Settings (lengths, goal, phone address and token) | the `me.tanishkyadav.tempo` defaults domain |

The ledger is built from this one file, so it is also your backup: copy it and you have your whole history.
Each session, focus or rest, is one JSON object per line:

```json
{"completed":true,"end":"2026-10-04T21:33:20Z","minutes":50,"phase":"focus","start":"2026-10-04T20:43:20Z","topic":"Options pricing, ch. 7"}
```

JSON Lines opens in any spreadsheet tool or in `jq`.
For example, total focus minutes per topic:

```sh
jq -s 'map(select(.phase == "focus"))
       | group_by(.topic)
       | map({topic: .[0].topic, minutes: (map(.minutes) | add)})' \
  "$HOME/Library/Application Support/Tempo/sessions.jsonl"
```

## Project layout

```
Sources/
  TempoApp.swift      App entry, menu bar and window scenes, URL and notification handling
  TimerModel.swift    Timer state and the menu bar label
  SessionStore.swift  The session log and the ledger maths (totals, streaks, topics)
  FocusBridge.swift   Do Not Disturb for the Mac (Shortcuts) and the phone (HTTP)
  AppSettings.swift   Stored settings
  PanelView.swift     The menu bar panel
  LedgerView.swift    The ledger window, chart and heatmap
  SettingsView.swift  The settings window
  Activities.swift    The activity list and its file
  JournalStore.swift  Daily checklists and their file
  JournalView.swift   The journal window
  Theme.swift         Colours, and the palette activities pick from
Resources/            Info.plist, AppIcon.svg and AppIcon.icns
android/              Tempo Companion, the Android app (Kotlin, no dependencies) and its tests
tools/
  make-icon.sh        Rebuilds AppIcon.icns and docs/icon.png from AppIcon.svg
  screenshots.sh      Renders the images in docs/ from the real views and sample data
  selftest.sh         Checks the data layer (old history, activities, journal, streaks) in a temporary folder
  update.sh           Backs up your data, pulls, tests, builds and installs
  tempo_mcp.py        The MCP server for AI assistants (no dependencies)
  test_tempo_mcp.py   Tests for the MCP server
build.sh              Compiles and bundles Tempo.app; --install copies it to /Applications
```

There is no Xcode project and there are no dependencies.
`build.sh` calls `swiftc` directly, and the Mac app builds with the Command Line Tools alone.
Run the phone app's tests with `cd android && ./gradlew testDebugUnitTest`.
