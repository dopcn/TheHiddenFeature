import SwiftUI
import UIKit

struct ChatView: View {
    private static let messageListBottomID = "chat-message-list-bottom"

    @Bindable var model: ChatSessionModel

    private let backgroundColor = Color(red: 0.93, green: 0.93, blue: 0.93)

    var body: some View {
        GeometryReader { proxy in
            let usesTabletLayout = UIDevice.current.userInterfaceIdiom == .pad

            VStack(spacing: 0) {
                ChatNavigationBar(
                    title: navigationTitle,
                    allowsTitleDoubleTap: model.isPeerTyping,
                    onTitleDoubleTap: model.notifyPeerWaitingForInput
                )

                Divider()
                    .overlay(Color.black.opacity(0.04))

                messageList(
                    availableWidth: proxy.size.width,
                    usesTabletLayout: usesTabletLayout
                )

                Divider()
                    .overlay(Color.black.opacity(0.03))

                ChatComposerView(
                    text: Binding(
                        get: { model.draft },
                        set: { newValue in
                            model.updateDraft(newValue)
                        }
                    ),
                    usesTabletLayout: usesTabletLayout,
                    onFocusChanged: model.setComposerFocused,
                    onSubmit: model.sendDraft
                )
            }
            .background(backgroundColor)
        }
        .background(backgroundColor.ignoresSafeArea())
        .onDisappear {
            model.setComposerFocused(false)
        }
    }

    private var navigationTitle: String {
        if model.isPeerTyping {
            return "对方正在输入..."
        }
        if model.isPeerWaitingForInput {
            return "对方正在等待你的输入..."
        }
        return model.peerAccount.displayName
    }

    private func messageList(
        availableWidth: CGFloat,
        usesTabletLayout: Bool
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        if shouldShowTime(before: message, at: index) {
                            Text(Self.formattedTime(message.wire.sentAt))
                                .font(.system(size: usesTabletLayout ? 15 : 13))
                                .foregroundStyle(Color.black.opacity(0.28))
                                .padding(.top, index == 0 ? 26 : 18)
                                .padding(.bottom, 13)
                        }

                        MessageBubbleView(
                            message: message,
                            localAccount: model.localAccount,
                            availableWidth: availableWidth,
                            usesTabletLayout: usesTabletLayout
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 18)
                        .id(Self.messageListBottomID)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                scrollToLatest(using: scrollProxy, animated: false)
            }
            .onChange(of: model.messages.last?.id) { _, _ in
                scrollToLatest(using: scrollProxy, animated: true)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardDidShowNotification
                )
            ) { _ in
                scrollToLatest(using: scrollProxy, animated: true)
            }
        }
    }

    private func shouldShowTime(before message: ChatMessage, at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previousDate = model.messages[index - 1].wire.sentAt
        return message.wire.sentAt.timeIntervalSince(previousDate) >= 5 * 60
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.messageListBottomID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.messageListBottomID, anchor: .bottom)
        }
    }

    private static func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M月d日 EEEE HH:mm"
        }
        return formatter.string(from: date)
    }
}

private struct ChatNavigationBar: View {
    let title: String
    let allowsTitleDoubleTap: Bool
    let onTitleDoubleTap: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard allowsTitleDoubleTap else { return }
                    onTitleDoubleTap()
                }

            HStack {
                ChatBackIcon()
                    .frame(width: 44, height: 44, alignment: .leading)

                Spacer()

                ChatMoreIcon()
                    .frame(width: 44, height: 44, alignment: .trailing)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 58 : 44)
        .background(Color(red: 0.93, green: 0.93, blue: 0.93))
    }
}

