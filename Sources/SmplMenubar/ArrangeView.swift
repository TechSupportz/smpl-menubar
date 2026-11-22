import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// Columns run from most to least visible. Top to bottom in a column is right to left in the bar,
/// read outward from the clock, the dot or the divider.
struct ArrangeView: View {
    let model: Model
    @State private var drag = DragState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            main
            Footer()
        }
        .frame(minWidth: 920, minHeight: 460)
        .coordinateSpace(.named(DragState.spaceName))
        .overlay(alignment: .topLeading) {
            FloatingDragCard(drag: drag)
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            drag.reduceMotion = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard let window = note.object as? NSWindow,
                  window.contentViewController is NSHostingController<ArrangeView> else { return }
            drag.cancel(model: model)
        }
        .onDisappear {
            drag.tearDown(model: model)
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(model: model)
                .contentShape(.rect)
                .gesture(WindowDragGesture())

            if model.accessError {
                AccessBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(Section.allCases) { section in
                    SectionCard(section: section, model: model, drag: drag)
                }
            }
        }
        .padding(20)
        .background {
            Color.clear
                .contentShape(.rect)
                .gesture(WindowDragGesture())
        }
        .animation(.smooth(duration: 0.3), value: model.accessError)
    }
}

// MARK: - Header

private struct Header: View {
    let model: Model

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("smpl.menubar")
                    .font(.system(size: 28, weight: .black))
                    .italic()
                    .tracking(-0.5)
                Text("Drag apps between sections, or up and down to reorder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(spacing: 6) {
                Menu {
                    ForEach(model.addableModules) { module in
                        Button {
                            withAnimation(.smooth(duration: 0.25)) {
                                model.addModule(module.id)
                            }
                        } label: {
                            Label { Text(module.name) } icon: { Image(nsImage: ControlCenterModules.menuIcon(module)) }
                        }
                    }
                } label: {
                    Label("Add System Item", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help("Show a system item, like Sound or Bluetooth, in the menu bar")
                .disabled(model.addableModules.isEmpty || model.accessError)
                Button { model.resync() } label: {
                    Label("Refresh Menu Bar", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help("Put every app back where Arrange says, in order")
                .disabled(model.accessError)
            }
            .fixedSize()
        }
    }
}

// MARK: - Section card

private enum RowEntry: Identifiable, Equatable {
    case app(MenuApp)
    case placeholder(Section)

    var id: String {
        switch self {
        case .app(let app): app.id
        case .placeholder(let section): "__placeholder__\(section.rawValue)"
        }
    }
}

private struct ScrollMetrics: Equatable {
    var offsetY: CGFloat
    var maxOffsetY: CGFloat
}

private struct SectionCard: View {
    let section: Section
    let model: Model
    let drag: DragState

    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var highlight: SectionHighlight {
        if drag.target?.section == section {
            return drag.willRemove ? .destructive : .accent
        }
        return .none
    }

    var body: some View {
        let apps = model.apps(in: section)
        let entries = makeEntries(from: apps)
        let isAnyDragActive = drag.app != nil

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.title3.weight(.semibold))
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: section.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .contentShape(.rect)
            .gesture(WindowDragGesture())

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .app(let app):
                            let isDraggedSource = drag.app?.id == app.id
                            DraggableRow(
                                app: app,
                                section: section,
                                model: model,
                                drag: drag,
                                isDraggedSource: isDraggedSource,
                                isAnyDragActive: isAnyDragActive
                            )
                        case .placeholder:
                            PlaceholderSlot(height: drag.rowHeight)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DragState.spaceName)) } action: { rect in
                                    if let target = drag.target, target.section == section {
                                        drag.placeholderFrame = (target, rect)
                                    }
                                }
                                .padding(.vertical, DragState.rowVerticalPadding)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DragState.spaceName)) } action: { rect in
                    drag.updateListGeometry(section: section, rect: rect, model: model)
                }
            }
            .scrollIndicators(.never)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                ScrollMetrics(
                    offsetY: geo.contentOffset.y + geo.contentInsets.top,
                    maxOffsetY: max(0, geo.contentSize.height - geo.containerSize.height + geo.contentInsets.top + geo.contentInsets.bottom)
                )
            } action: { _, metrics in
                drag.scrollMetrics[section] = metrics
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DragState.spaceName)) } action: { rect in
                drag.scrollViewFrames[section] = rect
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .groupBox(highlight: highlight)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DragState.spaceName)) } action: { rect in
            drag.sectionFrames[section] = rect
        }
        .onAppear {
            let binding = $scrollPosition
            drag.scrollToHandlers[section] = { y in
                binding.wrappedValue.scrollTo(y: y)
            }
        }
        .onDisappear {
            drag.scrollToHandlers.removeValue(forKey: section)
        }
    }

    private func makeEntries(from apps: [MenuApp]) -> [RowEntry] {
        guard let draggedID = drag.app?.id else {
            return apps.map(RowEntry.app)
        }
        let sourceIndex = apps.firstIndex { $0.id == draggedID }
        let others = apps.filter { $0.id != draggedID }
        var result = others.map(RowEntry.app)

        if let target = drag.target, target.section == section, !drag.willRemove {
            let index = min(max(target.index, 0), result.count)
            result.insert(.placeholder(section), at: index)
        }
        if let sourceIndex {
            // Keep the dragged source row mounted at zero height so its active DragGesture never cancels.
            let insertAt = min(sourceIndex, result.count)
            result.insert(.app(apps[sourceIndex]), at: insertAt)
        }
        return result
    }
}

