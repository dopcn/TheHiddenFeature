# The Hidden Feature 项目方案

## 1. 文档状态

本文档描述 The Hidden Feature 的产品目标、技术方案和预期使用方式。

当前工程已实现虚拟桌面、附近配对和跨设备拖动首版，并支持 iPhone 与 iPad 混合配对。

## 2. 项目背景

The Hidden Feature 是一个实验性、娱乐用途的双设备互动应用，支持 iPhone 与 iPad 混合配对。它在应用内部模拟一个系统风格的桌面，并通过两台设备之间的实时通信，制造“把一个 App 图标从一台设备直接拖到另一台设备”的视觉效果。

应用不读取或修改真实 iOS 桌面，也不能移动系统中实际安装的 App。所有壁纸、图标、页面和布局均为应用内部维护的虚拟内容。

### 2.1 核心体验

1. 两台 iPhone 或 iPad 分别打开 The Hidden Feature。
2. 用户将两台设备竖屏放置、顶边对齐，并指定左侧设备和右侧设备。
3. 两台设备完成附近连接后，分别显示内容不同的虚拟桌面。
4. 用户长按任意图标进入编辑模式，所有图标开始抖动。
5. 用户可以在本机拖动图标并触发布局重排。
6. 图标被拖到两台设备相邻的屏幕边缘时，目标设备显示同一图标的边缘预览。
7. 手指进入目标设备屏幕后，目标设备接管拖动。
8. 拖动完成后，图标从来源桌面移除并加入目标桌面。

### 2.2 技术边界

两台 iPhone 或 iPad 是相互独立的触摸设备。手指离开来源屏幕后，来源设备的触摸序列会结束，系统不会把同一次触摸事件传递给另一台设备。

因此，本项目实现的是以下组合效果：

- 来源设备播放图标移出动画。
- 两台设备同步图标、位置和交接状态。
- 目标设备在对应边缘显示临时图标。
- 手指触碰目标屏幕后，由一个新的触摸手势继续拖动。

该方案可以获得接近连续跨屏拖动的观感，但不能消除两台设备的实体边框，也不能保证像素级的物理连续。

## 3. 项目范围

### 3.1 首版包含

- iOS 风格的原创虚拟桌面。
- 状态区域、渐变壁纸、分页网格、页面指示器和 Dock。
- 长按进入编辑模式及全体图标抖动。
- 图标本机拖动、换位和弹簧重排动画。
- 左右两台 iPhone 或 iPad 的发现、配对和连接。
- 左到右、右到左的双向图标交接。
- 交接超时、断线和异常消息的安全回滚。
- Debug 日志和基础连接状态提示。

### 3.2 首版不包含

- 访问或修改真实 iOS 桌面。
- 启动真实 App，或为虚拟图标实现完整的假 App 页面。
- 后台、锁屏或应用被终止后的持续交接。
- 云端账户、云同步或跨会话布局保存。
- 使用 UWB 自动判断两台设备的摆放位置。
- App Store 发布和正式分发流程。

## 4. 总体实现方案

### 4.1 技术选型

| 模块 | 方案 |
| --- | --- |
| 界面 | SwiftUI |
| 最低系统 | iOS 17 / iPadOS 17 |
| 支持设备 | iPhone 与 iPad，竖屏全屏 |
| 附近连接 | Multipeer Connectivity |
| 数据编码 | `Codable` 消息封包 |
| 状态管理 | `@MainActor` + Observation |
| 本地存储 | 首版不持久化，每次新配对重置 |
| 第三方依赖 | 无 |

Multipeer Connectivity 可以通过基础 Wi-Fi、点对点 Wi-Fi或蓝牙承载附近设备会话，适合本项目的小数据量、低延迟状态同步。首版不直接实现 Core Bluetooth 协议。

Nearby Interaction 可以提供兼容设备之间的大致距离和方向，但不能直接提供两块屏幕的边缘、尺寸和像素对齐关系，而且会受到硬件和摆放方向限制。因此，首版通过用户选择“左侧设备”和“右侧设备”明确设备关系，不依赖 UWB。

### 4.2 工程配置

实施时需要调整当前 Xcode 工程：

- 将最低部署目标从 iOS 26.2 下调到 iOS 17。
- 将目标设备设置为 iPhone 与 iPad。
- 将 iPhone 与 iPad 支持方向限制为竖屏全屏。
- 添加本地网络用途说明。
- 在 `NSBonjourServices` 中声明 `_hiddenfeature._tcp`。
- 使用 `hiddenfeature` 作为 Multipeer Connectivity 服务类型。
- 增加单元测试和 UI 测试 Target。
- 使用开发者自己的 Apple Development Team 对两台真机签名。

