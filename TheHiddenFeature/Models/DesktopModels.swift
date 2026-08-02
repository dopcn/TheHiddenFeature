import SwiftUI

enum DeviceRole: String, Codable, Sendable {
    case left
    case right

    var title: String {
        switch self {
        case .left: "左侧设备"
        case .right: "右侧设备"
        }
    }

    var sharedEdge: HorizontalEdge {
        self == .left ? .trailing : .leading
    }

    var peerRole: DeviceRole {
        self == .left ? .right : .left
    }
}

enum IconColor: String, Codable, Hashable, Sendable {
    case blue
    case cyan
    case indigo
    case mint
    case orange
    case pink
    case purple
    case red
    case teal
    case yellow

    var color: Color {
        switch self {
        case .blue: .blue
        case .cyan: .cyan
        case .indigo: .indigo
        case .mint: .mint
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .teal: .teal
        case .yellow: .yellow
        }
    }
}

struct DesktopItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let symbolName: String
    let colors: [IconColor]
    let iconAssetName: String?
}

enum DesktopSlot: Codable, Hashable, Sendable {
    case page(page: Int, index: Int)
    case dock(index: Int)
}

struct DesktopLayout: Codable, Sendable {
    static let pageCapacity = 24
    static let dockCapacity = 4

    var pages: [[DesktopItem?]]
    var dock: [DesktopItem?]

    init(pages: [[DesktopItem?]], dock: [DesktopItem?]) {
        self.pages = pages.map { page in
            Array((page + Array(repeating: nil, count: Self.pageCapacity)).prefix(Self.pageCapacity))
        }
        self.dock = Array((dock + Array(repeating: nil, count: Self.dockCapacity)).prefix(Self.dockCapacity))
        if self.pages.isEmpty {
            self.pages = [Array(repeating: nil, count: Self.pageCapacity)]
        }
    }

    func item(at slot: DesktopSlot) -> DesktopItem? {
        switch slot {
        case let .page(page, index):
            guard pages.indices.contains(page), pages[page].indices.contains(index) else { return nil }
            return pages[page][index]
        case let .dock(index):
            guard dock.indices.contains(index) else { return nil }
            return dock[index]
        }
    }

    func slot(containing itemID: UUID) -> DesktopSlot? {
        for (pageIndex, page) in pages.enumerated() {
            if let index = page.firstIndex(where: { $0?.id == itemID }) {
                return .page(page: pageIndex, index: index)
            }
        }
        if let index = dock.firstIndex(where: { $0?.id == itemID }) {
            return .dock(index: index)
        }
        return nil
    }

    mutating func remove(itemID: UUID) {
        for pageIndex in pages.indices {
            for index in pages[pageIndex].indices where pages[pageIndex][index]?.id == itemID {
                pages[pageIndex][index] = nil
            }
        }
        for index in dock.indices where dock[index]?.id == itemID {
            dock[index] = nil
        }
        trimEmptyTrailingPages()
    }

    mutating func move(_ item: DesktopItem, to destination: DesktopSlot) {
        let source = slot(containing: item.id)
        if source == destination {
            return
        }
        if reorderWithinSameContainer(item, from: source, to: destination) {
            return
        }
        removeWithoutTrimming(itemID: item.id)

        switch destination {
        case let .page(page, index):
            ensurePage(page)
            insertIntoPages(item, page: page, index: index)
        case let .dock(index):
            insertIntoDock(item, index: index)
        }
    }

    func firstAvailablePageSlot(preferredPage: Int = 0) -> DesktopSlot {
        if pages.indices.contains(preferredPage),
           let index = pages[preferredPage].firstIndex(where: { $0 == nil }) {
            return .page(page: preferredPage, index: index)
        }
        for (pageIndex, page) in pages.enumerated() {
            if let index = page.firstIndex(where: { $0 == nil }) {
                return .page(page: pageIndex, index: index)
            }
        }
        return .page(page: pages.count, index: 0)
    }

    var itemCount: Int {
        pages.flatMap { $0 }.compactMap { $0 }.count + dock.compactMap { $0 }.count
    }

    private mutating func removeWithoutTrimming(itemID: UUID) {
        for pageIndex in pages.indices {
            for index in pages[pageIndex].indices where pages[pageIndex][index]?.id == itemID {
                pages[pageIndex][index] = nil
            }
        }
        for index in dock.indices where dock[index]?.id == itemID {
            dock[index] = nil
        }
    }

    private mutating func reorderWithinSameContainer(
        _ item: DesktopItem,
        from source: DesktopSlot?,
        to destination: DesktopSlot
    ) -> Bool {
        switch (source, destination) {
        case let (.page(sourcePage, sourceIndex)?, .page(destinationPage, destinationIndex))
            where sourcePage == destinationPage:
            if sourceIndex < destinationIndex {
                for index in sourceIndex..<destinationIndex {
                    pages[sourcePage][index] = pages[sourcePage][index + 1]
                }
            } else {
                for index in stride(from: sourceIndex, to: destinationIndex, by: -1) {
                    pages[sourcePage][index] = pages[sourcePage][index - 1]
                }
            }
            pages[sourcePage][destinationIndex] = item
            return true

        case let (.dock(sourceIndex)?, .dock(destinationIndex)):
            if sourceIndex < destinationIndex {
                for index in sourceIndex..<destinationIndex {
                    dock[index] = dock[index + 1]
                }
            } else {
                for index in stride(from: sourceIndex, to: destinationIndex, by: -1) {
                    dock[index] = dock[index - 1]
                }
            }
            dock[destinationIndex] = item
            return true

        default:
            return false
        }
    }

