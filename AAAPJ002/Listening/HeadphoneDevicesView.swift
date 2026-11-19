import SwiftUI
import UIKit
import Charts

struct HeadphoneDevicesView: View {
    @ObservedObject var store: HeadphoneStore
    @ObservedObject var history: PersonalRecordsStore
    let mode: HearingStore.Mode
    @State private var showsBluetoothSettings = false
    @State private var selectedDevice: String?
    @State private var feedbackDevice: String?
    @State private var selectionFeedback = UISelectionFeedbackGenerator()
    @State private var openedDevice: RecordedListeningDevice?
    @State private var returnDeviceID: String?
    @State private var coverRestoreRequest = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var devices: [RecordedListeningDevice] {
        (history.records?.recordedDevices ?? []).filter { $0.duration > 5 * 60 }
            .sorted { $0.duration == $1.duration ? $0.id < $1.id : $0.duration > $1.duration }
    }
    private var deviceIDs: [String] { devices.map { $0.id } }
    private var totalDeviceDuration: TimeInterval { devices.reduce(0) { $0 + $1.duration } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header.padding(.horizontal, 20)
                    if mode == .demo {
                        Label("示例设备 · 连接健康后查看你的记录", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                    }
                    if let error = history.error, history.records != nil {
                        Label("刷新未完成，显示上次读取的数据。" + error, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                    }
                    if history.isLoading && history.records == nil {
                        ProgressView("正在读取听音记录中的设备…")
                            .frame(maxWidth: .infinity).padding(.vertical, 80)
                    } else if let error = history.error, history.records == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Button("重新读取") { Task { await history.reload(mode: mode) } }
                        }.padding(20)
                    } else if devices.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "headphones").font(.largeTitle).foregroundStyle(Color.teal)
                            Text("暂无历史设备").font(.title3.weight(.semibold))
                            Text("累计听音超过 5 分钟的设备会显示在这里。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                            .listeningGlass().padding(.horizontal, 20)
                    } else {
                        carousel
                        durationShares.padding(.horizontal, 20)
                    }
                    if let error = store.storageError {
                        Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                    }
                }.padding(.top, 8).padding(.bottom, 32)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(ListeningBackdrop())
            .background {
                NavigationLink(isActive: Binding(
                    get: { openedDevice != nil },
                    set: { if !$0 { openedDevice = nil } }
                )) {
                    if let item = openedDevice {
                        RecordedListeningDeviceView(item: item, store: store, isDemo: mode == .demo)
                    }
                } label: { EmptyView() }.hidden()
            }
            .refreshable { store.refresh(); await history.reload(mode: mode) }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if store.bluetoothAccessDenied { showsBluetoothSettings = true }
                        else { store.detectConnectedHeadphones() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("识别已连接的耳机")
                }
            }
            .onAppear {
                reconcileSelection()
                restoreReturnedCover()
                selectionFeedback.prepare()
            }
            .onChange(of: openedDevice?.id) { value in
                if value == nil { restoreReturnedCover() }
            }
            .onChange(of: selectedDevice) { value in
                if let previous = feedbackDevice, let value = value,
                   previous != value, deviceIDs.contains(previous) {
                    selectionFeedback.selectionChanged()
                    selectionFeedback.prepare()
                }
                feedbackDevice = value
            }
            .onChange(of: deviceIDs) { _ in reconcileSelection() }
            .alert("需要蓝牙访问权限", isPresented: $showsBluetoothSettings) {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("允许蓝牙访问后，才能读取已连接耳机提供的型号信息。")
            }
        }.navigationViewStyle(.stack)
    }

    @ViewBuilder private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { title; connectedCapsule }
        } else {
            HStack(spacing: 12) { title; connectedCapsule; Spacer(minLength: 0) }
        }
    }
    private var title: some View {
        Text("我的设备").font(.largeTitle.bold()).fixedSize(horizontal: true, vertical: false)
    }
    @ViewBuilder private var connectedCapsule: some View {
        if let device = store.connectedHeadphones.first {
            if store.connectedHeadphones.count == 1 {
                NavigationLink { ConnectedHeadphoneView(device: device, store: store) } label: {
                    capsuleLabel(device.product.title)
                }.buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(store.connectedHeadphones) { item in
                        NavigationLink { ConnectedHeadphoneView(device: item, store: store) } label: {
                            Label(item.product.title, systemImage: item.product.symbol)
                        }
                    }
                } label: { capsuleLabel("\(store.connectedHeadphones.count) 副耳机已连接") }
            }
        }
    }
    private func capsuleLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text(text).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(.horizontal, 10).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .accessibilityElement(children: .ignore).accessibilityLabel(text + "，已连接，查看设备")
    }

    private var carousel: some View {
        VStack(spacing: 4) {
            if #available(iOS 17, *) {
                coverFlow
            } else {
                legacyCoverFlow
            }
            HStack(spacing: 8) {
                if devices.count <= 10 {
                    ForEach(devices) { item in
                        Button { withAnimation(.easeInOut(duration: 0.3)) { selectedDevice = item.id } } label: {
                            Capsule().fill(selectedDevice == item.id ? Color.teal : Color.secondary.opacity(0.25))
                                .frame(width: selectedDevice == item.id ? 16 : 5, height: 5)
                                .padding(.vertical, 9)
                        }.accessibilityLabel(deviceTitle(item))
                            .accessibilityAddTraits(selectedDevice == item.id ? .isSelected : [])
                    }
                } else {
                    Text("\((devices.firstIndex { $0.id == selectedDevice } ?? 0) + 1) / \(devices.count)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }.frame(minHeight: 23)
        }
    }

    private var coverHeight: CGFloat { typeSize.isAccessibilitySize ? 324 : 224 }

    @available(iOS 17, *)
    private var coverFlow: some View {
        ScrollViewReader { scroll in
        GeometryReader { viewport in
            let width = min(typeSize.isAccessibilitySize ? 292.0 : 232.0, viewport.size.width * 0.62)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(devices) { item in
                        GeometryReader { geometry in
                            let progress = (geometry.frame(in: .named("deviceCoverFlow")).midX - viewport.size.width / 2) / (width + 8)
                            let distance = min(abs(progress), 1.5)
                            coverCard(item, progress: progress)
                                .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(max(-1.5, min(1.5, -progress)) * 42)),
                                                  axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                .scaleEffect(reduceMotion ? 1 : 1 - distance * 0.12)
                                .offset(x: reduceMotion ? 0 : -max(-1.5, min(1.5, progress)) * 22)
                                .opacity(reduceMotion ? 1 : 1 - distance * 0.16)
                        }.frame(width: width, height: coverHeight)
                            .id(item.id)
                    }
                }.scrollTargetLayout()
                    .padding(.vertical, 10)
            }
            .contentMargins(.horizontal, (viewport.size.width - width) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $selectedDevice, anchor: .center)
            .coordinateSpace(name: "deviceCoverFlow")
            .scrollClipDisabled()
        }.frame(height: coverHeight + 20)
            .onChange(of: coverRestoreRequest) { _ in centerReturnedCover(using: scroll) }
            .onAppear { centerReturnedCover(using: scroll) }
        }
        .id(coverRestoreRequest)
    }

    // iOS 15/16 keep native paging with a compact, perspective-treated cover.
    private var legacyCoverFlow: some View {
        GeometryReader { viewport in
            TabView(selection: $selectedDevice) {
                ForEach(devices) { item in
                    GeometryReader { geometry in
                        let progress = (geometry.frame(in: .global).midX - viewport.frame(in: .global).midX) / viewport.size.width
                        coverCard(item, progress: progress)
                            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(-progress * 42)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                            .scaleEffect(reduceMotion ? 1 : max(0.82, 1 - abs(progress) * 0.12))
                            .frame(width: min(232, viewport.size.width * 0.62), height: coverHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.tag(Optional(item.id))
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
                .id(coverRestoreRequest)
        }.frame(height: coverHeight + 20)
    }

    private func coverCard(_ item: RecordedListeningDevice, progress: CGFloat) -> some View {
        let proximity = 1 - min(abs(progress), 1)
        let emphasis = proximity * proximity * (3 - 2 * proximity)
        return Button { openDevice(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(deviceTitle(item)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                artwork(item).frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 100 : 88)
                    .accessibilityHidden(true)
                DeviceDetailDuration(seconds: item.duration, size: 26)
                    .foregroundStyle(Color.primary)
                Text("累计聆听").font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    // System materials can lose their backdrop during a 3D
                    // transform. Render a stable surface and vary its emphasis
                    // continuously with position, rather than selection state.
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .opacity(0.55 + 0.45 * emphasis)
                }
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06 + 0.04 * emphasis), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(0.025 + 0.045 * emphasis), radius: 10, y: 5)
        }.buttonStyle(.plain)
            .overlay(CoverFlowTapSurface { openDevice(item) })
    }

    private var durationShares: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("聆听时长占比").font(.headline)
                Spacer()
                Text(ListeningFormat.duration(totalDeviceDuration)).font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(devices) { item in
                    NavigationLink {
                        RecordedListeningDeviceView(item: item, store: store, isDemo: mode == .demo)
                    } label: { shareRow(item) }.buttonStyle(.plain)
                    if item.id != devices.last?.id { Divider().padding(.leading, 68) }
                }
            }.padding(.horizontal, 16).listeningGlass()
            Text("按上方设备累计时长计算。不同采集设备的记录可能覆盖同一时段。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func shareRow(_ item: RecordedListeningDevice) -> some View {
        let share = totalDeviceDuration > 0 ? item.duration / totalDeviceDuration : 0
        return HStack(spacing: 14) {
            artwork(item, symbolSize: 30).frame(width: 42, height: 52).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(deviceTitle(item)).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(share.formatted(.percent.precision(.fractionLength(1))))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.teal).monospacedDigit()
                }
                ProgressView(value: share).tint(.teal).accessibilityHidden(true)
                Text(ListeningFormat.duration(item.duration)).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 16).accessibilityElement(children: .combine)
    }
    @ViewBuilder private func artwork(_ item: RecordedListeningDevice, symbolSize: CGFloat = 56) -> some View {
        if let product = item.device.product {
            HeadphoneProductArt(product: product, color: store.ledger.historyColor(for: item.id))
        } else {
            HeadphoneSymbol(symbol: item.device.symbol).font(.system(size: symbolSize, weight: .light))
                .foregroundStyle(Color.teal)
                .frame(width: symbolSize, height: symbolSize)
        }
    }
    private func deviceTitle(_ item: RecordedListeningDevice) -> String {
        item.device.product?.title ?? item.device.name ?? item.device.model ?? "采集设备"
    }
    private func reconcileSelection() {
        if !deviceIDs.contains(selectedDevice ?? "") {
            feedbackDevice = deviceIDs.first
            selectedDevice = deviceIDs.first
        }
    }

    private func openDevice(_ item: RecordedListeningDevice) {
        guard openedDevice == nil else { return }
        returnDeviceID = item.id
        openedDevice = item
    }

    private func restoreReturnedCover() {
        guard openedDevice == nil, let returnedID = returnDeviceID else { return }
        let target = deviceIDs.contains(returnedID) ? returnedID : deviceIDs.first
        feedbackDevice = target
        selectedDevice = target
        returnDeviceID = nil
        // Updating the binding to the same ID does not move a scroll view
        // stopped between targets. Issue an explicit centering request as well.
        coverRestoreRequest += 1
    }

    private func centerReturnedCover(using scroll: ScrollViewProxy) {
        guard let target = selectedDevice, deviceIDs.contains(target) else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { scroll.scrollTo(target, anchor: .center) }
    }
}

