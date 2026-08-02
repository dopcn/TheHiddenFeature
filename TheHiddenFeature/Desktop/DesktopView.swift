import SwiftUI
import UIKit

struct DesktopView: View {
    @Bindable var model: DesktopSessionModel

    @State private var slotFrames: [DesktopSlot: CGRect] = [:]
    @State private var showsLogs = false
    @State private var desktopSize: CGSize = .zero

    var body: some View {
        ZStack {
            ContinuousWallpaper(role: model.role)
                .ignoresSafeArea()

            GeometryReader { canvas in
                let metrics = DesktopMetrics(canvasSize: canvas.size)
                let desktopOrigin = canvas.frame(in: .global).origin
                ZStack(alignment: .top) {
                    VStack(spacing: metrics.sectionSpacing) {
                        pageArea(metrics: metrics, desktopOrigin: desktopOrigin)
                            .padding(
                                .top,
                                metrics.pageTopPadding + metrics.contentTopInset
                            )
                        desktopAccessory
                        dock(metrics: metrics, desktopOrigin: desktopOrigin)
                            .padding(.top, metrics.dockTopPadding)
                            .padding(.bottom, metrics.dockBottomPadding)
                            .offset(y: metrics.dockBottomOffset)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)

                    dragOverlays(canvasSize: canvas.size, metrics: metrics)

                    editHeader(metrics: metrics)
                        .padding(.horizontal, metrics.editHeaderHorizontalPadding)
                        .offset(
                            y: model.isEditing
                                ? metrics.editHeaderVerticalOffset
                                : 0
                        )
                        .zIndex(2)
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
            .ignoresSafeArea(
                .container,
                edges: UIDevice.current.userInterfaceIdiom == .pad ? .top : []
            )
        }
        .statusBarHidden(model.isEditing)
        .sheet(isPresented: $showsLogs) {
            DebugLogView(logs: model.logs)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func editHeader(metrics: DesktopMetrics) -> some View {
        if metrics.usesTabletLayout {
            tabletEditHeader
        } else {
            phoneEditHeader
        }
    }

    private var phoneEditHeader: some View {
        HStack {
            Text("编辑")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.3), lineWidth: 0.75)
                }

            Spacer()

            Button("完成") {
                model.finishEditing()
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.3), lineWidth: 0.75)
            }
        }
        .foregroundStyle(.white)
        .frame(height: 38)
        .opacity(model.isEditing ? 1 : 0)
        .allowsHitTesting(model.isEditing)
        .animation(.easeOut(duration: 0.18), value: model.isEditing)
    }

    private var tabletEditHeader: some View {
        HStack {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.58))
                .frame(width: 64, height: 30)
                .background(Color.white.opacity(0.88), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.55), lineWidth: 0.5)
                }

            Spacer()

            Button("完成") {
                model.finishEditing()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 0.62, green: 0.42, blue: 0.08))
            .padding(.horizontal, 15)
            .frame(height: 30)
            .background(Color.white.opacity(0.88), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.55), lineWidth: 0.5)
            }
        }
        .frame(height: 34)
        .opacity(model.isEditing ? 1 : 0)
        .allowsHitTesting(model.isEditing)
        .animation(.easeOut(duration: 0.18), value: model.isEditing)
    }

    private func pageArea(
        metrics: DesktopMetrics,
        desktopOrigin: CGPoint
    ) -> some View {
        TabView(selection: $model.currentPage) {
            ForEach(model.layout.pages.indices, id: \.self) { pageIndex in
                DesktopPageView(
                    model: model,
                    pageIndex: pageIndex,
                    slotFrames: slotFrames,
                    canvasSize: desktopSize,
                    desktopOrigin: desktopOrigin,
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
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
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

    private func dock(
        metrics: DesktopMetrics,
        desktopOrigin: CGPoint
    ) -> some View {
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
                            showsTitle: false,
                            usesTabletStyle: metrics.usesTabletLayout
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
                                canvasSize: desktopSize,
                                desktopOrigin: desktopOrigin
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
                iconSize: metrics.iconSize,
                showsTitle: false,
                usesTabletStyle: metrics.usesTabletLayout
            )
                .position(location)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
        } else if let transfer = model.sourceTransfer {
            IconView(
                item: transfer.transaction.item,
                isEditing: true,
                isLifted: true,
                iconSize: metrics.iconSize,
                showsTitle: false,
                usesTabletStyle: metrics.usesTabletLayout
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
                iconSize: metrics.iconSize,
                showsTitle: false,
                usesTabletStyle: metrics.usesTabletLayout
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
    let desktopOrigin: CGPoint
    let metrics: DesktopMetrics

    var body: some View {
        GeometryReader { proxy in
            let gridHeight = metrics.pageGridHeight ?? proxy.size.height
            let rowHeight = max(
                metrics.iconSize + metrics.titleAreaHeight,
                (gridHeight
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
                                iconSize: metrics.iconSize,
                                usesTabletStyle: metrics.usesTabletLayout
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
                                        canvasSize: canvasSize,
                                        desktopOrigin: desktopOrigin
                                    )
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
                }
            }
            .frame(maxWidth: metrics.pageMaxWidth)
            .frame(height: gridHeight, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

}

private struct DesktopIconInteraction: ViewModifier {
    let model: DesktopSessionModel
    let item: DesktopItem
    let slot: DesktopSlot
    let slotFrames: [DesktopSlot: CGRect]
    let canvasSize: CGSize
    let desktopOrigin: CGPoint

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(longPressDragGesture)
    }

    private var longPressDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .global
                )
            )
            .onChanged { value in
                switch value {
                case .first(true):
                    model.enterEditing()
                case let .second(true, dragValue?):
                    model.enterEditing()
                    updateDrag(dragValue)
                default:
                    break
                }
            }
            .onEnded { value in
                guard case let .second(true, dragValue?) = value else { return }
                endDrag(dragValue)
            }
    }

    private func updateDrag(_ value: DragGesture.Value) {
        let location = desktopLocation(from: value.location)
        let predictedEndLocation = desktopLocation(from: value.predictedEndLocation)
        if model.activeDragItem?.id != item.id {
            model.beginDragging(item, at: location)
        }
        guard model.activeDragItem?.id == item.id else { return }

        let nearest = DesktopLayoutEngine.nearestSlot(
            to: location,
            in: slotFrames,
            currentPage: model.currentPage
        )
        model.updateDragging(
            item,
            location: location,
            predictedEndLocation: predictedEndLocation,
            nearestSlot: nearest,
            canvasSize: canvasSize
        )
    }

    private func endDrag(_ value: DragGesture.Value) {
        guard model.activeDragItem?.id == item.id else { return }
        let location = desktopLocation(from: value.location)
        let nearest = DesktopLayoutEngine.nearestSlot(
            to: location,
            in: slotFrames,
            currentPage: model.currentPage
        )
        model.endDragging(item, nearestSlot: nearest ?? slot)
    }

    private func desktopLocation(from globalLocation: CGPoint) -> CGPoint {
        return CGPoint(
            x: globalLocation.x - desktopOrigin.x,
            y: globalLocation.y - desktopOrigin.y
        )
    }
}

private struct DesktopMetrics {
    let usesTabletLayout: Bool
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
    let dockTopPadding: CGFloat
    let dockBottomPadding: CGFloat
    let pageMaxWidth: CGFloat
    let pageGridHeight: CGFloat?
    let pageTopPadding: CGFloat
    let contentTopInset: CGFloat
    let editHeaderHorizontalPadding: CGFloat
    let editHeaderVerticalOffset: CGFloat
    let dockBottomOffset: CGFloat

    init(canvasSize: CGSize) {
        usesTabletLayout = canvasSize.width >= 600
        contentTopInset = usesTabletLayout ? 24 : 0
        let layoutHeight = canvasSize.height - contentTopInset
        let usesPortraitTabletGrid = usesTabletLayout && layoutHeight > canvasSize.width
        let widthBasedSize: CGFloat
        switch canvasSize.width {
        case ..<380:
            widthBasedSize = 56
        case ..<430:
            widthBasedSize = 60
        default:
            widthBasedSize = 64
        }
        let heightBasedSize = max(50, (layoutHeight - 165) / 6 - 18)
        iconSize = min(widthBasedSize, heightBasedSize)
        columnCount = usesTabletLayout ? (usesPortraitTabletGrid ? 5 : 6) : 4
        rowCount = (DesktopLayout.pageCapacity + columnCount - 1) / columnCount
        horizontalPadding = usesTabletLayout ? 18 : (canvasSize.width < 380 ? 10 : 16)
        sectionSpacing = layoutHeight < 700 ? 4 : 7
        rowSpacing = usesTabletLayout ? 10 : (layoutHeight < 700 ? 2 : 5)
        columnSpacing = usesTabletLayout ? 12 : 4
        titleAreaHeight = 20
        dockHorizontalPadding = canvasSize.width < 380 ? 8 : 11
        dockVerticalPadding = usesTabletLayout ? 16 : 12
        dockHeight = iconSize + dockVerticalPadding * 2
        dockMaxWidth = usesTabletLayout ? 340 : .infinity
        dockCornerRadius = dockHeight * 0.34
        dockTopPadding = usesTabletLayout ? 8 : 0
        dockBottomPadding = usesTabletLayout ? 16 : 0
        if usesPortraitTabletGrid {
            pageMaxWidth = min(canvasSize.width - 36, 600)
            pageGridHeight = layoutHeight * 0.65
        } else if usesTabletLayout {
            pageMaxWidth = min(canvasSize.width - 72, 1_050)
            pageGridHeight = nil
        } else {
            pageMaxWidth = .infinity
            pageGridHeight = nil
        }
        pageTopPadding = usesPortraitTabletGrid ? 52 : (usesTabletLayout ? 0 : 22)
        editHeaderHorizontalPadding = usesTabletLayout ? 18 : 28
        editHeaderVerticalOffset = usesTabletLayout ? 12 : -36
        dockBottomOffset = usesTabletLayout ? 0 : 12
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
