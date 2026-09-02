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
            Color.clear.frame(height: 46)
            HStack(alignment: .top, spacing: 18) {
                SidebarRail(selection: $page)
                Group {
                    if page == .home {
                        HomeDashboard()
                    } else if page == .stickyNotes {
                        StickyNotesBoard()
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
        .onAppear { store.removeExpiredTodos() }
        .onReceive(cleanupTimer) { store.removeExpiredTodos(now: $0) }
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
                .padding(.horizontal, 26).padding(.bottom, 22)
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
                    tracker.isTracking ? tracker.stopTracking() : tracker.startTracking()
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(tracker.isTracking ? Palette.focus : Palette.muted).frame(width: 7, height: 7)
                        Text(tracker.isTracking ? "Tracking" : "Start tracking")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(tracker.isTracking ? "Stop screen-time tracking" : "Track active apps and browser domains locally")
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
    var body: some View {
        VStack(spacing: 12) {
            TrackedTimeCard().frame(maxHeight: .infinity)
            FocusDriftCard().frame(height: 152)
            HStack(spacing: 26) { ProductivityCard(); DistractionCard() }.frame(height: 166)
        }
        .padding(14).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
    }
}

private struct TrackedTimeCard: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    @State private var displayedDate = Date()
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
            ActivityChart(segments: tracker.chartSegments(for: displayedDate))
        }
        .padding(18).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
        .onAppear { displayedDate = tracker.trackingDay(containing: Date()) }
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
                        ForEach(0...24, id: \.self) { column in
                            Rectangle().fill(Palette.grid).frame(width: 1, height: plotHeight)
                                .offset(x: plotWidth * CGFloat(column) / 24)
                        }
                        ForEach(0..<5, id: \.self) { row in
                            Rectangle().fill(Palette.grid).frame(width: plotWidth, height: 1)
                                .offset(y: plotHeight * CGFloat(row) / 4)
                        }
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(0..<24, id: \.self) { index in
                                ZStack(alignment: .top) {
                                    ForEach(segments.filter { $0.hourIndex == index }) { segment in
                                        let startY = plotHeight * CGFloat(segment.startMinute / 60)
                                        let segmentHeight = plotHeight * CGFloat((segment.endMinute - segment.startMinute) / 60)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Palette.neutral)
                                            .frame(height: max(2, segmentHeight))
                                            .offset(y: startY)
                                            .help(segmentHelp(segment, hour: hours[index]))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 4)
                            }
                        }
                        .frame(width: plotWidth, height: plotHeight)
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
        let start = Int(segment.startMinute.rounded(.down))
        let end = Int(segment.endMinute.rounded(.up))
        return "\(segment.activityName) · \(hourLabel(hour)) \(String(format: "%02d", start))–\(String(format: "%02d", end))"
    }
}

private struct FocusDriftCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Focus / drift score").font(.system(size: 16, weight: .semibold))
                    Text("30 minute windows").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                HStack(spacing: 24) {
                    Label("Focus", systemImage: "circle.fill").foregroundStyle(Palette.focus)
                    Label("Drift", systemImage: "circle.fill").foregroundStyle(Palette.warning)
                }.font(.system(size: 10))
            }
            GeometryReader { _ in
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Spacer()
                        Rectangle().fill(Palette.grid).frame(height: 1)
                    }
                }
            }
        }
        .padding(18).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }
}

private struct ProductivityCard: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker
    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Today’s productivity").font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: true, vertical: false)
                ZStack {
                    Circle().stroke(Palette.progressBackground, lineWidth: 9)
                    Circle().trim(from: 0, to: 0)
                        .stroke(Palette.focus, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("0%").font(.system(size: 21, weight: .bold))
                }.frame(width: 86, height: 86)
            }
            VStack(alignment: .leading, spacing: 10) {
                StatRow(name: "Focus", value: "0h")
                StatRow(name: "Neutral", value: tracker.shortDuration(tracker.todayDuration))
                StatRow(name: "Drift", value: "0h")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text(tracker.isTracking ? "Tracking locally" : "Tracking paused").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.focus)
                Text(tracker.sessions.isEmpty ? "No activity recorded" : "App activity recorded").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
        .padding(18).frame(maxWidth: .infinity).background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border, lineWidth: 1))
    }
}

private struct StatRow: View {
    let name: String
    let value: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.ink).frame(width: 9, height: 9)
            Text(name).frame(width: 52, alignment: .leading)
            Text(value)
        }.font(.system(size: 12))
    }
}

private struct DistractionCard: View {
    @EnvironmentObject private var tracker: ScreenTimeTracker

    var body: some View {
        let summary = tracker.topActivityToday
        VStack(alignment: .leading, spacing: 16) {
            Text("Most used app / website").font(.system(size: 16, weight: .semibold))
            HStack(spacing: 12) {
                Image(systemName: "clock").foregroundStyle(Palette.muted)
                    .frame(width: 30, height: 30).background(Palette.progressBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary?.name ?? "No activity yet").font(.system(size: 13, weight: .semibold))
                    Text(summary == nil ? "Screen-time data will appear here" : "Active app or browser domain")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(summary.map { tracker.shortDuration($0.duration) } ?? "0m").font(.system(size: 14, weight: .semibold))
            }
            Capsule().fill(Palette.progressBackground).frame(height: 8)
            Text(summary.map { "\($0.sessionCount) sessions  ·  \(tracker.shortDuration($0.averageDuration)) average" } ?? "0 sessions  ·  0m average")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .padding(18).frame(maxWidth: .infinity).background(Palette.surface)
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
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(goal.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                TextField("%", value: Binding(get: { goal.progress }, set: { store.setGoalProgress(goal.id, progress: $0) }), format: .number)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.focus).frame(width: 38)
                Text("%").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.focus)
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
    }
}

private struct TodoCard: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var showingAddTodo = false
    private var completedCount: Int { store.todos.filter(\.isCompleted).count }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CardHeader(title: "Todo") { showingAddTodo = true }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(store.todos) { todo in
                        HStack(spacing: 10) {
                            Button { store.toggleTodo(todo.id) } label: {
                                Image(systemName: todo.isCompleted ? "checkmark" : "square")
                                    .font(.system(size: 13, weight: .medium)).frame(width: 14)
                            }.buttonStyle(.plain)
                            Text(todo.title).font(.system(size: 14))
                                .foregroundStyle(todo.isCompleted ? Palette.muted : Palette.ink)
                            Spacer()
                            Button { store.deleteTodo(todo.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(Palette.muted.opacity(0.75)).help("Delete todo")
                        }
                    }
                }
            }
            Divider().overlay(Palette.border)
            Text("\(completedCount) of \(store.todos.count) complete")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.focus)
            Text("Completed items clear automatically after 24 hours.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        .padding(20).background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .sheet(isPresented: $showingAddTodo) { AddTodoSheet(isPresented: $showingAddTodo) }
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
