import SwiftUI

struct PairingView: View {
    @Bindable var model: DesktopSessionModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.08, blue: 0.18),
                    Color(red: 0.15, green: 0.12, blue: 0.32),
                    Color(red: 0.06, green: 0.28, blue: 0.38)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "ipad.and.iphone")
                    .font(.system(size: 62, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    Text("The Hidden Feature")
                        .font(.largeTitle.bold())
                    Text(model.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                pairingControls
                    .frame(maxWidth: 420)

                Spacer()

                Text("请将 iPhone 或 iPad 竖屏、顶边对齐放置")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }

    @ViewBuilder
    private var pairingControls: some View {
        switch model.phase {
        case .roleSelection:
            VStack(spacing: 12) {
                roleButton(.left, icon: "arrow.left.to.line")
                roleButton(.right, icon: "arrow.right.to.line")
            }
        case .discovering:
            if model.role == .left {
                waitingCard
            } else {
                peerList
            }
        case .connecting:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(model.statusText)
                    .font(.headline)
                cancelButton
            }
            .cardStyle()
        case .desktop:
            EmptyView()
        }
    }

    private func roleButton(_ role: DeviceRole, icon: String) -> some View {
        Button {
            model.chooseRole(role)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(role.title)
                        .font(.headline)
                    Text(role == .left ? "广播并等待右侧设备" : "搜索并选择左侧设备")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(18)
            .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var waitingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("在右侧设备上选择这台设备")
                .font(.headline)
            Text("保持应用在前台，并允许本地网络访问。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
            cancelButton
        }
        .cardStyle()
    }

    private var peerList: some View {
        VStack(spacing: 12) {
            if model.nearbyPeers.isEmpty {
                ProgressView()
                    .tint(.white)
                Text("正在搜索附近的左侧设备…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                Text("选择左侧设备")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(model.nearbyPeers) { peer in
                    Button {
                        model.connect(to: peer)
                    } label: {
                        Label(peer.name, systemImage: "iphone")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            cancelButton
        }
        .cardStyle()
    }

    private var cancelButton: some View {
        Button("返回角色选择") {
            model.returnToRoleSelection()
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.72))
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(20)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}
