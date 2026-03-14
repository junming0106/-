import SwiftUI
import SwiftData

struct WorkspaceView: View {
    @Bindable var workspace: Workspace
    @Bindable var viewModel: BoardViewModel
    let columnFrames: [UUID: CGRect]

    @State private var isEditingName = false
    @State private var showDeleteButton = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var clickMonitor: Any?

    /// Which edge/corner is being resized
    @State private var resizeEdge: ResizeEdge? = nil
    @State private var resizeStart: CGPoint = .zero
    @State private var resizeOrigin: CGPoint = .zero
    @State private var resizeSize: CGSize = .zero

    /// Cursor tracking
    @State private var currentCursorEdge: ResizeEdge? = nil
    @State private var currentCursorIsHovering = false

    @Environment(\.modelContext) private var modelContext

    private let edgeHitSize: Double = 10
    private let cornerHitSize: Double = 20

    enum ResizeEdge {
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Workspace rect in canvas space — uses stored position & size
    var canvasRect: CGRect {
        CGRect(
            x: workspace.positionX,
            y: workspace.positionY,
            width: workspace.width,
            height: workspace.height
        )
    }

    var body: some View {
        let rect = canvasRect

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gray.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            showDeleteButton ? Color.red.opacity(0.4) : Color.white.opacity(0.12),
                            lineWidth: showDeleteButton ? 1.5 : 0.5
                        )
                )
            nameLabel
                .padding(.leading, 14)
                .padding(.top, 8)

