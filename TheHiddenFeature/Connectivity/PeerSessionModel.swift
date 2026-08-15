import Foundation
import Observation
import UIKit

enum PeerConnectionPhase {
    case roleSelection
    case discovering
    case connecting
    case connected
}

@MainActor
@Observable
final class PeerSessionModel {
    private(set) var phase: PeerConnectionPhase = .roleSelection
    private(set) var role: DeviceRole?
    private(set) var experience: ExperienceMode?
    private(set) var nearbyPeers: [NearbyPeer] = []
    private(set) var connectedPeerName: String?
    private(set) var statusText = "选择这台设备的位置"
    private(set) var logs: [String] = []
    var errorMessage: String?

    @ObservationIgnored
    var messageHandler: ((SessionEnvelope) async -> Void)?

    @ObservationIgnored
    var resetHandler: (() -> Void)?

    @ObservationIgnored
    private let transport: any PeerTransport

    @ObservationIgnored
    private var eventTask: Task<Void, Never>?

    @ObservationIgnored
    private var sessionID: UUID?

    @ObservationIgnored
    private var sequence: UInt64 = 0

    @ObservationIgnored
    private var peerRole: DeviceRole?

    @ObservationIgnored
    private var pairingGeneration: UInt64 = 0

    @ObservationIgnored
    private var activeTransportGeneration: UInt64?

    @ObservationIgnored
    private var desktopSummary: DesktopSummary?

    convenience init() {
        self.init(transport: MultipeerTransport())
    }

    init(transport: any PeerTransport) {
        self.transport = transport
        observeTransport()
    }

    func chooseRole(
        _ role: DeviceRole,
        experience: ExperienceMode,
        desktopSummary: DesktopSummary?
    ) {
        guard phase == .roleSelection else { return }
        self.role = role
        self.experience = experience
        self.desktopSummary = desktopSummary
        nearbyPeers = []
        errorMessage = nil
        connectedPeerName = nil
        sessionID = role == .left ? UUID() : nil
        sequence = 0
        phase = .discovering
        statusText = role == .left ? "正在等待右侧设备连接…" : "正在搜索左侧设备…"
        log("选择角色：\(role.title)，功能：\(experience.title)")
        pairingGeneration &+= 1
        let generation = pairingGeneration
        activeTransportGeneration = generation

        Task {
            do {
                try await transport.start(role: role, generation: generation)
            } catch {
                guard activeTransportGeneration == generation else { return }
                showError(error.localizedDescription)
                await resetConnection(preserveError: true)
            }
        }
    }

    func connect(to peer: NearbyPeer) {
        guard role == .right, phase == .discovering else { return }
        phase = .connecting
        statusText = "正在连接 \(peer.name)…"
        let generation = activeTransportGeneration
        Task {
            do {
                try await transport.connect(to: peer.id)
            } catch {
                guard activeTransportGeneration == generation else { return }
                phase = .discovering
                statusText = "连接失败，请重新选择"
                showError(error.localizedDescription)
            }
        }
    }

    func send(
        _ payload: SessionPayload,
        correlationID: UUID?,
        reliably: Bool
    ) async throws {
        guard let sessionID else {
            throw SessionError.missingSession
        }
        sequence &+= 1
        let envelope = SessionEnvelope(
            protocolVersion: peerProtocolVersion,
            sessionID: sessionID,
            sequence: sequence,
            correlationID: correlationID,
            payload: payload
        )
        let data = try JSONEncoder().encode(envelope)
        try await transport.send(data, reliably: reliably)
    }

    func returnToRoleSelection() {
        Task {
            await resetConnection()
        }
    }

    func reset() async {
        await resetConnection()
    }

    func resetForBackground() {
        guard phase != .roleSelection else { return }
        Task {
            await resetConnection()
        }
    }

    func failAndReset(_ message: String) async {
        showError(message)
        await resetConnection(preserveError: true)
    }

    func clearError() {
        errorMessage = nil
    }

