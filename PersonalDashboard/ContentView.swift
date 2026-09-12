import SwiftUI
import Combine

private enum DashboardPage: String, CaseIterable, Identifiable {
    case home = "Home"
    case stickyNotes = "Sticky Notes"
    case insights = "Insights"
    case settings = "Settings"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "house"
        case .stickyNotes: "note.text"
        case .insights: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var page: DashboardPage = .home
    private let cleanupTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 18)
            HStack(alignment: .top, spacing: 18) {
                SidebarRail(selection: $page)
                Group {
                    if page == .home {
                        HomeDashboard()
                    } else if page == .stickyNotes {
                        StickyNotesBoard()
                    } else if page == .settings {
                        ClassificationSettingsView()
                    } else if page == .insights {
                        InsightsPage()
                    } else {
                        EmptyPage(page: page)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Palette.canvas)
        .preferredColorScheme(.light)
        .onAppear { store.removeExpiredCompletedTodos() }
        .onReceive(cleanupTimer) { store.removeExpiredCompletedTodos(now: $0) }
    }
}

private struct SidebarRail: View {
    @Binding var selection: DashboardPage

    var body: some View {
        VStack(spacing: 26) {
            ForEach(DashboardPage.allCases) { item in
                Button { selection = item } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selection == item ? Palette.ink : Palette.muted)
                        .frame(width: 44, height: 44)
                        .background(selection == item ? Palette.selected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(item.rawValue)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .frame(width: 64)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
    }
}

private struct EmptyPage: View {
    let page: DashboardPage

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: page.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.muted)
            Text(page.rawValue).font(.system(size: 24, weight: .semibold))
            Text("This page is ready for future dashboard features.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
    }
}

private struct HomeDashboard: View {
    @State private var selectedMode: DashboardMode = .screenTime

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                DashboardHeader(selectedMode: $selectedMode)
                Group {
                    if selectedMode == .calendar { CalendarPanel() } else { AnalyticsPanel() }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))

            RightColumn().frame(width: 258)
        }
    }
}

private enum DashboardMode {
    case calendar
    case screenTime
}

private struct DashboardHeader: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    @Binding var selectedMode: DashboardMode
    @State private var didRefresh = false
    @State private var refreshResetTask: Task<Void, Never>?

    var body: some View {
        HStack {
            Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 24, weight: .bold))
            Spacer()
            HStack(spacing: 0) {
                SegmentButton(title: "Calendar", selected: selectedMode == .calendar) { selectedMode = .calendar }
                SegmentButton(title: "Screen Time", selected: selectedMode == .screenTime) { selectedMode = .screenTime }
            }
            .padding(4).background(Palette.track)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if selectedMode == .screenTime {
                Button {
                    tracker.refresh()
                    refreshResetTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        didRefresh = true
                    }
                    refreshResetTask = Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            didRefresh = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.focus).frame(width: 7, height: 7)
                        Text(didRefresh ? "Updated" : "Tracking")
                        Image(systemName: didRefresh ? "checkmark" : "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Tracking is active. Click to refresh screen-time data and classifications.")
                .accessibilityLabel("Tracking active. Refresh screen time")
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
    }
}

private struct SegmentButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Palette.muted)
                .padding(.horizontal, 16).frame(height: 30)
                .background(selected ? Palette.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }.buttonStyle(.plain)
    }
}

private struct AnalyticsPanel: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    @State private var displayedDate = Date()

    var body: some View {
        VStack(spacing: 12) {
            TrackedTimeCard(displayedDate: $displayedDate).frame(maxHeight: .infinity)
            FocusDriftCard(displayedDate: displayedDate).frame(height: 152)
            GeometryReader { proxy in
                let cardWidth = max(0, (proxy.size.width - 26) / 2)
                HStack(spacing: 26) {
                    ProductivityCard(displayedDate: displayedDate)
                        .frame(width: cardWidth)
                    TopActivityCard(displayedDate: displayedDate)
                        .frame(width: cardWidth)
                }
            }
            .frame(height: 166)
        }
        .padding(14).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .onAppear { displayedDate = tracker.trackingDay(containing: Date()) }
    }
}

