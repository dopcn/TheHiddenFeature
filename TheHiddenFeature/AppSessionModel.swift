import Observation

enum AppScreen: Equatable {
    case featureSelection
    case pairing
    case desktop
    case chat
}

@MainActor
@Observable
final class AppSessionModel {
    private(set) var selectedExperience: ExperienceMode?

    let connection: PeerSessionModel
    let desktop: DesktopSessionModel
    let chat: ChatSessionModel

    var screen: AppScreen {
        guard let selectedExperience else { return .featureSelection }
        guard connection.phase == .connected else { return .pairing }
        return selectedExperience == .desktop ? .desktop : .chat
    }

    init(transport: (any PeerTransport)? = nil) {
        let connection = transport.map(PeerSessionModel.init(transport:)) ?? PeerSessionModel()
        self.connection = connection
        desktop = DesktopSessionModel(connection: connection)
        chat = ChatSessionModel(connection: connection)

        connection.messageHandler = { [weak self] envelope in
            await self?.route(envelope)
        }
        connection.resetHandler = { [weak self] in
            self?.desktop.resetSession()
            self?.chat.resetSession()
        }
    }

    func selectExperience(_ experience: ExperienceMode) {
        guard selectedExperience == nil, connection.phase == .roleSelection else { return }
        selectedExperience = experience
    }

    func chooseRole(_ role: DeviceRole) {
        guard let selectedExperience else { return }

        let summary: DesktopSummary?
        if selectedExperience == .desktop {
            desktop.prepare(for: role)
            summary = DesktopSummary(
                itemCount: desktop.layout.itemCount,
                pageCount: desktop.layout.pages.count
            )
        } else {
            chat.prepare(for: role)
            summary = nil
        }

        connection.chooseRole(
            role,
            experience: selectedExperience,
            desktopSummary: summary
        )
    }

    func connect(to peer: NearbyPeer) {
        connection.connect(to: peer)
    }

    func returnToRoleSelection() {
        connection.returnToRoleSelection()
    }

    func returnToFeatureSelection() {
        Task {
            await connection.reset()
            selectedExperience = nil
        }
    }

    func handleDidEnterBackground() {
        connection.resetForBackground()
    }

    private func route(_ envelope: SessionEnvelope) async {
        switch envelope.payload {
        case let .desktop(message):
            await desktop.receive(message, envelope: envelope)
        case let .chat(message):
            await chat.receive(message, envelope: envelope)
        case .hello:
            break
        }
    }
}
