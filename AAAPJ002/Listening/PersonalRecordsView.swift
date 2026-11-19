import SwiftUI
import UIKit

struct PersonalRecordsSection: View {
    @ObservedObject var history: PersonalRecordsStore
    @ObservedObject var headphones: HeadphoneStore
    let mode: HearingStore.Mode
    @State private var showsExplanation = false
    @State private var showsColors = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("个人纪录").font(.title2.weight(.bold))
                    Text("全部可读历史").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { showsExplanation = true } label: { Image(systemName: "info.circle").frame(width: 36, height: 44) }
                    .accessibilityLabel("个人纪录统计口径")
            }
            if let error = history.error, history.records != nil {
                Label("刷新未完成，显示上次读取的数据。" + error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if history.isLoading && history.records == nil {
                ProgressView("正在整理全部历史…").frame(maxWidth: .infinity).padding(40).listeningGlass()
            } else if let error = history.error, history.records == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("暂时无法读取个人纪录").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await history.reload(mode: mode) } }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20).listeningGlass()
            } else if let records = history.records, records.sampleCount > 0 {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    recordCard("单日听音最长", icon: "sun.max", detail: records.longestDay.map { fullDate($0.date) } ?? "暂无记录") {
                        RecordDurationText(seconds: records.longestDay?.duration)
                    }
                    recordCard("单次连续听音", icon: "timer", detail: records.longestSession.map { timeRange($0) } ?? "暂无记录") {
                        RecordDurationText(seconds: records.longestSession?.duration)
                    }
                    recordCard("连续记录最长", icon: "calendar.badge.checkmark", detail: records.longestStreak.map { "\(fullDate($0.start))\n至 \(fullDate($0.end))" } ?? "暂无记录") {
                        (Text("\(records.longestStreak?.days ?? 0)").font(.system(size: 33, weight: .semibold, design: .rounded)) + Text(" 天").font(.subheadline))
                    }
                    recordCard("单月听音最长", icon: "calendar", detail: records.bestMonth.map { "\(numericDate($0.month, format: "yyyy.MM"))\n\($0.days) 个有记录日" } ?? "暂无记录") {
                        RecordDurationText(seconds: records.bestMonth?.duration)
                    }
                }
                favouriteCard(records)
                VStack(alignment: .leading, spacing: 7) {
                    if let range = records.range {
                        Text("已读取 \(fullDate(range.start)) – \(fullDate(range.end))")
                    }
                    Text("\(records.activeDays) 个有记录日 · \(records.sampleCount) 条声音样本")
                    Text("按声音记录覆盖时段计算，不代表完整佩戴时间。长时间听音并非健康目标。")
                }.font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal").font(.largeTitle).foregroundStyle(Color.teal)
                    Text("你的聆听，会在这里留下纪录").font(.headline)
                    Text("暂无可读取的历史声音记录。请在报告页连接 Apple 健康，并检查读取权限；已有记录会参与全部历史统计。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22).listeningGlass()
            }
        }
        .sheet(isPresented: $showsExplanation) { PersonalRecordsExplanationView() }
        .sheet(isPresented: $showsColors) {
            if let favourite = history.records?.headphones.first, let product = favourite.device.product {
                NavigationView {
                    HeadphoneColorSelectionView(product: product, selection: Binding(
                        get: { headphones.ledger.historyColor(for: favourite.id) },
                        set: { headphones.setHistoryColor($0, for: favourite.id) }
                    ))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsColors = false } } }
                }.navigationViewStyle(.stack).tint(.teal)
            }
        }
    }

    private func recordCard<Value: View>(_ title: String, icon: String, detail: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(Color.teal)
                    .frame(width: 28, height: 28).background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                Text(title).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            value().foregroundStyle(Color.primary).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading).padding(16).listeningGlass()
    }

    private func favouriteCard(_ records: PersonalRecords) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("最常听音的耳机", systemImage: "headphones").font(.headline)
            if let favourite = records.headphones.first {
                HStack(alignment: .center, spacing: 18) {
                    Group {
                        if let product = favourite.device.product {
                            HeadphoneProductArt(product: product, color: headphones.ledger.historyColor(for: favourite.id))
                        } else {
                            HeadphoneSymbol(symbol: favourite.device.symbol).font(.system(size: 64, weight: .light)).foregroundStyle(Color.teal)
                        }
                    }.frame(width: 96, height: 110).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(favourite.device.product?.title ?? favourite.device.name ?? favourite.device.model ?? "耳机").font(.headline)
                        RecordDurationText(seconds: favourite.duration)
                        Text(favourite.id.hasPrefix("model:") ? "按系统提供的型号合并统计" : "该设备的历史记录时长")
                            .font(.caption).foregroundStyle(.secondary)
                        if favourite.device.product?.supportsColor == true {
                            Button { showsColors = true } label: {
                                Label(headphones.ledger.historyColor(for: favourite.id).title, systemImage: "paintpalette")
                            }.font(.caption)
                            Text("展示配色，可自行更改").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("暂时无法确认历史耳机").font(.title3.weight(.semibold))
                Text("这些健康样本未提供可确认的耳机型号。当前连接的耳机不会被自动填入历史排行。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if records.unattributedDuration > 0 {
                Text("\(ListeningFormat.duration(records.unattributedDuration))的历史时段无法归属到具体耳机。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).listeningGlass()
    }

    private func numericDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    private func fullDate(_ date: Date) -> String { numericDate(date, format: "yyyy.MM.dd") }
    private func timeRange(_ interval: DateInterval) -> String {
        if Calendar.current.isDate(interval.start, inSameDayAs: interval.end) {
            return fullDate(interval.start) + "\n" + numericDate(interval.start, format: "HH:mm") + " – " + numericDate(interval.end, format: "HH:mm")
        }
        return numericDate(interval.start, format: "yyyy.MM.dd HH:mm") + "\n– " + numericDate(interval.end, format: "yyyy.MM.dd HH:mm")
    }
}

struct RecordDurationText: View {
    let seconds: TimeInterval?
    var body: some View {
        Group {
            if let seconds = seconds, seconds > 0 {
                let minutes = Int(seconds / 60)
                if minutes >= 60 {
                    Text("\(minutes / 60)").font(.system(size: 31, weight: .semibold, design: .rounded)) + Text(" 小时 ").font(.caption) + Text("\(minutes % 60)").font(.system(size: 27, weight: .semibold, design: .rounded)) + Text(" 分").font(.caption)
                } else {
                    Text(minutes == 0 ? "<1" : "\(minutes)").font(.system(size: 31, weight: .semibold, design: .rounded)) + Text(" 分钟").font(.caption)
                }
            } else { Text("—").font(.largeTitle) }
        }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
    }
}

struct HeadphoneSymbol: View {
    var symbol: String = "headphones"
    var body: some View {
        Image(systemName: UIImage(systemName: symbol) == nil ? "headphones" : symbol)
            .symbolRenderingMode(.hierarchical)
    }
}

struct HeadphoneProductArt: View {
    let product: HeadphoneProduct
    let color: HeadphoneColor
    var body: some View {
        Image(product.assetName(color: color))
            .resizable()
            .scaledToFit()
            .accessibilityLabel(product.title + (product.supportsColor ? " · " + color.title : ""))
    }
}

struct HeadphoneColorSelectionView: View {
    let product: HeadphoneProduct
    @Binding var selection: HeadphoneColor

    var body: some View {
        List {
            Section {
                HeadphoneProductArt(product: product, color: selection)
                    .frame(height: 200).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .animation(.easeInOut(duration: 0.2), value: selection)
            }
            Section {
                ForEach(HeadphoneColor.allCases) { color in
                    Button {
                        selection = color
                    } label: {
                        HStack(spacing: 18) {
                            HeadphoneProductArt(product: product, color: color)
                                .frame(width: 60, height: 66).accessibilityHidden(true)
                            Text(color.title).foregroundStyle(Color.primary)
                            Spacer()
                            if selection == color {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.teal)
                            }
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .accessibilityLabel(color.title)
                    .accessibilityValue(selection == color ? "已选择" : "未选择")
                }
            } header: { Text("选择展示配色") } footer: {
                Text("默认使用星光色。此选择仅改变产品示意图，不代表系统读取到的真实颜色，也不会改变听音统计。图片涵盖当前五种配色，部分代际共用外观示意图。")
            }
        }.listStyle(.insetGrouped)
            .navigationTitle("耳机颜色").navigationBarTitleDisplayMode(.inline)
    }
}

struct PersonalRecordsExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                Section("历史范围") {
                    Text("查询 Apple 健康中全部可读取的耳机声音水平样本，不受报告页日、周、月选择影响。权限、删除和同步延迟都会影响范围；没有数据不能证明未佩戴。")
                }
                Section("计算方法") {
                    Text("单日：按当前时区拆分跨午夜记录，重叠或重复的时段只计算一次。")
                    Text("单次：同一设备、同一来源中，仅合并首尾相接或重叠的声音记录。设备或来源不同会分开；有任何间隔也会分开，不把样本间的空白推断为佩戴。无法确认真实摘戴时间。")
                    Text("连续：相邻日历日每天都存在有效记录，跨月、跨年仍可连续。")
                    Text("单月：选择累计记录时长最多的自然月，同时显示有记录天数。")
                    Text("耳机：只统计样本明确提供耳机型号的记录。iPhone、Watch 等采集设备不算耳机；没有设备标识时按型号合并，并在卡片上标注。无法确认的记录保留为未归属。")
                }
                Section("设备图") {
                    Text("已匹配的 AirPods 使用 Apple 产品实物示意图；AirPods 1、2 和 Pro 2 分别提供图片，部分充电接口版本共用外观图。Max 默认展示星光色，可手动选择其他配色。图片和配色均不代表系统确认的实际外观；无法匹配时显示通用图标。")
                }
                Section { Text("这里的时长表示可读取声音样本覆盖的时间，不是医学指标，也不鼓励追求更长的听音纪录。") }
            }.font(.subheadline)
            .navigationTitle("统计口径").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).tint(.teal)
    }
}

extension View {
    func listeningGlass() -> some View {
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.035), radius: 15, y: 6)
    }
}

struct ListeningBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(colors: [Color.teal.opacity(colorScheme == .dark ? 0.2 : 0.14), .clear], center: .topLeading, startRadius: 0, endRadius: 580)
            RadialGradient(colors: [Color.indigo.opacity(colorScheme == .dark ? 0.14 : 0.08), .clear], center: .topTrailing, startRadius: 20, endRadius: 400)
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