private struct TrackedTimeCard: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var tracker: ScreenTimeTracker
    @Binding var displayedDate: Date
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(tracker.formattedDuration(for: displayedDate)) Tracked").font(.system(size: 26, weight: .bold))
                Spacer()
                MetricLegend(label: "FOCUS", color: Palette.focus)
                MetricLegend(label: "NEUTRAL", color: Palette.neutral)
                MetricLegend(label: "DRIFT", color: Palette.drift)
                Spacer()
                HStack(spacing: 5) {
                    ChartDayButton(symbol: "chevron.left", help: "Previous day") { moveDay(-1) }
                    Button {
                        displayedDate = tracker.trackingDay(containing: Date())
                    } label: {
                        Text(dayLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(minWidth: 64, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    ChartDayButton(symbol: "chevron.right", help: "Next day") { moveDay(1) }
                }
            }.padding(.horizontal, 8)
            ActivityChart(segments: tracker.chartSegments(
                for: displayedDate,
                classificationRules: store.classificationRules
            ))
        }
        .padding(18).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }

    private var dayLabel: String {
        let today = tracker.trackingDay(containing: Date())
        if calendar.isDate(displayedDate, inSameDayAs: today) { return "Today" }
        return displayedDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func moveDay(_ value: Int) {
        displayedDate = calendar.date(byAdding: .day, value: value, to: displayedDate) ?? displayedDate
    }
}

private struct ChartDayButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Palette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.grid, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MetricLegend: View {
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Circle().fill(color).frame(width: 7, height: 7)
            Circle().fill(color).frame(width: 7, height: 7)
        }
    }
}

private struct ActivityChart: View {
    let segments: [ScreenTimeChartSegment]
    private let hours = (0..<24).map { (4 + $0) % 24 }
    private let minuteTicks = [0, 15, 30, 45, 60]

    var body: some View {
        GeometryReader { proxy in
            let yAxisWidth: CGFloat = 38
            let topAxisHeight: CGFloat = 24
            let plotWidth = max(1, proxy.size.width - yAxisWidth)
            let plotHeight = max(1, proxy.size.height - topAxisHeight)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("MIN")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .padding(.trailing, 6)
                        .frame(width: yAxisWidth, alignment: .trailing)
                    HStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            Text(hourLabel(hour))
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: plotWidth)
                }
                .frame(height: topAxisHeight)

                HStack(spacing: 0) {
                    GeometryReader { axis in
                        ForEach(minuteTicks, id: \.self) { minute in
                            let labelY = 5 + (axis.size.height - 10) * CGFloat(minute) / 60
                            Text("\(minute)")
                                .font(.system(size: 8))
                                .foregroundStyle(Palette.muted)
                                .position(x: axis.size.width - 10, y: labelY)
                        }
                    }
                    .frame(width: yAxisWidth, height: plotHeight)

                    ZStack(alignment: .topLeading) {
                        let columnWidth = plotWidth / 24
                        Path { path in
                            for column in 0...24 {
                                let x = plotWidth * CGFloat(column) / 24
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: plotHeight))
                            }
                        }
                        .stroke(Palette.grid, lineWidth: 1)
                        ForEach(0..<5, id: \.self) { row in
                            Rectangle().fill(Palette.grid).frame(width: plotWidth, height: 1)
                                .offset(y: plotHeight * CGFloat(row) / 4)
                        }
                        ForEach(0..<24, id: \.self) { index in
                            ForEach(segments.filter { $0.hourIndex == index }) { segment in
                                let startY = plotHeight * CGFloat(segment.startMinute / 60)
                                let segmentHeight = plotHeight * CGFloat((segment.endMinute - segment.startMinute) / 60)
                                let barWidth = max(1, columnWidth - 3)
                                let centeredX = CGFloat(index) * columnWidth + (columnWidth - barWidth) / 2
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(segment.classification.dashboardColor)
                                    .frame(width: barWidth, height: segmentHeight)
                                    .offset(x: centeredX, y: startY)
                                    .help(segmentHelp(segment, hour: hours[index]))
                            }
                        }
                    }
                    .frame(width: plotWidth, height: plotHeight)
                    .background(Palette.panel.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.grid, lineWidth: 1))
                }
                .frame(height: plotHeight)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    private func segmentHelp(_ segment: ScreenTimeChartSegment, hour: Int) -> String {
        let start = Int(segment.activityWindowStartMinute.rounded(.down))
        let end = Int(segment.activityWindowEndMinute.rounded(.up))
        let trackedMinutes = Int(segment.trackedDuration / 60)
        let trackedSeconds = Int(segment.trackedDuration) % 60
        return "\(segment.activityName) · \(segment.classification.displayName) · \(trackedMinutes)m \(trackedSeconds)s tracked between \(hourLabel(hour)) \(String(format: "%02d", start))–\(String(format: "%02d", end))"
    }
}

