# Personal Dashboard

A native macOS SwiftUI dashboard for goals, todos, and locally recorded screen time.

## Calendar

The Calendar tab provides persistent month and week views, selectable days, previous/next and Today navigation, a selected-day agenda, and an upcoming-events list. Events can be added with start and end times, notes, and a color category, or deleted from the agenda. Calendar data is stored locally with the rest of the dashboard data.

## Screen-time tracking

Select **Start tracking** in the dashboard. The app samples the frontmost application every five seconds and combines consecutive samples into sessions. For Safari, Google Chrome, Microsoft Edge, and Brave, it also asks macOS for the active tab URL and stores only the normalized website domain.

- Data stays on this Mac and is not sent over the network.
- Full URLs, page titles, document names, window titles, and keystrokes are never stored.
- The dashboard itself and long sleep/wake gaps are excluded.
- Tracking continues while the app is running, even if its window is closed, and resumes on the next launch if it was left enabled.
- Sessions older than 90 days are removed automatically.

macOS may ask for Automation access separately for each supported browser. The history file is stored at:

`~/Library/Application Support/PersonalDashboard/screen-time-sessions.json`
