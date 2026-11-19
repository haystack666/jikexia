import SwiftUI
import UIKit

struct ListeningSettingsView: View {
    @ObservedObject var store: HearingStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsPrivacy = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform").font(.title2).foregroundStyle(Color.teal)
                            .frame(width: 52, height: 52).background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("即刻匣").font(.title3.weight(.semibold))
                            Text("读懂你的设备使用习惯").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section {
                    HStack {
                        Label("当前数据", systemImage: "chart.bar.doc.horizontal")
                        Spacer()
                        Text(store.mode == .demo ? "演示数据" : "Apple 健康").foregroundStyle(.secondary)
                    }
                    Button { Task { await store.connect() } } label: {
                        HStack {
                            Label(store.mode == .health ? "管理健康访问" : "连接 Apple 健康", systemImage: "heart.fill")
                            Spacer()
                            if store.isConnecting { ProgressView() }
                            else { Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
                        }
                    }
                    .disabled(store.isConnecting || !HearingHealthClient.isAvailable)
                    Button { store.showDemo() } label: {
                        HStack {
                            Label("使用演示数据", systemImage: "sparkles")
                            Spacer()
                            if store.mode == .demo { Image(systemName: "checkmark") }
                        }
                    }
                } header: { Text("报告来源") } footer: {
                    Text(HearingHealthClient.isAvailable ? "只请求读取耳机声音水平和耳机通知。演示与个人记录始终分开显示，不会混合统计。" : "当前设备无法访问健康数据。iPad 需要 iPadOS 17 或更新版本；你仍可在支持的设备上预览演示报告。")
                }
                if let error = store.errorMessage {
                    Section { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                }
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Label("打开系统设置", systemImage: "gearshape") }
                    Text("若曾拒绝访问，请前往健康 App → 个人头像 → App → 即刻匣，调整读取权限。返回后下拉刷新报告。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("访问权限") }
                Section {
                    Button { showsPrivacy = true } label: { Label("数据说明与隐私", systemImage: "hand.raised") }
                    Link(destination: URL(string: "https://support.apple.com/en-us/108968")!) {
                        Label("Apple 耳机声音说明", systemImage: "arrow.up.right.square")
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("关于") } footer: { Text("给耳朵一点留白。") }
            }
            .navigationTitle("数据与设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showsPrivacy) { ListeningPrivacyView() }
        }.navigationViewStyle(.stack).tint(.teal)
    }
}

struct ListeningPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                Section {
                    Label("你的聆听，留在你的设备", systemImage: "lock.shield")
                        .font(.headline).padding(.vertical, 8)
                    Text("这一版本在本机读取和分析健康数据，不上传至服务器，不接入广告或第三方统计。不会录音，也不会读取歌曲、聊天或通话内容。")
                }
                Section("我们读取什么") {
                    explanation("耳机声音水平", "从 Apple 健康读取声音暴露样本，统计记录覆盖的时长与等效声级。声音数据来自系统及其他获授权的数据来源，不保证全部来自 AirPods。")
                    explanation("耳机通知", "读取系统已经保存的耳机声音暴露提醒。没有提醒记录，并不代表任何音量都适合长时间聆听。")
                    explanation("音频设备", "从健康听音记录中的设备字段整理历史设备，设备页仅显示累计超过 5 分钟的历史设备。允许蓝牙访问后，在前台读取系统已连接设备的标准设备信息服务，只展示型号可确认的耳机；不会扫描附近设备或读取配对列表。蓝牙连接信息仅在内存中处理，不用于推断佩戴时间或分配健康记录。展示配色保存在本机，不上传、不备份到 iCloud。")
                    explanation("个人纪录", "基于全部可读取的声音暴露历史，按当前时区计算单日、连续时段、连续日历日及自然月纪录。声音记录不等同于真实佩戴，重叠时段去重，不填补空白。只将明确提供耳机型号的样本参与耳机排行。")
                }
                Section("如何理解报告") {
                    explanation("时长有边界", "听音记录不等于全部佩戴时间，也不能完整代表通话时长。缺失记录会留空，不会补成零。")
                    explanation("声级有口径", "等效声级表示一段时间内的声音暴露水平，不是瞬时峰值。报告使用健康数据的统计结果，不将分贝直接做算术平均。图中的 80 dBA 是参考线，不是诊断界限。")
                    explanation("数据可能不完整", "设备、耳机、系统设置及授权范围会影响记录覆盖，更新也可能存在延迟。暂无记录可能意味着没有数据，也可能意味着未允许访问；App 无法直接区分。")
                }
                Section("你始终可以选择") {
                    Text("在健康 App 中更改权限，或切换到演示报告。只有主动点击分享时，才会打开系统分享面板，由你决定报告去向。")
                    Text("本报告用于了解听音习惯，不提供医学诊断。").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .navigationTitle("数据与隐私").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).tint(.teal)
    }
    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 5)
    }
}

struct ListeningRecordsView: View {
    let sessions: [ListeningSession]
    let isDemo: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(sessions) { record in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "waveform").foregroundStyle(Color.teal).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.start.formatted(.dateTime.month().day().hour().minute()))
                                    .font(.subheadline.weight(.medium))
                                Text("至 \(record.end.formatted(.dateTime.month().day().hour().minute()))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(ListeningFormat.duration(record.duration)) · 记录来源：\(record.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("采集设备：\(record.device.flatMap { $0.description.isEmpty ? nil : $0.description } ?? "系统未提供")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("合并 \(record.sampleCount) 条声音样本")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(ListeningFormat.level(record.level)).font(.title3.monospacedDigit().weight(.medium))
                                Text("dBA").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }
                    if sessions.isEmpty { Text("当前周期暂无可读取的听音时段").foregroundStyle(.secondary) }
                } header: { Text((isDemo ? "演示数据" : "当前周期") + " · \(sessions.count) 个听音时段") } footer: {
                    Text("同一设备、同一来源中首尾相接或重叠的分钟样本合并为一个时段，不填补记录间隔。声级按声音能量和覆盖时间计算。时段表示声音记录连续，不等同于一次完整佩戴；采集设备也可能是 iPhone 或 Watch。")
                }
            }
            .navigationTitle("听音记录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).tint(.teal)
    }
}

struct ListeningShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
