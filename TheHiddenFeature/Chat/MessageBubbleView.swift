import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let localAccount: ChatAccount
    let availableWidth: CGFloat
    let usesTabletLayout: Bool

    private var isOutgoing: Bool {
        message.wire.senderID == localAccount.id
    }

    private var bubbleColor: Color {
        isOutgoing
            ? Color(red: 149 / 255, green: 236 / 255, blue: 105 / 255)
            : .white
    }

    private var maximumBubbleWidth: CGFloat {
        if usesTabletLayout {
            return min(availableWidth * 0.56, 560)
        }
        return min(availableWidth * 0.68, 300)
    }

    var body: some View {
        HStack(alignment: .top, spacing: usesTabletLayout ? 13 : 7) {
            if isOutgoing {
                Spacer(minLength: usesTabletLayout ? 120 : 50)
                failureIndicator
                bubble
                ChatAvatarView(account: localAccount, usesTabletLayout: usesTabletLayout)
            } else {
                ChatAvatarView(
                    account: ChatAccount.account(for: accountRole(for: message.wire.senderID)),
                    usesTabletLayout: usesTabletLayout
                )
                bubble
                Spacer(minLength: usesTabletLayout ? 120 : 50)
            }
        }
        .padding(.horizontal, usesTabletLayout ? 14 : 12)
        .padding(.vertical, usesTabletLayout ? 8 : 6)
    }

    private var bubble: some View {
        Text(message.wire.body)
            .font(.system(size: usesTabletLayout ? 19 : 17))
            .foregroundStyle(.black)
            .lineSpacing(3)
            .padding(.vertical, usesTabletLayout ? 11 : 10)
            .padding(.horizontal, usesTabletLayout ? 14 : 12)
            .padding(isOutgoing ? .trailing : .leading, 6)
            .frame(
                minWidth: usesTabletLayout ? 50 : 46,
                minHeight: usesTabletLayout ? 44 : 42,
                alignment: .leading
            )
            .background {
                ChatBubbleBackground(
                    isOutgoing: isOutgoing,
                    color: bubbleColor
                )
            }
            .frame(
                maxWidth: maximumBubbleWidth,
                alignment: isOutgoing ? .trailing : .leading
            )
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var failureIndicator: some View {
        if message.state == .failed {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 18))
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func accountRole(for accountID: String) -> DeviceRole {
        accountID == ChatAccount.account(for: .left).id ? .left : .right
    }
}

private struct ChatAvatarView: View {
    let account: ChatAccount
    let usesTabletLayout: Bool

    var body: some View {
        Image(account.avatarStyle.assetName)
            .resizable()
            .scaledToFill()
            .frame(
                width: usesTabletLayout ? 44 : 40,
                height: usesTabletLayout ? 44 : 40
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(account.displayName)
    }
}

private struct ChatBubbleBackground: View {
    let isOutgoing: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let tailWidth: CGFloat = 7
            let tailOverlap: CGFloat = 2
            let cornerRadius: CGFloat = 5
            let bubbleRect = CGRect(
                x: isOutgoing ? 0 : tailWidth,
                y: 0,
                width: size.width - tailWidth,
                height: size.height
            )
            let tailCenterY = min(max(size.height * 0.34, 15), 22)

            var tailPath = Path()
            if isOutgoing {
                tailPath.move(
                    to: CGPoint(x: bubbleRect.maxX - tailOverlap, y: tailCenterY - 6)
                )
                tailPath.addLine(to: CGPoint(x: size.width, y: tailCenterY))
                tailPath.addLine(
                    to: CGPoint(x: bubbleRect.maxX - tailOverlap, y: tailCenterY + 6)
                )
            } else {
                tailPath.move(
                    to: CGPoint(x: bubbleRect.minX + tailOverlap, y: tailCenterY - 6)
                )
                tailPath.addLine(to: CGPoint(x: 0, y: tailCenterY))
                tailPath.addLine(
                    to: CGPoint(x: bubbleRect.minX + tailOverlap, y: tailCenterY + 6)
                )
            }
            tailPath.closeSubpath()
            context.fill(tailPath, with: .color(color))

            var bubblePath = Path()
            bubblePath.addRoundedRect(
                in: bubbleRect,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
            context.fill(bubblePath, with: .color(color))
        }
    }
}
