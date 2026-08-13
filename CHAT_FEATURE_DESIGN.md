# 双设备聊天功能设计

## 1. 文档状态

本文档描述 The Hidden Feature 新增“双设备聊天”体验的产品范围、交互流程、代码结构、通信协议和验收标准。用户提供的 iPhone 与 iPad 对话截图是本功能的视觉基准；实现时按设备尺寸自适应，不直接按截图像素硬编码。

该功能是一个仅供个人使用的双设备演示，不上架、不分发，也不接入微信服务。界面只模仿常见的微信单聊对话布局，不使用微信名称、Logo、官方头像或其他官方素材。

## 2. 功能目标

在保留现有跨设备桌面演示的前提下，为应用增加一个聊天入口。用户在一台 iPhone 和一台 iPad 上分别打开 The Hidden Feature，进入聊天功能，选择左侧或右侧设备并完成附近连接，然后以两个不同的预设账号进行一对一文字聊天。

核心体验如下：

1. 启动应用后看到功能入口页。
2. 点击“双设备聊天”。
3. 两台设备分别选择“左侧设备”和“右侧设备”。
4. 左侧设备广播，右侧设备搜索并连接左侧设备。
5. 握手成功后，不显示联系人列表、会话列表或微信首页，直接进入两个账号的一对一对话页。
6. 任一设备发送文字后，本机立即显示消息，对端收到并显示消息。
7. 每台设备都将自己发送的消息显示在右侧，将收到的消息显示在左侧。
8. 连接断开或应用进入后台后结束本次聊天，返回配对流程。

## 3. 范围与边界

### 3.1 第一版包含

- 新的功能入口页。
- 现有“跨设备桌面”入口。
- 新的“双设备聊天”入口。
- 复用现有左侧/右侧角色选择、附近发现和连接流程。
- 两个由设备角色决定的预设账号。
- 单个一对一聊天页面。
- 纯文本及系统 Emoji 消息。
- 消息发送中、已送达和发送失败状态。
- 消息 ID 去重和应用层送达确认。
- 自动滚动到最新消息。
- 键盘避让、空消息拦截和消息长度限制。
- 完整显示参考界面中的顶部返回、省略号以及底部语音、麦克风、表情和加号图标。
- 除文本输入和通过键盘发送消息外，上述图标第一版均为无操作的视觉元素。
- 断线提示及安全退出会话。

### 3.2 第一版不包含

- 真实微信登录或微信协议接入。
- 联系人列表、会话列表、朋友圈或底部标签栏。
- 图片、文件、语音、视频、红包或表情包消息。
- 账号注册、密码和用户资料编辑。
- 互联网服务器、云同步、离线消息和推送通知。
- 已读回执、撤回、引用、转发和消息搜索。
- 跨应用启动或后台持续通信。
- 聊天记录持久化。

## 4. 入口与页面流程

应用顶层增加功能选择状态，原有功能和聊天功能并存：

```text
启动应用
  |
  v
功能入口页
  |-- 跨设备桌面 --> 角色选择 --> 发现/连接 --> 虚拟桌面
  |
  `-- 双设备聊天 --> 角色选择 --> 发现/连接 --> 单聊对话页
