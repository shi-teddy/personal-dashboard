import SwiftUI

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case month = "Month"
    case week = "Week"

    var id: String { rawValue }
}

struct CalendarPanel: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var displayedMonth = Calendar.current.startOfMonth(containing: Date())
    @State private var selectedDate = Date()
    @State private var hasSelectedDate = false
    @State private var displayMode: CalendarDisplayMode = .month
    @State private var showingAddEvent = false
    @State private var isAgendaVisible = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            calendarToolbar
            Divider().overlay(Palette.grid)
                .padding(.horizontal, 10)

            HStack(alignment: .top, spacing: 18) {
                Group {
                    if displayMode == .month {
                        MonthCalendarGrid(
                            displayedMonth: displayedMonth,
                            selectedDate: $selectedDate,
                            hasSelectedDate: $hasSelectedDate,
                            events: store.calendarEvents,
                            onSelectDate: { isAgendaVisible = true }
                        )
                    } else {
                        WeekCalendarGrid(
                            selectedDate: $selectedDate,
                            hasSelectedDate: $hasSelectedDate,
                            events: store.calendarEvents,
                            onSelectDate: { isAgendaVisible = true }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isAgendaVisible {
                    DayAgendaPanel(selectedDate: selectedDate) {
                        showingAddEvent = true
                    }
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(6)
            .animation(.easeInOut(duration: 0.18), value: isAgendaVisible)
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
        .sheet(isPresented: $showingAddEvent) {
            AddCalendarEventSheet(date: selectedDate, isPresented: $showingAddEvent)
        }
    }

    private var calendarToolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 22, weight: .bold))
                Text(displayMode == .month ? "Month overview" : "Week overview")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()

            CalendarToolbarButton(symbol: "chevron.left", help: "Previous \(displayMode.rawValue.lowercased())") {
                move(by: -1)
            }
            Button("Today") {
                selectedDate = Date()
                hasSelectedDate = true
                isAgendaVisible = true
                displayedMonth = calendar.startOfMonth(containing: Date())
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 74, height: 36)
            .background(Palette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.grid, lineWidth: 1))

            CalendarToolbarButton(symbol: "chevron.right", help: "Next \(displayMode.rawValue.lowercased())") {
                move(by: 1)
            }

            HStack(spacing: 0) {
                ForEach(CalendarDisplayMode.allCases) { mode in
                    CalendarModeButton(title: mode.rawValue, selected: displayMode == mode) {
                        displayMode = mode
                    }
                }
            }
            .padding(4)
            .frame(width: 174)
            .background(Palette.track)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                if isAgendaVisible {
                    hasSelectedDate = false
                    isAgendaVisible = false
                } else {
                    hasSelectedDate = true
                    isAgendaVisible = true
                }
            } label: {
                Image(systemName: isAgendaVisible ? "sidebar.trailing" : "sidebar.trailing")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(isAgendaVisible ? Palette.selected : Palette.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.grid, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(isAgendaVisible ? "Hide day details" : "Show day details")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func move(by value: Int) {
        if displayMode == .month {
            displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
            selectedDate = calendar.date(byAdding: .month, value: value, to: selectedDate) ?? selectedDate
        } else {
            selectedDate = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDate) ?? selectedDate
            displayedMonth = calendar.startOfMonth(containing: selectedDate)
        }
    }
}

private struct CalendarModeButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Palette.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? Palette.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarToolbarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Palette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.grid, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MonthCalendarGrid: View {
    let displayedMonth: Date
    @Binding var selectedDate: Date
    @Binding var hasSelectedDate: Bool
    let events: [CalendarEvent]
    let onSelectDate: () -> Void

    private let calendar = Calendar.current
    private let weekdayLabels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    private var dates: [Date] {
        let start = calendar.startOfMonth(containing: displayedMonth)
        let weekday = calendar.component(.weekday, from: start)
        let leadingDays = (weekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: start) ?? start
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 22)

            GeometryReader { proxy in
                let cellHeight = proxy.size.height / 6
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { column in
                                let date = dates[row * 7 + column]
                                MonthDayCell(
                                    date: date,
                                    isCurrentMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                                    isSelected: hasSelectedDate && calendar.isDate(date, inSameDayAs: selectedDate),
                                    isToday: calendar.isDateInToday(date),
                                    events: events.filter { calendar.isDate($0.startAt, inSameDayAs: date) }
                                ) {
                                    selectedDate = date
                                    hasSelectedDate = true
                                    onSelectDate()
                                }
                                .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight)
                                .clipped()
                            }
                        }
                    }
                }
                .background(Palette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.grid, lineWidth: 1))
            }
        }
    }
}