private struct ChatComposerView: View {
    @Binding var text: String
    let usesTabletLayout: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: usesTabletLayout ? 16 : 9) {
            DecorativeChatIcon(kind: .voice, size: 23)

            ChatTextField(
                text: $text,
                fontSize: usesTabletLayout ? 18 : 17,
                onFocusChanged: onFocusChanged,
                onSubmit: onSubmit
            )
                .padding(.leading, 12)
                .padding(.trailing, 42)
                .frame(height: usesTabletLayout ? 46 : 40)
                .background(.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .trailing) {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: 42, height: usesTabletLayout ? 46 : 40)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

            DecorativeChatIcon(kind: .smile, size: 25)
            DecorativeChatIcon(kind: .plus, size: 25)
                .padding(.leading, usesTabletLayout ? 0 : 3)
        }
        .padding(.horizontal, usesTabletLayout ? 20 : 10)
        .padding(.vertical, usesTabletLayout ? 11 : 7)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }
}

private struct ChatTextField: UIViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.returnKeyType = .send
        textField.enablesReturnKeyAutomatically = false
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = .black
        textField.tintColor = .systemBlue
        textField.font = .systemFont(ofSize: fontSize)
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        textField.returnKeyType = .send
        textField.font = .systemFont(ofSize: fontSize)
        if textField.text != text {
            textField.text = text
        }
    }

    static func dismantleUIView(_ textField: UITextField, coordinator: Coordinator) {
        textField.resignFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ChatTextField

        init(parent: ChatTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChanged(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChanged(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            let onSubmit = parent.onSubmit
            DispatchQueue.main.async {
                onSubmit()
            }
            return false
        }
    }
}

private struct DecorativeChatIcon: View {
    enum Kind {
        case voice
        case smile
        case plus
    }

    let kind: Kind
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black, lineWidth: outerLineWidth)

            switch kind {
            case .voice:
                RotatedWiFiGlyph(lineWidth: outerLineWidth)
            case .smile:
                SmileGlyph()
            case .plus:
                PlusGlyph()
                    .padding(size * 0.20)
            }
        }
        .foregroundStyle(.black)
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var outerLineWidth: CGFloat {
        switch kind {
        case .voice:
            1.15
        case .smile, .plus:
            1.15
        }
    }
}

private struct RotatedWiFiGlyph: View {
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: size * 0.30, y: size * 0.50)

            Path { path in
                path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: size * 0.11,
                    startAngle: .degrees(-45),
                    endAngle: .degrees(45),
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(Color.black)

            Path { path in
                for radiusRatio in [0.23, 0.36] {
                    let radius = size * radiusRatio
                    let startOffset = radius / sqrt(2)

                    path.move(
                        to: CGPoint(
                            x: center.x + startOffset,
                            y: center.y - startOffset
                        )
                    )
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-45),
                        endAngle: .degrees(45),
                        clockwise: false
                    )
                }
            }
            .stroke(
                Color.black,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
        }
    }
}

private struct ChatBackIcon: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 10, y: 5))
            path.addLine(to: CGPoint(x: 3, y: 12))
            path.addLine(to: CGPoint(x: 10, y: 19))
        }
        .stroke(
            Color.black,
            style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 13, height: 24)
    }
}

private struct ChatMoreIcon: View {
    var body: some View {
        HStack(spacing: 4.5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.black)
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct SmileGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: width * 0.145, height: height * 0.145)
                    .position(x: width * 0.33, y: height * 0.35)

                Circle()
                    .fill(Color.black)
                    .frame(width: width * 0.145, height: height * 0.145)
                    .position(x: width * 0.68, y: height * 0.35)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.21, y: height * 0.54))
                    path.addLine(to: CGPoint(x: width * 0.79, y: height * 0.54))
                    path.addCurve(
                        to: CGPoint(x: width * 0.21, y: height * 0.54),
                        control1: CGPoint(x: width * 0.76, y: height * 0.84),
                        control2: CGPoint(x: width * 0.24, y: height * 0.84)
                    )
                }
                .stroke(
                    Color.black,
                    style: StrokeStyle(
                        lineWidth: width * 0.045,
                        lineCap: .butt,
                        lineJoin: .miter
                    )
                )
            }
        }
    }
}

private struct PlusGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.50, y: height * 0.08))
                path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.92))
                path.move(to: CGPoint(x: width * 0.08, y: height * 0.50))
                path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.50))
            }
            .stroke(
                Color.black,
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
        }
    }
}