    private mutating func insertIntoPages(_ item: DesktopItem, page: Int, index: Int) {
        let safeIndex = min(max(index, 0), Self.pageCapacity - 1)
        var displaced: DesktopItem? = item
        var pageIndex = max(page, 0)
        var slotIndex = safeIndex

        while let current = displaced {
            ensurePage(pageIndex)
            displaced = pages[pageIndex][slotIndex]
            pages[pageIndex][slotIndex] = current
            slotIndex += 1
            if slotIndex == Self.pageCapacity {
                pageIndex += 1
                slotIndex = 0
            }
        }
    }

    private mutating func insertIntoDock(_ item: DesktopItem, index: Int) {
        let safeIndex = min(max(index, 0), Self.dockCapacity - 1)
        let displaced = dock[safeIndex]
        dock[safeIndex] = item

        guard let displaced else { return }
        if let emptyIndex = dock.indices.dropFirst(safeIndex + 1).first(where: { dock[$0] == nil }) {
            for position in stride(from: emptyIndex, to: safeIndex, by: -1) {
                dock[position] = dock[position - 1]
            }
            dock[safeIndex + 1] = displaced
        } else {
            insertIntoPages(displaced, page: 0, index: firstEmptyPageIndex())
        }
    }

    private func firstEmptyPageIndex() -> Int {
        pages[0].firstIndex(where: { $0 == nil }) ?? Self.pageCapacity - 1
    }

    private mutating func ensurePage(_ page: Int) {
        while pages.count <= page {
            pages.append(Array(repeating: nil, count: Self.pageCapacity))
        }
    }

    private mutating func trimEmptyTrailingPages() {
        while pages.count > 2, pages.last?.allSatisfy({ $0 == nil }) == true {
            pages.removeLast()
        }
    }
}

extension DesktopLayout {
    static func preset(for role: DeviceRole) -> DesktopLayout {
        let leftItems = [
            item("天气", "cloud.sun.fill", [.cyan, .blue], "Weather", "A001"),
            item("照片", "photo.on.rectangle.angled", [.pink, .orange], "Photos", "A002"),
            item("地图", "map.fill", [.mint, .blue], "Maps", "A003"),
            item("备忘录", "note.text", [.yellow, .orange], "Notes", "A004"),
            item("提示", "lightbulb.fill", [.yellow, .orange], "Tips", "A005"),
            item("语音备忘录", "waveform", [.red, .pink], "VoiceMemos", "A006"),
            item("时钟", "clock.fill", [.indigo, .blue], "Clock", "A007"),
            item("图书", "books.vertical.fill", [.orange, .red], "Books", "A008"),
            item("播客", "dot.radiowaves.left.and.right", [.purple, .pink], "Podcasts", "A009"),
            item("测距仪", "viewfinder", [.blue, .cyan], "Measure", "A010"),
            item("健康", "heart.fill", [.pink, .red], "Health", "A011"),
            item("文件", "folder.fill", [.blue, .indigo], "Files", "A012"),
            item("家庭", "house.fill", [.yellow, .orange], "Home", "A013"),
            item("音乐备忘录", "metronome.fill", [.purple, .indigo], "MusicMemos", "A014"),
            item("查找", "location.fill", [.cyan, .blue], "FindMy", "A015"),
            item("指南针", "safari.fill", [.blue, .mint], "Compass", "A016")
        ]
        let rightItems = [
            item("日历", "calendar", [.red, .orange], "Calendar", "B001"),
            item("邮件", "envelope.fill", [.blue, .cyan], "Mail", "B002"),
            item("相机", "camera.fill", [.indigo, .purple], "Camera", "B003"),
            item("计算器", "plus.forwardslash.minus", [.orange, .yellow], "Calculator", "B004"),
            item("提醒事项", "checklist", [.mint, .teal], "Reminders", "B005"),
            item("音乐", "music.note", [.pink, .purple], "Music", "B006"),
            item("新闻", "newspaper.fill", [.orange, .red], "News", "B007"),
            item("遥控器", "button.programmable", [.blue, .indigo], "Remote", "B008"),
            item("通讯录", "person.crop.circle.fill", [.cyan, .blue], "Contacts", "B009"),
            item("设置", "gearshape.fill", [.indigo, .blue], "Settings", "B010"),
            item("Pages", "doc.richtext.fill", [.orange, .yellow], "Pages", "B011"),
            item("健身记录", "chart.bar.fill", [.mint, .blue], "Activity", "B012"),
            item("iMovie", "star.fill", [.purple, .indigo], "iMovie", "B013"),
            item("Safari", "safari.fill", [.blue, .cyan], "Safari", "B014"),
            item("钱包", "wallet.pass.fill", [.orange, .yellow], "Wallet", "B015"),
            item("App Store", "a.circle.fill", [.blue, .cyan], "AppStore", "B016")
        ]
        let items = role == .left ? leftItems : rightItems
        var firstPage = Array<DesktopItem?>(repeating: nil, count: pageCapacity)
        var secondPage = Array<DesktopItem?>(repeating: nil, count: pageCapacity)
        for (index, item) in items.prefix(10).enumerated() {
            firstPage[index] = item
        }
        for (offset, item) in items.dropFirst(10).prefix(2).enumerated() {
            secondPage[offset] = item
        }
        let dockItems = Array(items.suffix(4)).map(Optional.some)
        return DesktopLayout(pages: [firstPage, secondPage], dock: dockItems)
    }

    private static func item(
        _ title: String,
        _ symbol: String,
        _ colors: [IconColor],
        _ iconAssetName: String,
        _ suffix: String
    ) -> DesktopItem {
        let uuid = UUID(uuidString: "10000000-0000-0000-0000-00000000\(suffix)")!
        return DesktopItem(
            id: uuid,
            title: title,
            symbolName: symbol,
            colors: colors,
            iconAssetName: "Apple\(iconAssetName)"
        )
    }
}
