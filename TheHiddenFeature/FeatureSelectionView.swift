import SwiftUI

struct FeatureSelectionView: View {
    let onSelect: (ExperienceMode) -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.07, blue: 0.16),
                    Color(red: 0.13, green: 0.10, blue: 0.29),
                    Color(red: 0.04, green: 0.24, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 54, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                    Text("The Hidden Feature")
                        .font(.largeTitle.bold())
                    Text("选择双设备体验")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                }

                VStack(spacing: 14) {
                    featureButton(
                        .desktop,
                        icon: "ipad.and.iphone",
                        subtitle: "在两块屏幕之间交接桌面图标"
                    )
                    featureButton(
                        .chat,
                        icon: "message.fill",
                        subtitle: "用两个预设账号进行附近聊天"
                    )
                }
                .frame(maxWidth: 460)

                Spacer()

                Text("两台设备需要选择相同功能和不同位置")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.56))
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }

    private func featureButton(
        _ experience: ExperienceMode,
        icon: String,
        subtitle: String
    ) -> some View {
        Button {
            onSelect(experience)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(experience.title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
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
}

#Preview {
    FeatureSelectionView { _ in }
        .preferredColorScheme(.dark)
}