private struct PlaceholderSlot: View {
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(Color.accentColor.opacity(0.10))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1))
            .frame(height: height)
    }
}

private struct DraggableRow: View {
    let app: MenuApp
    let section: Section
    let model: Model
    let drag: DragState
    let isDraggedSource: Bool
    let isAnyDragActive: Bool
    @GestureState private var isTrackingGesture = false

    var body: some View {
        AppRow(
            app: app,
            isDragActive: isAnyDragActive,
            onRemove: ControlCenterModules.isModule(app.id) ? {
                withAnimation(.smooth(duration: 0.25)) { model.removeModule(app.id) }
            } : nil
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DragState.spaceName)) } action: { rect in
            if !isDraggedSource, rect.height > 1 {
                drag.rowFrames[app.id] = rect
                drag.rowHeight = rect.height
            }
        }
        .padding(.vertical, isDraggedSource ? 0 : DragState.rowVerticalPadding)
        .frame(height: isDraggedSource ? 0 : nil)
        .opacity(isDraggedSource ? 0 : 1)
        .clipped()
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(DragState.spaceName))
                .updating($isTrackingGesture) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    drag.handleChanged(app: app, section: section, value: value, model: model)
                }
                .onEnded { value in
                    drag.handleEnded(value: value, model: model)
                }
        )
        .onChange(of: isTrackingGesture) { _, tracking in
            if !tracking {
                // Defer a tick so normal releases run `onEnded` first; only aborted gestures cancel here.
                DispatchQueue.main.async {
                    drag.handleGestureEndedTracking(appID: app.id, model: model)
                }
            }
        }
        .onDisappear {
            if isDraggedSource {
                drag.handleGestureEndedTracking(appID: app.id, model: model)
            }
        }
    }
}

private struct FloatingDragCard: View {
    let drag: DragState