```

“直接进入对话界面”的含义是：连接成功后直接进入单聊，不经过聊天首页、联系人列表或会话列表。首次建立连接仍必须经过角色选择和配对，否则两台设备无法确定广播方、搜索方及各自账号。

建议新增：

```swift
enum ExperienceMode: String, Codable, Sendable {
    case desktop
    case chat
}
```

两台设备握手时必须交换 `ExperienceMode`。如果一台选择桌面、另一台选择聊天，则停止握手并提示两台设备选择相同功能。

## 5. 账号设计

账号不需要注册，由设备角色静态映射。示例名称和头像均为项目内自制内容，后续可以直接替换常量。

| 设备角色 | 账号 ID | 默认名称 | 默认头像 |
| --- | --- | --- | --- |
| 左侧设备 | `work-account` | 工作号 | 自制人物头像 A |
| 右侧设备 | `weizhou-account` | 尾舟 | 自制人物头像 B |

账号模型：

```swift
struct ChatAccount: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let avatarStyle: AvatarStyle
}
```

角色只决定身份和连接职责，不直接决定气泡方向。气泡方向始终通过消息发送者与本地账号比较得出：

```swift
let isOutgoing = message.senderID == localAccount.id
```

因此，同一条消息在发送方设备显示于右侧，在接收方设备显示于左侧。

## 6. 对话界面设计

### 6.1 整体布局

界面按用户提供的截图模仿微信单聊页面。截图中的照片消息和历史文字仅用于说明布局，第一版进入会话时不预置这些聊天内容。

```text
+------------------------------------------------+
| 系统状态栏                                     |
+------------------------------------------------+
|  <               对端名称                 ···  |
+------------------------------------------------+
|                                                |
|  [头像] [收到的白色消息气泡]                   |
|                                                |
|                    [绿色消息气泡] [头像]       |
|                                                |
|                  时间标签                      |
|                                                |
+------------------------------------------------+
| (语音)  [ 文本输入框              (麦克风) ]  :)  (+) |
+------------------------------------------------+
```

- 保留系统状态栏，不自制时间、电量和网络图标。
- 顶部导航栏使用与消息区域接近的浅灰背景，下方保留一条细分隔线。
- 导航栏标题居中显示对端账号名称。左侧设备显示“尾舟”，右侧设备显示“工作号”，与两张参考图一致。
- 顶部左侧显示返回箭头，右侧显示横向省略号。两者第一版只负责还原视觉，点击不执行操作。
- 消息区域使用浅灰背景并占据导航栏和输入栏之间的全部空间。
- 收到的消息显示在左侧，由方形圆角头像、白色气泡和朝左的小尖角组成。
- 发出的消息显示在右侧，由绿色气泡、朝右的小尖角和方形圆角头像组成。
- 连续消息保持参考图中的垂直间距；较长时间间隔可以在中间显示浅灰色时间标签。
- 正常的 `.sending`、`.sent` 和 `.delivered` 状态不显示额外文字或对勾，避免偏离参考界面；只有发送失败时才在气泡旁显示轻量失败标记。
- 输入栏使用白色或极浅灰背景，固定在屏幕底部，并在键盘出现时停靠在键盘上方。

### 6.2 图标与交互规则

参考界面中的图标必须全部显示：

| 位置 | 图标 | 第一版行为 |
| --- | --- | --- |
| 顶部左侧 | 返回箭头 | 仅显示，点击无操作 |
| 顶部右侧 | 横向省略号 | 仅显示，点击无操作 |
| 输入栏左侧 | 圆形语音图标 | 仅显示，点击无操作 |
| 文本框右侧内部 | 麦克风图标 | 仅显示，点击无操作 |
| 输入栏右侧 | 圆形笑脸图标 | 仅显示，点击无操作 |
| 输入栏最右侧 | 圆形加号图标 | 仅显示，点击无操作 |

文本框是页面中唯一可交互的控件：

- 点击文本框获得焦点并调起系统键盘。
- 第一版使用单行 `TextField`，外观保持参考图中的固定高度。
- 键盘提交键显示为“发送”；用户点击键盘“发送”后，将有效文本通过 Multipeer Connectivity 发给对端。
- 空文本或只有空白字符时不发送。
- 发送成功后清空文本框并保持键盘显示，便于连续输入。
- 麦克风图标虽然位于文本框内部，但不拦截文本框点击；点击该区域仍然让文本框获得焦点。

### 6.3 iPhone 与 iPad

- iPhone 使用全宽单列对话布局。
- iPad 同样直接显示单聊页面，不增加无实际用途的联系人侧边栏。
- iPad 按参考图使用全宽消息画布：收到的消息靠左屏幕边缘排列，发出的消息靠右屏幕边缘排列，不将整个消息列收窄并居中。
- 气泡自身设置最大宽度，长文本只在气泡内换行，不横跨整块 iPad 屏幕。
- iPhone 与 iPad 使用相同的图标集合、气泡规则和输入逻辑，只根据可用尺寸调整外边距、头像尺寸和气泡最大宽度。
- 两种设备继续保持工程现有的竖屏、全屏约束。

### 6.4 滚动与键盘

- 初次进入对话时不预置截图中的历史消息，也不额外插入连接提示；消息区域保持为空，直到任一设备发送第一条消息。
- 发送或收到新消息时自动滚动到底部。
- 用户正在查看较早消息时，可暂不强制滚动，并显示“新消息”提示；第一版也可以简化为始终滚到底部。
- 输入框保持单行；超出可见宽度时由系统水平滚动文本内容。
- 消息正文去除首尾空白后最多 2,000 个字符。

## 7. 代码结构

现有 `DesktopSessionModel` 同时包含连接、握手和桌面拖动状态。增加第二个业务功能后，应将公共会话职责从桌面功能中拆出，避免聊天模型依赖桌面模型。

建议结构：

```text
TheHiddenFeature/
├── TheHiddenFeatureApp.swift
├── ContentView.swift
├── AppSessionModel.swift
├── Connectivity/
│   ├── PeerTransport.swift
│   └── MultipeerTransport.swift
├── Models/
│   ├── SessionModels.swift
│   ├── DesktopModels.swift
│   └── PeerMessages.swift
├── Pairing/
│   └── PairingView.swift
├── Desktop/
│   ├── DesktopSessionModel.swift
│   └── ...
└── Chat/
    ├── ChatModels.swift
    ├── ChatSessionModel.swift
    ├── ChatView.swift
    ├── MessageBubbleView.swift
    └── ChatComposerView.swift