private struct FocusDriftCard: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let displayedDate: Date

    var body: some View {
        let points = tracker.focusDriftPoints(
            for: displayedDate,
            classificationRules: store.classificationRules
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Focus / drift score").font(.system(size: 16, weight: .semibold))
                    Text("30 minute windows · maximum 30").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                HStack(spacing: 24) {
                    Label("Focus", systemImage: "circle.fill").foregroundStyle(Palette.focus)
                    Label("Drift", systemImage: "circle.fill").foregroundStyle(Palette.warning)
                }.font(.system(size: 10))
            }
            GeometryReader { proxy in
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { row in
                            Rectangle().fill(Palette.grid).frame(height: 1)
                            if row != 3 { Spacer() }
                        }
                    }
                    if points.isEmpty {
                        Text("Classified activity will build this trend")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    } else {
                        scoreAreaPath(points: points, size: proxy.size, keyPath: \.focusScore)
                            .fill(Palette.focus.opacity(0.12))
                        scoreAreaPath(points: points, size: proxy.size, keyPath: \.driftScore)
                            .fill(Palette.warning.opacity(0.10))
                        scorePath(points: points, size: proxy.size, keyPath: \.focusScore)
                            .stroke(Palette.focus, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        scorePath(points: points, size: proxy.size, keyPath: \.driftScore)
                            .stroke(Palette.warning, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round, dash: [5, 4]))
                    }
                }
            }
        }
        .padding(18).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }

    private func scorePath(
        points: [FocusDriftPoint],
        size: CGSize,
        keyPath: KeyPath<FocusDriftPoint, Double>
    ) -> Path {
        let chartPoints = points.map { chartPoint(for: $0, size: size, keyPath: keyPath) }
        var path = Path()
        guard let first = chartPoints.first else { return path }
        path.move(to: first)
        guard chartPoints.count > 1 else { return path }

        for index in 0..<(chartPoints.count - 1) {
            let previous = chartPoints[max(0, index - 1)]
            let current = chartPoints[index]
            let next = chartPoints[index + 1]
            let following = chartPoints[min(chartPoints.count - 1, index + 2)]
            let lowerY = min(current.y, next.y)
            let upperY = max(current.y, next.y)
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: min(upperY, max(lowerY, current.y + (next.y - previous.y) / 6))
            )
            let control2 = CGPoint(
                x: next.x - (following.x - current.x) / 6,
                y: min(upperY, max(lowerY, next.y - (following.y - current.y) / 6))
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        return path
    }

    private func scoreAreaPath(
        points: [FocusDriftPoint],
        size: CGSize,
        keyPath: KeyPath<FocusDriftPoint, Double>
    ) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }
        var area = scorePath(points: points, size: size, keyPath: keyPath)
        let firstPoint = chartPoint(for: first, size: size, keyPath: keyPath)
        let lastPoint = chartPoint(for: last, size: size, keyPath: keyPath)
        area.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
        area.addLine(to: CGPoint(x: firstPoint.x, y: size.height))
        area.closeSubpath()
        return area
    }

    private func chartPoint(
        for point: FocusDriftPoint,
        size: CGSize,
        keyPath: KeyPath<FocusDriftPoint, Double>
    ) -> CGPoint {
        let x = size.width * CGFloat(point.windowIndex) / 48
        let score = min(30, max(0, point[keyPath: keyPath]))
        let y = size.height * (1 - CGFloat(score / 30))
        return CGPoint(x: x, y: y)
    }
}