/// Receives taps on visible covers even while the native scroll view is
/// decelerating. A normal child button can lose that first tap to stopping the
/// scroll; observing it on the scroll view avoids waiting for center selection.
private struct CoverFlowTapSurface: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.action = action
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view = view else { return }
            coordinator?.install(on: view)
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.remove() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void
        private weak var surface: UIView?
        private weak var scrollView: UIScrollView?
        private lazy var tap: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            return recognizer
        }()

        init(action: @escaping () -> Void) { self.action = action }

        func install(on view: UIView) {
            surface = view
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scroll = candidate as? UIScrollView {
                    guard scroll !== scrollView else { return }
                    remove()
                    surface = view
                    scrollView = scroll
                    scroll.delaysContentTouches = false
                    scroll.addGestureRecognizer(tap)
                    return
                }
                ancestor = candidate.superview
            }
        }

        func remove() {
            scrollView?.removeGestureRecognizer(tap)
            scrollView = nil
            surface = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let surface = surface, surface.window != nil else { return false }
            return surface.bounds.contains(touch.location(in: surface))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let surface = surface,
                  surface.bounds.contains(recognizer.location(in: surface)) else { return }
            if let scroll = scrollView { scroll.setContentOffset(scroll.contentOffset, animated: false) }
            action()
        }
    }
}

