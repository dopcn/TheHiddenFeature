import SwiftUI
import UIKit

struct DesktopView: View {
    @Bindable var model: DesktopSessionModel

    @State private var slotFrames: [DesktopSlot: CGRect] = [:]
    @State private var showsLogs = false
    @State private var desktopSize: CGSize = .zero

    var body: some View {
        GeometryReader { canvas in
            let metrics = DesktopMetrics(canvasSize: canvas.size)
            ZStack {
                ContinuousWallpaper(role: model.role)

                VStack(spacing: metrics.sectionSpacing) {
                    editHeader
                    pageArea(metrics: metrics)
                    desktopAccessory
                    dock(metrics: metrics)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, metrics.bottomPadding)

                dragOverlays(canvasSize: canvas.size, metrics: metrics)
            }
            .coordinateSpace(name: "desktop")
            .contentShape(Rectangle())
            .onTapGesture {
                model.finishEditing()
            }
            .simultaneousGesture(targetTakeoverGesture(canvasSize: canvas.size))
            .onPreferenceChange(SlotFramePreferenceKey.self) { slotFrames = $0 }
            .onAppear { desktopSize = canvas.size }
            .onChange(of: canvas.size) { _, newSize in desktopSize = newSize }
        }
        .sheet(isPresented: $showsLogs) {
            DebugLogView(logs: model.logs)
                .presentationDetents([.medium, .large])
        }
    }