应用不需要蓝牙后台模式，也不申请 Nearby Interaction 权限。

## 5. 界面与本机交互

### 5.1 虚拟桌面

桌面使用原创系统风素材，不直接复制苹果壁纸或第三方 App 图标：

- 壁纸使用 SwiftUI 渐变绘制。
- 图标使用圆角矩形、渐变色和 SF Symbols 组合。
- 左右设备使用不同的虚构 App 集合，每个图标拥有全局唯一 ID。
- 默认采用四列、自适应六行布局。
- 默认提供两个页面和四个 Dock 位置，并预留空格方便重排和接收图标。
- 图标标题、页面布局和 Dock 均由本地模型生成。

图标点击在首版中不打开内容。

### 5.2 编辑和拖动

- 长按图标 0.5 秒进入编辑模式。
- 进入编辑模式时触发一次触觉反馈。
- 所有图标以略有不同的相位持续抖动。
- 当前拖动图标放大并增加阴影，使其与网格中的占位图标区分。
- 图标中心进入其他槽位后更新占位位置，并使用弹簧动画重排。
- 图标可以在当前页面和 Dock 之间移动。
- 目标区域满位时，将已有图标顺延到后续槽位；必要时创建新页面。
- 点击“完成”或桌面空白区域退出编辑模式。

普通状态下允许左右滑动切换页面。拖动状态下暂停本机翻页，避免与跨设备边缘手势冲突。

## 6. 两台设备的连接

### 6.1 配对流程

1. 启动后进入角色选择页。
2. 一台设备选择“左侧设备”，另一台选择“右侧设备”。
3. 左侧设备启动附近服务广播。
4. 右侧设备搜索附近的 The Hidden Feature。
5. 用户在右侧设备上确认要连接的设备。
6. 两台设备建立加密的 `MCSession`。
7. 双方交换协议版本、会话 ID、设备角色和初始桌面摘要。
8. 握手成功后进入虚拟桌面。

左侧设备的右边缘与右侧设备的左边缘被定义为共享边缘。

如果连接断开，应用取消当前交接并返回配对界面。重新配对会重新生成预设桌面。

### 6.2 消息传输策略

消息分为两类：

- 拖动坐标、边缘进度等高频预览消息：约 30 Hz 发送，使用非可靠传输，接收端只处理最新序号。
- 请求、接受、提交、确认、取消等状态消息：使用可靠传输。

所有消息都包含：

- 协议版本。
- 当前会话 ID。
- 消息序号。
- 消息类型。
- 交接事务 ID。
- 对应负载。

旧会话、重复事务、过期序号和不符合当前状态的消息必须被忽略。

## 7. 跨设备拖动状态机

### 7.1 触发条件

当图标进入共享边缘约 20 pt 的区域，并且预测拖动位置继续向屏幕外超过约 32 pt 时，来源设备开始交接。

仅进入边缘但没有明确向外拖动时，不启动跨设备交接，以减少误触。

### 7.2 交接流程

1. 来源设备创建唯一的交接事务。
2. 来源发送图标数据、原始位置和归一化纵坐标。
3. 目标根据自己的桌面高度换算纵坐标，在共享边缘绘制临时图标。
4. 来源播放图标向屏幕外移动的动画，但暂时保留数据所有权。
5. 目标进入最长 1.2 秒的等待接管状态。
6. 用户在目标屏幕共享边缘 96 pt 范围内、与预期纵坐标误差不超过 72 pt 的位置触碰屏幕。
7. 目标立即将临时图标吸附到新手势并发送接受消息。
8. 来源发送提交消息，目标确认收到后成为新所有者。
9. 来源收到确认后从自己的桌面模型中永久删除图标。
10. 用户在目标设备松手后，图标落入最近的有效槽位并触发布局重排。

目标设备接管后应立即跟随手指，不等待完整网络往返。提交尚未完成时，目标设备以临时状态显示图标，并缓存最终落点。

### 7.3 回滚规则

以下情况必须取消交接：

- 1.2 秒内没有有效目标触摸。
- 用户将来源图标拖离共享边缘。
- 任一设备断开连接。
- 收到拒绝、版本不兼容或无效状态消息。
- 提交阶段超时。

取消时：

- 目标设备移除临时图标。
- 来源设备恢复图标所有权。
- 来源图标使用动画回到原槽位。
- 两台设备都清除该事务的临时状态。

来源只有在收到目标确认后才永久删除图标，从而避免图标因通信失败而丢失。

## 8. 主要数据结构

计划使用以下核心模型：