    var body: some View {
        if let app = drag.app {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            let chromeOpacity: Double = (drag.isLifted || drag.willRemove) ? 1 : 0
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if drag.willRemove {
                    Label("Remove", systemImage: "minus.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: drag.cardSize.width, height: drag.cardSize.height)
            .background(Color(nsColor: .controlBackgroundColor).opacity(chromeOpacity), in: shape)
            .overlay(
                shape.strokeBorder(
                    drag.willRemove ? Color.red.opacity(0.6) : Color.primary.opacity(0.14 * chromeOpacity),
                    lineWidth: 1
                )
            )
            .animation(.easeOut(duration: 0.14), value: drag.willRemove)
            .shadow(
                color: .black.opacity(drag.isLifted ? 0.18 : 0),
                radius: drag.isLifted ? 12 : 0,
                x: 0,
                y: drag.isLifted ? 6 : 0
            )
            .scaleEffect(drag.isRemoving ? 0.86 : (drag.isLifted ? 1.02 : 1.0))
            .opacity(drag.isRemoving ? 0 : 1)
            .position(
                x: drag.cardOrigin.x + drag.cardSize.width / 2,
                y: drag.cardOrigin.y + drag.cardSize.height / 2
            )
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Drag state

/// Coordinates direct-manipulation dragging across all four columns.
/// Only properties read by rows/overlay are tracked; geometry registries are `@ObservationIgnored`
/// so pointer motion only redraws `FloatingDragCard` and never re-evaluates columns unless the slot changes.
@MainActor
@Observable
private final class DragState {
    nonisolated static let spaceName = "arrangeBoard"
    static let rowVerticalPadding: CGFloat = 1

    struct Target: Equatable {
        var section: Section
        /// Insertion index among the section's other (non-dragged) items: 0 = top, count = bottom.
        var index: Int
    }

    var app: MenuApp?
    var target: Target?
    var willRemove = false
    var cardOrigin: CGPoint = .zero
    var cardSize: CGSize = CGSize(width: 200, height: 34)
    var isLifted = false
    var isRemoving = false

    @ObservationIgnored var rowHeight: CGFloat = 34
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored var sectionFrames: [Section: CGRect] = [:]
    @ObservationIgnored var scrollViewFrames: [Section: CGRect] = [:]
    @ObservationIgnored var listFrames: [Section: CGRect] = [:]
    @ObservationIgnored var rowFrames: [String: CGRect] = [:]
    @ObservationIgnored var placeholderFrame: (target: Target, rect: CGRect)?
    @ObservationIgnored var scrollMetrics: [Section: ScrollMetrics] = [:]
    @ObservationIgnored var scrollToHandlers: [Section: (CGFloat) -> Void] = [:]

    @ObservationIgnored private var origin: Target?
    @ObservationIgnored private var grabOffset: CGPoint = .zero
    @ObservationIgnored private var lastPointer: CGPoint = .zero
    @ObservationIgnored private var activeStartLocation: CGPoint?
    @ObservationIgnored private var cancelledStartLocation: CGPoint?
    @ObservationIgnored private var isSettling = false
    @ObservationIgnored private var pendingCommit: (() -> Void)?
    @ObservationIgnored private var sessionID = 0
    @ObservationIgnored private var cursorActive = false
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var autoScrollTimer: Timer?
    @ObservationIgnored private var autoScrollTargetY: [Section: CGFloat] = [:]

    private var slotStride: CGFloat { rowHeight + Self.rowVerticalPadding * 2 }

    private var reorderAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.24, bounce: 0.0)
    }

    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.2, bounce: 0.0)
    }

    func updateListGeometry(section: Section, rect: CGRect, model: Model) {
        let previous = listFrames[section]
        listFrames[section] = rect
        // If the user scrolls a column (trackpad or auto-scroll) mid-drag, keep the slot locked to the pointer.
        if app != nil, !isSettling, previous?.minY != rect.minY {
            updateTarget(pointer: lastPointer, model: model)
        }
    }

    func handleChanged(app: MenuApp, section: Section, value: DragGesture.Value, model: Model) {
        if cancelledStartLocation == value.startLocation { return }
        if self.app == nil || isSettling {
            begin(app: app, section: section, value: value, model: model)
        }
        guard self.app?.id == app.id, !isSettling else { return }
        if cursorActive { NSCursor.closedHand.set() }
        lastPointer = value.location
        cardOrigin = CGPoint(x: value.location.x - grabOffset.x, y: value.location.y - grabOffset.y)
        updateTarget(pointer: value.location, model: model)
    }

    func handleEnded(value: DragGesture.Value, model: Model) {
        if cancelledStartLocation == value.startLocation {
            cancelledStartLocation = nil
            return
        }
        guard app != nil, !isSettling else { return }
        end(model: model)
    }

    func handleGestureEndedTracking(appID: String, model: Model) {
        if cancelledStartLocation != nil, app == nil || isSettling {
            cancelledStartLocation = nil
        }
        guard app?.id == appID, !isSettling else { return }
        cancel(model: model)
        cancelledStartLocation = nil
    }

    func cancel(model: Model) {
        guard app != nil, !isSettling else { return }
        cancelledStartLocation = activeStartLocation
        stopActiveTracking()
        guard let origin else {
            finishWithoutAnimation(model: model)
            return
        }
        settle(to: origin, commit: nil, model: model)
    }

    func tearDown(model: Model) {
        stopActiveTracking()
        if let commit = pendingCommit {
            pendingCommit = nil
            commit()
        }
        finishWithoutAnimation(model: model)
    }

    // MARK: Lifecycle

    private func begin(app: MenuApp, section: Section, value: DragGesture.Value, model: Model) {
        // Measure the grabbed row's on-screen frame before committing any previous settling drop.
        let frame = rowFrames[app.id] ?? CGRect(
            x: listFrames[section]?.minX ?? value.startLocation.x - 100,
            y: value.startLocation.y - rowHeight / 2,
            width: listFrames[section]?.width ?? 200,
            height: rowHeight
        )

        // Interruptible: if a previous drop is still settling, commit it right away.
        if isSettling {
            let commit = pendingCommit
            pendingCommit = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                commit?()
                resetState(model: model)
            }
        }

        sessionID += 1
        let currentSession = sessionID
        activeStartLocation = value.startLocation
        cancelledStartLocation = nil
        lastPointer = value.location
        placeholderFrame = nil
        autoScrollTargetY.removeAll()

        let sectionApps = model.apps(in: section)
        let startIndex = sectionApps.firstIndex { $0.id == app.id } ?? 0
        let startTarget = Target(section: section, index: startIndex)

        let clampedGrab = CGPoint(
            x: min(max(value.startLocation.x - frame.minX, 0), frame.width),
            y: min(max(value.startLocation.y - frame.minY, 0), frame.height)
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.app = app
            self.origin = startTarget
            self.target = startTarget
            self.willRemove = false
            self.isSettling = false
            self.isRemoving = false
            self.isLifted = false
            self.cardSize = frame.size
            self.grabOffset = clampedGrab
            self.cardOrigin = CGPoint(x: value.location.x - clampedGrab.x, y: value.location.y - clampedGrab.y)
        }

        model.isDragging = true
        setClosedHandCursor()
        installKeyMonitor(model: model)
        startAutoScroll(model: model)

        // Defer one turn so the card renders at rest first, then springs up smoothly.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionID == currentSession, !self.isSettling else { return }
            withAnimation(self.reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.2, bounce: 0.15)) {
                self.isLifted = true
            }
        }
    }

    private func end(model: Model) {
        guard let draggedApp = app, let origin else {
            finishWithoutAnimation(model: model)
            return
        }
        stopActiveTracking()

        if willRemove, ControlCenterModules.isModule(draggedApp.id) {
            isSettling = true
            let currentSession = sessionID
            let commit: () -> Void = { model.removeModule(draggedApp.id) }
            pendingCommit = commit

            withAnimation(.easeOut(duration: 0.16), completionCriteria: .logicallyComplete) {
                isRemoving = true
                isLifted = false
            } completion: { [weak self] in
                guard let self, self.sessionID == currentSession else { return }
                self.pendingCommit = nil
                commit()
                if model.apps.contains(where: { $0.id == draggedApp.id }) {
                    // Removal failed (e.g. permissions); fade the row back smoothly instead of snapping.
                    withAnimation(.smooth(duration: 0.2)) {
                        self.resetState(model: model)
                    }
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.resetState(model: model)
                    }
                }
            }
            return
        }

        let landing = target ?? origin
        let commit: (() -> Void)?
        if landing == origin {
            commit = nil
        } else {
            let others = model.apps(in: landing.section).filter { $0.id != draggedApp.id }
            let beforeID = landing.index < others.count ? others[landing.index].id : nil
            commit = {
                model.move(draggedApp.id, to: landing.section, before: beforeID)
            }
        }
        settle(to: landing, commit: commit, model: model)
    }

    private func settle(to landing: Target, commit: (() -> Void)?, model: Model) {
        isSettling = true
        let currentSession = sessionID
        pendingCommit = commit

        if target != landing || willRemove {
            withAnimation(reorderAnimation) {
                target = landing
                willRemove = false
            }
        }

        let destination = visibleLandingRect(for: landing)

        withAnimation(settleAnimation, completionCriteria: .logicallyComplete) {
            cardOrigin = destination.origin
            cardSize.width = destination.width
            isLifted = false
        } completion: { [weak self] in
            guard let self, self.sessionID == currentSession else { return }
            self.pendingCommit = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                commit?()
                self.resetState(model: model)
            }
        }
    }

    private func finishWithoutAnimation(model: Model) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resetState(model: model)
        }
    }

    private func resetState(model: Model) {
        app = nil
        origin = nil
        target = nil
        willRemove = false
        isSettling = false
        isLifted = false
        isRemoving = false
        placeholderFrame = nil
        activeStartLocation = nil
        autoScrollTargetY.removeAll()
        model.isDragging = false
    }

    // MARK: Hit-testing & slot calculation

    private func updateTarget(pointer: CGPoint, model: Model) {
        guard let draggedApp = app, let origin else { return }
        let isModule = ControlCenterModules.isModule(draggedApp.id)
        let cardMidY = cardOrigin.y + cardSize.height / 2

        let matchedSection = hitSection(at: pointer, isModule: isModule)
        let nextTarget: Target?
        let nextWillRemove: Bool

        if let section = matchedSection {
            if isModule, section == .disabled {
                // Dropping a system item in Disabled removes it from the menu bar.
                nextTarget = Target(section: .disabled, index: 0)
                nextWillRemove = true
            } else {
                let index = targetIndex(in: section, cardMidY: cardMidY, draggedID: draggedApp.id, model: model)
                nextTarget = Target(section: section, index: index)
                nextWillRemove = false
            }
        } else if isModule {
            nextTarget = nil
            nextWillRemove = true
        } else {
            // Regular apps snap back to their starting slot when dragged well outside the columns.
            nextTarget = origin
            nextWillRemove = false
        }

        guard nextTarget != target || nextWillRemove != willRemove else { return }

        let crossedSection = nextTarget?.section != target?.section || nextWillRemove != willRemove
        withAnimation(reorderAnimation) {
            target = nextTarget
            willRemove = nextWillRemove
        }
        if crossedSection {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func hitSection(at point: CGPoint, isModule: Bool) -> Section? {
        guard !sectionFrames.isEmpty else { return nil }
        let boardRect = sectionFrames.values.reduce(CGRect.null) { $0.union($1) }
        // Give enough outer margin so grazing an edge never accidentally triggers Remove or Cancel.
        let outerMargin: CGFloat = isModule ? 16 : 24
        guard boardRect.insetBy(dx: -outerMargin, dy: -outerMargin).contains(point) else { return nil }

        // Expand interior horizontal edges by half the column gap so there are zero dead zones between columns.
        for section in Section.allCases {
            guard let frame = sectionFrames[section] else { continue }
            if frame.insetBy(dx: -6, dy: -outerMargin).contains(point) {
                return section
            }
        }
        // Fallback inside the outer margin: pick the horizontally closest column.
        return Section.allCases.min { a, b in
            let ax = sectionFrames[a]?.midX ?? .greatestFiniteMagnitude
            let bx = sectionFrames[b]?.midX ?? .greatestFiniteMagnitude
            return abs(point.x - ax) < abs(point.x - bx)
        }
    }

    private func targetIndex(in section: Section, cardMidY: CGFloat, draggedID: String, model: Model) -> Int {
        let otherCount = model.apps(in: section).filter { $0.id != draggedID }.count
        guard otherCount > 0 else { return 0 }
        let topY = listFrames[section]?.minY ?? ((sectionFrames[section]?.minY ?? 0) + 56)
        let relativeMidY = cardMidY - topY
        let stride = slotStride
        let raw = Int(floor(relativeMidY / stride))
        let clamped = min(max(raw, 0), otherCount)

        if let current = target, current.section == section, !willRemove {
            let currentIndex = min(max(current.index, 0), otherCount)
            if clamped == currentIndex { return currentIndex }
            // Small deadband prevents jitter when the pointer rests near a boundary between two rows.
            let deadband: CGFloat = 5
            if clamped == currentIndex + 1 {
                let threshold = CGFloat(currentIndex + 1) * stride + deadband
                return relativeMidY >= threshold ? clamped : currentIndex
            } else if clamped == currentIndex - 1 {
                let threshold = CGFloat(currentIndex) * stride - deadband
                return relativeMidY <= threshold ? clamped : currentIndex
            }
        }
        return clamped
    }

    /// Computes the landing rect in board coordinates, scrolling the target slot into view if it's
    /// scrolled offscreen so the settling card never flies over the header or footer.
    private func visibleLandingRect(for landing: Target) -> CGRect {
        let raw = landingRect(for: landing)
        guard let viewport = scrollViewFrames[landing.section], viewport.height > cardSize.height else {
            return raw
        }
        if raw.minY >= viewport.minY && raw.maxY <= viewport.maxY {
            return raw
        }
        let slotLocalY = CGFloat(landing.index) * slotStride + Self.rowVerticalPadding
        let metrics = scrollMetrics[landing.section] ?? ScrollMetrics(offsetY: 0, maxOffsetY: 0)
        // Account for a placeholder that was just re-inserted into this column before scrollMetrics refreshed.
        let effectiveMaxY = max(metrics.maxOffsetY, slotLocalY + cardSize.height + 12 - viewport.height)
        var targetScrollY = metrics.offsetY
        if raw.minY < viewport.minY {
            targetScrollY = max(0, slotLocalY - 4)
        } else if raw.maxY > viewport.maxY {
            targetScrollY = min(effectiveMaxY, slotLocalY + cardSize.height - viewport.height + 12)
        }
        if abs(targetScrollY - metrics.offsetY) > 0.5, let scrollTo = scrollToHandlers[landing.section] {
            scrollTo(targetScrollY)
        }
        let adjustedY = viewport.minY + (slotLocalY - targetScrollY)
        let clampedY = min(max(adjustedY, viewport.minY), viewport.maxY - cardSize.height)
        return CGRect(x: raw.minX, y: clampedY, width: raw.width, height: raw.height)
    }

    private func landingRect(for landing: Target) -> CGRect {
        if let measured = placeholderFrame, measured.target == landing, measured.rect.width > 1 {
            return measured.rect
        }
        let list = listFrames[landing.section]
        let x = list?.minX ?? ((sectionFrames[landing.section]?.minX ?? cardOrigin.x) + 14)
        let y = (list?.minY ?? cardOrigin.y) + CGFloat(landing.index) * slotStride + Self.rowVerticalPadding
        let width = list?.width ?? cardSize.width
        return CGRect(x: x, y: y, width: width, height: cardSize.height)
    }

    // MARK: Auto-scroll, Escape & cursor

    private func startAutoScroll(model: Model) {
        autoScrollTimer?.invalidate()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickAutoScroll(model: model)
            }
        }
    }

    private func tickAutoScroll(model: Model) {
        guard let draggedApp = app, !isSettling,
              let section = hitSection(at: lastPointer, isModule: ControlCenterModules.isModule(draggedApp.id)),
              target?.section == section, !willRemove,
              let viewport = scrollViewFrames[section],
              viewport.minX <= lastPointer.x, lastPointer.x <= viewport.maxX,
              let metrics = scrollMetrics[section], metrics.maxOffsetY > 0.5,
              let scrollTo = scrollToHandlers[section] else {
            autoScrollTargetY.removeAll()
            return
        }
        let edgeZone: CGFloat = 34
        let delta: CGFloat
        if lastPointer.y < viewport.minY + edgeZone {
            let ratio = min(1, max(0, (viewport.minY + edgeZone - lastPointer.y) / edgeZone))
            delta = -(3 + ratio * 10)
        } else if lastPointer.y > viewport.maxY - edgeZone {
            let ratio = min(1, max(0, (lastPointer.y - (viewport.maxY - edgeZone)) / edgeZone))
            delta = 3 + ratio * 10
        } else {
            autoScrollTargetY.removeValue(forKey: section)
            return
        }
        // Step from a tracked target offset rather than waiting for onScrollGeometryChange each frame.
        let current = autoScrollTargetY[section] ?? metrics.offsetY
        let next = min(max(0, current + delta), metrics.maxOffsetY)
        guard abs(next - current) > 0.5 else { return }
        autoScrollTargetY[section] = next
        scrollTo(next)
        updateTarget(pointer: lastPointer, model: model)
    }

    private func installKeyMonitor(model: Model) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            MainActor.assumeIsolated {
                self?.cancel(model: model)
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func setClosedHandCursor() {
        cursorActive = true
        NSCursor.closedHand.set()
    }

    private func restoreCursorIfNeeded() {
        guard cursorActive else { return }
        cursorActive = false
        NSCursor.arrow.set()
    }

    private func stopActiveTracking() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollTargetY.removeAll()
        removeKeyMonitor()
        restoreCursorIfNeeded()
    }
}

