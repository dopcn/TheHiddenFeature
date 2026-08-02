import Observation
import SwiftUI
import UIKit

enum AppPhase {
    case roleSelection
    case discovering
    case connecting
    case desktop
}

@MainActor
@Observable
final class DesktopSessionModel {
    private(set) var phase: AppPhase = .roleSelection
    private(set) var role: DeviceRole?
    private(set) var nearbyPeers: [NearbyPeer] = []
    private(set) var connectedPeerName: String?
    private(set) var statusText = "选择这台设备的位置"
    private(set) var logs: [String] = []

    var layout = DesktopLayout.preset(for: .left)
    var currentPage = 0
    var isEditing = false
    var activeDragItem: DesktopItem?
    var dragLocation: CGPoint?
    private(set) var sourceTransfer: SourceTransfer?
    private(set) var targetTransfer: TargetTransfer?

    var errorMessage: String?

    private let transport: any PeerTransport
    private var eventTask: Task<Void, Never>?
    private var transferTimeoutTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var sequence: UInt64 = 0
    private var lastPreviewSequence: UInt64 = 0
    private var peerRole: DeviceRole?
    private var lastHoverSlot: DesktopSlot?
    private var pairingGeneration: UInt64 = 0
    private var activeTransportGeneration: UInt64?

    convenience init() {
        self.init(transport: MultipeerTransport())
#if DEBUG
        openLocalDesktopForDebugging()
#endif
    }

    init(transport: any PeerTransport) {
        self.transport = transport
        observeTransport()
    }

#if DEBUG
    private func openLocalDesktopForDebugging() {
        role = .left
        layout = .preset(for: .left)
        currentPage = 0
        connectedPeerName = nil
        phase = .desktop
        statusText = "本机桌面拖动调试"
        if ProcessInfo.processInfo.arguments.contains("-StartInEditMode") {
            isEditing = true
        }
        log("Debug 模式：跳过连接，直接进入本机桌面")
    }
#endif