struct RecordedListeningDeviceView: View {
    let item: RecordedListeningDevice
    @ObservedObject var store: HeadphoneStore
    var isDemo = false

    var body: some View {
        DeviceDetailView(title: item.device.product?.title ?? item.device.name ?? item.device.model ?? "采集设备",
                         subtitle: isDemo ? "演示设备 · 示例听音记录" : "Apple 健康 · 历史听音记录",
                         product: item.device.product, symbol: deviceSymbol,
                         preferenceKey: item.id, store: store,
                         statistics: item.statistics, totalDuration: item.duration,
                         fields: [DeviceDetailField("名称", item.device.name),
                                  DeviceDetailField("制造商", item.device.manufacturer),
                                  DeviceDetailField("型号编号", item.device.model),
                                  DeviceDetailField("记录来源", item.sources.joined(separator: "、")),
                                  DeviceDetailField("最早记录", DeviceDetailFormat.date(item.firstSeen)),
                                  DeviceDetailField("最近记录", DeviceDetailFormat.date(item.lastSeen))],
                         identityNote: item.device.localIdentifier?.isEmpty == false
                            ? "按健康记录中的设备标识汇总。"
                            : "系统未提供单台设备标识，按设备字段汇总，可能包含多台同型号设备。")
    }

    private var deviceSymbol: String {
        if item.device.isHeadphone { return item.device.symbol }
        let name = ((item.device.model ?? "") + " " + (item.device.name ?? "")).lowercased()
        if name.contains("iphone") { return "iphone" }
        if name.contains("ipad") { return "ipad" }
        if name.contains("watch") { return "applewatch" }
        if name.contains("speaker") || name.contains("音箱") { return "hifispeaker" }
        return "waveform"
    }
}

