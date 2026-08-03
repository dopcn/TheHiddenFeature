import SwiftUI
import UIKit

struct IconView: View {
    let item: DesktopItem
    var isEditing = false
    var isLifted = false
    var iconSize: CGFloat = 60
    var showsTitle = true
    var usesTabletStyle = false

    @State private var wigglePhase = false

    var body: some View {
        VStack(spacing: max(4, iconSize * 0.08)) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconBackground)
                iconArtwork
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) {
                if isEditing && !isLifted {
                    ZStack {
                        Circle()
                            .fill(
                                usesTabletStyle
                                    ? Color(white: 0.78).opacity(0.96)
                                    : .white.opacity(0.82)
                            )
                        Image(systemName: "minus")
                            .font(
                                .system(
                                    size: iconSize * (usesTabletStyle ? 0.18 : 0.17),
                                    weight: .heavy
                                )
                            )
                            .foregroundStyle(
                                usesTabletStyle
                                    ? Color.black.opacity(0.82)
                                    : Color(red: 0.18, green: 0.48, blue: 0.54)
                            )
                    }
                    .frame(
                        width: iconSize * (usesTabletStyle ? 0.36 : 0.31),
                        height: iconSize * (usesTabletStyle ? 0.36 : 0.31)
                    )
                    .overlay {
                        Circle().stroke(.black.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .offset(
                        x: -iconSize * (usesTabletStyle ? 0.11 : 0.09),
                        y: -iconSize * (usesTabletStyle ? 0.11 : 0.09)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(
                color: .black.opacity(isLifted ? 0.38 : 0.2),
                radius: isLifted ? iconSize * 0.2 : iconSize * 0.05,
                y: isLifted ? iconSize * 0.11 : 2
            )

            if showsTitle {
                Text(item.title)
                    .font(
                        .system(
                            size: usesTabletStyle ? 13 : (iconSize < 56 ? 10 : 12),
                            weight: .medium
                        )
                    )
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            }
        }
        .scaleEffect(isLifted ? 1.12 : 1)
        .rotationEffect(
            .degrees(
                isEditing && !isLifted
                    ? (wigglePhase ? wiggleAngle : -wiggleAngle)
                    : 0
            )
        )
        .offset(
            x: isEditing && !isLifted && !usesTabletStyle
                ? (wigglePhase ? 0.8 : -0.8) * phaseDirection
                : 0,
            y: isEditing && !isLifted && !usesTabletStyle
                ? (wigglePhase ? -0.45 : 0.45)
                : 0
        )
        .task(id: isEditing && !isLifted) {
            let shouldWiggle = isEditing && !isLifted
            guard shouldWiggle else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    wigglePhase = false
                }
                return
            }

            wigglePhase = false
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: wiggleDuration)) {
                    wigglePhase.toggle()
                }
                do {
                    try await Task.sleep(for: .seconds(wiggleDuration))
                } catch {
                    return
                }
            }
        }
    }

    @ViewBuilder
    private var iconArtwork: some View {
        if let iconAssetName = item.iconAssetName,
           let iconImage = UIImage(
               named: "\(iconAssetName).png",
               in: .main,
               compatibleWith: nil
           ) {
            Image(uiImage: iconImage)
                .resizable()
                .scaledToFill()
        } else if item.title == "日历" {
            CalendarIconArtwork(iconSize: iconSize)
        } else if item.title == "时钟" {
            ClockIconArtwork(iconSize: iconSize)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(highlightOpacity),
                                .clear,
                                .black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: item.symbolName)
                    .font(.system(size: iconSize * symbolScale, weight: .semibold))
                    .symbolRenderingMode(symbolRenderingMode)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            }
        }
    }

    private var iconBackground: LinearGradient {
        let colors = item.colors.isEmpty
            ? [Color.gray, Color.secondary]
            : item.colors.map(\.color)
        let direction = item.id.uuid.1 % 2
        return LinearGradient(
            colors: colors,
            startPoint: direction == 0 ? .topLeading : .top,
            endPoint: direction == 0 ? .bottomTrailing : .bottom
        )
    }

    private var iconCornerRadius: CGFloat {
        iconSize * 0.235
    }

    private var highlightOpacity: Double {
        0.12 + Double(item.id.uuid.2 % 4) * 0.035
    }

    private var symbolScale: CGFloat {
        0.39 + CGFloat(item.id.uuid.3 % 3) * 0.025
    }

    private var symbolRenderingMode: SymbolRenderingMode {
        item.id.uuid.4 % 3 == 0 ? .monochrome : .hierarchical
    }

    private var wiggleDuration: Double {
        0.12 + Double(item.id.uuid.0 % 4) * 0.018
    }

    private var wiggleAngle: Double {
        1.4 + Double(item.id.uuid.1 % 4) * 0.18
    }

    private var phaseDirection: CGFloat {
        item.id.uuid.2 % 2 == 0 ? 1 : -1
    }
}

private struct CalendarIconArtwork: View {
    let iconSize: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let components = Calendar.current.dateComponents(
                [.weekday, .day],
                from: context.date
            )
            VStack(spacing: 0) {
                Text(weekdayName(components.weekday))
                    .font(.system(size: iconSize * 0.18, weight: .bold))
                    .foregroundStyle(.red)
                    .frame(height: iconSize * 0.32)
                Text("\(components.day ?? 1)")
                    .font(.system(size: iconSize * 0.49, weight: .regular, design: .rounded))
                    .foregroundStyle(.black)
                    .minimumScaleFactor(0.7)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, iconSize * 0.04)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.97))
        }
    }

    private func weekdayName(_ weekday: Int?) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        guard let weekday, names.indices.contains(weekday - 1) else { return "今天" }
        return names[weekday - 1]
    }
}

private struct ClockIconArtwork: View {
    let iconSize: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let components = Calendar.current.dateComponents(
                [.hour, .minute, .second],
                from: context.date
            )
            let hour = Double(components.hour ?? 0)
            let minute = Double(components.minute ?? 0)
            let second = Double(components.second ?? 0)

            ZStack {
                Circle()
                    .fill(Color(white: 0.96))
                    .padding(iconSize * 0.09)
                ForEach(0..<12, id: \.self) { tick in
                    Capsule()
                        .fill(.black.opacity(tick.isMultiple(of: 3) ? 0.85 : 0.52))
                        .frame(
                            width: tick.isMultiple(of: 3) ? 1.6 : 1,
                            height: iconSize * 0.055
                        )
                        .offset(y: -iconSize * 0.36)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                clockHand(
                    length: iconSize * 0.2,
                    width: 3,
                    angle: (hour.truncatingRemainder(dividingBy: 12) + minute / 60) * 30,
                    color: .black
                )
                clockHand(
                    length: iconSize * 0.28,
                    width: 2,
                    angle: minute * 6,
                    color: .black
                )
                clockHand(
                    length: iconSize * 0.3,
                    width: 1,
                    angle: second * 6,
                    color: .orange
                )
                Circle()
                    .fill(.orange)
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func clockHand(
        length: CGFloat,
        width: CGFloat,
        angle: Double,
        color: Color
    ) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}