private struct ProductivityCard: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let displayedDate: Date

    var body: some View {
        let summary = tracker.productivitySummary(
            for: displayedDate,
            classificationRules: store.classificationRules
        )
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Day’s productivity")
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
                ProductivityRing(summary: summary)
                    .frame(width: 82, height: 82)
            }
            VStack(alignment: .leading, spacing: 9) {
                StatRow(name: "Focus", value: tracker.shortDuration(summary.focusDuration), color: Palette.focus)
                StatRow(name: "Neutral", value: tracker.shortDuration(summary.neutralDuration), color: Palette.neutral)
                StatRow(name: "Drift", value: tracker.shortDuration(summary.driftDuration), color: Palette.warning)
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 7) {
                Text(summary.totalDuration > 0 ? "\(summary.grade) grade" : "No grade yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(summary.totalDuration > 0 ? Palette.focus : Palette.muted)
                Text(productivityMessage(summary))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 108, alignment: .leading)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }

    private func productivityMessage(_ summary: ScreenTimeProductivitySummary) -> String {
        guard summary.totalDuration > 0 else { return "Classify activity in Settings to calculate your score." }
        switch summary.score {
        case 90...: return "Excellent focus day"
        case 80...: return "Strong focus day"
        case 70...: return "Productive day"
        case 60...: return "Mixed focus day"
        default: return "High-drift day"
        }
    }
}

private struct ProductivityRing: View {
    let summary: ScreenTimeProductivitySummary

