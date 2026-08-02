import Foundation

let peerProtocolVersion = 2

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

struct Handshake: Codable, Sendable {
    let role: DeviceRole
    let deviceName: String
    let summary: DesktopSummary
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

enum PeerMessage: Codable, Sendable {
    case hello(Handshake)
    case transferRequest(TransferOffer)
    case transferPreview(TransferPreview)
    case transferAccept
    case transferCommit
    case transferAcknowledged
    case transferCancel(TransferCancelReason)
}

struct PeerEnvelope: Codable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let sequence: UInt64
    let transactionID: UUID?
    let message: PeerMessage
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