private struct MonthDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let events: [CalendarEvent]
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle((isSelected || isToday) ? Color.white : (isCurrentMonth ? Palette.ink : Palette.muted.opacity(0.55)))
                .frame(width: 22, height: 22)
                .background(isSelected ? Palette.ink : (isToday ? Palette.warning : Color.clear))
                .clipShape(Circle())

            if !events.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 3) {
                        ForEach(events) { event in
                            EventChip(event: event)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 3)
        .padding(.leading, 4)
        .padding(.trailing, 3)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .clipped()
        .overlay(alignment: .topTrailing) {
            Rectangle().fill(Palette.grid).frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.grid).frame(height: 1)
        }
    }
}

private struct EventChip: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 4) {
            Capsule().fill(event.color.tint).frame(width: 3)
            Text(event.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 5)
        .frame(height: 20)
        .background(event.color.background)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct WeekCalendarGrid: View {
    @Binding var selectedDate: Date
    @Binding var hasSelectedDate: Bool
    let events: [CalendarEvent]
    let onSelectDate: () -> Void
    private let calendar = Calendar.current
    private let startHour = 6
    private let endHour = 23
    private let hourHeight: CGFloat = 52
    private let timeColumnWidth: CGFloat = 48

    private var dates: [Date] {
        let start = calendar.mondayStart(of: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var timelineHeight: CGFloat {
        CGFloat(endHour - startHour) * hourHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: timeColumnWidth)
                ForEach(dates, id: \.self) { date in
                    Button {
                        selectedDate = date
                        hasSelectedDate = true
                        onSelectDate()
                    } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted)
                            Text(date.formatted(.dateTime.day()))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(dayMarkerColor(for: date))
                                .frame(width: 30, height: 30)
                                .background(dayMarkerBackground(for: date))
                                .clipShape(Circle())
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 58)

            Divider().overlay(Palette.grid)

            ScrollView(.vertical) {
                GeometryReader { proxy in
                    let dayWidth = max(1, (proxy.size.width - timeColumnWidth) / 7)
                    ZStack(alignment: .topLeading) {
                        ForEach(startHour...endHour, id: \.self) { hour in
                            let y = CGFloat(hour - startHour) * hourHeight
                            let labelY = if hour == startHour {
                                y + 4
                            } else if hour == endHour {
                                y - 16
                            } else {
                                y - 6
                            }
                            Text(hourLabel(hour))
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.muted)
                                .frame(width: timeColumnWidth - 8, alignment: .trailing)
                                .offset(y: labelY)
                            Rectangle()
                                .fill(Palette.grid)
                                .frame(width: proxy.size.width - timeColumnWidth, height: 1)
                                .offset(x: timeColumnWidth, y: y)
                        }

                        ForEach(0...7, id: \.self) { column in
                            Rectangle()
                                .fill(Palette.grid)
                                .frame(width: 1, height: timelineHeight)
                                .offset(x: timeColumnWidth + CGFloat(column) * dayWidth)
                        }

                        ForEach(Array(dates.enumerated()), id: \.offset) { dayIndex, date in
                            let dayEvents = events.filter { calendar.isDate($0.startAt, inSameDayAs: date) }
                            ForEach(dayEvents) { event in
                                if let placement = placement(for: event, on: date) {
                                    Button {
                                        selectedDate = date
                                        hasSelectedDate = true
                                        onSelectDate()
                                    } label: {
                                        WeekEventBlock(event: event)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: max(22, dayWidth - 8), height: placement.height, alignment: .topLeading)
                                    .offset(
                                        x: timeColumnWidth + CGFloat(dayIndex) * dayWidth + 4,
                                        y: placement.y
                                    )
                                }
                            }
                        }
                    }
                    .frame(height: timelineHeight)
                }
                .frame(height: timelineHeight)
            }
        }
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.grid, lineWidth: 1))
        .padding(8)
    }

    private func dayMarkerBackground(for date: Date) -> Color {
        if hasSelectedDate && calendar.isDate(date, inSameDayAs: selectedDate) { return Palette.ink }
        if calendar.isDateInToday(date) { return Palette.warning }
        return .clear
    }

    private func dayMarkerColor(for date: Date) -> Color {
        (hasSelectedDate && calendar.isDate(date, inSameDayAs: selectedDate)) || calendar.isDateInToday(date)
            ? .white
            : Palette.ink
    }

    private func placement(for event: CalendarEvent, on date: Date) -> (y: CGFloat, height: CGFloat)? {
        guard let visibleStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date),
              let visibleEnd = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date) else {
            return nil
        }
        let clippedStart = max(event.startAt, visibleStart)
        let clippedEnd = min(event.endAt, visibleEnd)
        guard clippedEnd > clippedStart else { return nil }
        let y = CGFloat(clippedStart.timeIntervalSince(visibleStart) / 3600) * hourHeight
        let height = max(22, CGFloat(clippedEnd.timeIntervalSince(clippedStart) / 3600) * hourHeight)
        return (y, height)
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}

