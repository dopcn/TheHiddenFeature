import Foundation
import Observation

@MainActor
@Observable
final class ChatSessionModel {
    static let maximumMessageLength = 2_000
    static let maximumMessageCount = 1_000

    private static let typingHeartbeatInterval = Duration.milliseconds(1_500)
    private static let typingIdleInterval = Duration.seconds(10)
    private static let peerTypingTimeout = Duration.seconds(12)
    private static let peerWaitingForInputTimeout = Duration.seconds(10)

    private(set) var localAccount = ChatAccount.account(for: .left)
    private(set) var peerAccount = ChatAccount.account(for: .right)
    private(set) var messages: [ChatMessage] = []
    private(set) var draft = ""
    private(set) var isPeerTyping = false
    private(set) var isPeerWaitingForInput = false

    var isConnected: Bool {
        connection.phase == .connected
    }

    @ObservationIgnored
    private let connection: PeerSessionModel

    @ObservationIgnored
    private var receivedMessageIDs: Set<UUID> = []

    @ObservationIgnored
    private var localRole: DeviceRole = .left

    @ObservationIgnored
    private var hasSentLiveMessageToPeer = false

    @ObservationIgnored
    private var hasReceivedLiveMessageFromPeer = false

    @ObservationIgnored
    private var isComposerFocused = false

    @ObservationIgnored
    private var isLocalTyping = false

    @ObservationIgnored
    private var lastTypingSignalTime: ContinuousClock.Instant?

    @ObservationIgnored
    private var localTypingIdleTask: Task<Void, Never>?

    @ObservationIgnored
    private var peerTypingTimeoutTask: Task<Void, Never>?

    @ObservationIgnored
    private var peerWaitingForInputTimeoutTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastPeerTypingSequence: UInt64?

    @ObservationIgnored
    private var pendingChatTransmissions: [PendingChatTransmission] = []

    @ObservationIgnored
    private var chatTransmissionTask: Task<Void, Never>?

    @ObservationIgnored
    private var typingGeneration: UInt64 = 0

    private let typingClock = ContinuousClock()

    init(connection: PeerSessionModel) {
        self.connection = connection
    }

    func prepare(for role: DeviceRole) {
        resetSession()
        localRole = role
        localAccount = .account(for: role)
        peerAccount = .account(for: role.peerRole)
        loadPresetHistory()
    }

    func resetSession() {
        typingGeneration &+= 1
        localTypingIdleTask?.cancel()
        localTypingIdleTask = nil
        peerTypingTimeoutTask?.cancel()
        peerTypingTimeoutTask = nil
        peerWaitingForInputTimeoutTask?.cancel()
        peerWaitingForInputTimeoutTask = nil
        chatTransmissionTask?.cancel()
        chatTransmissionTask = nil
        pendingChatTransmissions.removeAll()
        isComposerFocused = false
        isLocalTyping = false
        lastTypingSignalTime = nil
        isPeerTyping = false
        isPeerWaitingForInput = false
        lastPeerTypingSequence = nil
        hasSentLiveMessageToPeer = false
        hasReceivedLiveMessageFromPeer = false
        messages.removeAll()
        receivedMessageIDs.removeAll()
        draft = ""
    }

    func updateDraft(_ newValue: String) {
        let limitedValue = String(newValue.prefix(Self.maximumMessageLength))
        guard limitedValue != draft else { return }

        draft = limitedValue
        guard isComposerFocused,
              isConnected,
              localRole == .right,
              hasReceivedLiveMessageFromPeer,
              !limitedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            endLocalTyping()
            return
        }

