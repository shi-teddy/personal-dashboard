# Performance review — 2026-09-14

Baseline source: `46f5650` (including the newer daily todo cleanup and Insights changes). The working tree was clean when this task started. User data, storage formats, todo behavior and the bundled animation JSON were preserved.

## Measurements

`Tools/benchmark-performance.sh` compiles the real cat controller/view/artwork and tracker with `swiftc -O`, runs a native NSPanel with Focus Cat enabled, observes 30 seconds of sleep, runs one complete preview, queries 9,000 synthetic sessions across about 83 days 100 times, then supplies twelve five-second tracking samples. Browser monitoring is disabled in this probe; it cannot close a tab. Storage and defaults are isolated. CPU uses `getrusage`; memory uses `/usr/bin/time -l`. The observation moved from the controller's phase publisher to its new dedicated animation publisher; workloads otherwise match.

| Metric | Before | After |
| --- | ---: | ---: |
| Sleeping CPU time over 30 seconds | 1.894043 s | 0.207148 s |
| Average sleeping CPU, one core | 6.31% | 0.69% |
| Sleeping phase callbacks over 30 seconds | 1,798 | 120 |
| Cat creation, artwork load and panel setup | 560.49 ms | 255.22 ms |
| Complete preview duration | 20.825 s | 21.108 s |
| Preview phase publications | 1,251 | 1,268 |
| Preview 95th-percentile publication gap | 17.939 ms | 17.783 ms |
| Preview publication gaps over 33.4 ms | 6 | 3 |
| 100 repeated chart/score/summary/top-activity queries, CPU | 0.873400 s | 0.007540 s |
| Atomic history replacements for twelve samples | 12 | 2 |
| Maximum resident set size | 77,414,400 bytes | 77,594,624 bytes |
| Peak physical footprint | 110,592,720 bytes | 105,595,600 bytes |

These are single before/after runs, not statistical benchmarks or battery-life measurements. Machine load and filesystem caches were uncontrolled, and the runs were separated by a user pause. The resident set is essentially unchanged; do not claim a significant RSS reduction. The modest physical-footprint reduction and startup difference need repeated runs before attributing them entirely to code. Phase publication gaps approximate animation pacing, not display-server frame presentation. No authored clip durations, travel calibration, paw timings, or positional formulas changed.

An additional `top`/`sample` baseline of the installed **Debug** application showed 35.5–46.0% CPU and a 131.5 MB physical footprint. Its stack sample showed substantial SwiftUI/AppKit layout and display-list work. That live app had different data/state and system conditions than the isolated probe; it is not used as a numerical before/after comparison.

## Causes and changes