private struct WeekEventBlock: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 4) {
            Capsule().fill(event.color.tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                Text(event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.color.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct DayAgendaPanel: View {
    @EnvironmentObject private var store: DashboardStore
    let selectedDate: Date
    let addAction: () -> Void
    private let calendar = Calendar.current

    private var events: [CalendarEvent] {
        store.calendarEvents
            .filter { calendar.isDate($0.startAt, inSameDayAs: selectedDate) }
            .sorted { $0.startAt < $1.startAt }
    }

    private var upcoming: [CalendarEvent] {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDate)) ?? selectedDate
        return Array(store.calendarEvents.filter { $0.startAt >= endOfDay }.sorted { $0.startAt < $1.startAt }.prefix(2))
    }

    private var scheduledDuration: TimeInterval {
        events.reduce(0) { $0 + max(0, $1.endAt.timeIntervalSince($1.startAt)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 18, weight: .bold))
                Text("\(events.count) \(events.count == 1 ? "event" : "events") · \(durationText(scheduledDuration)) scheduled")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            ScrollView {
                VStack(spacing: 12) {
                    if events.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 24, weight: .light))
                            Text("No events scheduled")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ForEach(events) { event in
                            AgendaEventCard(event: event)
                        }
                    }

                    if !upcoming.isEmpty {
                        Divider().overlay(Palette.grid).padding(.vertical, 4)
                        Text("Upcoming")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(upcoming) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(event.color.tint).frame(width: 8, height: 8).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.system(size: 12, weight: .semibold))
                                    Text(event.startAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }

            Button(action: addAction) {
                Label("Add event", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Palette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Palette.canvas.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.grid, lineWidth: 1))
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes == 0 { return "0m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

private struct AgendaEventCard: View {
    @EnvironmentObject private var store: DashboardStore
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 0) {
            Capsule().fill(event.color.tint).frame(width: 5)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(event.startAt.formatted(date: .omitted, time: .shortened)) – \(event.endAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                Text(event.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                if !event.notes.isEmpty {
                    Text(event.notes).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            .padding(14)
            Spacer(minLength: 4)
            Button { store.deleteCalendarEvent(event.id) } label: {
                Image(systemName: "trash").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .padding(.trailing, 12)
            .help("Delete event")
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.grid, lineWidth: 1))
    }
}

private struct AddCalendarEventSheet: View {
    @EnvironmentObject private var store: DashboardStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var notes = ""
    @State private var color: CalendarEventColor = .green
    @FocusState private var titleFocused: Bool

    init(date: Date, isPresented: Binding<Bool>) {
        _isPresented = isPresented
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        _startAt = State(initialValue: start)
        _endAt = State(initialValue: start.addingTimeInterval(60 * 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New event").font(.system(size: 22, weight: .bold))
            TextField("Event name", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
            eventDateRow("Starts", selection: $startAt)
            eventDateRow("Ends", selection: $endAt, range: startAt...)
            TextField("Notes (optional)", text: $notes)
                .textFieldStyle(.roundedBorder)
            Picker("Color", selection: $color) {
                ForEach(CalendarEventColor.allCases) { color in
                    Text(color.displayName).tag(color)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add Event") {
                    store.addCalendarEvent(
                        title: title,
                        startAt: startAt,
                        endAt: endAt,
                        notes: notes,
                        color: color
                    )
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 430)
        .onAppear { titleFocused = true }
        .onChange(of: startAt) { _, newStart in
            if endAt <= newStart { endAt = newStart.addingTimeInterval(60 * 60) }
        }
    }

    private func eventDateRow(
        _ label: String,
        selection: Binding<Date>,
        range: PartialRangeFrom<Date>? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 46, alignment: .leading)

            if let range {
                DatePicker("", selection: selection, in: range, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 136)
                DatePicker("", selection: selection, in: range, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 104)
            } else {
                DatePicker("", selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 136)
                DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 104)
            }
            Spacer(minLength: 0)
        }
    }
}

private extension CalendarEventColor {
    var tint: Color {
        switch self {
        case .green: Palette.focus
        case .purple: Color(red: 0.53, green: 0.39, blue: 0.62)
        case .tan: Color(red: 0.62, green: 0.51, blue: 0.34)
        }
    }

    var background: Color { tint.opacity(0.14) }
}

private extension Calendar {
    func startOfMonth(containing date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    func mondayStart(of date: Date) -> Date {
        let start = startOfDay(for: date)
        let weekday = component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }
}