```swift
struct DesktopItem: Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let symbolName: String
    let colors: [IconColor]
}

enum DeviceRole: String, Codable, Sendable {
    case left
    case right
}

struct TransferTransaction: Codable, Sendable {
    let id: UUID
    let item: DesktopItem
    let sourceSlot: DesktopSlot
    let normalizedY: Double
    var phase: TransferPhase
}

struct PeerEnvelope: Codable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let sequence: UInt64
    let transactionID: UUID?
    let message: PeerMessage
}
```

通信层通过抽象接口与桌面状态分离：

```swift
protocol PeerTransport {
    var events: AsyncStream<PeerEvent> { get }

    func start(role: DeviceRole) async throws
    func send(_ message: PeerEnvelope, reliably: Bool) async throws
    func stop() async
}
```

生产环境使用 Multipeer Connectivity 实现该接口；测试环境使用内存传输实现，以便稳定模拟乱序、超时和断线。

## 9. 计划中的代码分层

建议按职责拆分：

```text
TheHiddenFeature/
├── App/
│   └── TheHiddenFeatureApp.swift
├── Models/
│   ├── DesktopModels.swift
│   └── PeerMessages.swift
├── Desktop/
│   ├── DesktopView.swift
│   ├── DesktopSessionModel.swift
│   ├── IconView.swift
│   └── LayoutEngine.swift
├── Connectivity/
│   ├── PeerTransport.swift
│   └── MultipeerTransport.swift
├── Pairing/
│   └── PairingView.swift
└── Resources/
    └── Assets.xcassets
```

分层目标是让布局算法、通信传输和 SwiftUI 界面可以分别测试，避免在单个 View 中同时处理手势、网络和数据一致性。

## 10. 使用方式

以下步骤描述功能实现完成后的使用流程。

### 10.1 安装

1. 使用运行 iOS 17、iPadOS 17 或更新系统的两台 iPhone/iPad。
2. 在 Xcode 中打开 `TheHiddenFeature.xcodeproj`。
3. 为 TheHiddenFeature Target 选择可用的 Apple Development Team。
4. 分别选择两台真机作为运行目标并安装应用。
5. 首次启动时，允许应用访问本地网络。
6. 确保两台设备的 Wi-Fi 和蓝牙均已开启。

应用不需要连接互联网，也不要求两台设备登录同一个 Apple ID。

### 10.2 配对

1. 在两台设备上同时打开应用。
2. 将两台设备竖屏放在同一平面并将顶边对齐。
3. 左边的设备选择“左侧设备”。
4. 右边的设备选择“右侧设备”。
5. 在右侧设备的列表中选择左侧设备。
6. 等待两台设备显示连接成功并进入虚拟桌面。

### 10.3 本机移动图标

1. 长按任意图标约 0.5 秒。
2. 等待桌面图标开始抖动。
3. 保持按压并拖动图标。
4. 将图标移动到另一个槽位或 Dock。
5. 松开手指完成放置。
6. 点击“完成”退出编辑模式。

### 10.4 跨设备移动图标

从左侧设备移动到右侧设备：

1. 在左侧设备长按并拖动图标。
2. 将图标快速拖向左侧设备的右边缘。
3. 观察图标从左侧屏幕移出，并在右侧设备的左边缘出现。
4. 让手指越过两台设备之间的边框并触碰右侧屏幕。
5. 右侧设备接管图标后继续拖动。
6. 在目标位置松手，图标会进入右侧桌面的网格。

从右侧设备移回左侧设备时，执行相反方向的操作。

如果手指没有在 1.2 秒内进入目标屏幕，交接会取消，图标会返回来源手机的原位置。

## 11. 测试与验收

### 11.1 自动测试

- 网格换位和页面顺延。
- Dock 插入、移出和满位处理。
- 不同屏幕高度之间的纵坐标映射。
- 正常交接、双向交接和连续多次交接。
- 接管超时、断线和取消。
- 重复、乱序、过期和错误会话消息。
- 提交前后各阶段的所有权一致性。
- 消息编码和协议版本兼容检查。

### 11.2 真机验收

在两台真机上完成以下检查：

- 左右角色可以稳定发现并建立连接。
- 长按、抖动和本机重排行为正常。
- 连续完成至少五次左到右交接。
- 连续完成至少五次右到左交接。
- 每次成功交接后，图标只存在于目标设备。
- 接管超时后，图标返回来源位置。
- 拖动过程中断开连接不会造成永久复制或丢失。
- iPhone 与 iPad 混合配对时，可以在近似相同物理高度显示交接图标。
- 稳定近距离连接下，目标边缘预览不出现明显超过 200 ms 的停顿。

## 12. 参考资料

- [Apple：Multipeer Connectivity](https://developer.apple.com/documentation/multipeerconnectivity)
- [Apple：MCNearbyServiceBrowser](https://developer.apple.com/documentation/multipeerconnectivity/mcnearbyservicebrowser)
- [Apple：Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Apple：Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)