    var body: some View {
        ZStack {
            Circle().stroke(Palette.progressBackground, lineWidth: 9)
            if summary.totalDuration > 0 {
                ForEach(Array(ProductivityClassification.allCases.enumerated()), id: \.offset) { index, classification in
                    let bounds = segmentBounds(for: index)
                    Circle()
                        .trim(from: bounds.start, to: bounds.end)
                        .stroke(
                            classification.dashboardColor,
                            style: StrokeStyle(lineWidth: 9, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            Text("\(summary.score)%").font(.system(size: 20, weight: .bold))
        }
    }

    private func segmentBounds(for index: Int) -> (start: CGFloat, end: CGFloat) {
        guard summary.totalDuration > 0 else { return (0, 0) }
        let classifications = ProductivityClassification.allCases
        let startDuration = classifications.prefix(index).reduce(0) {
            $0 + summary.duration(for: $1)
        }
        let endDuration = startDuration + summary.duration(for: classifications[index])
        return (
            CGFloat(startDuration / summary.totalDuration),
            CGFloat(endDuration / summary.totalDuration)
        )
    }
}

private struct StatRow: View {
    let name: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).frame(width: 48, alignment: .leading)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

private struct TopActivityCard: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let displayedDate: Date

    var body: some View {
        let summaries = tracker.topActivities(
            for: displayedDate,
            classificationRules: store.classificationRules,
            limit: 3
        )
        VStack(alignment: .leading, spacing: 7) {
            Text("Top apps & sites").font(.system(size: 16, weight: .semibold))
            if summaries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis").foregroundStyle(Palette.muted)
                    Text("Screen-time data will appear here")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
                    TopActivityRow(
                        rank: index + 1,
                        summary: summary,
                        maximumDuration: summaries.first?.duration ?? 1
                    )
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }
}

private struct TopActivityRow: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let rank: Int
    let summary: ScreenTimeActivitySummary
    let maximumDuration: TimeInterval

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 7) {
                Text("\(rank)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(summary.classification.dashboardColor)
                    .frame(width: 18, height: 18)
                    .background(summary.classification.dashboardColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text("\(summary.classification.displayName) · \(summary.kind.displayName)")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(tracker.shortDuration(summary.duration))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.progressBackground)
                    Capsule().fill(summary.classification.dashboardColor)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .padding(.leading, 25)
        }
    }

    private var progress: CGFloat {
        guard maximumDuration > 0 else { return 0 }
        return CGFloat(min(1, summary.duration / maximumDuration))
    }
}

private struct InsightDaySummary: Identifiable {
    let date: Date
    let productivity: ScreenTimeProductivitySummary

    var id: Date { date }
}

private struct InsightActivityTotal: Identifiable {
    let id: String
    let name: String
    let kind: ActivitySourceKind
    let classification: ProductivityClassification
    var duration: TimeInterval
}

private struct InsightsPage: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var tracker: ScreenTimeTracker
    @State private var anchorDate = Date()
    private let calendar = Calendar.current

    private var days: [InsightDaySummary] {
        let end = tracker.trackingDay(containing: anchorDate)
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: end) else { return nil }
            return InsightDaySummary(
                date: date,
                productivity: tracker.productivitySummary(
                    for: date,
                    classificationRules: store.classificationRules
                )
            )
        }
    }

    private var totalSummary: ScreenTimeProductivitySummary {
        days.reduce(ScreenTimeProductivitySummary(focusDuration: 0, neutralDuration: 0, driftDuration: 0)) {
            ScreenTimeProductivitySummary(
                focusDuration: $0.focusDuration + $1.productivity.focusDuration,
                neutralDuration: $0.neutralDuration + $1.productivity.neutralDuration,
                driftDuration: $0.driftDuration + $1.productivity.driftDuration
            )
        }
    }

    private var averageScore: Int {
        let activeDays = days.filter { $0.productivity.totalDuration > 0 }
        guard !activeDays.isEmpty else { return 0 }
        return activeDays.reduce(0) { $0 + $1.productivity.score } / activeDays.count
    }

    private var bestDay: InsightDaySummary? {
        days.filter { $0.productivity.totalDuration > 0 }
            .max { $0.productivity.score < $1.productivity.score }
    }

    private var topActivities: [InsightActivityTotal] {
        var totals: [String: InsightActivityTotal] = [:]
        for day in days {
            for activity in tracker.topActivities(
                for: day.date,
                classificationRules: store.classificationRules,
                limit: 1_000
            ) {
                if var existing = totals[activity.id] {
                    existing.duration += activity.duration
                    totals[activity.id] = existing
                } else {
                    totals[activity.id] = InsightActivityTotal(
                        id: activity.id,
                        name: activity.name,
                        kind: activity.kind,
                        classification: activity.classification,
                        duration: activity.duration
                    )
                }
            }
        }
        return Array(totals.values)
            .sorted { $0.duration == $1.duration ? $0.name < $1.name : $0.duration > $1.duration }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        let summary = totalSummary
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Insights").font(.system(size: 26, weight: .bold))
                    Text(rangeLabel).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                InsightNavigationButton(symbol: "chevron.left", help: "Previous week") { moveWeek(-1) }
                Button("This week") { anchorDate = Date() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 82, height: 34)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
                InsightNavigationButton(symbol: "chevron.right", help: "Next week") { moveWeek(1) }
            }

            HStack(spacing: 14) {
                InsightMetricCard(
                    title: "Total screen time",
                    value: tracker.shortDuration(summary.totalDuration),
                    detail: "Across seven days",
                    symbol: "clock"
                )
                InsightMetricCard(
                    title: "Flow time",
                    value: tracker.shortDuration(summary.focusDuration),
                    detail: percentageDetail(summary.focusDuration, total: summary.totalDuration),
                    symbol: "bolt.fill"
                )
                InsightMetricCard(
                    title: "Average score",
                    value: "\(averageScore)%",
                    detail: "On active days",
                    symbol: "gauge.with.dots.needle.50percent"
                )
                InsightMetricCard(
                    title: "Best day",
                    value: bestDay?.date.formatted(.dateTime.weekday(.abbreviated)) ?? "—",
                    detail: bestDay.map { "\($0.productivity.score)% productivity" } ?? "No activity yet",
                    symbol: "trophy"
                )
            }
            .frame(height: 112)

            HStack(alignment: .top, spacing: 18) {
                InsightTrendCard(days: days)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 18) {
                    InsightBreakdownCard(summary: summary)
                    InsightTopActivitiesCard(activities: topActivities)
                }
                .frame(width: 350)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
    }

    private var rangeLabel: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "Last 7 days" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private func moveWeek(_ offset: Int) {
        anchorDate = calendar.date(byAdding: .day, value: offset * 7, to: anchorDate) ?? anchorDate
    }

    private func percentageDetail(_ value: TimeInterval, total: TimeInterval) -> String {
        guard total > 0 else { return "No classified time" }
        return "\(Int((value / total * 100).rounded()))% of tracked time"
    }
}

