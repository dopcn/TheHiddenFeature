import Foundation

let peerProtocolVersion = 5

enum ExperienceMode: String, Codable, Sendable {
    case desktop
    case chat

    var title: String {
        switch self {
        case .desktop: "跨设备桌面"
        case .chat: "双设备聊天"
        }
    }
}

enum DeviceFormFactor: String, Codable, Sendable {
    case phone
    case tablet

    /// UIKit points are only an approximation of physical distance. These
    /// reference densities make top-aligned phone/tablet handoff materially
    /// closer than mapping both screens by percentage alone.
    var nominalPointsPerInch: Double {
        switch self {
        case .phone: 163
        case .tablet: 132
        }
    }
}

struct DesktopSummary: Codable, Sendable {
    let itemCount: Int
    let pageCount: Int
}

struct SessionHandshake: Codable, Sendable {
    let role: DeviceRole
    let experience: ExperienceMode
    let deviceName: String
    let desktopSummary: DesktopSummary?
}

struct TransferOffer: Codable, Sendable {
    let item: DesktopItem
    let sourceSlot: DesktopSlot
    let sourceY: Double
    let sourceCanvasHeight: Double
    let sourceFormFactor: DeviceFormFactor
    let normalizedY: Double
}

struct TransferPreview: Codable, Sendable {
    let sourceY: Double
    let normalizedY: Double
    let edgeProgress: Double
}

enum TransferCancelReason: String, Codable, Sendable {
    case movedAway
    case takeoverTimedOut
    case commitTimedOut
    case disconnected
    case invalidState
}

enum DesktopPeerMessage: Codable, Sendable {
    case transferRequest(TransferOffer)
    case transferPreview(TransferPreview)
    case transferAccept
    case transferCommit
    case transferAcknowledged
    case transferCancel(TransferCancelReason)
}

struct ChatWireMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let senderID: String
    let body: String
    let sentAt: Date
}

enum ChatPeerMessage: Codable, Sendable {
    case send(ChatWireMessage)
    case acknowledged(messageID: UUID)
    case typing(ChatTypingEvent)
    case waitingForInput(ChatWaitingForInputEvent)
}

struct ChatTypingEvent: Codable, Sendable {
    let senderID: String
    let phase: ChatTypingPhase
}

enum ChatTypingPhase: String, Codable, Sendable {
    case active
    case inactive
}

struct ChatWaitingForInputEvent: Codable, Sendable {
    let senderID: String
}

enum SessionPayload: Codable, Sendable {
    case hello(SessionHandshake)
    case desktop(DesktopPeerMessage)
    case chat(ChatPeerMessage)
}

struct SessionEnvelope: Codable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let sequence: UInt64
    let correlationID: UUID?
    let payload: SessionPayload
}

struct TransferTransaction: Codable, Sendable {
    let id: UUID
    let item: DesktopItem
    let sourceSlot: DesktopSlot
    let normalizedY: Double
    var phase: TransferPhase
}

enum TransferPhase: String, Codable, Sendable {
    case offered
    case accepted
    case committed
    case acknowledged
    case cancelled
}
