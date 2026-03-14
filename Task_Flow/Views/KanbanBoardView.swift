import SwiftUI
import SwiftData

// MARK: - Column Frame Preference

struct ColumnFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Board View (Canvas)

struct KanbanBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]
    @Query private var connections: [CardConnection]
    @Query private var workspaces: [Workspace]
    @Bindable var viewModel: BoardViewModel
    @Binding var showAIAssistant: Bool

    @State private var columnFrames: [UUID: CGRect] = [:]
    @State private var pendingDeleteConnection: CardConnection?

    // Canvas pan
    @State private var currentPan: CGSize = .zero
    @GestureState private var gesturePan: CGSize = .zero

    // Canvas zoom (anchored to mouse position)
    @State private var currentScale: CGFloat = 1.0
    @State private var zoomStartScale: CGFloat?
    @State private var zoomStartPan: CGSize?
    @State private var zoomAnchorScreen: CGPoint = .zero

    private var totalOffset: CGSize {
        CGSize(
            width: currentPan.width + gesturePan.width,
            height: currentPan.height + gesturePan.height
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AmbientGradientView()
                GridBackgroundView()

                canvasContent
            }
            .clipped()
            .onAppear {
                if columns.isEmpty {
                    viewModel.createDefaultColumns(context: modelContext)
                }
            }
            .sheet(isPresented: $viewModel.showingNewTaskSheet) {
                if let column = viewModel.newTaskColumnTarget {
                    NewTaskView(column: column, viewModel: viewModel)
                }
            }
            .gesture(canvasPanGesture)
            .gesture(canvasZoomGesture(in: geo))
            .contextMenu {
                Button(action: {
                    captureMousePosition(in: geo)
                    viewModel.createColumnAtPosition(
                        context: modelContext,
                        columns: columns,
                        canvasOffset: totalOffset
                    )
                }) {
                    Label("New Column Here", systemImage: "plus.rectangle.on.rectangle")
                }

                Button(action: {
                    captureMousePosition(in: geo)
                    let pos = viewModel.newColumnPosition ?? CGPoint(x: 200, y: 200)
                    let canvasX = pos.x - totalOffset.width
                    let canvasY = pos.y - totalOffset.height
                    let ws = Workspace(
                        name: "Workspace",
                        positionX: canvasX - Workspace.defaultWidth / 2,
                        positionY: canvasY - Workspace.defaultHeight / 2,
                        order: workspaces.count
                    )
                    modelContext.insert(ws)
                    viewModel.newColumnPosition = nil
                }) {
                    Label("New Workspace Here", systemImage: "rectangle.dashed")
                }

                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        viewModel.autoArrangeColumns(columns, connections: connections)
                    }
                }) {
                    Label("Auto Arrange", systemImage: "rectangle.3.group")
                }

                Divider()

                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        showAIAssistant.toggle()
                    }
                }) {
                    Label(showAIAssistant ? "Hide AI Assistant" : "AI Assistant", systemImage: "sparkles")
                }

                Divider()

                if viewModel.isConnecting {
                    Button(action: { viewModel.cancelConnecting() }) {
                        Label("Cancel Connection", systemImage: "xmark.circle")
                    }
                }

                Button(action: {
                    zoomAtMouse(by: 0.2, in: geo)
                }) {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }

                Button(action: {
                    zoomAtMouse(by: -0.2, in: geo)
                }) {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }

                Button(action: { fitAllColumns(in: geo) }) {
                    Label("Fit All", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentPan = .zero
                        currentScale = 1.0
                    }
                }) {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
            }
            .onTapGesture {
                if viewModel.isConnecting {
                    viewModel.cancelConnecting()
                }
                pendingDeleteConnection = nil
            }
        }
        .sheet(isPresented: $viewModel.showingNewColumnSheet) {
            NewColumnView()
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        ZStack(alignment: .topLeading) {
            // Workspaces — bottommost layer, behind everything
            ForEach(workspaces) { ws in
                let isWsDragging = viewModel.draggingWorkspaceID == ws.id
                let wsOffset = isWsDragging ? viewModel.workspaceDragOffset : .zero

                WorkspaceView(workspace: ws, viewModel: viewModel, columnFrames: columnFrames)
                    .offset(wsOffset)
                    .gesture(workspaceDragGesture(for: ws))
            }

            // Connection lines between columns
            ForEach(connections) { conn in
                ConnectionLineView(
                    connection: conn,
                    columnFrames: columnFrames,
                    isPendingDelete: pendingDeleteConnection?.id == conn.id,
                    onLongPress: {
                        withAnimation(.spring(response: 0.25)) {
                            pendingDeleteConnection = conn
                        }
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.25)) {
                            modelContext.delete(conn)
                            pendingDeleteConnection = nil
                        }
                    }
                )
            }

            // Columns — free positioned, drag managed here
            ForEach(columns) { column in
                let isDragging = viewModel.draggingColumnID == column.id
                let isWsDragging = column.workspace != nil && viewModel.draggingWorkspaceID == column.workspace?.id
                let colOffset = isDragging ? viewModel.columnDragOffset : .zero
                let wsOffset = isWsDragging ? viewModel.workspaceDragOffset : .zero
                let extraOffset = CGSize(width: colOffset.width + wsOffset.width, height: colOffset.height + wsOffset.height)

                ColumnView(
                    column: column,
                    viewModel: viewModel,
                    allColumns: columns,
                    onAddTask: { col in
                        viewModel.newTaskColumnTarget = col
                        viewModel.showingNewTaskSheet = true
                    }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ColumnFrameKey.self,
                            value: [column.id: geo.frame(in: .named("canvas"))]
                        )
                    }
                )
                .offset(extraOffset)
                .zIndex(isDragging ? 100 : 0)
                .shadow(color: isDragging ? .black.opacity(0.2) : .clear, radius: isDragging ? 12 : 0, y: isDragging ? 6 : 0)
                .position(
                    x: column.positionX + 160,
                    y: column.positionY + 200
                )
                .gesture(columnDragGesture(for: column))
                .contextMenu {
                    if column.workspace != nil {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                column.workspace = nil
                            }
                        }) {
                            Label("Remove from Workspace", systemImage: "rectangle.badge.minus")
                        }
                    }
                }
            }

            // Connection endpoint dots — topmost layer, above columns
            ForEach(connections) { conn in
                let fromRect = columnFrames[conn.fromColumnID]
                let toRect = columnFrames[conn.toColumnID]

                if let fromRect, let toRect {
                    let endpoints = computeEndpoints(from: fromRect, to: toRect)
                    let dotColor = conn.displayColor.opacity(0.85)

                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .position(endpoints.from)

                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .position(endpoints.to)
                }
            }
        }
        .coordinateSpace(name: "canvas")
        .scaleEffect(currentScale, anchor: .topLeading)
        .offset(totalOffset)
        .onPreferenceChange(ColumnFrameKey.self) { frames in
            columnFrames = frames
        }
    }

    // MARK: - Column Drag (at board level to keep stable coordinate space)

    private func columnDragGesture(for column: BoardColumn) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if viewModel.draggingColumnID == nil {
                    NSCursor.closedHand.push()
                }
                viewModel.draggingColumnID = column.id
                viewModel.columnDragOffset = value.translation
            }
            .onEnded { value in
                NSCursor.pop()
                column.positionX += value.translation.width
                column.positionY += value.translation.height
                viewModel.draggingColumnID = nil
                viewModel.columnDragOffset = .zero

                // Auto-assign column to workspace if dropped inside one
                assignColumnToWorkspace(column)
            }
    }

    // MARK: - Workspace Drag

    private func workspaceDragGesture(for ws: Workspace) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if viewModel.draggingWorkspaceID == nil {
                    NSCursor.closedHand.push()
                }
                viewModel.draggingWorkspaceID = ws.id
                viewModel.workspaceDragOffset = value.translation
            }
            .onEnded { value in
                NSCursor.pop()
                let dx = value.translation.width
                let dy = value.translation.height

                // Move workspace position
                ws.positionX += dx
                ws.positionY += dy

                // Move all contained columns together
                for col in ws.columns {
                    col.positionX += dx
                    col.positionY += dy
                }

                viewModel.draggingWorkspaceID = nil
                viewModel.workspaceDragOffset = .zero
            }
    }

    /// Check if column center (in canvas space) falls inside any workspace bounds
    private func assignColumnToWorkspace(_ column: BoardColumn) {
        // Column center in canvas space
        let colCenter: CGPoint
        if let frame = columnFrames[column.id] {
            colCenter = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            colCenter = CGPoint(x: column.positionX + 160, y: column.positionY + 200)
        }

        // Check all workspaces — assign to first matching, detach if outside all
        for ws in workspaces {
            let rect = workspaceBounds(ws)
            if rect.contains(colCenter) {
                if column.workspace?.id != ws.id {
                    column.workspace = ws
                    // Fit workspace to include the new column
                    ws.fitToColumns(columnFrames: columnFrames)
                }
                return
            }
        }
        // Not inside any workspace — detach
        column.workspace = nil
    }

    /// Workspace bounds from stored position & size
    private func workspaceBounds(_ ws: Workspace) -> CGRect {
        CGRect(x: ws.positionX, y: ws.positionY, width: ws.width, height: ws.height)
    }

    // MARK: - Canvas Pan & Zoom

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($gesturePan) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                currentPan.width += value.translation.width
                currentPan.height += value.translation.height
            }
    }

    private func canvasZoomGesture(in geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Capture start state on first frame
                if zoomStartScale == nil {
                    zoomStartScale = currentScale
                    zoomStartPan = currentPan
                    zoomAnchorScreen = mouseLocationInView(geo: geo)
                }

                let oldScale = zoomStartScale!
                let oldPan = zoomStartPan!
                let newScale = min(max(oldScale * value.magnification, 0.3), 2.0)

                // Canvas point under mouse: canvasP = (screenP - pan) / scale
                let canvasX = (zoomAnchorScreen.x - oldPan.width) / oldScale
                let canvasY = (zoomAnchorScreen.y - oldPan.height) / oldScale

                // New pan so canvasP stays at same screen position
                currentPan = CGSize(
                    width: zoomAnchorScreen.x - canvasX * newScale,
                    height: zoomAnchorScreen.y - canvasY * newScale
                )
                currentScale = newScale
            }
            .onEnded { _ in
                zoomStartScale = nil
                zoomStartPan = nil
            }
    }

    private func mouseLocationInView(geo: GeometryProxy) -> CGPoint {
        guard let window = NSApp.keyWindow else {
            return CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        let mouseScreen = NSEvent.mouseLocation
        let windowRect = window.convertFromScreen(NSRect(origin: mouseScreen, size: .zero))
        let frameInWindow = geo.frame(in: .global)
        let x = windowRect.origin.x - frameInWindow.origin.x
        let y = frameInWindow.height - (windowRect.origin.y - frameInWindow.origin.y)
        return CGPoint(x: x, y: y)
    }

    private func zoomAtMouse(by delta: CGFloat, in geo: GeometryProxy) {
        let mouse = mouseLocationInView(geo: geo)
        let oldScale = currentScale
        let newScale = min(max(currentScale + delta, 0.3), 2.0)

        let canvasX = (mouse.x - currentPan.width) / oldScale
        let canvasY = (mouse.y - currentPan.height) / oldScale

        withAnimation(.spring(response: 0.3)) {
            currentScale = newScale
            currentPan = CGSize(
                width: mouse.x - canvasX * newScale,
                height: mouse.y - canvasY * newScale
            )
        }
    }

    private func captureMousePosition(in geo: GeometryProxy) {
        guard let window = NSApp.keyWindow else { return }
        let mouseScreen = NSEvent.mouseLocation
        let windowRect = window.convertFromScreen(NSRect(origin: mouseScreen, size: .zero))
        // Convert from window coordinates (bottom-left) to view coordinates (top-left)
        let frameInWindow = geo.frame(in: .global)
        let x = windowRect.origin.x - frameInWindow.origin.x
        let y = frameInWindow.height - (windowRect.origin.y - frameInWindow.origin.y)
        viewModel.newColumnPosition = CGPoint(x: x, y: y)
    }

    private func fitAllColumns(in geo: GeometryProxy) {
        guard !columns.isEmpty else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentPan = .zero
                currentScale = 1.0
            }
            return
        }

        // Column centers in canvas space: (positionX + 160, positionY + 200)
        // Column size: 320 wide, estimate ~400 tall
        let colWidth: Double = 320
        let colHeight: Double = 400
        let padding: Double = 60

        let halfW = colWidth / 2
        let halfH = colHeight / 2
        let leftEdges: [Double] = columns.map { $0.positionX + 160 - halfW }
        let rightEdges: [Double] = columns.map { $0.positionX + 160 + halfW }
        let topEdges: [Double] = columns.map { $0.positionY + 200 - halfH }
        let bottomEdges: [Double] = columns.map { $0.positionY + 200 + halfH }

        let minX = leftEdges.min()! - padding
        let maxX = rightEdges.max()! + padding
        let minY = topEdges.min()! - padding
        let maxY = bottomEdges.max()! + padding

        let contentWidth = maxX - minX
        let contentHeight = maxY - minY

        // Calculate scale to fit content in viewport
        let scaleX = geo.size.width / contentWidth
        let scaleY = geo.size.height / contentHeight
        let fitScale = min(min(scaleX, scaleY), 1.0)  // don't zoom in beyond 1.0
        let clampedScale = max(fitScale, 0.3)

        // After scaling from topLeading, content top-left = (minX * scale, minY * scale)
        // We want content center to align with view center
        let scaledCenterX = (minX + contentWidth / 2) * clampedScale
        let scaledCenterY = (minY + contentHeight / 2) * clampedScale

        let panX = geo.size.width / 2 - scaledCenterX
        let panY = geo.size.height / 2 - scaledCenterY

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentScale = clampedScale
            currentPan = CGSize(width: panX, height: panY)
        }
    }
}