private struct InsightNavigationButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct InsightMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Palette.focus)
            }
            Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
    }
}

private struct InsightTrendCard: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let days: [InsightDaySummary]

    private var maximumDuration: TimeInterval {
        max(1, days.map(\.productivity.totalDuration).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily activity").font(.system(size: 17, weight: .semibold))
                    Text("Tracked time by classification").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                HStack(spacing: 14) {
                    InsightLegend(label: "Flow", color: Palette.focus)
                    InsightLegend(label: "Neutral", color: Palette.neutral)
                    InsightLegend(label: "Brainrot", color: Palette.warning)
                }
            }

            GeometryReader { proxy in
                let chartHeight = max(1, proxy.size.height - 42)
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(days) { day in
                        VStack(spacing: 5) {
                            Text(tracker.shortDuration(day.productivity.totalDuration))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                            Spacer(minLength: 0)
                            VStack(spacing: 1) {
                                InsightBarSegment(
                                    color: Palette.focus,
                                    height: chartHeight * CGFloat(day.productivity.focusDuration / maximumDuration)
                                )
                                InsightBarSegment(
                                    color: Palette.neutral,
                                    height: chartHeight * CGFloat(day.productivity.neutralDuration / maximumDuration)
                                )
                                InsightBarSegment(
                                    color: Palette.warning,
                                    height: chartHeight * CGFloat(day.productivity.driftDuration / maximumDuration)
                                )
                            }
                            .frame(maxWidth: 46)
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(18)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }
}

private struct InsightBarSegment: View {
    let color: Color
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: max(0, height))
    }
}

private struct InsightLegend: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted)
        }
    }
}

private struct InsightBreakdownCard: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let summary: ScreenTimeProductivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Classification breakdown").font(.system(size: 16, weight: .semibold))
            InsightBreakdownRow(name: "Flow", duration: summary.focusDuration, total: summary.totalDuration, color: Palette.focus)
            InsightBreakdownRow(name: "Neutral", duration: summary.neutralDuration, total: summary.totalDuration, color: Palette.neutral)
            InsightBreakdownRow(name: "Brainrot", duration: summary.driftDuration, total: summary.totalDuration, color: Palette.warning)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }
}

private struct InsightBreakdownRow: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let name: String
    let duration: TimeInterval
    let total: TimeInterval
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(tracker.shortDuration(duration)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.progressBackground)
                    Capsule().fill(color).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 6)
        }
    }

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(duration / total)
    }
}

private struct InsightTopActivitiesCard: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    let activities: [InsightActivityTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top apps & sites").font(.system(size: 16, weight: .semibold))
            if activities.isEmpty {
                Text("Screen-time activity will appear here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(activity.classification.dashboardColor)
                            .frame(width: 20, height: 20)
                            .background(activity.classification.dashboardColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(activity.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text("\(activity.classification.displayName) · \(activity.kind.displayName)")
                                .font(.system(size: 8)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text(tracker.shortDuration(activity.duration))
                            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }
}

private struct RightColumn: View {
    var body: some View {
        VStack(spacing: 18) {
            GoalsCard().frame(height: 380)
            TodoCard().frame(maxHeight: .infinity)
        }
    }
}

private struct CardHeader: View {
    let title: String
    let action: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.system(size: 24, weight: .bold))
            Spacer()
            Button(action: action) {
                Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                    .frame(width: 28, height: 28).background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.muted.opacity(0.55), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }
}

private struct GoalsCard: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var showingAddGoal = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CardHeader(title: "Goals") { showingAddGoal = true }
            ScrollView { VStack(spacing: 20) { ForEach(store.goals) { GoalRow(goal: $0) } } }
            Spacer(minLength: 0)
        }
        .padding(20).background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .sheet(isPresented: $showingAddGoal) { AddGoalSheet(isPresented: $showingAddGoal) }
    }
}

