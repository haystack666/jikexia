import SwiftUI
import UIKit

private enum ListeningTab: Hashable { case report, trends, devices }
private enum ListeningSheet: String, Identifiable {
    case settings, privacy, share, records
    #if DEBUG
    case headphoneColors, deviceDetail, collectorDetail, connectedDetail
    #endif
    var id: String { rawValue }
}

struct ListeningRootView: View {
    @StateObject private var store = HearingStore()
    @StateObject private var headphones = HeadphoneStore()
    @StateObject private var history = PersonalRecordsStore()
    @State private var tab: ListeningTab = .report
    @State private var sheet: ListeningSheet?
    @State private var reportCalendarReport: ListeningReport?
    #if DEBUG
    @State private var previewHeadphoneColor: HeadphoneColor = .starlight
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if requiresNewerIPadOS {
                upgradeView
            } else {
                TabView(selection: $tab) {
                    page(isTrends: false)
                        .tabItem { Label("报告", systemImage: "waveform.path") }.tag(ListeningTab.report)
                    page(isTrends: true)
                        .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(ListeningTab.trends)
                    HeadphoneDevicesView(store: headphones, history: history, mode: store.mode)
                        .tabItem { Label("设备", systemImage: "airpodspro") }.tag(ListeningTab.devices)
                }
                .tint(.teal)
                .task(id: store.queryKey) { await store.reload() }
                .task(id: store.mode.rawValue) { await history.reload(mode: store.mode) }
                .onAppear { if scenePhase == .active { headphones.start() } }
                .onDisappear { headphones.stop() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        headphones.start()
                        Task { await store.reload() }
                        Task { await history.reload(mode: store.mode) }
                    } else { headphones.stop() }
                }
                .sheet(item: $sheet) { item in
                    switch item {
                    case .settings: ListeningSettingsView(store: store)
                    case .privacy: ListeningPrivacyView()
                    case .share: ListeningShareSheet(text: store.shareText)
                    case .records: ListeningRecordsView(sessions: store.report?.sessions ?? [], isDemo: store.mode == .demo)
                    #if DEBUG
                    case .headphoneColors:
                        NavigationView {
                            HeadphoneColorSelectionView(product: .airPodsMax2, selection: $previewHeadphoneColor)
                                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
                        }.navigationViewStyle(.stack)
                    case .deviceDetail, .collectorDetail, .connectedDetail:
                        NavigationView {
                            Group {
                                if item == .connectedDetail {
                                    if let device = headphones.connectedHeadphones.first {
                                        ConnectedHeadphoneView(device: device, store: headphones)
                                    } else { Text("当前没有可识别的蓝牙耳机") }
                                } else if let device = history.records?.recordedDevices.first(where: {
                                    item == .collectorDetail ? !$0.device.isHeadphone : $0.device.product?.supportsColor == true
                                }) ?? (item == .deviceDetail ? history.records?.recordedDevices.first : nil) {
                                    RecordedListeningDeviceView(item: device, store: headphones, isDemo: store.mode == .demo)
                                } else { ProgressView("正在读取设备档案…") }
                            }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
                        }.navigationViewStyle(.stack)
                    #endif
                    }
                }
            }
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--show-trends") { tab = .trends }
            if args.contains("--show-devices") { tab = .devices }
            if args.contains("--show-settings") { sheet = .settings }
            if args.contains("--show-records") { sheet = .records }
            if args.contains("--show-headphone-colors") { sheet = .headphoneColors }
            if args.contains("--show-device-detail") { sheet = .deviceDetail }
            if args.contains("--show-collector-detail") { sheet = .collectorDetail }
            if args.contains("--show-connected-detail") { sheet = .connectedDetail }
            if args.contains("--show-calendar") {
                Task { await store.reload(); reportCalendarReport = store.report }
            }
            #endif
        }
        .sheet(isPresented: Binding(
            get: { reportCalendarReport != nil },
            set: { if !$0 { reportCalendarReport = nil } }
        )) {
            if let report = reportCalendarReport {
                ListeningCalendarView(initialDate: min(Date(), report.interval.end.addingTimeInterval(-1)),
                                      history: history, mode: store.mode)
            }
        }
    }

    private var isWide: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }

    private func page(isTrends: Bool) -> some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !isTrends { pageCaption }

                    if store.mode == .demo { demoBanner }
                    if isTrends {
                        PersonalRecordsSection(history: history, headphones: headphones, mode: store.mode)
                    } else {
                        if !headphones.connectedHeadphones.isEmpty { connectedHeadphonesButton }
                        periodSelector
                        if let error = store.errorMessage { errorBanner(error) }
                        if store.isLoading && store.report == nil {
                            ProgressView("正在整理听音记录…")
                                .frame(maxWidth: .infinity).padding(.vertical, 90)
                        } else if let report = store.report {
                            if report.hasExposure {
                                if isWide {
                                    HStack(alignment: .top, spacing: 20) {
                                        VStack(spacing: 20) {
                                            ListeningHero(report: report)
                                            insightCard(report)
                                        }.frame(maxWidth: .infinity)
                                        VStack(spacing: 20) {
                                            ListeningChartView(report: report, period: store.period, showsDuration: true)
                                            ListeningChartView(report: report, period: store.period)
                                            summaryCard(report)
                                        }.frame(maxWidth: .infinity)
                                    }
                                } else {
                                    ListeningHero(report: report)
                                    ListeningChartView(report: report, period: store.period, showsDuration: true)
                                    ListeningChartView(report: report, period: store.period)
                                    summaryCard(report)
                                    insightCard(report)
                                }
                                recordsButton(report)
                            } else { emptyState }
                        } else if store.errorMessage != nil { emptyState }
                        footer
                    }
                }
                .padding(.horizontal, isWide ? 32 : 20).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: 1160).frame(maxWidth: .infinity)
            }
            .background(ListeningBackdrop())
            .refreshable {
                if isTrends { await history.reload(mode: store.mode) }
                else { await store.reload() }
            }
            .navigationTitle(isTrends ? "聆听统计" : "听音报告")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !isTrends {
                        Button { sheet = .share } label: { Image(systemName: "square.and.arrow.up") }
                            .disabled(store.report?.hasExposure != true).accessibilityLabel("分享听音报告")
                    }
                    Button { sheet = .settings } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("数据与设置")
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var connectedHeadphonesButton: some View {
        Button { tab = .devices } label: {
            HStack(spacing: 12) {
                if let device = headphones.connectedHeadphones.first {
                    HeadphoneProductArt(product: device.product, color: headphones.ledger.historyColor(for: device.id))
                        .frame(width: 48, height: 48).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("已连接的耳机").font(.caption2).foregroundStyle(.secondary)
                    Text(headphones.connectedHeadphones.map { $0.product.title }.joined(separator: "、"))
                        .font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }.foregroundStyle(Color.primary).padding(16).listeningGlass()
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var pageCaption: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text("读懂你的设备使用习惯")
                Label("本机分析", systemImage: "lock.shield")
            }.font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Text("读懂你的设备使用习惯")
                Spacer()
                Label("本机分析", systemImage: "lock.shield")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connectButton: some View {
        Button("连接健康") { sheet = .settings }
            .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(.teal)
    }

    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(Color.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在预览演示报告").font(.subheadline.weight(.medium))
                    Text("示例数据，不代表你的健康记录").font(.caption2).foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 4)
                    connectButton
                }
            }
            if typeSize.isAccessibilitySize { connectButton }
        }
        .padding(14)
        .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var periodSelector: some View {
        VStack(spacing: 14) {
            Picker("报告周期", selection: $store.period) {
                ForEach(ListeningPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                if store.period != .all {
                Button { store.offset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 32, height: 28) }
                    .accessibilityLabel("上一周期")
                }
                Spacer(minLength: 0)
                Button {
                    if let report = store.report { reportCalendarReport = report }
                } label: {
                    HStack(spacing: 6) {
                        Text(ListeningFormat.dateRange(store.interval, period: store.period))
                        Image(systemName: "calendar").font(.caption)
                    }
                    .font(.subheadline.weight(.medium)).monospacedDigit().multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .disabled(store.report == nil)
                Spacer(minLength: 0)
                if store.period != .all {
                Button { store.offset = min(0, store.offset + 1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 28) }
                    .disabled(store.offset >= 0).accessibilityLabel("下一周期")
                }
            }
        }
    }

    private func summaryCard(_ report: ListeningReport) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("记录天数", systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                (Text("\(report.activeDays)").font(.system(size: 28, weight: .semibold, design: .rounded)) + Text(" 天").font(.caption).foregroundColor(.secondary))
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("系统耳机提醒", systemImage: "bell.badge").font(.caption).foregroundStyle(.secondary)
                (Text("\(report.notificationCount)").font(.system(size: 28, weight: .semibold, design: .rounded)) + Text(" 次").font(.caption).foregroundColor(.secondary))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .reportCard()
    }

    private func insightCard(_ report: ListeningReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("聆听切片").font(.headline)
                Spacer()
                Image(systemName: "waveform").foregroundStyle(Color.teal)
            }
            if let busiest = report.busiestPoint {
                insightRow(icon: "clock", title: "听得最多的" + (store.period.bucketComponent == .month ? "月份" : store.period == .day ? "时段" : "一天"), value: bucketTitle(busiest.date), detail: ListeningFormat.duration(busiest.duration))
            }
            Divider()
            if let loudest = report.loudestPoint {
                insightRow(icon: "speaker.wave.2", title: "声音较高的" + (store.period.bucketComponent == .month ? "月份" : store.period == .day ? "时段" : "一天"), value: bucketTitle(loudest.date), detail: "\(ListeningFormat.level(loudest.level)) dBA · 时段等效声级")
            }
        }
        .reportCard()
    }

    private func bucketTitle(_ date: Date) -> String {
        date.formatted(store.period.bucketComponent == .month ? .dateTime.year().month() : store.period == .day ? .dateTime.hour() : .dateTime.month().day().weekday(.wide))
    }

    private func insightRow(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.teal)
                .frame(width: 38, height: 38).background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func recordsButton(_ report: ListeningReport) -> some View {
        Button { sheet = .records } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(Color.teal)
                Text("查看听音时段").font(.subheadline.weight(.medium))
                Spacer()
                Text("\(report.sessions.count) 段").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.foregroundStyle(Color.primary).reportCard(inset: 18)
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "ear.badge.checkmark").font(.system(size: 48, weight: .light)).foregroundStyle(Color.teal)
            Text("让每一次聆听，都有迹可循").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text("这个周期暂无可读取的耳机声音记录。可能尚未产生数据，或未允许访问。听音后再来看看，也可以在健康 App 中检查授权。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("查看数据与访问设置") { sheet = .settings }.buttonStyle(.borderedProminent)
            Button("先看看演示报告") { store.showDemo() }.font(.subheadline)
        }.padding(.vertical, 30).reportCard()
    }

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("暂时无法更新", systemImage: "exclamationmark.circle").font(.subheadline.weight(.medium))
            Text(text).font(.caption).foregroundStyle(.secondary)
            Button("重试") { Task { await store.reload() } }.font(.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading).reportCard()
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: store.mode == .demo ? "sparkles" : "heart.fill")
                    .foregroundStyle(store.mode == .demo ? Color.teal : Color.pink)
                Text(store.mode == .demo ? "演示数据 · 仅供体验" : "数据来自 Apple 健康")
            }
            Text("听音记录不等于全部佩戴时间")
            Button("了解数据与隐私") { sheet = .privacy }.padding(.top, 2)
        }
        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 4)
    }

    private var requiresNewerIPadOS: Bool {
        if #available(iOS 17.0, *) { return false }
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    private var upgradeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "ipad").font(.system(size: 64)).foregroundStyle(Color.teal)
            Text("在更新的 iPadOS 上，读懂你的聆听").font(.title2.bold())
            Text("即刻匣的 iPad 听音报告需要 iPadOS 17 或更新版本，以访问 Apple 健康数据。请更新系统后继续。")
                .foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).padding(40).frame(maxWidth: 560)
    }
}