    private var editHeader: some View {
        HStack {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
                .accessibilityHidden(true)

            Spacer()

            Button("完成") {
                model.finishEditing()
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(.regularMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
        .frame(height: 38)
        .opacity(model.isEditing ? 1 : 0)
        .allowsHitTesting(model.isEditing)
        .animation(.easeOut(duration: 0.18), value: model.isEditing)
    }

    private func pageArea(metrics: DesktopMetrics) -> some View {
        TabView(selection: $model.currentPage) {
            ForEach(model.layout.pages.indices, id: \.self) { pageIndex in
                DesktopPageView(
                    model: model,
                    pageIndex: pageIndex,
                    slotFrames: slotFrames,
                    canvasSize: desktopSize,
                    metrics: metrics
                )
                .tag(pageIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .scrollDisabled(model.isEditing || model.sourceTransfer != nil || model.targetTransfer != nil)
        .onChange(of: model.layout.pages.count) { _, count in
            if model.currentPage >= count {
                model.currentPage = max(0, count - 1)
            }
        }
    }

    @ViewBuilder
    private var desktopAccessory: some View {
        if model.isEditing {
            HStack(spacing: 7) {
                ForEach(model.layout.pages.indices, id: \.self) { page in
                    Circle()
                        .fill(page == model.currentPage ? .white : .white.opacity(0.38))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(height: 28)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                Text("搜索")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
            .onTapGesture(count: 3) {
                showsLogs = true
            }
            .accessibilityLabel("搜索。连续轻点三次打开调试日志")
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }

    private func dock(metrics: DesktopMetrics) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<DesktopLayout.dockCapacity, id: \.self) { index in
                let slot = DesktopSlot.dock(index: index)
                ZStack {
                    SlotFrameReader(slot: slot)
                    if let item = model.layout.dock[index] {
                        IconView(
                            item: item,
                            isEditing: model.isEditing,
                            iconSize: metrics.iconSize,
                            showsTitle: false
                        )
                        .opacity(
                            model.activeDragItem?.id == item.id
                                || model.sourceTransfer?.transaction.item.id == item.id
                                ? 0.16
                                : 1
                        )
                        .modifier(
                            DesktopIconInteraction(
                                model: model,
                                item: item,
                                slot: slot,
                                slotFrames: slotFrames,
                                canvasSize: desktopSize
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, metrics.dockHorizontalPadding)
        .padding(.vertical, metrics.dockVerticalPadding)
        .frame(height: metrics.dockHeight)
        .frame(maxWidth: metrics.dockMaxWidth)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: metrics.dockCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.dockCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    @ViewBuilder
    private func dragOverlays(canvasSize: CGSize, metrics: DesktopMetrics) -> some View {
        if let item = model.activeDragItem, let location = model.dragLocation {
            IconView(
                item: item,
                isEditing: true,
                isLifted: true,
                iconSize: metrics.iconSize
            )
                .position(location)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
        } else if let transfer = model.sourceTransfer {
            IconView(
                item: transfer.transaction.item,
                isEditing: true,
                isLifted: true,
                iconSize: metrics.iconSize
            )
                .position(transfer.location)
                .allowsHitTesting(false)
        }

        if let transfer = model.targetTransfer,
           let location = model.targetPreviewLocation(canvasSize: canvasSize) {
            IconView(
                item: transfer.transaction.item,
                isEditing: true,
                isLifted: transfer.isCaptured,
                iconSize: metrics.iconSize
            )
            .opacity(transfer.isCaptured ? 1 : 0.78)
            .position(location)
            .allowsHitTesting(false)
            .transition(
                .move(edge: model.role?.sharedEdge == .trailing ? .trailing : .leading)
                    .combined(with: .opacity)
            )
        }
    }

    private func targetTakeoverGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("desktop"))
            .onChanged { value in
                model.updateTargetTouch(location: value.location, canvasSize: canvasSize)
            }
            .onEnded { value in
                let nearest = DesktopLayoutEngine.nearestSlot(
                    to: value.location,
                    in: slotFrames,
                    currentPage: model.currentPage
                )
                model.endTargetTouch(nearestSlot: nearest)
            }
    }

}

private struct DesktopPageView: View {
    @Bindable var model: DesktopSessionModel
    let pageIndex: Int
    let slotFrames: [DesktopSlot: CGRect]
    let canvasSize: CGSize
    let metrics: DesktopMetrics

    var body: some View {
        GeometryReader { proxy in
            let rowHeight = max(
                metrics.iconSize + metrics.titleAreaHeight,
                (proxy.size.height
                    - metrics.rowSpacing * CGFloat(metrics.rowCount - 1))
                    / CGFloat(metrics.rowCount)
            )
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: metrics.columnSpacing),
                    count: metrics.columnCount
                ),
                spacing: metrics.rowSpacing
            ) {
                ForEach(0..<DesktopLayout.pageCapacity, id: \.self) { index in
                    let slot = DesktopSlot.page(page: pageIndex, index: index)
                    ZStack {
                        SlotFrameReader(slot: slot)
                        if let item = model.layout.pages[pageIndex][index] {
                            IconView(
                                item: item,
                                isEditing: model.isEditing,
                                iconSize: metrics.iconSize
                            )
                                .opacity(
                                    model.activeDragItem?.id == item.id
                                        || model.sourceTransfer?.transaction.item.id == item.id
                                        ? 0.16
                                        : 1
                                )
                                .modifier(
                                    DesktopIconInteraction(
                                        model: model,
                                        item: item,
                                        slot: slot,
                                        slotFrames: slotFrames,
                                        canvasSize: canvasSize
                                    )
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
                }
            }
            .frame(maxWidth: metrics.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

}

private struct DesktopIconInteraction: ViewModifier {
    let model: DesktopSessionModel
    let item: DesktopItem
    let slot: DesktopSlot
    let slotFrames: [DesktopSlot: CGRect]
    let canvasSize: CGSize

    func body(content: Content) -> some View {
        content
            .gesture(dragGesture)
            .simultaneousGesture(longPressGesture)
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
            .onEnded { _ in
                model.enterEditing()
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("desktop"))
            .onChanged { value in
                guard model.isEditing else { return }
                if model.activeDragItem?.id != item.id {
                    model.beginDragging(item, at: value.location)
                }
                guard model.activeDragItem?.id == item.id else { return }

                let nearest = DesktopLayoutEngine.nearestSlot(
                    to: value.location,
                    in: slotFrames,
                    currentPage: model.currentPage
                )
                model.updateDragging(
                    item,
                    location: value.location,
                    predictedEndLocation: value.predictedEndLocation,
                    nearestSlot: nearest,
                    canvasSize: canvasSize
                )
            }
            .onEnded { value in
                guard model.activeDragItem?.id == item.id else { return }
                let nearest = DesktopLayoutEngine.nearestSlot(
                    to: value.location,
                    in: slotFrames,
                    currentPage: model.currentPage
                )
                model.endDragging(item, nearestSlot: nearest ?? slot)
            }
    }
}

private struct DesktopMetrics {
    let iconSize: CGFloat
    let columnCount: Int
    let rowCount: Int
    let horizontalPadding: CGFloat
    let sectionSpacing: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let titleAreaHeight: CGFloat
    let dockHorizontalPadding: CGFloat
    let dockVerticalPadding: CGFloat
    let dockHeight: CGFloat
    let dockMaxWidth: CGFloat
    let dockCornerRadius: CGFloat
    let pageMaxWidth: CGFloat
    let bottomPadding: CGFloat

    init(canvasSize: CGSize) {
        let usesTabletLayout = canvasSize.width >= 600
        let widthBasedSize: CGFloat
        switch canvasSize.width {
        case ..<380:
            widthBasedSize = 56
        case ..<430:
            widthBasedSize = 60
        default:
            widthBasedSize = 64
        }
        let heightBasedSize = max(50, (canvasSize.height - 165) / 6 - 18)
        iconSize = min(widthBasedSize, heightBasedSize)
        columnCount = usesTabletLayout ? 6 : 4
        rowCount = DesktopLayout.pageCapacity / columnCount
        horizontalPadding = usesTabletLayout ? 18 : (canvasSize.width < 380 ? 10 : 16)
        sectionSpacing = canvasSize.height < 700 ? 4 : 7
        rowSpacing = usesTabletLayout ? 10 : (canvasSize.height < 700 ? 2 : 5)
        columnSpacing = usesTabletLayout ? 12 : 4
        titleAreaHeight = 20
        dockHorizontalPadding = canvasSize.width < 380 ? 8 : 11
        dockVerticalPadding = 9
        dockHeight = iconSize + dockVerticalPadding * 2
        dockMaxWidth = usesTabletLayout ? 430 : .infinity
        dockCornerRadius = dockHeight * 0.34
        pageMaxWidth = usesTabletLayout ? min(canvasSize.width - 36, 840) : .infinity
        bottomPadding = canvasSize.height < 700 ? 3 : 7
    }
}

private struct ContinuousWallpaper: View {
    let role: DeviceRole?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            wallpaperArtwork(size: CGSize(width: size.width * 2, height: size.height))
                .frame(width: size.width * 2, height: size.height)
                .position(
                    x: role == .right ? 0 : size.width,
                    y: size.height / 2
                )
        }
        .ignoresSafeArea()
        .clipped()
    }

    @ViewBuilder
    private func wallpaperArtwork(size: CGSize) -> some View {
        if let wallpaper = UIImage(
            named: "AppleWallpaper.jpg",
            in: .main,
            compatibleWith: nil
        ) {
            Image(uiImage: wallpaper)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(Color.black.opacity(0.08))
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.08, blue: 0.19),
                    Color(red: 0.19, green: 0.09, blue: 0.36),
                    Color(red: 0.04, green: 0.36, blue: 0.46)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct DebugLogView: View {
    let logs: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if logs.isEmpty {
                        ContentUnavailableView("暂无日志", systemImage: "text.alignleft")
                    } else {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("连接日志")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
