# Personal Dashboard

A native macOS SwiftUI dashboard for goals, todos, and locally recorded screen time.

## Calendar

The Calendar tab provides persistent month and week views, selectable days, previous/next and Today navigation, a selected-day agenda, and an upcoming-events list. Events can be added with start and end times, notes, and a color category, or deleted from the agenda. Calendar data is stored locally with the rest of the dashboard data.

## Screen-time tracking

Tracking starts with the app. The app samples the frontmost application every five seconds and combines consecutive samples into sessions. For Safari, Google Chrome, Microsoft Edge, and Brave, it also asks macOS for the active tab URL and stores only the normalized website domain.

- Data stays on this Mac and is not sent over the network.
- Full URLs, page titles, document names, window titles, and keystrokes are never stored.
- Lock-screen activity and long sleep/wake gaps are excluded; tracking pauses while the Mac is asleep, its display is asleep, its session is inactive, or input has been idle for five minutes.
- Tracking continues while the app is running, even if its window is closed, and starts again on the next launch.
- Sessions older than 90 days are removed automatically.

macOS may ask for Automation access separately for each supported browser. The history file is stored at:

`~/Library/Application Support/PersonalDashboard/screen-time-sessions.json`

The tracking day runs from 4 AM to 4 AM. Unclassified sources disappear at the next 4 AM boundary and reappear when used again. Historical totals remain available.

## Goals and todos

Goal titles wrap. Select a goal's percentage to adjust it in a small progress editor; changes are saved only with **Save**.

New todos appear after the last unchecked item. Completed todos stay at the bottom and expire 24 hours after completion, including when the app is relaunched. The draggable divider separates today's tasks from the backlog; deleting or moving a task preserves the remaining tasks' membership.

## Verification

Run `Tools/test-todos.sh`, `Tools/test-tracking.sh`, and `Tools/test-focus-cat.sh`. The checks use isolated storage and defaults. The Focus Cat checks also build the Release app and render its native animation frames. Xcode and a logged-in macOS desktop are required for native UI checks. See [ISSUE_AUDIT.md](ISSUE_AUDIT.md) for the review of all nine GitHub issues and validation scope.

## Focus Cat animation

Performance measurements, cache invalidation rules, polling behavior and validation
limits are documented in [PERFORMANCE.md](PERFORMANCE.md). Run
`Tools/benchmark-performance.sh` for an isolated native idle/preview and synthetic
tracking benchmark. Visible transitions use 60 Hz updates; the sleeping cat keeps
its subtle breathing at 4 Hz without invalidating the dashboard.

Focus Cat uses the approved `workcat-v3/workcat_final.gif` animation: wrapped sleeping tail,
closed sleeping eyes and mouth, the same walking gait in both directions, and the restored
GIF paw raise. All seven animation clips are bundled in
`PersonalDashboard/Resources/ApprovedCatAnimation.json`; no older cat artwork or separate
sleep illustration is rendered. The frames are drawn natively at 60 fps with transparent
backgrounds. Travel is calibrated to finish on a complete walking cycle. The close action
occurs during the raised-paw hold, and the paw lowers before the cat returns home.

Run `Tools/test-focus-cat.sh` with Xcode installed and a logged-in macOS desktop to build
Release and check the real controller's complete preview sequence. By default the checks disable browser
monitoring, never close real tabs, and export native-view images to
`output/approved-cat-integration`. They also cover cancellation, re-enabling, mirrored paw
coordinates, frame bounds, and the timing of the paw hold and lowering.

The portable animation data can be regenerated with
`python3 Tools/FocusCatAnimation/generate.py` (NumPy, Pillow, and OpenCV required only for
regeneration). The generator uses the exact approved renderer and records the reference
GIF's SHA-256; the app has no Python or external-file dependency.

The awake face retains the reference's small dot eyes. A red exclamation mark briefly
appears just above the head during waking. Chrome window/tab IDs stay strings, as
declared in Chrome's scripting dictionary. While approaching, the cat rechecks its
target every 0.35 seconds and returns home if the tab is gone, switched, or no longer
a distraction. A partially raised paw lowers before returning.

The checks also compile the real Chrome scripts and cover navigation, identity guards,
and cancellation during wake, walk, and reach. An optional `--live-close-fixture`
check requires an explicitly prepared active tab at
`about:blank#focus-cat-close-regression-20260911`; it closes only that fixture tab
after testing the URL and identity guards. This live check is not part of the default run.