struct ConnectedHeadphoneView: View {
    let device: ConnectedHeadphone
    @ObservedObject var store: HeadphoneStore

    var body: some View {
        DeviceDetailView(title: device.product.title, subtitle: "蓝牙识别 · 型号已确认",
                         product: device.product, symbol: device.product.symbol,
                         preferenceKey: device.id, store: store,
                         statistics: nil, totalDuration: nil,
                         fields: [DeviceDetailField("名称", device.name),
                                  DeviceDetailField("制造商", device.information.manufacturer),
                                  DeviceDetailField("型号编号", device.information.modelNumber),
                                  DeviceDetailField("产品 ID", device.information.appleProductID.map { String(format: "0x%04X", $0) })],
                         identityNote: "型号来自蓝牙设备信息。颜色由你选择，连接状态不代表佩戴或播放。")
    }
}

private struct DeviceDetailField: Identifiable {
    let title: String
    let value: String
    var id: String { title }
    init(_ title: String, _ value: String?) {
        self.title = title
        self.value = value.flatMap { $0.isEmpty ? nil : $0 } ?? "系统未提供"
    }
}

private enum DeviceDetailFormat {
    static func date(_ date: Date, pattern: String = "yyyy.MM.dd") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

private enum DeviceDetailPeriod: String, CaseIterable, Identifiable {
    case week = "近 7 天", month = "近 30 天", all = "全部"
    var id: String { rawValue }
    func start(now: Date) -> Date? {
        guard self != .all else { return nil }
        return Calendar.current.date(byAdding: .day, value: self == .week ? -6 : -29,
                                     to: Calendar.current.startOfDay(for: now))
    }
}

private struct DeviceDetailView: View {
    let title: String
    let subtitle: String
    let product: HeadphoneProduct?
    let symbol: String
    let preferenceKey: String
    @ObservedObject var store: HeadphoneStore
    let statistics: DeviceListeningStatistics?
    let totalDuration: TimeInterval?
    let fields: [DeviceDetailField]
    let identityNote: String
    @State private var period: DeviceDetailPeriod = .week
    @State private var showsInfo = false
    @State private var showsColors = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private let now = Date()