    func addDebugLog(_ text: String) {
        log(text)
    }

    private func observeTransport() {
        eventTask = Task { [weak self, transport] in
            for await event in transport.events {
                guard let self else { return }
                await handle(event)
            }
        }
    }

    private func handle(_ event: PeerEvent) async {
        guard event.generation == activeTransportGeneration else { return }

        switch event.payload {
        case let .peersChanged(peers):
            nearbyPeers = peers

        case let .connected(peerName):
            guard role != nil, phase == .discovering || phase == .connecting else { return }
            connectedPeerName = peerName
            phase = .connecting
            statusText = "正在与 \(peerName) 完成握手…"
            log("Multipeer 已连接：\(peerName)")
            if role == .left {
                await sendHello()
            }

        case .disconnected:
            guard role != nil else { return }
            showError("附近连接已断开，当前会话已结束")
            log("连接断开")
            await resetConnection(preserveError: true)

        case let .receivedData(data, peerName):
            do {
                let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
                await handle(envelope)
            } catch {
                let message = "无法解析来自 \(peerName) 的消息：\(error.localizedDescription)"
                showError(message)
                log(message)
            }

        case let .failure(message):
            showError(message)
            log(message)
        }
    }

    private func handle(_ envelope: SessionEnvelope) async {
        guard envelope.protocolVersion == peerProtocolVersion else {
            await failAndReset("两台设备的协议版本不兼容")
            return
        }

        if case let .hello(handshake) = envelope.payload,
           role == .right,
           sessionID == nil {
            guard handshake.role == .left else { return }
            sessionID = envelope.sessionID
        }

        guard envelope.sessionID == sessionID else {
            log("忽略旧会话消息")
            return
        }

        if case let .hello(handshake) = envelope.payload {
            await handleHello(handshake)
            return
        }

        guard phase == .connected else {
            log("握手完成前忽略功能消息")
            return
        }

        switch (experience, envelope.payload) {
        case (.desktop?, .desktop), (.chat?, .chat):
            await messageHandler?(envelope)
        default:
            log("忽略与当前功能不匹配的消息")
        }
    }

    private func sendHello() async {
        guard let role, let experience else { return }
        let hello = SessionHandshake(
            role: role,
            experience: experience,
            deviceName: UIDevice.current.name,
            desktopSummary: experience == .desktop ? desktopSummary : nil
        )
        do {
            try await send(.hello(hello), correlationID: nil, reliably: true)
        } catch {
            await failAndReset("握手发送失败：\(error.localizedDescription)")
        }
    }

    private func handleHello(_ hello: SessionHandshake) async {
        guard let role, hello.role == role.peerRole else {
            await failAndReset("两台设备选择了相同位置，请重新配对")
            return
        }
        guard let experience, hello.experience == experience else {
            await failAndReset("两台设备请选择相同功能")
            return
        }

        peerRole = hello.role
        if role == .right {
            await sendHello()
            guard self.role != nil else { return }
        }
        phase = .connected
        statusText = "已连接 \(hello.deviceName)"
        if let summary = hello.desktopSummary {
            log("握手完成，对端有 \(summary.itemCount) 个图标")
        } else {
            log("聊天握手完成")
        }
    }

    private func resetConnection(preserveError: Bool = false) async {
        pairingGeneration &+= 1
        activeTransportGeneration = nil
        await transport.stop()
        role = nil
        peerRole = nil
        connectedPeerName = nil
        nearbyPeers = []
        sessionID = nil
        sequence = 0
        desktopSummary = nil
        phase = .roleSelection
        statusText = "选择这台设备的位置"
        resetHandler?()
        if !preserveError {
            errorMessage = nil
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
        if logs.count > 80 {
            logs.removeFirst(logs.count - 80)
        }
#if DEBUG
        print("[TheHiddenFeature] \(message)")
#endif
    }

    enum SessionError: LocalizedError {
        case missingSession

        var errorDescription: String? {
            "附近连接尚未建立"
        }
    }
}