private struct ListeningHero: View {
    let report: ListeningReport
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("聆听概览", systemImage: "headphones").font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "waveform").foregroundStyle(Color.mint)
            }.foregroundStyle(.white.opacity(0.75))
            if typeSize.isAccessibilitySize {
                durationValue
                soundValue
            } else {
                HStack(alignment: .center, spacing: 16) {
                    durationValue.frame(maxWidth: .infinity, alignment: .leading)
                    soundValue.frame(width: 100, height: 100)
                }
            }
            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "leaf").foregroundStyle(Color.mint)
                Text("给耳朵一点留白，也是一种好习惯。")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(24)
        .background {
            ZStack(alignment: .topTrailing) {
                Color(red: 0.045, green: 0.11, blue: 0.12)
                RadialGradient(colors: [Color.teal.opacity(0.4), .clear], center: .topTrailing, startRadius: 0, endRadius: 280)
                Image(systemName: "waveform").font(.system(size: 170, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.035)).offset(x: 40, y: 25).accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var durationValue: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已记录听音").font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(ListeningFormat.duration(report.duration))
                .font(.system(size: 33, weight: .semibold, design: .rounded))
                .foregroundStyle(.white).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
            Text("在声音里，也在日常里").font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
    }

    @ViewBuilder private var soundValue: some View {
        if #available(iOS 16.0, *), let level = report.averageLevel {
            VStack(spacing: 14) {
                Gauge(value: min(110, max(40, level)), in: 40...110) {
                    Image(systemName: "ear").foregroundColor(.white.opacity(0.8))
                } currentValueLabel: {
                    Text(ListeningFormat.level(level)).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundColor(.white)
                }
                .gaugeStyle(.accessoryCircular).tint(Gradient(colors: [.mint, .teal]))
                .foregroundStyle(.white).scaleEffect(1.35)
                .accessibilityLabel("等效声级").accessibilityValue("\(ListeningFormat.level(level)) dBA")
                Text("dBA · 等效声级").font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            }
        } else {
            VStack(spacing: 8) {
                Text(ListeningFormat.level(report.averageLevel)).font(.system(size: 36, weight: .medium, design: .rounded))
                Text("dBA · 等效声级").font(.caption2)
            }.foregroundStyle(.mint)
        }
    }
}

extension View {
    func reportCard(inset: CGFloat = 20) -> some View {
        padding(inset)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.035), lineWidth: 1))
    }
}