    private var selectedDays: [PersonalDayRecord] {
        let start = period.start(now: now)
        return (statistics?.days ?? []).filter { start == nil || $0.date >= start! }
    }
    private var selectedDuration: TimeInterval { selectedDays.reduce(0) { $0 + $1.duration } }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(size: 34, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 6)
                if statistics != nil {
                    Picker("听音统计范围", selection: $period) {
                        ForEach(DeviceDetailPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                hero
                if let statistics = statistics, let totalDuration = totalDuration {
                    Text(periodCaption).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("累计聆听时长").font(.headline)
                        DeviceDetailDuration(seconds: totalDuration, size: 38)
                        Text(historyCaption(statistics)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).deviceDetailSurface()
                    LazyVGrid(columns: columns, spacing: 14) {
                        metric("听音时段", footnote: "段 · 全部历史") {
                            Text("\(statistics.sessions.count)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        metric("平均每段", footnote: "全部历史") {
                            DeviceDetailDuration(seconds: statistics.averageSession, size: 30)
                        }
                        metric("最长一段", footnote: statistics.longestSession.map { DeviceDetailFormat.date($0.start) } ?? "暂无记录") {
                            DeviceDetailDuration(seconds: statistics.longestSession?.duration, size: 30)
                        }
                        metric("平均声级", footnote: "dB(A) · 按声音能量计算") {
                            Text(ListeningFormat.level(statistics.averageLevel))
                                .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                    DeviceDetailTrend(days: statistics.days, now: now)
                    Text("按声音记录覆盖时段统计，不等于完整佩戴时间。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("听音统计", systemImage: "waveform.path").font(.headline)
                        Text("暂无可关联的历史记录").font(.title3.weight(.semibold))
                        Text("可在历史设备中查看健康记录。当前蓝牙设备不会仅凭名称或型号与历史自动关联。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).deviceDetailSurface()
                }
                Button { showsInfo = true } label: {
                    HStack {
                        Label("设备信息与统计说明", systemImage: "info.circle")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.font(.subheadline).foregroundStyle(Color.primary).padding(20).deviceDetailSurface()
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.bottom, 32)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(ListeningBackdrop())
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .modifier(DeviceDetailTabBar())
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if product?.supportsColor == true {
                    Button { showsColors = true } label: { Image(systemName: "paintpalette") }
                        .accessibilityLabel("更改展示配色")
                }
                Button { showsInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("设备信息与统计说明")
            }
        }
        .sheet(isPresented: $showsInfo) {
            NavigationView {
                List {
                    Section("设备信息") {
                        ForEach(fields) { field in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(field.title).font(.subheadline)
                                Text(field.value).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }.padding(.vertical, 3)
                        }
                    }
                    Section("统计说明") {
                        Text(identityNote)
                        if statistics != nil {
                            Text("同一设备、同一来源中首尾相接或重叠的声音样本合为一段；有间隔则分段。时段数量不是摘戴次数。")
                            Text("时长合并重叠覆盖，平均声级按声音能量加权计算，不是音量百分比。")
                            if let longest = statistics?.longestSession {
                                Text("最长一段：\(DeviceDetailFormat.date(longest.start, pattern: "yyyy.MM.dd HH:mm")) – \(DeviceDetailFormat.date(longest.end, pattern: "yyyy.MM.dd HH:mm"))")
                            }
                        }
                    }.font(.subheadline)
                }
                .navigationTitle("设备信息").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsInfo = false } } }
            }.navigationViewStyle(.stack)
        }
        .sheet(isPresented: $showsColors) {
            if let product = product {
                NavigationView {
                    HeadphoneColorSelectionView(product: product, selection: Binding(
                        get: { store.ledger.historyColor(for: preferenceKey) },
                        set: { store.setHistoryColor($0, for: preferenceKey) }
                    ))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsColors = false } } }
                }.navigationViewStyle(.stack)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(statistics == nil ? "你的设备" : period.rawValue + "聆听")
                    .font(.headline)
                Spacer(minLength: 10)
                if product?.supportsColor == true {
                    Button { showsColors = true } label: {
                        Label(store.ledger.historyColor(for: preferenceKey).title, systemImage: "circle.lefthalf.filled")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            Group {
                if let product = product {
                    HeadphoneProductArt(product: product, color: store.ledger.historyColor(for: preferenceKey))
                        .shadow(color: Color.black.opacity(0.1), radius: 16, y: 12)
                } else {
                    HeadphoneSymbol(symbol: symbol).font(.system(size: 92, weight: .ultraLight))
                        .foregroundStyle(Color.teal)
                }
            }.frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 160 : 112).padding(.vertical, 4)
            if statistics != nil {
                DeviceDetailDuration(seconds: selectedDuration, size: 42)
                Text("\(selectedDays.count) 个有记录日")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(title).font(.title2.weight(.semibold))
                Text(fields.first(where: { $0.title == "型号编号" })?.value ?? "蓝牙型号已确认")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .listeningGlass()
    }

    private func metric<Value: View>(_ title: String, footnote: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            value().lineLimit(1).minimumScaleFactor(0.65)
            Text(footnote).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(16).deviceDetailSurface()
    }

    private var periodCaption: String {
        let start = period.start(now: now) ?? statistics?.days.first?.date ?? now
        return "\(DeviceDetailFormat.date(start)) – \(DeviceDetailFormat.date(now))"
    }

    private func historyCaption(_ stats: DeviceListeningStatistics) -> String {
        guard let first = stats.days.first?.date, let last = stats.days.last?.date else { return "暂无历史记录" }
        return "\(DeviceDetailFormat.date(first)) – \(DeviceDetailFormat.date(last)) · \(stats.days.count) 个有记录日"
    }
}

private struct DeviceDetailDuration: View {
    let seconds: TimeInterval?
    let size: CGFloat
    var body: some View {
        value.font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityLabel(ListeningFormat.duration(seconds))
    }
    private var value: Text {
        guard let seconds = seconds, seconds.isFinite else { return Text("—") }
        let minutes = max(0, Int(seconds / 60))
        let unit = Font.system(size: size * 0.38, weight: .medium, design: .rounded)
        if minutes >= 60 {
            return Text("\(minutes / 60)") + Text(" h ").font(unit) + Text("\(minutes % 60)") + Text(" min").font(unit)
        }
        if minutes > 0 || seconds <= 0 { return Text("\(minutes)") + Text(" min").font(unit) }
        return Text("<1") + Text(" min").font(unit)
    }
}

private struct DeviceDetailTrend: View {
    let days: [PersonalDayRecord]
    let now: Date
    @State private var selected: Date?
    private var points: [PersonalDayRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let values = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.duration) })
        return (-29...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { PersonalDayRecord(date: $0, duration: values[$0] ?? 0) }
        }
    }
    private var selection: PersonalDayRecord? {
        points.first { $0.date == selected }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("近 30 天聆听趋势").font(.headline)
            HStack {
                if let selection = selection {
                    Text(DeviceDetailFormat.date(selection.date) + " · " + ListeningFormat.duration(selection.duration))
                } else {
                    Text("轻触柱形，查看当天听音时长")
                }
                Spacer(minLength: 0)
                Text("小时")
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if #available(iOS 16, *) { chart }
            else {
                ForEach(Array(points.suffix(7)), id: \.date) { point in
                    HStack {
                        Text(DeviceDetailFormat.date(point.date, pattern: "MM.dd")).font(.caption)
                        ProgressView(value: point.duration, total: max(1, points.map(\.duration).max() ?? 1)).tint(.teal)
                        Text(ListeningFormat.duration(point.duration)).font(.caption2)
                    }
                }
            }
            if !points.contains(where: { $0.duration > 0 }) {
                Text("近 30 天没有可读取的听音记录").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).deviceDetailSurface()
    }

    @available(iOS 16, *)
    private var chart: some View {
        Chart {
            ForEach(points, id: \.date) { point in
                BarMark(x: .value("日期", point.date, unit: .day), y: .value("小时", point.duration / 3600))
                    .foregroundStyle(Color.teal.gradient).cornerRadius(3)
                    .opacity(selected == nil || selected == point.date ? 1 : 0.35)
            }
            if let selection = selection {
                RuleMark(x: .value("选中日期", selection.date, unit: .day)).foregroundStyle(Color.secondary.opacity(0.35))
            }
        }
        .chartYScale(domain: 0...max(1, (points.map(\.duration).max() ?? 0) / 3600 * 1.15))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                if let date = value.as(Date.self) { AxisValueLabel(DeviceDetailFormat.date(date, pattern: "MM.dd")) }
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        let x = event.location.x - geometry[proxy.plotAreaFrame].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        selected = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.date
                    })
            }
        }
        .frame(height: 170)
        .accessibilityLabel("近三十天的每日听音时长")
    }
}

private extension View {
    func deviceDetailSurface() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.035), lineWidth: 0.5))
    }
}

private struct DeviceDetailTabBar: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16, *) { content.toolbar(.hidden, for: .tabBar) }
        else { content }
    }
}