private struct AppRow: View {
    let app: MenuApp
    var isDragActive = false
    /// Set for system items, which a − button takes out of the menu bar.
    var onRemove: (() -> Void)? = nil
    @State private var isHovered = false

    private var showsHover: Bool { isHovered && !isDragActive }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            Text(app.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from the menu bar")
                .opacity(showsHover ? 1 : 0)
                .allowsHitTesting(showsHover)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.primary.opacity(showsHover ? 0.06 : 0), in: .rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .onChange(of: isDragActive) { _, active in
            if active { isHovered = false }
        }
    }
}

// MARK: - Banner & footer

private struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("smpl.menubar needs Full Disk Access to hide apps.")
            Spacer(minLength: 12)
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .groupBox()
    }
}

private enum SectionHighlight: Equatable {
    case none, accent, destructive
}

private extension View {
    /// A System Settings–style group: a slightly raised fill with a hairline edge.
    func groupBox(highlight: SectionHighlight = .none) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let fill: Color = switch highlight {
        case .none: Color(nsColor: .quaternarySystemFill)
        case .accent: Color.accentColor.opacity(0.07)
        case .destructive: Color.red.opacity(0.08)
        }
        let stroke: Color = switch highlight {
        case .none: Color(nsColor: .separatorColor)
        case .accent: Color.accentColor.opacity(0.7)
        case .destructive: Color.red.opacity(0.6)
        }
        return background {
            shape.fill(fill)
                .animation(.easeOut(duration: 0.14), value: highlight)
        }
        .overlay {
            shape.strokeBorder(stroke)
                .animation(.easeOut(duration: 0.14), value: highlight)
        }
    }
}

