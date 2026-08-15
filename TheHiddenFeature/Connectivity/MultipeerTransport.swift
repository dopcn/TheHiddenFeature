@preconcurrency import MultipeerConnectivity
import UIKit

@MainActor
final class MultipeerTransport: NSObject, PeerTransport {
    private static let serviceType = "hiddenfeature"

    nonisolated let events: AsyncStream<PeerEvent>

    nonisolated private let continuation: AsyncStream<PeerEvent>.Continuation
    nonisolated private let callbackQueue = DispatchQueue(
        label: "com.dopcn.TheHiddenFeature.multipeer-events"
    )
    nonisolated private let generationLock = NSLock()
    nonisolated(unsafe) private var callbackGenerations: [ObjectIdentifier: UInt64] = [:]
    private let localPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var role: DeviceRole?
    private var discoveredPeers: [UUID: MCPeerID] = [:]
    private var invitationPending = false
    private var generation: UInt64 = 0

    override init() {
        var streamContinuation: AsyncStream<PeerEvent>.Continuation!
        events = AsyncStream { streamContinuation = $0 }
        continuation = streamContinuation
        localPeerID = MCPeerID(displayName: Self.safeDisplayName(UIDevice.current.name))
        super.init()
    }

    private static func safeDisplayName(_ deviceName: String) -> String {
        var result = ""
        for character in deviceName {
            let candidate = result + String(character)
            guard candidate.utf8.count <= 48 else { break }
            result = candidate
        }
        return result.isEmpty ? "iPhone" : result
    }

    func start(role: DeviceRole, generation: UInt64) async throws {
        await stop()
        self.generation = generation
        self.role = role
        let session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
        self.session = session
        registerCallbackSource(session, generation: generation)

        switch role {
        case .left:
            let advertiser = MCNearbyServiceAdvertiser(
                peer: localPeerID,
                discoveryInfo: ["role": role.rawValue],
                serviceType: Self.serviceType
            )
            advertiser.delegate = self
            self.advertiser = advertiser
            registerCallbackSource(advertiser, generation: generation)
            advertiser.startAdvertisingPeer()
        case .right:
            let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: Self.serviceType)
            browser.delegate = self
            self.browser = browser
            registerCallbackSource(browser, generation: generation)
            browser.startBrowsingForPeers()
        }
    }

    func connect(to peerID: UUID) async throws {
        guard role == .right,
              let peer = discoveredPeers[peerID],
              let browser,
              let session else {
            throw TransportError.peerUnavailable
        }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 12)
    }

    func send(_ data: Data, reliably: Bool) async throws {
        guard let session, !session.connectedPeers.isEmpty else {
            throw TransportError.notConnected
        }
        try session.send(
            data,
            toPeers: session.connectedPeers,
            with: reliably ? .reliable : .unreliable
        )
    }

    func stop() async {
        if let advertiser {
            unregisterCallbackSource(advertiser)
            advertiser.stopAdvertisingPeer()
            advertiser.delegate = nil
        }
        advertiser = nil
        if let browser {
            unregisterCallbackSource(browser)
            browser.stopBrowsingForPeers()
            browser.delegate = nil
        }
        browser = nil
        if let session {
            unregisterCallbackSource(session)
            session.delegate = nil
            session.disconnect()
        }
        session = nil
        discoveredPeers.removeAll()
        invitationPending = false
        role = nil
    }

    private func updatePeers(generation: UInt64) {
        let peers = discoveredPeers.map { NearbyPeer(id: $0.key, name: $0.value.displayName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        emit(.peersChanged(peers), generation: generation)
    }

    private func registerCallbackSource(_ object: AnyObject, generation: UInt64) {
        generationLock.lock()
        callbackGenerations[ObjectIdentifier(object)] = generation
        generationLock.unlock()
    }

    private func unregisterCallbackSource(_ object: AnyObject) {
        generationLock.lock()
        callbackGenerations.removeValue(forKey: ObjectIdentifier(object))
        generationLock.unlock()
    }

    nonisolated private func registeredGeneration(for object: AnyObject) -> UInt64? {
        generationLock.lock()
        defer { generationLock.unlock() }
        return callbackGenerations[ObjectIdentifier(object)]
    }

    nonisolated private func emit(
        _ payload: PeerEventPayload,
        generation: UInt64
    ) {
        callbackQueue.async { [continuation] in
            continuation.yield(PeerEvent(generation: generation, payload: payload))
        }
    }

    enum TransportError: LocalizedError {
        case peerUnavailable
        case notConnected

        var errorDescription: String? {
            switch self {
            case .peerUnavailable: "所选设备已不可用，请重新搜索"
            case .notConnected: "附近连接尚未建立"
            }
        }
    }
}

extension MultipeerTransport: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        guard let generation = registeredGeneration(for: session) else { return }
        let peerName = peerID.displayName
        switch state {
        case .connected:
            emit(.connected(peerName: peerName), generation: generation)
            Task { @MainActor [weak self] in
                guard let self, self.session === session else { return }
                invitationPending = true
            }
        case .notConnected:
            emit(.disconnected, generation: generation)
            Task { @MainActor [weak self] in
                guard let self, self.session === session else { return }
                if session.connectedPeers.isEmpty {
                    invitationPending = false
                }
            }
        case .connecting:
            break
        @unknown default:
            emit(.failure("收到未知的连接状态"), generation: generation)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        guard let generation = registeredGeneration(for: session) else { return }
        let peerName = peerID.displayName
        emit(.receivedData(data, peerName: peerName), generation: generation)
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        guard let generation = registeredGeneration(for: advertiser) else { return }
        emit(.failure("无法开始广播：\(error.localizedDescription)"), generation: generation)
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        guard let generation = registeredGeneration(for: advertiser) else {
            invitationHandler(false, nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self,
                  self.generation == generation,
                  self.advertiser === advertiser,
                  role == .left,
                  !invitationPending,
                  let session,
                  session.connectedPeers.isEmpty else {
                invitationHandler(false, nil)
                return
            }
            invitationPending = true
            invitationHandler(true, session)
        }
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        guard let generation = registeredGeneration(for: browser) else { return }
        emit(.failure("无法搜索附近设备：\(error.localizedDescription)"), generation: generation)
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard info?["role"] == DeviceRole.left.rawValue else { return }
        guard let generation = registeredGeneration(for: browser) else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  self.generation == generation,
                  self.browser === browser else { return }
            guard !discoveredPeers.values.contains(peerID) else { return }
            let id = UUID()
            discoveredPeers[id] = peerID
            updatePeers(generation: generation)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        guard let generation = registeredGeneration(for: browser) else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  self.generation == generation,
                  self.browser === browser else { return }
            discoveredPeers = discoveredPeers.filter { $0.value != peerID }
            updatePeers(generation: generation)
        }
    }
}