private struct GoalRow: View {
    @EnvironmentObject private var store: DashboardStore
    let goal: GoalItem
    @State private var showingProgressEditor = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(goal.title)
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer()
                Button { showingProgressEditor = true } label: {
                    Text("\(goal.progress)%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.focus)
                }
                .buttonStyle(.plain)
                .help("Edit progress")
                Button { store.deleteGoal(goal.id) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Delete goal")
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.progressBackground)
                    Capsule().fill(Palette.focus).frame(width: proxy.size.width * CGFloat(goal.progress) / 100)
                }
            }.frame(height: 10)
        }
        .sheet(isPresented: $showingProgressEditor) {
            EditGoalProgressSheet(goal: goal, isPresented: $showingProgressEditor)
        }
    }
}

private struct EditGoalProgressSheet: View {
    @EnvironmentObject private var store: DashboardStore
    let goal: GoalItem
    @Binding var isPresented: Bool
    @State private var progress: Double

    init(goal: GoalItem, isPresented: Binding<Bool>) {
        self.goal = goal
        _isPresented = isPresented
        _progress = State(initialValue: Double(goal.progress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit progress")
                .font(.system(size: 20, weight: .bold))
            Text(goal.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Slider(value: $progress, in: 0...100, step: 1)
                Text("\(Int(progress))%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.focus)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") {
                    store.setGoalProgress(goal.id, progress: Int(progress))
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 340)
    }
}

private struct TodoCard: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var showingAddTodo = false
    @State private var draggedTodoID: UUID?
    @State private var todoDragOffset: CGFloat = 0
    @State private var dividerDragStartIndex: Int?
    @State private var dividerDragOffset: CGFloat = 0
    private var completedCount: Int { store.todos.filter(\.isCompleted).count }
    private var activeTodoCount: Int { store.todos.filter { !$0.isCompleted }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CardHeader(title: "Todo") { showingAddTodo = true }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(store.todos.enumerated()), id: \.element.id) { index, todo in
                        if index == store.todoDividerIndex {
                            todoDivider
                        }
                        todoRow(todo)
                    }
                    if store.todoDividerIndex == activeTodoCount,
                       activeTodoCount == store.todos.count {
                        todoDivider
                    }
                }
            }
            Divider().overlay(Palette.border)
            Text("\(completedCount) of \(store.todos.count) complete")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.focus)
            Text("Completed items clear 24 hours after completion.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        .padding(20).background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .sheet(isPresented: $showingAddTodo) { AddTodoSheet(isPresented: $showingAddTodo) }
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(spacing: 10) {
            Button { store.toggleTodo(todo.id) } label: {
                Image(systemName: todo.isCompleted ? "checkmark" : "square")
                    .font(.system(size: 13, weight: .medium)).frame(width: 14)
            }.buttonStyle(.plain)
            Text(todo.title).font(.system(size: 14))
                .foregroundStyle(todo.isCompleted ? Palette.muted : Palette.ink)
            Spacer()
            Button { store.deleteTodo(todo.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted.opacity(0.75))
            .help("Delete todo")
        }
        .contentShape(Rectangle())
        .offset(y: draggedTodoID == todo.id ? todoDragOffset : 0)
        .zIndex(draggedTodoID == todo.id ? 1 : 0)
        .opacity(draggedTodoID == todo.id ? 0.86 : 1)
        .simultaneousGesture(todoDragGesture(for: todo.id))
        .help("Drag to reorder")
    }

    private var todoDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Palette.border).frame(height: 1)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.muted)
            Rectangle().fill(Palette.border).frame(height: 1)
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .offset(y: dividerDragOffset)
        .zIndex(2)
        .gesture(dividerDragGesture)
        .help("Drag to separate Do Today tasks from the backlog")
    }

    private var dividerDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if dividerDragStartIndex == nil {
                    dividerDragStartIndex = store.todoDividerIndex
                }
                dividerDragOffset = value.translation.height
            }
            .onEnded { value in
                let startIndex = dividerDragStartIndex ?? store.todoDividerIndex
                let rowStride: CGFloat = 34
                let rowDelta = Int((value.translation.height / rowStride).rounded())
                withAnimation(.easeInOut(duration: 0.16)) {
                    store.setTodoDividerIndex(startIndex + rowDelta)
                    dividerDragStartIndex = nil
                    dividerDragOffset = 0
                }
            }
    }

    private func todoDragGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                draggedTodoID = id
                todoDragOffset = value.translation.height
            }
            .onEnded { value in
                guard let sourceIndex = store.todos.firstIndex(where: { $0.id == id }) else {
                    draggedTodoID = nil
                    todoDragOffset = 0
                    return
                }
                let rowStride: CGFloat = 34
                let dividerGap: CGFloat = 44
                let dividerIndex = store.todoDividerIndex
                let startsInBacklog = sourceIndex >= dividerIndex
                let isMovingTowardDivider = startsInBacklog
                    ? value.translation.height < 0
                    : value.translation.height > 0
                let rowsBeforeDivider = startsInBacklog
                    ? max(0, sourceIndex - dividerIndex)
                    : max(0, dividerIndex - 1 - sourceIndex)
                let sameSideDistance = CGFloat(rowsBeforeDivider) * rowStride
                let dragMagnitude = abs(value.translation.height)
                let crossedDivider = isMovingTowardDivider
                    && dragMagnitude >= sameSideDistance + dividerGap
                let logicalTranslation: CGFloat
                if isMovingTowardDivider {
                    let logicalMagnitude = min(dragMagnitude, sameSideDistance)
                        + max(0, dragMagnitude - sameSideDistance - dividerGap)
                    logicalTranslation = value.translation.height < 0
                        ? -logicalMagnitude
                        : logicalMagnitude
                } else {
                    logicalTranslation = value.translation.height
                }
                let rowDelta = Int((logicalTranslation / rowStride).rounded())
                let destination = min(max(sourceIndex + rowDelta, 0), store.todos.count - 1)
                withAnimation(.easeInOut(duration: 0.16)) {
                    store.moveTodo(id, toIndex: destination, crossedDivider: crossedDivider)
                    draggedTodoID = nil
                    todoDragOffset = 0
                }
            }
    }
}