        registerLocalTypingActivity()
    }

    func setComposerFocused(_ isFocused: Bool) {
        guard isComposerFocused != isFocused else { return }
        isComposerFocused = isFocused
        if !isFocused {
            endLocalTyping()
        }
    }

    func sendDraft() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected,
              !body.isEmpty,
              body.count <= Self.maximumMessageLength else { return }

        endLocalTyping()
        clearPeerWaitingForInput()
        let wire = ChatWireMessage(
            id: UUID(),
            senderID: localAccount.id,
            body: body,
            sentAt: Date()
        )
        append(ChatMessage(wire: wire, state: .sending))
        if localRole == .left {
            hasSentLiveMessageToPeer = true
        }
        draft = ""
        enqueueMessage(wire)
    }

    func receive(_ message: ChatPeerMessage, envelope: SessionEnvelope) async {
        switch message {
        case let .send(wire):
            await receive(
                wire,
                correlationID: envelope.correlationID,
                sequence: envelope.sequence
            )
        case let .acknowledged(messageID):
            receiveAcknowledgement(messageID)
        case let .typing(event):
            receive(event, sequence: envelope.sequence)
        case let .waitingForInput(event):
            receive(event)
        }
    }

    private func receive(
        _ wire: ChatWireMessage,
        correlationID: UUID?,
        sequence: UInt64
    ) async {
        guard correlationID == wire.id,
              wire.senderID == peerAccount.id,
              !wire.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              wire.body.count <= Self.maximumMessageLength else {
            connection.addDebugLog("忽略无效聊天消息")
            return
        }

        clearPeerTyping(through: sequence)
        if localRole == .right {
            hasReceivedLiveMessageFromPeer = true
            clearPeerWaitingForInput()
        }
        if receivedMessageIDs.insert(wire.id).inserted {
            append(ChatMessage(wire: wire, state: .delivered))
        }

        do {
            try await connection.send(
                .chat(.acknowledged(messageID: wire.id)),
                correlationID: wire.id,
                reliably: true
            )
        } catch {
            connection.addDebugLog("聊天确认发送失败：\(error.localizedDescription)")
        }
    }

    private func receiveAcknowledgement(_ messageID: UUID) {
        guard let index = messages.firstIndex(where: {
            $0.id == messageID && $0.wire.senderID == localAccount.id
        }) else { return }
        messages[index].state = .delivered
    }

    private func registerLocalTypingActivity() {
        let now = typingClock.now
        if !isLocalTyping {
            isLocalTyping = true
            lastTypingSignalTime = now
            enqueueTyping(.active, reliably: true)
        } else if let lastTypingSignalTime,
                  lastTypingSignalTime.duration(to: now) >= Self.typingHeartbeatInterval {
            self.lastTypingSignalTime = now
            enqueueTyping(.active, reliably: false)
        }

        localTypingIdleTask?.cancel()
        let generation = typingGeneration
        localTypingIdleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.typingIdleInterval)
            } catch {
                return
            }
            guard let self, self.typingGeneration == generation else { return }
            self.endLocalTyping()
        }
    }

    private func endLocalTyping() {
        localTypingIdleTask?.cancel()
        localTypingIdleTask = nil
        lastTypingSignalTime = nil
        guard isLocalTyping else { return }

        isLocalTyping = false
        if isConnected {
            enqueueTyping(.inactive, reliably: true)
        }
    }

    private func enqueueTyping(_ phase: ChatTypingPhase, reliably: Bool) {
        pendingChatTransmissions.append(
            PendingChatTransmission(
                payload: .chat(
                    .typing(ChatTypingEvent(senderID: localAccount.id, phase: phase))
                ),
                correlationID: nil,
                reliably: reliably,
                generation: typingGeneration,
                kind: .typing
            )
        )
        startChatTransmissionIfNeeded()
    }

    private func enqueueMessage(_ wire: ChatWireMessage) {
        pendingChatTransmissions.append(
            PendingChatTransmission(
                payload: .chat(.send(wire)),
                correlationID: wire.id,
                reliably: true,
                generation: typingGeneration,
                kind: .message(wire.id)
            )
        )
        startChatTransmissionIfNeeded()
    }

    func notifyPeerWaitingForInput() {
        guard isConnected,
              localRole == .left,
              hasSentLiveMessageToPeer,
              isPeerTyping else { return }

        pendingChatTransmissions.append(
            PendingChatTransmission(
                payload: .chat(
                    .waitingForInput(
                        ChatWaitingForInputEvent(senderID: localAccount.id)
                    )
                ),
                correlationID: nil,
                reliably: true,
                generation: typingGeneration,
                kind: .waitingForInput
            )
        )
        startChatTransmissionIfNeeded()
    }

    private func startChatTransmissionIfNeeded() {
        guard chatTransmissionTask == nil else { return }
        let generation = typingGeneration
        chatTransmissionTask = Task { [weak self] in
            await self?.drainChatTransmissions(generation: generation)
        }
    }

    private func drainChatTransmissions(generation: UInt64) async {
        defer {
            if typingGeneration == generation {
                chatTransmissionTask = nil
            }
        }

        while typingGeneration == generation,
              !Task.isCancelled,
              !pendingChatTransmissions.isEmpty {
            let transmission = pendingChatTransmissions.removeFirst()
            guard transmission.generation == generation, isConnected else { continue }

            do {
                try await connection.send(
                    transmission.payload,
                    correlationID: transmission.correlationID,
                    reliably: transmission.reliably
                )
                if case let .message(messageID) = transmission.kind {
                    updateState(for: messageID, from: .sending, to: .sent)
                }
            } catch {
                guard typingGeneration == generation else { return }
                switch transmission.kind {
                case .typing:
                    connection.addDebugLog("输入状态发送失败：\(error.localizedDescription)")
                case .waitingForInput:
                    connection.addDebugLog("等待输入提醒发送失败：\(error.localizedDescription)")
                case let .message(messageID):
                    updateState(for: messageID, to: .failed)
                    connection.addDebugLog("聊天消息发送失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func receive(_ event: ChatWaitingForInputEvent) {
        guard localRole == .right,
              hasReceivedLiveMessageFromPeer,
              event.senderID == peerAccount.id else {
            connection.addDebugLog("忽略无效等待输入提醒")
            return
        }

        isPeerWaitingForInput = true
        peerWaitingForInputTimeoutTask?.cancel()
        let generation = typingGeneration
        peerWaitingForInputTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.peerWaitingForInputTimeout)
            } catch {
                return
            }
            guard let self, self.typingGeneration == generation else { return }
            self.peerWaitingForInputTimeoutTask = nil
            self.isPeerWaitingForInput = false
        }
    }

    private func receive(_ event: ChatTypingEvent, sequence: UInt64) {
        guard localRole == .left,
              hasSentLiveMessageToPeer,
              event.senderID == peerAccount.id else {
            connection.addDebugLog("忽略无效输入状态")
            return
        }
        if let lastPeerTypingSequence, sequence <= lastPeerTypingSequence {
            connection.addDebugLog("忽略过期输入状态")
            return
        }
        lastPeerTypingSequence = sequence

        switch event.phase {
        case .active:
            showPeerTyping()
        case .inactive:
            clearPeerTyping(through: sequence)
        }
    }

    private func showPeerTyping() {
        isPeerTyping = true
        peerTypingTimeoutTask?.cancel()
        let generation = typingGeneration
        peerTypingTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.peerTypingTimeout)
            } catch {
                return
            }
            guard let self, self.typingGeneration == generation else { return }
            self.peerTypingTimeoutTask = nil
            self.isPeerTyping = false
        }
    }

    private func clearPeerTyping(through sequence: UInt64?) {
        if let sequence {
            if let lastPeerTypingSequence {
                self.lastPeerTypingSequence = max(lastPeerTypingSequence, sequence)
            } else {
                lastPeerTypingSequence = sequence
            }
        }
        peerTypingTimeoutTask?.cancel()
        peerTypingTimeoutTask = nil
        isPeerTyping = false
    }

    private func clearPeerWaitingForInput() {
        peerWaitingForInputTimeoutTask?.cancel()
        peerWaitingForInputTimeoutTask = nil
        isPeerWaitingForInput = false
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > Self.maximumMessageCount {
            messages.removeFirst(messages.count - Self.maximumMessageCount)
        }
    }

    private func loadPresetHistory() {
        let workAccount = ChatAccount.account(for: .left)
        let weizhouAccount = ChatAccount.account(for: .right)
        let firstMessageDate = Date().addingTimeInterval(-5 * 60)
        let entries = [
            (senderID: weizhouAccount.id, body: "1"),
            (senderID: weizhouAccount.id, body: "1"),
            (senderID: workAccount.id, body: "test"),
            (senderID: workAccount.id, body: "1"),
            (senderID: weizhouAccount.id, body: "1"),
            (senderID: workAccount.id, body: "1")
        ]

        messages = entries.enumerated().map { index, entry in
            ChatMessage(
                wire: ChatWireMessage(
                    id: UUID(),
                    senderID: entry.senderID,
                    body: entry.body,
                    sentAt: firstMessageDate.addingTimeInterval(Double(index) * 15)
                ),
                state: .delivered
            )
        }
    }

    private func updateState(
        for messageID: UUID,
        from expectedState: ChatMessageState? = nil,
        to newState: ChatMessageState
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        if let expectedState, messages[index].state != expectedState {
            return
        }
        messages[index].state = newState
    }
}

private struct PendingChatTransmission {
    let payload: SessionPayload
    let correlationID: UUID?
    let reliably: Bool
    let generation: UInt64
    let kind: ChatTransmissionKind
}

private enum ChatTransmissionKind {
    case typing
    case waitingForInput
    case message(UUID)
}