```

职责划分：

- `AppSessionModel`：功能选择、角色选择、发现、连接、握手、会话 ID、消息序号和功能消息路由。
- `PeerTransport`：业务无关的数据发送与事件接收接口。
- `MultipeerTransport`：保留现有 Multipeer Connectivity 实现。
- `DesktopSessionModel`：只管理虚拟桌面、拖动和图标交接。
- `ChatSessionModel`：只管理账号、消息列表、草稿、发送状态、确认和去重。
- `ContentView`：根据顶层状态显示入口页、配对页、桌面页或聊天页。

## 8. 通信层复用与调整

### 8.1 保持不变

- `MCNearbyServiceAdvertiser` 和 `MCNearbyServiceBrowser` 的发现方式。
- 左侧设备广播、右侧设备浏览并邀请的职责。
- `_hiddenfeature._tcp` Bonjour 服务声明。
- `MCSession` 的加密连接。
- `AsyncStream<PeerEvent>` 事件出口。
- 断线和错误回调方式。

### 8.2 需要调整

当前 `PeerTransport.send` 直接接收桌面业务的 `PeerEnvelope`。建议将传输层改为发送原始 `Data`，由会话层负责编解码：

```swift
@MainActor
protocol PeerTransport: AnyObject {
    var events: AsyncStream<PeerEvent> { get }

    func start(role: DeviceRole, generation: UInt64) async throws
    func connect(to peerID: UUID) async throws
    func send(_ data: Data, reliably: Bool) async throws
    func stop() async
}
```

公共封包负责区分功能消息：

```swift
struct SessionEnvelope: Codable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let sequence: UInt64
    let payload: SessionPayload
}

enum SessionPayload: Codable, Sendable {
    case hello(SessionHandshake)
    case desktop(DesktopPeerMessage)
    case chat(ChatPeerMessage)
}
```

所有聊天正文、送达确认和握手消息使用可靠传输。第一版没有需要使用非可靠传输的聊天消息；如果以后增加“正在输入”，该临时状态可以使用非可靠传输。

## 9. 聊天数据模型

网络消息与本地 UI 状态分离。`ChatWireMessage` 可以编码传输，`ChatMessageState` 只在发送方本地维护。

```swift
struct ChatWireMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let senderID: String
    let body: String
    let sentAt: Date
}