private struct AddTodoSheet: View {
    @EnvironmentObject private var store: DashboardStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New todo").font(.system(size: 22, weight: .bold))
            TextField("What needs doing?", text: $title).textFieldStyle(.roundedBorder).focused($focused).onSubmit(add)
            HStack {
                Spacer(); Button("Cancel") { isPresented = false }
                Button("Add", action: add).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(26).frame(width: 380).onAppear { focused = true }
    }
    private func add() { store.addTodo(title: title); isPresented = false }
}

private struct AddGoalSheet: View {
    @EnvironmentObject private var store: DashboardStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var progress = 0
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New goal").font(.system(size: 22, weight: .bold))
            TextField("Goal name", text: $title).textFieldStyle(.roundedBorder).focused($focused)
            HStack {
                Text("Starting progress"); Spacer()
                TextField("0", value: $progress, format: .number).textFieldStyle(.roundedBorder).frame(width: 64)
                Text("%")
            }
            HStack {
                Spacer(); Button("Cancel") { isPresented = false }
                Button("Add") { store.addGoal(title: title, progress: progress); isPresented = false }
                    .keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(26).frame(width: 400).onAppear { focused = true }
    }
}

enum Palette {
    static let canvas = Color(red: 0.93, green: 0.92, blue: 0.89)
    static let panel = Color(red: 0.985, green: 0.98, blue: 0.96)
    static let surface = Color(red: 0.975, green: 0.97, blue: 0.94)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.09)
    static let muted = Color(red: 0.39, green: 0.40, blue: 0.36)
    static let border = Color(red: 0.78, green: 0.77, blue: 0.70)
    static let selected = Color(red: 0.77, green: 0.83, blue: 0.70)
    static let track = Color(red: 0.86, green: 0.86, blue: 0.82)
    static let progressBackground = Color(red: 0.87, green: 0.87, blue: 0.82)
    static let grid = Color(red: 0.88, green: 0.87, blue: 0.82)
    static let focus = Color(red: 0.40, green: 0.53, blue: 0.25)
    static let neutral = Color(red: 0.35, green: 0.43, blue: 0.49)
    static let drift = Color(red: 0.47, green: 0.29, blue: 0.43)
    static let warning = Color(red: 0.65, green: 0.25, blue: 0.22)
}

private extension ProductivityClassification {
    var dashboardColor: Color {
        switch self {
        case .flow: Palette.focus
        case .neutral: Palette.neutral
        case .brainrot: Palette.warning
        }
    }
}