// MARK: - Individual Connection Line (n8n style, long-press delete)

struct ConnectionLineView: View {
    @Bindable var connection: CardConnection
    let columnFrames: [UUID: CGRect]
    let isPendingDelete: Bool
    let onLongPress: () -> Void
    let onDelete: () -> Void

    @State private var showColorPicker = false

    var body: some View {
        let fromRect = columnFrames[connection.fromColumnID]
        let toRect = columnFrames[connection.toColumnID]

        if let fromRect, let toRect {
            let endpoints = computeEndpoints(from: fromRect, to: toRect)
            let from = endpoints.from
            let to = endpoints.to
            let midPoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let lineColor = isPendingDelete ? Color.red.opacity(0.7) : connection.displayColor.opacity(0.6)

            ZStack {
                // Visible line
                N8NConnector(from: from, to: to)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(lineWidth: isPendingDelete ? 2.5 : 2, lineCap: .round, lineJoin: .round)
                    )

                // Fat invisible hit area
                N8NConnector(from: from, to: to)
                    .stroke(Color.clear, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .contentShape(N8NConnector(from: from, to: to).stroke(style: StrokeStyle(lineWidth: 24)))
                    .onLongPressGesture(minimumDuration: 0.5) {
                        onLongPress()
                    }
                    .onTapGesture(count: 2) {
                        showColorPicker = true
                    }

                // Action buttons at midpoint
                if isPendingDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.red)
                            .background(Circle().fill(.ultraThinMaterial).frame(width: 28, height: 28))
                    }
                    .buttonStyle(.plain)
                    .position(midPoint)
                    .transition(.scale.combined(with: .opacity))
                }

