import Foundation

struct NearbyPeer: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
}

struct PeerEvent: Sendable {
    let generation: UInt64
    let payload: PeerEventPayload
}

enum PeerEventPayload: Sendable {
    case peersChanged([NearbyPeer])
    case connected(peerName: String)
    case disconnected
    case receivedData(Data, peerName: String)
    case failure(String)
}

@MainActor
protocol PeerTransport: AnyObject {
    var events: AsyncStream<PeerEvent> { get }

    func start(role: DeviceRole, generation: UInt64) async throws
    func connect(to peerID: UUID) async throws
    func send(_ data: Data, reliably: Bool) async throws
    func stop() async
}
