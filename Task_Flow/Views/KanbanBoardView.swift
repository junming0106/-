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
    @Bindable var viewModel: BoardViewModel
    @Binding var showAIAssistant: Bool

    @State private var columnFrames: [UUID: CGRect] = [:]
    @State private var pendingDeleteConnection: CardConnection?

    // Canvas pan
    @State private var currentPan: CGSize = .zero
    @GestureState private var gesturePan: CGSize = .zero

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

                Button(action: { resetCanvasPosition() }) {
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
                let extraOffset = isDragging ? viewModel.columnDragOffset : .zero

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
                    x: column.positionX + 150,
                    y: column.positionY + 200
                )
                .highPriorityGesture(
                    columnDragGesture(for: column)
                )
            }
        }
        .coordinateSpace(name: "canvas")
        .offset(totalOffset)
        .onPreferenceChange(ColumnFrameKey.self) { frames in
            columnFrames = frames
        }
    }

    // MARK: - Column Drag (managed at board level — no gesture conflict)

    private func columnDragGesture(for column: BoardColumn) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                viewModel.draggingColumnID = column.id
                viewModel.columnDragOffset = value.translation
            }
            .onEnded { value in
                column.positionX += value.translation.width
                column.positionY += value.translation.height
                viewModel.draggingColumnID = nil
                viewModel.columnDragOffset = .zero
            }
    }

    // MARK: - Canvas Pan

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

    private func resetCanvasPosition() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentPan = .zero
        }
    }
}

// MARK: - Individual Connection Line (n8n style, long-press delete)

struct ConnectionLineView: View {
    let connection: CardConnection
    let columnFrames: [UUID: CGRect]
    let isPendingDelete: Bool
    let onLongPress: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let fromRect = columnFrames[connection.fromColumnID]
        let toRect = columnFrames[connection.toColumnID]

        if let fromRect, let toRect {
            let endpoints = computeEndpoints(from: fromRect, to: toRect)
            let from = endpoints.from
            let to = endpoints.to
            let midPoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)

            ZStack {
                // Visible line
                N8NConnector(from: from, to: to)
                    .stroke(
                        isPendingDelete ? Color.red.opacity(0.7) : Color.secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: isPendingDelete ? 2.5 : 2, lineCap: .round, lineJoin: .round)
                    )

                // Arrowhead
                N8NArrowhead(from: from, to: to)
                    .fill(isPendingDelete ? Color.red.opacity(0.7) : Color.secondary.opacity(0.45))

                // Fat invisible hit area
                N8NConnector(from: from, to: to)
                    .stroke(Color.clear, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .contentShape(N8NConnector(from: from, to: to).stroke(style: StrokeStyle(lineWidth: 24)))
                    .onLongPressGesture(minimumDuration: 0.5) {
                        onLongPress()
                    }

                // Delete button
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
            }
        }
    }

    /// Pick the best edge pair (right→left, bottom→top, etc.) based on relative position
    private func computeEndpoints(from: CGRect, to: CGRect) -> (from: CGPoint, to: CGPoint) {
        let dx = to.midX - from.midX
        let dy = to.midY - from.midY

        if abs(dx) > abs(dy) {
            // Primarily horizontal
            if dx > 0 {
                return (CGPoint(x: from.maxX, y: from.midY), CGPoint(x: to.minX, y: to.midY))
            } else {
                return (CGPoint(x: from.minX, y: from.midY), CGPoint(x: to.maxX, y: to.midY))
            }
        } else {
            // Primarily vertical
            if dy > 0 {
                return (CGPoint(x: from.midX, y: from.maxY), CGPoint(x: to.midX, y: to.minY))
            } else {
                return (CGPoint(x: from.midX, y: from.minY), CGPoint(x: to.midX, y: to.maxY))
            }
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

// MARK: - n8n Arrowhead (filled triangle at endpoint)

struct N8NArrowhead: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x
        let dy = to.y - from.y

        // Compute the angle of the curve at the endpoint
        let angle: CGFloat
        if abs(dx) >= abs(dy) {
            let offset = max(abs(dx) * 0.5, 50)
            let cp2 = CGPoint(x: to.x - offset, y: to.y)
            angle = atan2(to.y - cp2.y, to.x - cp2.x)
        } else {
            let offset = max(abs(dy) * 0.5, 50)
            let cp2 = CGPoint(x: to.x, y: to.y - (dy > 0 ? offset : -offset))
            angle = atan2(to.y - cp2.y, to.x - cp2.x)
        }

        let arrowLen: CGFloat = 10
        let arrowWidth: CGFloat = 6

        let tip = to
        let left = CGPoint(
            x: tip.x - arrowLen * cos(angle) + arrowWidth * sin(angle),
            y: tip.y - arrowLen * sin(angle) - arrowWidth * cos(angle)
        )
        let right = CGPoint(
            x: tip.x - arrowLen * cos(angle) - arrowWidth * sin(angle),
            y: tip.y - arrowLen * sin(angle) + arrowWidth * cos(angle)
        )

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}