                // Color picker popover anchor
                if showColorPicker {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .position(midPoint)
                        .popover(isPresented: $showColorPicker) {
                            ConnectionColorPicker(connection: connection)
                        }
                }
            }
        }
    }

}

/// Pick the best edge pair (right→left, bottom→top, etc.) based on relative position
private func computeEndpoints(from: CGRect, to: CGRect) -> (from: CGPoint, to: CGPoint) {
    let dx = to.midX - from.midX
    let dy = to.midY - from.midY

    if abs(dx) > abs(dy) {
        if dx > 0 {
            return (CGPoint(x: from.maxX, y: from.midY), CGPoint(x: to.minX, y: to.midY))
        } else {
            return (CGPoint(x: from.minX, y: from.midY), CGPoint(x: to.maxX, y: to.midY))
        }
    } else {
        if dy > 0 {
            return (CGPoint(x: from.midX, y: from.maxY), CGPoint(x: to.midX, y: to.minY))
        } else {
            return (CGPoint(x: from.midX, y: from.minY), CGPoint(x: to.midX, y: to.maxY))
        }
    }
}

// MARK: - n8n-style Smooth Connector (horizontal-first bezier)

struct N8NConnector: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)

        let dx = to.x - from.x
        let dy = to.y - from.y

        if abs(dx) >= abs(dy) {
            // Horizontal-dominant: n8n style S-curve with horizontal control points
            let offset = max(abs(dx) * 0.5, 50)
            let cp1 = CGPoint(x: from.x + offset, y: from.y)
            let cp2 = CGPoint(x: to.x - offset, y: to.y)
            path.addCurve(to: to, control1: cp1, control2: cp2)
        } else {
            // Vertical-dominant: S-curve with vertical control points
            let offset = max(abs(dy) * 0.5, 50)
            let cp1 = CGPoint(x: from.x, y: from.y + (dy > 0 ? offset : -offset))
            let cp2 = CGPoint(x: to.x, y: to.y - (dy > 0 ? offset : -offset))
            path.addCurve(to: to, control1: cp1, control2: cp2)
        }

        return path
    }
}

// MARK: - Connection Color Picker

struct ConnectionColorPicker: View {
    @Bindable var connection: CardConnection

    private func displayColor(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "yellow": return .yellow
        case "white": return .white
        default: return Color(red: 0.45, green: 0.47, blue: 0.50)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Line Color")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 6), spacing: 8) {
                ForEach(CardConnection.colorOptions, id: \.self) { name in
                    Button(action: { connection.colorName = name }) {
                        Circle()
                            .fill(displayColor(for: name))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: connection.colorName == name ? 2.5 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(displayColor(for: name).opacity(0.5), lineWidth: connection.colorName == name ? 1 : 0)
                                    .padding(-2)
                            )
                            .scaleEffect(connection.colorName == name ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
    }
}
