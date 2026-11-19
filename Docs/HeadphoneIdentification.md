# 耳机型号与展示配色

- Apple 型号编号来源：[识别 AirPods](https://support.apple.com/en-us/109525)。
- 产品 ID 对照参考：[MagicPodsCore AapModelIds.h](https://github.com/steam3d/MagicPodsCore/blob/HEAD/src/sdk/aap/enums/AapModelIds.h)。仅使用型号与编号事实对照，未引入其实现代码。
- 蓝牙广播研究：[LibrePods](https://github.com/librepods-org/librepods/blob/HEAD/android/app/src/main/java/me/kavishdevar/librepods/bluetooth/BLEManager.kt)、[OpenPods](https://github.com/adolfintel/OpenPods)。这些平台能解析 Apple 广播中的型号、部分颜色编码，不等于 iOS 公共接口一定能收到同一广播。当前版本不扫描广播；蓝牙权限用于读取已连接设备的标准设备信息服务。
- iOS 的 AVAudioSession 提供当前音频输出名称、端口类型与 UID，没有产品型号或颜色字段；名称可被用户修改。界面不再显示通用当前音频输出或按名称建议外观，只展示通过蓝牙设备信息确认型号的已连接耳机。
- HealthKit 的 HKDevice 若包含已知产品 ID 或 A 型号，可以查表展示型号。若返回的是 iPhone / Watch 采集设备或未知 ID，保持未归属。手动选择设备外观不会重新分配任何健康记录。
- 设备页从全部可读历史的 HKDevice 整理设备，按设备标识汇总覆盖时长；只显示累计时长超过 5 分钟的历史设备，短记录仍保留在健康数据与统计中。历史设备清单在内存计算，重新读取时更新。当前蓝牙设备与历史设备不会仅凭相同名称合并。
- Max 展示默认星光色。星光、午夜、蓝、紫、橙五种当前配色以离线图片打包。用户可在蓝牙耳机信息页和历史排行中选择，分别保存，不按名字将历史记录与蓝牙设备关联。
- AirPods 1、2、Pro 2 图片分别来自 Apple 商店产品 MMEF2、MV7N2、MTJV3；Pro 2 的充电接口版本共用示意图。Max 早期版本暂共用当前配色示意图。产品图不代表系统已确认实际颜色。
- 统一处理透明边界后，以等比例缩放、最长边 664 px 的方式居中到 800 × 800 透明画布；不拉伸产品，不使用填满容器的裁切。

## 已连接设备的真机验证与实现

- 2026.11.19 在 iPhone 17 Pro / iOS 27.2 实测：ExternalAccessory 的 connectedAccessories 为空；CoreBluetooth retrieveConnectedPeripherals(withServices: [180A]) 可返回已连接 AirPods 和 Apple Watch。
- AirPods 的标准特征返回制造商 Apple Inc.、型号 A3049、PnP ID 原始字节 01 4c 00 24 20 01 00。按小端解码得到 Bluetooth SIG 厂商 0x004C、产品 0x2024，匹配 AirPods Pro 2（USB-C）。耳机改名不影响此结果。
- 另一个同名外围设备仅返回未知产品 ID 0x2018，未将其猜作另一副耳机或合并入历史；Watch7,9 同样不进入耳机列表。未将私人设备名、外围设备 UUID 或健康记录写入此文档。
- 正式实现只查询标准设备信息服务 180A，通过 App 本地连接读取 2A24 / 2A29 / 2A50 后立即释放。无广播扫描、特征写入或私有 API。前台每 15 秒核对系统连接，读取超时 8 秒，后台停止。已完成的设备信息与进行中的读取分开保存；同一连接复用型号，不会因另一设备读取完成、读取失败或场景切换而清空。单次连接枚举缺失约 2 秒后再次确认再移除；蓝牙关闭或权限撤销立即清空。后台保留展示快照，回前台重新核对；实际已确认断连后丢弃型号缓存，下次连接重新读取。
- 只接受已知 A 型号或 Apple 厂商命名空间中的已知 PnP 产品 ID；型号与产品 ID 冲突时隐藏。颜色仍由用户选择。首次蓝牙访问由设备页的检测按钮触发，拒绝授权时历史设备继续可用。
- 这是上述设备与系统版本的实测结果；其他耳机或系统版本是否公开同一服务，需要逐一验证，不能保证覆盖全部型号。
- 2026.11.20 修复后在同一台 iPhone 17 Pro 连续观察约 90 秒：首次识别后，6 次 15 秒周期核对均持续保留 1 副已确认耳机，后续周期无重复型号读取、无中途空列表。暂时缺失、确认断连、重新连接和关闭蓝牙的状态转换另由 Tests/HeadphoneConnectionChecks.swift 回归覆盖；实际物理断连仍需另外验证。