enum ChatMessageState: Equatable, Sendable {
    case sending
    case sent
    case delivered
    case failed
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let wire: ChatWireMessage
    var state: ChatMessageState

    var id: UUID { wire.id }
}
```

聊天协议：

```swift
enum ChatPeerMessage: Codable, Sendable {
    case send(ChatWireMessage)
    case acknowledged(messageID: UUID)
}
```

`sentAt` 用于显示时间，不作为身份或去重依据。消息唯一性只依赖 UUID。第一版按本机提交和接收顺序追加消息，不解决两台设备在同一瞬间发送时的全局排序问题；这不影响消息送达，但两端在极端并发情况下可能出现不同的相邻消息顺序。若以后要求完全一致，可由左侧设备为所有消息分配会话级序号。

## 10. 消息发送流程

### 10.1 发送方

1. 去除输入内容首尾空白和换行。
2. 拒绝空消息或超过长度限制的消息。
3. 创建全局唯一消息 ID。
4. 立即在本地消息列表追加 `.sending` 消息并清空输入框。
5. 使用可靠传输发送 `.chat(.send(message))`。
6. 传输调用成功后标记为 `.sent`。这只表示数据已交给传输层，不表示对端界面已经处理。
7. 收到匹配的 `acknowledged` 后标记为 `.delivered`。
8. 发送调用失败或连接断开时标记为 `.failed`。

### 10.2 接收方

1. 校验协议版本、会话 ID、功能类型和发送者账号。
2. 校验正文非空且不超过长度限制。
3. 根据消息 ID 检查是否已经处理。
4. 未处理的消息追加到列表，显示为收到的消息。
5. 无论消息是首次收到还是重复收到，都返回同一个消息 ID 的 `acknowledged`，避免发送方因确认丢失而长期停留在未送达状态。

### 10.3 去重

`ChatSessionModel` 在当前会话中维护已接收消息 ID 集合：

```swift
private var receivedMessageIDs: Set<UUID> = []
```

聊天记录仅存在于内存，退出或重新配对时同时清空消息列表和去重集合。

## 11. 状态管理

顶层状态建议从当前桌面专用状态扩展为：

```swift
enum AppPhase {
    case featureSelection
    case roleSelection(ExperienceMode)
    case discovering(ExperienceMode)
    case connecting(ExperienceMode)
    case desktop
    case chat
}
```

聊天模型状态：

```swift
@MainActor
@Observable
final class ChatSessionModel {
    private(set) var localAccount: ChatAccount
    private(set) var peerAccount: ChatAccount
    private(set) var messages: [ChatMessage] = []
    var draft = ""
    private(set) var isConnected = true
}
```

状态转换：

```text
未连接
  -> 发现中
  -> 连接中
  -> 握手中
  -> 聊天中
       |-- 发送中 -> 已发送 -> 已送达
       `-- 发送中 ------------> 失败
  -> 断开
  -> 角色选择
```

## 12. 连接、后台与错误处理

- 对端断开：顶部立即显示断开状态，停止发送，未完成消息标记失败，然后退出聊天并返回角色选择。
- 应用进入后台：沿用当前行为，停止传输并结束会话；重新进入应用后需要重新配对。
- 握手功能不一致：显示“两台设备请选择相同功能”。
- 两台设备选择相同角色：拒绝进入聊天。
- 无本地网络权限：保留现有错误提示。
- 消息解析失败：记录 Debug 日志，忽略该消息，不终止整个会话。
- 未知会话或旧会话消息：忽略。
- 重复消息：不重复显示，但仍发送确认。
- 消息发送失败：保留失败气泡；第一版可以提供点击失败标记重新发送，重试时继续使用原消息 ID。

## 13. 安全与资源限制

虽然这是个人项目，仍应限制输入和网络负载：

- 单条文本最多 2,000 个字符。
- 当前会话最多保留 1,000 条消息；超过后从最早消息开始移除。
- 只接受当前会话和预期对端账号发来的消息。
- 延续 `MCSession` 的加密要求。
- 不写入账号密码、令牌或其他敏感数据。

## 14. 测试方案