            // Delete button — top-right, shown on long press
            if showDeleteButton {
                Button(action: { deleteWorkspace() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                        .background(Circle().fill(.ultraThinMaterial).frame(width: 22, height: 22))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
                .transition(.scale.combined(with: .opacity))
            }

            // Resize handles (invisible, gesture-only)
            resizeHandles(rect: rect)
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let edge = hitTestEdge(at: location, size: CGSize(width: rect.width, height: rect.height))
                let newCursor = edge.map { cursorForEdge($0) } ?? NSCursor.openHand
                if currentCursorEdge != edge {
                    if currentCursorEdge != nil || currentCursorIsHovering {
                        NSCursor.pop()
                    }
                    newCursor.push()
                    currentCursorEdge = edge
                    currentCursorIsHovering = true
                }
            case .ended:
                if currentCursorIsHovering {
                    NSCursor.pop()
                    currentCursorEdge = nil
                    currentCursorIsHovering = false
                }
            }
        }
        .position(x: rect.midX, y: rect.midY)
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation(.spring(response: 0.25)) {
                showDeleteButton.toggle()
            }
        }
        .onTapGesture {
            if showDeleteButton {
                withAnimation(.spring(response: 0.25)) {
                    showDeleteButton = false
                }
            }
        }
    }

    // MARK: - Resize Handles

    @ViewBuilder
    private func resizeHandles(rect: CGRect) -> some View {
        let w = rect.width
        let h = rect.height
        let e = edgeHitSize
        let c = cornerHitSize

        // Corners first (rendered below in ZStack, but we use .zIndex to raise them)
        // Position inward by half corner size so the entire hit area stays inside the frame
        resizeHandle(edge: .topLeft, x: c / 2, y: c / 2, width: c, height: c)
            .zIndex(1)
        resizeHandle(edge: .topRight, x: w - c / 2, y: c / 2, width: c, height: c)
            .zIndex(1)
        resizeHandle(edge: .bottomLeft, x: c / 2, y: h - c / 2, width: c, height: c)
            .zIndex(1)
        resizeHandle(edge: .bottomRight, x: w - c / 2, y: h - c / 2, width: c, height: c)
            .zIndex(1)

        // Edges — inset to avoid overlapping corners
        resizeHandle(edge: .top, x: w / 2, y: e / 2, width: w - c * 2, height: e)
        resizeHandle(edge: .bottom, x: w / 2, y: h - e / 2, width: w - c * 2, height: e)
        resizeHandle(edge: .left, x: e / 2, y: h / 2, width: e, height: h - c * 2)
        resizeHandle(edge: .right, x: w - e / 2, y: h / 2, width: e, height: h - c * 2)
    }

    private func resizeHandle(edge: ResizeEdge, x: Double, y: Double, width: Double, height: Double) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        if resizeEdge == nil {
                            resizeEdge = edge
                            resizeStart = value.startLocation
                            resizeOrigin = CGPoint(x: workspace.positionX, y: workspace.positionY)
                            resizeSize = CGSize(width: workspace.width, height: workspace.height)
                        }
                        let dx = value.location.x - resizeStart.x
                        let dy = value.location.y - resizeStart.y
                        applyResize(edge: edge, translation: CGSize(width: dx, height: dy))
                    }
                    .onEnded { _ in
                        resizeEdge = nil
                    }
            )
    }

    /// Hit-test mouse position to determine which edge/corner zone it's in
    private func hitTestEdge(at point: CGPoint, size: CGSize) -> ResizeEdge? {
        let e = edgeHitSize
        let c = cornerHitSize
        let w = size.width
        let h = size.height

        let nearLeft = point.x < c
        let nearRight = point.x > w - c
        let nearTop = point.y < c
        let nearBottom = point.y > h - c

        // Corners (priority)
        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }

        // Edges
        if point.y < e { return .top }
        if point.y > h - e { return .bottom }
        if point.x < e { return .left }
        if point.x > w - e { return .right }

        return nil
    }

    private func applyResize(edge: ResizeEdge, translation: CGSize) {
        let dx = translation.width
        let dy = translation.height
        let minW = Workspace.minWidth
        let minH = Workspace.minHeight

        var newX = resizeOrigin.x
        var newY = resizeOrigin.y
        var newW = resizeSize.width
        var newH = resizeSize.height

        switch edge {
        case .left:
            newX = resizeOrigin.x + dx
            newW = resizeSize.width - dx
        case .right:
            newW = resizeSize.width + dx
        case .top:
            newY = resizeOrigin.y + dy
            newH = resizeSize.height - dy
        case .bottom:
            newH = resizeSize.height + dy
        case .topLeft:
            newX = resizeOrigin.x + dx
            newW = resizeSize.width - dx
            newY = resizeOrigin.y + dy
            newH = resizeSize.height - dy
        case .topRight:
            newW = resizeSize.width + dx
            newY = resizeOrigin.y + dy
            newH = resizeSize.height - dy
        case .bottomLeft:
            newX = resizeOrigin.x + dx
            newW = resizeSize.width - dx
            newH = resizeSize.height + dy
        case .bottomRight:
            newW = resizeSize.width + dx
            newH = resizeSize.height + dy
        }

        // Enforce minimum size
        if newW < minW {
            if edge == .left || edge == .topLeft || edge == .bottomLeft {
                newX = resizeOrigin.x + resizeSize.width - minW
            }
            newW = minW
        }
        if newH < minH {
            if edge == .top || edge == .topLeft || edge == .topRight {
                newY = resizeOrigin.y + resizeSize.height - minH
            }
            newH = minH
        }

        workspace.positionX = newX
        workspace.positionY = newY
        workspace.width = newW
        workspace.height = newH
    }

    private func cursorForEdge(_ edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .left, .right:
            return NSCursor.resizeLeftRight
        case .top, .bottom:
            return NSCursor.resizeUpDown
        case .topLeft, .bottomRight:
            return nwseResizeCursor
        case .topRight, .bottomLeft:
            return neswResizeCursor
        }
    }

    /// Diagonal resize cursors (macOS doesn't provide built-in ones)
    private var nwseResizeCursor: NSCursor {
        if let cursor = NSCursor.value(forKey: "_windowResizeNorthWestSouthEastCursor") as? NSCursor {
            return cursor
        }
        return NSCursor.resizeUpDown
    }

    private var neswResizeCursor: NSCursor {
        if let cursor = NSCursor.value(forKey: "_windowResizeNorthEastSouthWestCursor") as? NSCursor {
            return cursor
        }
        return NSCursor.resizeUpDown
    }

    // MARK: - Name Label

    @ViewBuilder
    private var nameLabel: some View {
        if isEditingName {
            TextField("Name", text: $workspace.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .textFieldStyle(.plain)
                .focused($isNameFieldFocused)
                .onSubmit { finishEditing() }
                .onExitCommand { finishEditing() }
                .onAppear {
                    isNameFieldFocused = true
                    clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                        DispatchQueue.main.async { finishEditing() }
                        return event
                    }
                }
                .onDisappear { removeClickMonitor() }
        } else {
            Text(workspace.name.isEmpty ? "Untitled" : workspace.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(workspace.name.isEmpty ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.6))
                .frame(minWidth: 50, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isEditingName = true }
        }
    }

    private func deleteWorkspace() {
        withAnimation(.spring(response: 0.25)) {
            for col in workspace.columns {
                col.workspace = nil
            }
            modelContext.delete(workspace)
        }
    }

    private func finishEditing() {
        guard isEditingName else { return }
        isEditingName = false
        isNameFieldFocused = false
        removeClickMonitor()
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