    func chooseRole(_ role: DeviceRole) {
        guard phase == .roleSelection else { return }
        self.role = role
        layout = .preset(for: role)
        currentPage = 0
        nearbyPeers = []
        errorMessage = nil
        connectedPeerName = nil
        sessionID = role == .left ? UUID() : nil
        sequence = 0
        lastPreviewSequence = 0
        phase = .discovering
        statusText = role == .left ? "正在等待右侧设备连接…" : "正在搜索左侧设备…"
        log("选择角色：\(role.title)")
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

    func returnToRoleSelection() {
        Task {
            await resetConnection()
        }
    }

    func enterEditing() {
        guard phase == .desktop, !isEditing else { return }
        isEditing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func finishEditing() {
        guard sourceTransfer == nil, targetTransfer == nil else { return }
        activeDragItem = nil
        dragLocation = nil
        lastHoverSlot = nil
        isEditing = false
    }

    func beginDragging(_ item: DesktopItem, at location: CGPoint) {
        guard phase == .desktop, targetTransfer == nil else { return }
        if !isEditing {
            enterEditing()
        }
        guard activeDragItem == nil || activeDragItem?.id == item.id else { return }
        activeDragItem = item
        dragLocation = location
        lastHoverSlot = layout.slot(containing: item.id)
    }

    func updateDragging(
        _ item: DesktopItem,
        location: CGPoint,
        predictedEndLocation: CGPoint,
        nearestSlot: DesktopSlot?,
        canvasSize: CGSize
    ) {
        guard activeDragItem?.id == item.id else {
            beginDragging(item, at: location)
            return
        }
        dragLocation = location

        if sourceTransfer != nil {
            updateSourceTransfer(location: location, canvasSize: canvasSize)
            return
        }

        if shouldBeginTransfer(
            location: location,
            predictedEndLocation: predictedEndLocation,
            canvasSize: canvasSize
        ) {
            beginSourceTransfer(item: item, location: location, canvasSize: canvasSize)
            return
        }

        lastHoverSlot = nearestSlot
    }

    func endDragging(_ item: DesktopItem, nearestSlot: DesktopSlot?) {
        guard activeDragItem?.id == item.id else { return }
        if sourceTransfer == nil, let nearestSlot {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                layout.move(item, to: nearestSlot)
            }
        }
        activeDragItem = nil
        dragLocation = nil
        lastHoverSlot = nil
    }

    func updateTargetTouch(location: CGPoint, canvasSize: CGSize) {
        guard var transfer = targetTransfer else { return }

        if !transfer.isCaptured {
            let expectedY = mappedTargetY(transfer, targetHeight: canvasSize.height)
            let isNearY = abs(location.y - expectedY) <= 72
            let isNearEdge: Bool
            switch role?.sharedEdge {
            case .leading:
                isNearEdge = location.x <= 96
            case .trailing:
                isNearEdge = location.x >= canvasSize.width - 96
            case nil:
                isNearEdge = false
            }
            guard isNearY, isNearEdge else { return }
            transfer.isCaptured = true
            transfer.transaction.phase = .accepted
            restartTransferTimeout(for: transfer.transaction.id, reason: .commitTimedOut)
            Task {
                await send(.transferAccept, transactionID: transfer.transaction.id, reliably: true)
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            log("目标设备接管交接 \(shortID(transfer.transaction.id))")
        }

        transfer.location = location
        targetTransfer = transfer
    }

    func endTargetTouch(nearestSlot: DesktopSlot?) {
        guard var transfer = targetTransfer, transfer.isCaptured else { return }
        transfer.pendingSlot = nearestSlot ?? layout.firstAvailablePageSlot(preferredPage: currentPage)
        targetTransfer = transfer
        finalizeTargetTransferIfReady()
    }

    func targetPreviewLocation(canvasSize: CGSize) -> CGPoint? {
        guard let transfer = targetTransfer else { return nil }
        if let location = transfer.location {
            return location
        }
        let x: CGFloat = role?.sharedEdge == .leading ? 10 : canvasSize.width - 10
        return CGPoint(x: x, y: mappedTargetY(transfer, targetHeight: canvasSize.height))
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
        guard event.generation == activeTransportGeneration else {
            return
        }

        switch event.payload {
        case let .peersChanged(peers):
            nearbyPeers = peers
        case let .connected(peerName):
            guard role != nil, phase == .discovering || phase == .connecting else {
                return
            }
            connectedPeerName = peerName
            phase = .connecting
            statusText = "正在与 \(peerName) 完成握手…"
            log("Multipeer 已连接：\(peerName)")
            if role == .left {
                await sendHello()
            }
        case .disconnected:
            guard role != nil else { return }
            showError("附近连接已断开，当前交接已安全取消")
            log("连接断开")
            await resetConnection(preserveError: true)
        case let .receivedData(data, peerName):
            do {
                let envelope = try JSONDecoder().decode(PeerEnvelope.self, from: data)
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

    private func handle(_ envelope: PeerEnvelope) async {
        guard envelope.protocolVersion == peerProtocolVersion else {
            showError("两台设备的协议版本不兼容")
            return
        }

        if case let .hello(handshake) = envelope.message,
           role == .right,
           sessionID == nil {
            guard handshake.role == .left else { return }
            sessionID = envelope.sessionID
        }

        guard envelope.sessionID == sessionID else {
            log("忽略旧会话消息")
            return
        }

        switch envelope.message {
        case let .hello(handshake):
            await handleHello(handshake)
        case let .transferRequest(offer):
            await receiveTransferRequest(offer, envelope: envelope)
        case let .transferPreview(preview):
            guard envelope.sequence > lastPreviewSequence else { return }
            lastPreviewSequence = envelope.sequence
            receiveTransferPreview(preview, transactionID: envelope.transactionID)
        case .transferAccept:
            await receiveTransferAccept(transactionID: envelope.transactionID)
        case .transferCommit:
            await receiveTransferCommit(transactionID: envelope.transactionID)
        case .transferAcknowledged:
            receiveTransferAcknowledgement(transactionID: envelope.transactionID)
        case let .transferCancel(reason):
            receiveTransferCancellation(reason: reason, transactionID: envelope.transactionID)
        }
    }

    private func sendHello() async {
        guard let role else { return }
        let hello = Handshake(
            role: role,
            deviceName: UIDevice.current.name,
            summary: DesktopSummary(itemCount: layout.itemCount, pageCount: layout.pages.count)
        )
        await send(.hello(hello), transactionID: nil, reliably: true)
    }

    private func handleHello(_ hello: Handshake) async {
        guard let role, hello.role == role.peerRole else {
            showError("两台设备选择了相同位置，请重新配对")
            await resetConnection(preserveError: true)
            return
        }
        peerRole = hello.role
        if role == .right {
            await sendHello()
        }
        phase = .desktop
        statusText = "已连接 \(hello.deviceName)"
        log("握手完成，对端有 \(hello.summary.itemCount) 个图标")
    }

    private func shouldBeginTransfer(
        location: CGPoint,
        predictedEndLocation: CGPoint,
        canvasSize: CGSize
    ) -> Bool {
        guard phase == .desktop, connectedPeerName != nil, let role else { return false }
        switch role.sharedEdge {
        case .trailing:
            return location.x >= canvasSize.width - 20
                && predictedEndLocation.x >= canvasSize.width + 32
        case .leading:
            return location.x <= 20 && predictedEndLocation.x <= -32
        }
    }

    private func beginSourceTransfer(item: DesktopItem, location: CGPoint, canvasSize: CGSize) {
        guard sourceTransfer == nil,
              targetTransfer == nil,
              let sourceSlot = layout.slot(containing: item.id) else { return }
        let normalizedY = normalizedY(location.y, height: canvasSize.height)
        let transaction = TransferTransaction(
            id: UUID(),
            item: item,
            sourceSlot: sourceSlot,
            normalizedY: normalizedY,
            phase: .offered
        )
        sourceTransfer = SourceTransfer(
            transaction: transaction,
            location: location,
            lastPreviewSentAt: 0,
            commitRetryCount: 0
        )
        restartTransferTimeout(for: transaction.id, reason: .takeoverTimedOut)
        let offer = TransferOffer(
            item: item,
            sourceSlot: sourceSlot,
            sourceY: Double(location.y),
            sourceCanvasHeight: Double(canvasSize.height),
            sourceFormFactor: currentFormFactor,
            normalizedY: normalizedY
        )
        Task {
            await send(.transferRequest(offer), transactionID: transaction.id, reliably: true)
        }
        log("开始交接 \(shortID(transaction.id))：\(item.title)")
    }

    private func updateSourceTransfer(location: CGPoint, canvasSize: CGSize) {
        guard var transfer = sourceTransfer, let role else { return }
        transfer.location = location

        let movedAway: Bool
        switch role.sharedEdge {
        case .trailing:
            movedAway = location.x < canvasSize.width - 44
        case .leading:
            movedAway = location.x > 44
        }
        if movedAway, transfer.transaction.phase == .offered {
            cancelSourceTransfer(reason: .movedAway, notifyPeer: true)
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        if now - transfer.lastPreviewSentAt >= 1.0 / 30.0 {
            transfer.lastPreviewSentAt = now
            let y = normalizedY(location.y, height: canvasSize.height)
            let progress: Double
            switch role.sharedEdge {
            case .trailing:
                progress = Double(max(0, location.x - (canvasSize.width - 20)) / 52)
            case .leading:
                progress = Double(max(0, 20 - location.x) / 52)
            }
            Task {
                await send(
                    .transferPreview(
                        TransferPreview(
                            sourceY: Double(location.y),
                            normalizedY: y,
                            edgeProgress: min(progress, 1)
                        )
                    ),
                    transactionID: transfer.transaction.id,
                    reliably: false
                )
            }
        }
        sourceTransfer = transfer
    }

    private func receiveTransferRequest(_ offer: TransferOffer, envelope: PeerEnvelope) async {
        guard phase == .desktop,
              let transactionID = envelope.transactionID,
              sourceTransfer == nil,
              targetTransfer == nil,
              layout.slot(containing: offer.item.id) == nil else {
            if let transactionID = envelope.transactionID {
                await send(.transferCancel(.invalidState), transactionID: transactionID, reliably: true)
            }
            return
        }
        let transaction = TransferTransaction(
            id: transactionID,
            item: offer.item,
            sourceSlot: offer.sourceSlot,
            normalizedY: offer.normalizedY,
            phase: .offered
        )
        targetTransfer = TargetTransfer(
            transaction: transaction,
            sourceY: offer.sourceY,
            sourceCanvasHeight: offer.sourceCanvasHeight,
            sourceFormFactor: offer.sourceFormFactor,
            normalizedY: offer.normalizedY,
            location: nil,
            isCaptured: false,
            isCommitted: false,
            pendingSlot: nil
        )
        isEditing = true
        restartTransferTimeout(for: transactionID, reason: .takeoverTimedOut)
        log("收到交接 \(shortID(transactionID))：\(offer.item.title)")
    }

    private func receiveTransferPreview(_ preview: TransferPreview, transactionID: UUID?) {
        guard var transfer = targetTransfer,
              transfer.transaction.id == transactionID,
              !transfer.isCaptured else { return }
        transfer.sourceY = preview.sourceY
        transfer.normalizedY = min(max(preview.normalizedY, 0), 1)
        targetTransfer = transfer
    }

    private func receiveTransferAccept(transactionID: UUID?) async {
        guard var transfer = sourceTransfer,
              transfer.transaction.id == transactionID else { return }
        if transfer.transaction.phase == .committed {
            await send(.transferCommit, transactionID: transfer.transaction.id, reliably: true)
            return
        }
        guard transfer.transaction.phase == .offered else { return }
        transfer.transaction.phase = .committed
        sourceTransfer = transfer
        restartTransferTimeout(for: transfer.transaction.id, reason: .commitTimedOut)
        await send(.transferCommit, transactionID: transfer.transaction.id, reliably: true)
        log("提交交接 \(shortID(transfer.transaction.id))")
    }

    private func receiveTransferCommit(transactionID: UUID?) async {
        guard var transfer = targetTransfer,
              transfer.transaction.id == transactionID,
              transfer.isCaptured else { return }
        if transfer.transaction.phase == .committed {
            await send(.transferAcknowledged, transactionID: transfer.transaction.id, reliably: true)
            return
        }
        guard transfer.transaction.phase == .accepted else { return }
        transfer.transaction.phase = .committed
        transfer.isCommitted = true
        targetTransfer = transfer
        transferTimeoutTask?.cancel()
        await send(.transferAcknowledged, transactionID: transfer.transaction.id, reliably: true)
        log("确认交接 \(shortID(transfer.transaction.id))")
        finalizeTargetTransferIfReady()
    }

    private func receiveTransferAcknowledgement(transactionID: UUID?) {
        guard let transfer = sourceTransfer,
              transfer.transaction.id == transactionID,
              transfer.transaction.phase == .committed else { return }
        transferTimeoutTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            layout.remove(itemID: transfer.transaction.item.id)
        }
        if activeDragItem?.id == transfer.transaction.item.id {
            activeDragItem = nil
            dragLocation = nil
        }
        sourceTransfer = nil
        log("交接完成 \(shortID(transfer.transaction.id))")
    }

    private func receiveTransferCancellation(reason: TransferCancelReason, transactionID: UUID?) {
        if let transfer = sourceTransfer, transfer.transaction.id == transactionID {
            transferTimeoutTask?.cancel()
            sourceTransfer = nil
            log("来源交接回滚：\(reason.rawValue)")
        }
        if let transfer = targetTransfer,
           transfer.transaction.id == transactionID,
           !transfer.isCommitted {
            transferTimeoutTask?.cancel()
            targetTransfer = nil
            log("目标交接取消：\(reason.rawValue)")
        }
    }

    private func finalizeTargetTransferIfReady() {
        guard let transfer = targetTransfer,
              transfer.isCommitted,
              let destination = transfer.pendingSlot else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            layout.move(transfer.transaction.item, to: destination)
        }
        targetTransfer = nil
        log("图标已落位：\(transfer.transaction.item.title)")
    }

    private func cancelSourceTransfer(reason: TransferCancelReason, notifyPeer: Bool) {
        guard let transfer = sourceTransfer, !transfer.isCommitted else { return }
        transferTimeoutTask?.cancel()
        sourceTransfer = nil
        if notifyPeer {
            Task {
                await send(.transferCancel(reason), transactionID: transfer.transaction.id, reliably: true)
            }
        }
        log("取消交接：\(reason.rawValue)")
    }

    private func cancelTargetTransfer(reason: TransferCancelReason, notifyPeer: Bool) {
        guard let transfer = targetTransfer, !transfer.isCommitted else { return }
        transferTimeoutTask?.cancel()
        targetTransfer = nil
        if notifyPeer {
            Task {
                await send(.transferCancel(reason), transactionID: transfer.transaction.id, reliably: true)
            }
        }
        log("目标交接超时：\(reason.rawValue)")
    }

    private func restartTransferTimeout(for transactionID: UUID, reason: TransferCancelReason) {
        transferTimeoutTask?.cancel()
        transferTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled, let self else { return }
            if var transfer = sourceTransfer,
               transfer.transaction.id == transactionID,
               transfer.isCommitted {
                transfer.commitRetryCount += 1
                sourceTransfer = transfer
                if transfer.commitRetryCount <= 2 {
                    await send(
                        .transferCommit,
                        transactionID: transactionID,
                        reliably: true
                    )
                    restartTransferTimeout(for: transactionID, reason: reason)
                } else {
                    showError("交接确认超时，连接已重置以避免图标重复")
                    await resetConnection(preserveError: true)
                }
            } else if sourceTransfer?.transaction.id == transactionID {
                cancelSourceTransfer(reason: reason, notifyPeer: true)
            } else if targetTransfer?.transaction.id == transactionID {
                cancelTargetTransfer(reason: reason, notifyPeer: true)
            }
        }
    }

    private func send(
        _ message: PeerMessage,
        transactionID: UUID?,
        reliably: Bool
    ) async {
        guard let sessionID else { return }
        sequence &+= 1
        let envelope = PeerEnvelope(
            protocolVersion: peerProtocolVersion,
            sessionID: sessionID,
            sequence: sequence,
            transactionID: transactionID,
            message: message
        )
        do {
            try await transport.send(envelope, reliably: reliably)
        } catch {
            log("发送失败：\(error.localizedDescription)")
        }
    }

    private func resetConnection(preserveError: Bool = false) async {
        pairingGeneration &+= 1
        activeTransportGeneration = nil
        transferTimeoutTask?.cancel()
        sourceTransfer = nil
        targetTransfer = nil
        activeDragItem = nil
        dragLocation = nil
        isEditing = false
        await transport.stop()
        role = nil
        peerRole = nil
        connectedPeerName = nil
        nearbyPeers = []
        sessionID = nil
        sequence = 0
        lastPreviewSequence = 0
        phase = .roleSelection
        statusText = "选择这台设备的位置"
        if !preserveError {
            errorMessage = nil
        }
    }

    private func normalizedY(_ y: CGFloat, height: CGFloat) -> Double {
        guard height > 0 else { return 0.5 }
        return Double(min(max(y / height, 0), 1))
    }

    private var currentFormFactor: DeviceFormFactor {
        UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone
    }

    private func mappedTargetY(
        _ transfer: TargetTransfer,
        targetHeight: CGFloat
    ) -> CGFloat {
        guard transfer.sourceCanvasHeight > 0 else {
            return CGFloat(transfer.normalizedY) * targetHeight
        }
        let scale = currentFormFactor.nominalPointsPerInch
            / transfer.sourceFormFactor.nominalPointsPerInch
        return CGFloat(transfer.sourceY * scale)
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

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(6))
    }
}

struct SourceTransfer {
    var transaction: TransferTransaction
    var location: CGPoint
    var lastPreviewSentAt: TimeInterval
    var commitRetryCount: Int

    var isCommitted: Bool {
        transaction.phase == .committed || transaction.phase == .acknowledged
    }
}

struct TargetTransfer {
    var transaction: TransferTransaction
    var sourceY: Double
    var sourceCanvasHeight: Double
    var sourceFormFactor: DeviceFormFactor
    var normalizedY: Double
    var location: CGPoint?
    var isCaptured: Bool
    var isCommitted: Bool
    var pendingSlot: DesktopSlot?
}
