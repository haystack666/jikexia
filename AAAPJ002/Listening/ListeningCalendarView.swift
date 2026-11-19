import SwiftUI

struct ListeningCalendarView: View {
    @ObservedObject var history: PersonalRecordsStore
    let mode: HearingStore.Mode
    @State private var selectedDate: Date
    @State private var visibleMonth: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(initialDate: Date, history: PersonalRecordsStore, mode: HearingStore.Mode) {
        self.history = history
        self.mode = mode
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
        _visibleMonth = State(initialValue: initialDate)
    }

    private var durations: [Date: TimeInterval] {
        Dictionary(uniqueKeysWithValues: (history.records?.days ?? []).map { ($0.date, $0.duration) })
    }

    private var calendarSheetHeight: CGFloat {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: visibleMonth)!.start
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: start)!.count
        let weeks = (leading + days + 6) / 7
        return CGFloat(236 + weeks * 50)
    }

    var body: some View {
        if #available(iOS 16, *) {
            calendarContent
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(calendarSheetHeight)])
                .presentationDragIndicator(.visible)
        } else {
            calendarContent
        }
    }

    private var calendarContent: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .demo {
                            Label("示例日历", systemImage: "sparkles")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if history.isLoading && history.records == nil {
                            ProgressView("正在读取每日听音时长…").frame(maxWidth: .infinity).padding(.vertical, 60)
                        } else if let error = history.error, history.records == nil {
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                            Button("重新读取") { Task { await history.reload(mode: mode) } }
                        } else {
                            CompactListeningCalendar(durations: durations, selectedDate: $selectedDate, month: $visibleMonth)
                                .padding(12).listeningGlass()
                            Text("日期下方为当日听音时长，— 表示暂无记录。")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            if history.error != nil && history.records != nil {
                                Text("刷新未完成，暂时显示上次读取的数据。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: max(0, min(geometry.size.width - 40, 560)))
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(ListeningBackdrop())
            .navigationTitle("听音日历").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { if history.records == nil { await history.reload(mode: mode) } }
            .refreshable { await history.reload(mode: mode) }
        }.navigationViewStyle(.stack).tint(.teal)
    }
}

private enum CalendarListeningFormat {
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
    static func compact(_ seconds: TimeInterval?) -> String {
        guard let seconds = seconds, seconds > 0 else { return "—" }
        let minutes = Int(seconds / 60)
        if minutes == 0 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes / 60)h\(minutes % 60)m"
    }
}

private struct CompactListeningCalendar: View {
    let durations: [Date: TimeInterval]
    @Binding var selectedDate: Date
    @Binding var month: Date
    private let calendar = Calendar.current
    private var start: Date { calendar.dateInterval(of: .month, for: month)!.start }
    private var slots: [Date?] {
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        return Array(repeating: nil, count: leading) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(String(CalendarListeningFormat.date(start).prefix(7)))
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(start.formatted(.dateTime.year().month(.wide)))
                Spacer()
                Button { month = calendar.date(byAdding: .month, value: -1, to: start)! } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }.accessibilityLabel("上个月")
                Button { month = calendar.date(byAdding: .month, value: 1, to: start)! } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }.disabled(start >= calendar.dateInterval(of: .month, for: Date())!.start)
                    .accessibilityLabel("下个月")
            }.buttonStyle(.plain).foregroundStyle(Color.teal)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(0..<7) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(slots.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        Button { selectedDate = date } label: {
                            VStack(spacing: 2) {
                                Text("\(calendar.component(.day, from: date))").font(.system(size: 16, weight: .medium))
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(calendar.isDate(date, inSameDayAs: selectedDate) ? Color.white : Color.primary)
                                    .background(Circle().fill(calendar.isDate(date, inSameDayAs: selectedDate) ? Color.teal : .clear))
                                Text(date > calendar.startOfDay(for: Date()) ? " " : CalendarListeningFormat.compact(durations[date]))
                                    .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(Color.teal)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }.frame(maxWidth: .infinity).frame(height: 44)
                        }.buttonStyle(.plain).disabled(date > calendar.startOfDay(for: Date()))
                            .opacity(date > calendar.startOfDay(for: Date()) ? 0.25 : 1)
                            .accessibilityLabel(CalendarListeningFormat.date(date) + "，" + (durations[date].map { ListeningFormat.duration($0) } ?? "暂无记录"))
                    } else { Color.clear.frame(height: 44) }
                }
            }
        }
    }
}