- **Cat idle work:** the controller kept its 60 Hz timer running during sleep and published phase changes through the object observed by the dashboard. Sleep now has a separate 4 Hz timer with tolerance, retaining the authored 2.4-second, subpixel breathing motion. The 60 Hz timer starts immediately for wake/walk/paw/recovery/return/settle and stops at sleep. Disabled cats have neither timer. A dedicated animation observable drives only the overlay. Repeated assignments of the same running pose/direction were removed, and frame callbacks execute directly on the main run loop instead of creating a Task each frame.
- **Blocking browser work:** detection, target checks, close attempts, and tracking URL reads previously executed Apple events synchronously on the main thread. A shared serial worker now owns blocking requests; each subsystem also rejects overlapping scans/samples. Apple events have a two-second timeout. The accessibility close-button lookup runs on that worker once per trip and its position is reused at the paw transition.
- **Polling:** detection previously woke every 2.5 seconds while enabled, even outside Chrome. It now stops outside a foreground supported Chrome process, uses workspace activation/launch/termination events to restart promptly, and backs off from 2.5 to 5 to 10 seconds after irrelevant/error results. A relevant site resets the interval. During an intervention, identity checks retain the 0.35-second cadence but skip while a request is in flight. The nominal steady idle scan rate is therefore 24 to 6 per minute in foreground Chrome, and zero scheduled detection outside it. These rates describe the verified scheduling policy; actual live Apple-event traffic was **not** counted before/after. Chrome has no tab-navigation notification used by this implementation, so a new site in a continuously foreground, quiet browser can take up to roughly ten seconds plus request latency to be detected.
- **Close safety:** original text window/tab IDs, distraction classification, exact URL comparison at close time, and three bounded navigation retries remain. Queued close work is revoked on disable/cancel/return. Late scan results cannot re-enable a disabled cat. Requests test whether Chrome is still running rather than relaunching it. A busy/unresponsive browser can delay or prevent an intervention; it cannot justify closing a replacement tab.
- **Tracking:** the five-second cadence and five-minute idle cutoff remain. Foreground browser reads occur off the UI thread; stale answers after a lock, clear, or foreground-process change are discarded. Sleep/session/display reasons remain independent; sampling timers stop while suspended. Only dirty history is persisted, normally no more than once per 30 seconds, with a one-shot pending flush. Idle transitions, sleep, session loss, clear and normal termination flush immediately. Forced process kill/power loss can lose up to roughly 30 seconds of newly sampled data; normal shutdown flushes it. The 4 AM day and 90-day retention remain; retention scans wait until the earliest possible expiry. Unchanged endpoints and no-op retention passes no longer publish mutations.
- **Analytics:** tracker-owned caches store day subsets, duration, chart segments, focus/drift points, productivity and top activities. Session mutation invalidates them; changed classification rules invalidate classified results; calendar/time-zone changes invalidate all. Date intervals and top-activity limits are part of the keys. Cache sizes are bounded. Existing calculations and tie-breaking remain; view bodies receive cached results after the first computation for a revision.
- **Resources:** `ApprovedCatArtwork.shared` already decoded once. It still does. Decoded coordinate arrays are released after compiling CGPaths, while small manifest metadata and the reusable paths remain. Constant drawing colors are reused. No frame is regenerated, reauthored or transformed into a new geometry copy during playback.
- **Requested visual correction:** the top screen-time chart's Drift legend uses the same red `Palette.warning` as the Drift bars and score legend.

## Verification

- `Tools/test-todos.sh` passed, including current daily cleanup/completion history persistence.
- `Tools/test-tracking.sh` passed: previous chronology, 4 AM, classification ties and overnight/idle tests; new persistence batching, explicit flush, no-op write suppression, cache hits, classification/session/clear invalidation, cached-versus-fresh chart equality, sample overlap/stale reply handling and sampling-timer suspension/resumption/termination checks.
- `Tools/test-focus-cat.sh` passed: all prior native renders, sequence/timing, cancellation and generated close-script guards; new sleeping/animating/disabled timer states, unavailable/disabled browser suppression, adaptive backoff, overlapping scan prevention, disabled-result rejection, worker serialization and a non-browser AppleScript execution on the worker.
- Debug and Release Xcode builds passed. Existing SwiftUI `onChange` deprecation warnings remain.
- `git diff --check` passed.
- The verified Release build was installed at `/Applications/PersonalDashboard.app`, locally signed and reopened. The top Drift legend was visually verified red. The user's Focus Cat enabled/disabled preference was preserved. The previous installed bundle is backed up at `/private/tmp/dashboard-before-performance.EGYY1m/PersonalDashboard.app`.

## Remaining limits and hotspots

No live browser fixture was opened or closed, and actual browser IPC traffic, hardware wakeups, power draw and full-application launch latency were not profiled. Earlier automatic approval review rejected fixture navigation; this task did not bypass it. Cat frame callbacks are measured directly, not presented as hardware wakeup counts.

The first query after a session/rule change still computes synchronously; subsequent queries reuse results. History still uses a full-file JSON snapshot, now batched, and its flush runs on the main thread. Accessibility traversal can hold the serial browser worker when Chrome is slow, but no longer blocks drawing. Visible animation still uses a 60 Hz run-loop timer rather than a display link; the probe does not establish a guaranteed 60 presented frames per second under load. Further optimization should be driven by Instruments traces with large real histories and real browser interactions, rather than extrapolating battery savings from these short runs.