/// A full-width strip under the sections: settings on the left, credits on the right.
private struct Footer: View {
    @State private var launchAtLogin = LoginItem.isOn
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        HStack(spacing: 0) {
            settings
            Spacer(minLength: 16)
            credits
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // A step darker than the window, so it reads as secondary to the sections above.
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .contentShape(.rect)
        .gesture(WindowDragGesture())
    }

    @ViewBuilder private var settings: some View {
            SettingCard(symbol: "power", title: "Launch at Login") {
                // Only when macOS needs you to approve it.
                if needsApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
            } control: {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin || needsApproval },
                    set: { on in
                        LoginItem.set(on)
                        launchAtLogin = LoginItem.isOn
                        needsApproval = LoginItem.needsApproval
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider().padding(.vertical, 10)

            SettingCard(symbol: "timer", title: "Hide items after", info: AnyView(HideInfo())) {
                EmptyView()
            } control: {
                HideDelayPicker()
            }

    }

    private var credits: some View {
            VStack(alignment: .trailing, spacing: 2) {
                Link("built by nitish", destination: URL(string: "https://github.com/TechSupportz/smpl-menubar")!)
                    .foregroundStyle(.secondary)
                Text(appVersion)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.trailing, 4)
    }
}

/// One setting: icon, title and an optional caption on the left, its control on the right.
private struct SettingCard<Caption: View, Control: View>: View {
    let symbol: String
    let title: String
    var info: AnyView?
    @ViewBuilder let caption: Caption
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                // Baseline-aligned, so the (i) sits level with the title's letters.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title).font(.body.weight(.medium)).fixedSize()
                    info
                }
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 16)
        // At least this wide so the two settings line up; wider if the title needs it.
        .frame(minWidth: 240)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private var appVersion: String {
    "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
}

