import SwiftUI

enum DesktopLayoutEngine {
    static func nearestSlot(
        to point: CGPoint,
        in frames: [DesktopSlot: CGRect],
        currentPage: Int
    ) -> DesktopSlot? {
        frames
            .filter { slot, _ in
                switch slot {
                case let .page(page, _):
                    page == currentPage
                case .dock:
                    true
                }
            }
            .min { lhs, rhs in
                squaredDistance(from: point, to: lhs.value.midpoint)
                    < squaredDistance(from: point, to: rhs.value.midpoint)
            }?
            .key
    }

    private static func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

extension CGRect {
    var midpoint: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

struct SlotFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DesktopSlot: CGRect] = [:]

    static func reduce(
        value: inout [DesktopSlot: CGRect],
        nextValue: () -> [DesktopSlot: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SlotFrameReader: View {
    let slot: DesktopSlot

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SlotFramePreferenceKey.self,
                value: [slot: proxy.frame(in: .named("desktop"))]
            )
        }
    }
}
