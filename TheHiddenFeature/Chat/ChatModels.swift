import Foundation

enum ChatAvatarStyle: String, Codable, Hashable, Sendable {
    case coral
    case sand

    var assetName: String {
        switch self {
        case .coral:
            "ChatAvatarWork"
        case .sand:
            "ChatAvatarWeizhou"
        }
    }
}

struct ChatAccount: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let avatarStyle: ChatAvatarStyle

    static func account(for role: DeviceRole) -> ChatAccount {
        switch role {
        case .left:
            ChatAccount(
                id: "work-account",
                displayName: "工作号",
                avatarStyle: .coral
            )
        case .right:
            ChatAccount(
                id: "weizhou-account",
                displayName: "尾舟",
                avatarStyle: .sand
            )
        }
    }
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