/// Choices for how long revealed items stay after the pointer leaves the menu bar.
enum HideDelay {
    static let key = "hideDelay"
    static let `default`: TimeInterval = 2
    static let choices: [TimeInterval] = [1, 2, 3, 5, 10]
}

private struct HideDelayPicker: View {
    @AppStorage(HideDelay.key) private var delay = HideDelay.default

    var body: some View {
        Picker("Hide items after", selection: $delay) {
            ForEach(HideDelay.choices, id: \.self) { Text("\(Int($0)) s").tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        .help("How long revealed apps stay after you leave the menu bar")
    }
}

/// The (i) beside Hide items after: when revealed apps hide.
private struct HideInfo: View {
    @State private var isShown = false

    var body: some View {
        Button { isShown.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("When revealed apps hide")
        .popover(isPresented: $isShown, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("When apps hide").font(.headline)
                rule("menubar.rectangle", "Apps you've revealed stay while your pointer is on the menu bar or one of their menus is open.")
                rule("timer", "Once you leave the bar and close their menus, they hide after this time.")
                rule("circle.fill", "If you clicked the dot to show them, clicking it again hides them straight away.")
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
            // The settings row it's anchored in keeps titles to one line; the popover inherits that.
            .lineLimit(nil)
        }
    }

    private func rule(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
