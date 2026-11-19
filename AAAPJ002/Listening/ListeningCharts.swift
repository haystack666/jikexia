import SwiftUI
import Charts

struct ListeningChartView: View {
    let report: ListeningReport
    let period: ListeningPeriod
    var showsDuration = false
    @State private var selected: ListeningPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(showsDuration ? "听音时长" : "声音轨迹").font(.headline)
                    Text(selectionDescription).font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Text(showsDuration ? "分钟" : "dBA")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if !report.hasExposure {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").font(.title).foregroundStyle(.tertiary)
                    Text("有记录后，趋势会在这里呈现").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 180)
            } else if #available(iOS 16.0, *) {
                nativeChart
            } else {
                legacyChart
            }
            if !showsDuration {
                HStack(spacing: 6) {
                    Capsule().fill(Color.orange).frame(width: 12, height: 2)
                    Text("80 dBA 参考线 · 声音影响也与持续时间有关")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .reportCard()
        .onChange(of: report.interval) { _ in selected = nil }
    }

    private var selectionDescription: String {
        guard let selected = selected else {
            if #available(iOS 16.0, *) { return "轻触或滑动图表，查看每个时段" }
            return "最近有记录的时段"
        }
        let date = bucketLabel(selected.date)
        let value = showsDuration ? ListeningFormat.duration(selected.duration) : "\(ListeningFormat.level(selected.level)) dBA"
        return "\(date) · \(value)"
    }

    @available(iOS 16.0, *)
    private var nativeChart: some View {
        Chart {
            ForEach(report.points.filter { $0.level != nil }) { point in
                if showsDuration {
                    BarMark(x: .value("时间", point.date, unit: period.bucketComponent), y: .value("分钟", (point.duration ?? 0) / 60))
                        .foregroundStyle(Color.teal.gradient).cornerRadius(4)
                        .opacity(selected == nil || selected?.id == point.id ? 1 : 0.3)
                } else {
                    BarMark(x: .value("时间", point.date, unit: period.bucketComponent), yStart: .value("基线", lowerBound), yEnd: .value("声音水平", point.level ?? lowerBound))
                        .foregroundStyle((point.level ?? 0) >= 80 ? Color.orange.gradient : Color.teal.gradient)
                        .cornerRadius(4)
                        .opacity(selected == nil || selected?.id == point.id ? 1 : 0.3)
                }
            }
            if !showsDuration {
                RuleMark(y: .value("参考线", 80))
                    .foregroundStyle(Color.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let selected = selected {
                RuleMark(x: .value("选中时间", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: report.interval.start...report.interval.end)
        .chartYScale(domain: showsDuration ? 0...durationUpperBound : lowerBound...levelUpperBound)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.secondary.opacity(0.16))
                AxisValueLabel().foregroundStyle(Color.secondary)
            }
        }
        .chartXAxis {
            if period == .day {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                }
            } else if period == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else if period.bucketComponent == .month {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    if let date = value.as(Date.self) { AxisValueLabel(bucketLabel(date)) }
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        selected = report.points.filter { $0.level != nil }.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                    })
            }
        }
        .frame(height: 190)
        .accessibilityLabel(showsDuration ? "听音时长趋势" : "耳机声音水平趋势")
    }

    private func bucketLabel(_ date: Date) -> String {
        switch period {
        case .day: return date.formatted(.dateTime.hour())
        case .week, .month: return date.formatted(.dateTime.month().day())
        case .year: return date.formatted(.dateTime.month())
        case .all: return date.formatted(.dateTime.year().month())
        }
    }

    private var lowerBound: Double { min(40, (report.points.compactMap(\.level).min() ?? 40) - 5) }
    private var levelUpperBound: Double { max(100, (report.points.compactMap(\.level).max() ?? 100) + 5) }
    private var durationUpperBound: Double { max(30, (report.points.compactMap(\.duration).max() ?? 0) / 60 * 1.15) }

    // Native progress views keep the iOS 15 fallback accessible without requiring Charts.
    private var legacyChart: some View {
        VStack(spacing: 12) {
            ForEach(Array(report.points.filter { $0.level != nil }.suffix(7))) { point in
                HStack(spacing: 12) {
                    Text(bucketLabel(point.date))
                        .font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    ProgressView(value: showsDuration ? (point.duration ?? 0) / 60 : (point.level ?? 0), total: showsDuration ? durationUpperBound : levelUpperBound)
                        .tint(.teal)
                    Text(showsDuration ? "\(Int((point.duration ?? 0) / 60))" : ListeningFormat.level(point.level))
                        .font(.caption.monospacedDigit()).frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