### 14.1 自动测试

建议增加内存版 `PeerTransport` 和 XCTest Target，覆盖：

- 左右角色映射到不同账号。
- 两端选择不同功能时握手失败。
- 本地发送后立即产生发送中消息。
- 接收消息后追加气泡并返回确认。
- 收到确认后更新为已送达。
- 重复消息不会产生重复气泡。
- 空消息和超长消息不会发送。
- 发送失败后消息状态为失败。
- 断开后清空当前聊天状态。
- 旧会话消息被忽略。

测试文件建议命名为：

```text
TheHiddenFeatureTests/
├── AppSessionModelTests.swift
└── ChatSessionModelTests.swift
```

### 14.2 手动测试

至少使用一台 iPhone 和一台 iPad：

1. iPhone 选择左侧、iPad 选择右侧并互发消息。
2. 交换设备角色后重新测试。
3. 连续快速发送多条消息，确认顺序和自动滚动。
4. 两台设备几乎同时发送消息。
5. 输入中文、英文和 Emoji。
6. 发送期间关闭一台设备的应用或网络。
7. 应用进入后台后确认会话结束且能够重新配对。
8. 验证原有桌面演示的配对、拖动、交接和回滚没有退化。
9. 分别在 iPhone 和 iPad 上确认顶部返回、省略号及底部语音、麦克风、表情、加号图标全部可见。
10. 点击上述装饰图标，确认不会切换页面、弹出面板或触发其他功能。
11. 点击文本框及其内部麦克风区域，确认系统键盘弹出且输入焦点仍在文本框。
12. 点击键盘“发送”，确认文本传到对端、输入框清空且键盘保持显示。

每次代码变更至少执行：

```sh
xcodebuild -project TheHiddenFeature.xcodeproj \
  -scheme TheHiddenFeature \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## 15. 分阶段实施

### 阶段一：公共会话拆分

- 增加功能入口和 `ExperienceMode`。
- 从 `DesktopSessionModel` 抽离连接、握手和路由职责。
- 将 `PeerTransport` 改为业务无关的数据接口。
- 保证原桌面功能行为不变。

### 阶段二：聊天协议和状态

- 增加账号、聊天消息和发送状态模型。
- 实现可靠发送、确认、去重和错误处理。
- 使用内存传输测试消息状态机。

### 阶段三：聊天界面

- 按 iPhone/iPad 参考截图实现导航栏、消息列表、气泡、头像和输入栏。
- 补齐返回、省略号、语音、麦克风、表情和加号图标，并保持为无操作的视觉元素。
- 完成键盘适配和自动滚动。
- 分别适配 iPhone 与 iPad 竖屏布局。

### 阶段四：双真机验证

- 验证配对、双向消息、断线和重新连接。
- 回归原桌面跨设备拖动体验。
- 调整气泡尺寸、间距、颜色和动画，使对话观感接近目标界面。

## 16. 第一版验收标准

- 应用启动后同时提供桌面演示和聊天入口。
- 两台设备进入聊天入口后仍可选择左侧/右侧角色并完成现有配对。
- 两台设备被映射为不同的固定账号。
- 握手完成后直接进入这两个账号的单聊页面。
- 任一设备发送合法文本后，本机立即显示，对端能够收到并显示。
- 自己发送的消息始终在右侧，对端消息始终在左侧。
- iPhone 和 iPad 聊天页均完整显示参考截图中的返回、省略号、语音、麦克风、表情和加号图标。
- 除文本框外，参考截图中的图标点击后均不执行功能。
- 点击文本框或文本框内的麦克风区域能够调起系统键盘。
- 点击键盘“发送”能够发送有效文本，随后清空文本框并保持键盘显示。
- 重复网络消息不会生成重复气泡。
- 对端处理消息后，发送方能够看到已送达状态。
- 断线后不能继续发送，并能够返回配对流程重新连接。
- 原有跨设备桌面演示继续正常工作。
- iOS Simulator 无签名构建通过，并在一台 iPhone 与一台 iPad 上完成双向发送验证。
