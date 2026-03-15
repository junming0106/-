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
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \BoardColumn.order) private var allColumns: [BoardColumn]
    @Query private var connections: [CardConnection]
    @Query private var allWorkspaces: [Workspace]
    @Bindable var viewModel: BoardViewModel
    let board: Board

    @AppStorage("showGridBackground") private var showGridBackground = true

    /// Columns belonging to the current board
    private var columns: [BoardColumn] {
        allColumns.filter { $0.board?.id == board.id }
    }

    /// Workspaces belonging to the current board
    private var workspaces: [Workspace] {
        allWorkspaces.filter { $0.board?.id == board.id }
    }

    @State private var columnFrames: [UUID: CGRect] = [:]
    @State private var pendingDeleteConnection: CardConnection?

    // View frame for mouse position calculations
    @State private var viewFrame: CGRect = .zero

    // Selection
    @State private var selectedColumnIDs: Set<UUID> = []
    @State private var selectedWorkspaceIDs: Set<UUID> = []
    @State private var selectionRect: CGRect? = nil
    @State private var selectionStart: CGPoint = .zero
    @State private var isSelecting = false
    @State private var isShiftHeld = false
    @State private var isPanning = false

    // Canvas pan
    @State private var currentPan: CGSize = .zero

    // Canvas zoom (anchored to mouse position)
    @State private var currentScale: CGFloat = 1.0
    @State private var zoomStartScale: CGFloat?
    @State private var zoomStartPan: CGSize?
    @State private var zoomAnchorScreen: CGPoint = .zero

    private var totalOffset: CGSize { currentPan }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AmbientGradientView()
                if showGridBackground {
                    GridBackgroundView()
                }

                canvasContent
            }
            .clipped()
            .onAppear { viewFrame = geo.frame(in: .global) }
            .onChange(of: geo.size) { _, _ in viewFrame = geo.frame(in: .global) }
            .sheet(isPresented: $viewModel.showingNewTaskSheet) {
                if let column = viewModel.newTaskColumnTarget {
                    NewTaskView(column: column, viewModel: viewModel)
                }
            }
            .overlay {
                // Transparent overlay that captures Shift+drag for canvas panning
                // Must sit on top of all child views to intercept their gestures
                Color.clear
                    .contentShape(Rectangle())
                    .allowsHitTesting(isShiftHeld || isPanning || isSpaceHeld)
                    .gesture(canvasPanGesture)
            }
            .overlay {
                // Selection rectangle visual (in screen space)
                if let rect = selectionRect {
                    Rectangle()
                        .fill(Color.blue.opacity(0.08))
                        .overlay(
                            Rectangle()
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .gesture(selectionDragGesture)
            .gesture(canvasZoomGesture(in: geo))
            .onAppear { setupShiftMonitor() }
            .onDisappear { removeShiftMonitor() }
            .contextMenu {
                if hasSelection {
                    // Selection context menu
                    let colCount = selectedColumnIDs.count
                    let wsCount = selectedWorkspaceIDs.count

                    Text("\(colCount) Columns, \(wsCount) Workspaces Selected")
                        .font(.headline)

                    Divider()

                    // Move to workspace
                    if !workspaces.isEmpty {
                        Menu("Move to Workspace") {
                            ForEach(workspaces) { ws in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        moveColumnsToWorkspace(selectedColumns, workspace: ws)
                                        clearSelection()
                                    }
                                }) {
                                    Label(ws.name.isEmpty ? "Untitled" : ws.name, systemImage: "rectangle.dashed")
                                }
                            }
                        }
                    }

                    // Create new workspace from selection
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            createWorkspaceFromSelection()
                        }
                    }) {
                        Label("Group into New Workspace", systemImage: "rectangle.dashed.badge.record")
                    }

                    // Remove from workspace
                    if selectedColumns.contains(where: { $0.workspace != nil }) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                for col in selectedColumns {
                                    col.workspace = nil
                                }
                                clearSelection()
                            }
                        }) {
                            Label("Remove from Workspace", systemImage: "rectangle.badge.minus")
                        }
                    }

                    Divider()

                    // Select all
                    Button(action: {
                        selectedColumnIDs = Set(columns.map(\.id))
                        selectedWorkspaceIDs = Set(workspaces.map(\.id))
                    }) {
                        Label("Select All", systemImage: "checkmark.rectangle.stack")
                    }

                    Button(action: {
                        clearSelection()
                    }) {
                        Label("Deselect All", systemImage: "xmark.rectangle")
                    }

                    Divider()

                    // Delete selected
                    Button(role: .destructive, action: {
                        withAnimation(.spring(response: 0.3)) {
                            for col in selectedColumns {
                                viewModel.deleteColumn(col, context: modelContext, undoManager: undoManager)
                            }
                            clearSelection()
                        }
                    }) {
                        Label("Delete \(colCount) Columns", systemImage: "trash")
                    }
                } else {
                    // Normal canvas context menu
                    Button(action: {
                        let pos = mouseCanvasPosition()
                        let newCol = BoardColumn(
                            title: "New Column",
                            order: columns.count,
                            positionX: pos.x - 160,
                            positionY: pos.y - 200
                        )
                        newCol.board = board
                        modelContext.insert(newCol)
                    }) {
                        Label("New Column Here", systemImage: "plus.rectangle.on.rectangle")
                    }

                    Button(action: {
                        let pos = mouseCanvasPosition()
                        let ws = Workspace(
                            name: "Workspace",
                            positionX: pos.x - Workspace.defaultWidth / 2,
                            positionY: pos.y - Workspace.defaultHeight / 2,
                            order: workspaces.count
                        )
                        ws.board = board
                        modelContext.insert(ws)
                    }) {
                        Label("New Workspace Here", systemImage: "rectangle.dashed")
                    }

                    Button(action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            viewModel.autoArrangeColumns(columns, connections: connections, workspaces: workspaces, undoManager: undoManager)
                        }
                    }) {
                        Label("Auto Arrange", systemImage: "rectangle.3.group")
                    }

                    Divider()

                    Button(action: {
                        QuickInputPanel.shared.toggle()
                    }) {
                        Label("AI Assistant (⌃⇧Space)", systemImage: "sparkles")
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
            }
            .onTapGesture {
                if viewModel.isConnecting {
                    viewModel.cancelConnecting()
                }
                pendingDeleteConnection = nil
                if hasSelection {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        clearSelection()
                    }
                }
                // Close task detail panel when clicking canvas background
                if viewModel.selectedTask != nil {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTask = nil
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showingNewColumnSheet) {
            NewColumnView(board: board)
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        ZStack(alignment: .topLeading) {
            // Workspaces — bottommost layer, behind everything
            ForEach(workspaces) { ws in
                let isWsDragging = viewModel.draggingWorkspaceID == ws.id
                let isWsSelectedDragging = !isWsDragging
                    && selectedWorkspaceIDs.contains(ws.id)
                    && isSelectionDragActive
                let wsOffset = isWsDragging ? viewModel.workspaceDragOffset
                    : isWsSelectedDragging ? viewModel.columnDragOffset
                    : .zero

                WorkspaceView(workspace: ws, viewModel: viewModel, columnFrames: columnFrames)
                    .overlay {
                        if selectedWorkspaceIDs.contains(ws.id) {
                            let rect = workspaceBounds(ws)
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.blue.opacity(0.8), lineWidth: 2.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.blue.opacity(0.05))
                                )
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                        }
                    }
                    .offset(wsOffset)
                    .gesture(workspaceDragGesture(for: ws))
                    .contextMenu {
                        Button(action: {
                            let pos = mouseCanvasPosition()
                            // Column uses .position(x: posX + 160, y: posY + 200), so offset back
                            let colX = pos.x - 160
                            let colY = pos.y - 200
                            let newCol = BoardColumn(
                                title: "New Column",
                                order: columns.count,
                                positionX: colX,
                                positionY: colY
                            )
                            newCol.board = board
                            newCol.workspace = ws
                            modelContext.insert(newCol)
                            ws.expandToFitColumns(columnFrames: columnFrames)
                        }) {
                            Label("Add Column", systemImage: "plus.rectangle.on.rectangle")
                        }

                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                let wsCols = columns.filter { $0.workspace?.id == ws.id }
                                let wsConns = connections.filter { conn in
                                    let ids = Set(wsCols.map(\.id))
                                    return ids.contains(conn.fromColumnID) && ids.contains(conn.toColumnID)
                                }
                                viewModel.autoArrangeColumns(wsCols, connections: Array(wsConns), workspaces: [ws], undoManager: undoManager)
                            }
                        }) {
                            Label("Auto Arrange", systemImage: "rectangle.3.group")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            withAnimation(.spring(response: 0.3)) {
                                undoManager?.beginUndoGrouping()
                                for col in ws.columns {
                                    col.workspace = nil
                                }
                                modelContext.delete(ws)
                                undoManager?.endUndoGrouping()
                            }
                        }) {
                            Label("Delete Workspace", systemImage: "trash")
                        }
                    }
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
                let isSelectedDragging = !isDragging
                    && selectedColumnIDs.contains(column.id)
                    && isSelectionDragActive
                // Column follows if its parent workspace is selected and being dragged via selection
                let isWsSelectedDragging = !isDragging && !isSelectedDragging
                    && column.workspace != nil
                    && selectedWorkspaceIDs.contains(column.workspace!.id)
                    && isSelectionDragActive
                let isWsDragging = column.workspace != nil && viewModel.draggingWorkspaceID == column.workspace?.id
                let selectionOffset = (isDragging || isSelectedDragging || isWsSelectedDragging) ? viewModel.columnDragOffset : .zero
                let wsOffset = isWsDragging ? viewModel.workspaceDragOffset : .zero
                let extraOffset = CGSize(width: selectionOffset.width + wsOffset.width, height: selectionOffset.height + wsOffset.height)

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
                .zIndex((isDragging || isSelectedDragging || isWsSelectedDragging) ? 100 : 0)
                .shadow(color: (isDragging || isSelectedDragging || isWsSelectedDragging) ? .black.opacity(0.2) : .clear, radius: (isDragging || isSelectedDragging || isWsSelectedDragging) ? 12 : 0, y: (isDragging || isSelectedDragging || isWsSelectedDragging) ? 6 : 0)
                .overlay {
                    if selectedColumnIDs.contains(column.id) {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.column, style: .continuous)
                            .stroke(Color.blue.opacity(0.8), lineWidth: 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.column, style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                    }
                }
                .position(
                    x: column.positionX + 160,
                    y: column.positionY + 200
                )
                .gesture(columnDragGesture(for: column))
                .onTapGesture {
                    // Toggle selection on tap
                    if NSEvent.modifierFlags.contains(.command) {
                        if selectedColumnIDs.contains(column.id) {
                            selectedColumnIDs.remove(column.id)
                        } else {
                            selectedColumnIDs.insert(column.id)
                        }
                    } else if hasSelection {
                        clearSelection()
                    }
                }
                .contextMenu {
                    if selectedColumnIDs.contains(column.id) && selectedColumnIDs.count > 1 {
                        // Batch operations for selected columns
                        let count = selectedColumnIDs.count

                        Text("\(count) Columns Selected")
                            .font(.headline)

                        Divider()

                        if !workspaces.isEmpty {
                            Menu("Move to Workspace") {
                                ForEach(workspaces) { ws in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3)) {
                                            moveColumnsToWorkspace(selectedColumns, workspace: ws)
                                            clearSelection()
                                        }
                                    }) {
                                        Label(ws.name.isEmpty ? "Untitled" : ws.name, systemImage: "rectangle.dashed")
                                    }
                                }
                            }
                        }

                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                createWorkspaceFromSelection()
                            }
                        }) {
                            Label("Group into New Workspace", systemImage: "rectangle.dashed.badge.record")
                        }

                        if selectedColumns.contains(where: { $0.workspace != nil }) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    for col in selectedColumns {
                                        col.workspace = nil
                                    }
                                    clearSelection()
                                }
                            }) {
                                Label("Remove from Workspace", systemImage: "rectangle.badge.minus")
                            }
                        }

                        Divider()

                        Button(action: {
                            selectedColumnIDs = Set(columns.map(\.id))
                            selectedWorkspaceIDs = Set(workspaces.map(\.id))
                        }) {
                            Label("Select All", systemImage: "checkmark.rectangle.stack")
                        }

                        Button(action: {
                            clearSelection()
                        }) {
                            Label("Deselect All", systemImage: "xmark.rectangle")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            withAnimation(.spring(response: 0.3)) {
                                for col in selectedColumns {
                                    viewModel.deleteColumn(col, context: modelContext, undoManager: undoManager)
                                }
                                clearSelection()
                            }
                        }) {
                            Label("Delete \(count) Columns", systemImage: "trash")
                        }
                    } else {
                        // Single column context menu
                        Button(action: {
                            viewModel.newTaskColumnTarget = column
                            viewModel.showingNewTaskSheet = true
                        }) {
                            Label("Add Task", systemImage: "plus.square")
                        }

                        Divider()

                        Button(action: {
                            viewModel.startConnecting(from: column)
                        }) {
                            Label("Connect to…", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }

                        if column.workspace != nil {
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    column.workspace = nil
                                }
                            }) {
                                Label("Remove from Workspace", systemImage: "rectangle.badge.minus")
                            }
                        } else if !workspaces.isEmpty {
                            Menu("Move to Workspace") {
                                ForEach(workspaces) { ws in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3)) {
                                            moveColumnsToWorkspace([column], workspace: ws)
                                        }
                                    }) {
                                        Label(ws.name.isEmpty ? "Untitled" : ws.name, systemImage: "rectangle.dashed")
                                    }
                                }
                            }
                        }

                        Divider()

                        Button(action: {
                            duplicateColumn(column)
                        }) {
                            Label("Duplicate Column", systemImage: "plus.square.on.square")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.deleteColumn(column, context: modelContext, undoManager: undoManager)
                            }
                        }) {
                            Label("Delete Column", systemImage: "trash")
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
                let dx = value.translation.width
                let dy = value.translation.height

                if selectedColumnIDs.contains(column.id) {
                    // Group multi-selection move as one undo step
                    undoManager?.beginUndoGrouping()

                    // Move all selected columns
                    for col in selectedColumns {
                        col.positionX += dx
                        col.positionY += dy
                    }

                    // Move all selected workspaces and their contained columns
                    let selectedWsList = workspaces.filter { selectedWorkspaceIDs.contains($0.id) }
                    let alreadyMovedIDs = Set(selectedColumns.map(\.id))
                    for ws in selectedWsList {
                        ws.positionX += dx
                        ws.positionY += dy
                        // Move workspace's columns that weren't already moved as selected columns
                        for col in ws.columns where !alreadyMovedIDs.contains(col.id) {
                            col.positionX += dx
                            col.positionY += dy
                        }
                    }

                    // Auto-assign each moved column to workspace
                    for col in selectedColumns {
                        assignColumnToWorkspace(col)
                    }

                    undoManager?.endUndoGrouping()
                } else {
                    column.positionX += dx
                    column.positionY += dy
                    assignColumnToWorkspace(column)
                }

                viewModel.draggingColumnID = nil
                viewModel.columnDragOffset = .zero
            }
    }

    // MARK: - Workspace Drag

    private func workspaceDragGesture(for ws: Workspace) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if selectedWorkspaceIDs.contains(ws.id) && hasSelection {
                    // Use column drag state so all selected items follow
                    if viewModel.draggingColumnID == nil {
                        NSCursor.closedHand.push()
                        // Use a sentinel ID to indicate selection drag initiated from workspace
                        viewModel.draggingColumnID = ws.id
                    }
                    viewModel.columnDragOffset = value.translation
                } else {
                    if viewModel.draggingWorkspaceID == nil {
                        NSCursor.closedHand.push()
                    }
                    viewModel.draggingWorkspaceID = ws.id
                    viewModel.workspaceDragOffset = value.translation
                }
            }
            .onEnded { value in
                NSCursor.pop()
                let dx = value.translation.width
                let dy = value.translation.height

                if selectedWorkspaceIDs.contains(ws.id) && hasSelection {
                    // Move all selected columns
                    for col in selectedColumns {
                        col.positionX += dx
                        col.positionY += dy
                    }

                    // Move all selected workspaces and their contained columns
                    let selectedWsList = workspaces.filter { selectedWorkspaceIDs.contains($0.id) }
                    let alreadyMovedIDs = Set(selectedColumns.map(\.id))
                    for selWs in selectedWsList {
                        selWs.positionX += dx
                        selWs.positionY += dy
                        for col in selWs.columns where !alreadyMovedIDs.contains(col.id) {
                            col.positionX += dx
                            col.positionY += dy
                        }
                    }

                    viewModel.draggingColumnID = nil
                    viewModel.columnDragOffset = .zero
                } else {
                    // Single workspace drag
                    ws.positionX += dx
                    ws.positionY += dy
                    for col in ws.columns {
                        col.positionX += dx
                        col.positionY += dy
                    }

                    viewModel.draggingWorkspaceID = nil
                    viewModel.workspaceDragOffset = .zero
                }
            }
    }

    /// Duplicate a column (with its tasks)
    private func duplicateColumn(_ column: BoardColumn) {
        let newCol = BoardColumn(
            title: column.title + " Copy",
            order: columns.count,
            colorName: column.colorName,
            iconName: column.iconName,
            positionX: column.positionX + 40,
            positionY: column.positionY + 40
        )
        newCol.board = board
        newCol.workspace = column.workspace
        modelContext.insert(newCol)

        // Duplicate tasks
        for task in column.sortedTasks {
            let newTask = TaskItem(
                title: task.title,
                taskDescription: task.taskDescription,
                priority: task.priority,
                dueDate: task.dueDate,
                tags: task.tags,
                order: task.order
            )
            newTask.column = newCol
            modelContext.insert(newTask)
        }

        // Expand workspace if needed
        if let ws = newCol.workspace {
            ws.expandToFitColumns(columnFrames: columnFrames)
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

        // If column is already in a workspace, check if it's fully outside → detach
        if let currentWs = column.workspace {
            let colFrame: CGRect
            if let frame = columnFrames[column.id] {
                colFrame = frame
            } else {
                colFrame = CGRect(x: column.positionX, y: column.positionY + 50, width: 320, height: 300)
            }
            let wsRect = workspaceBounds(currentWs)
            // Detach if no overlap at all
            if !wsRect.intersects(colFrame) {
                column.workspace = nil
            } else {
                currentWs.expandToFitColumns(columnFrames: columnFrames)
            }
            return
        }

        // Check all workspaces — assign to first matching, detach if outside all
        for ws in workspaces {
            let rect = workspaceBounds(ws)
            if rect.contains(colCenter) {
                column.workspace = ws
                ws.expandToFitColumns(columnFrames: columnFrames)
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

    // MARK: - Selected columns helper

    private var selectedColumns: [BoardColumn] {
        columns.filter { selectedColumnIDs.contains($0.id) }
    }

    private var hasSelection: Bool {
        !selectedColumnIDs.isEmpty || !selectedWorkspaceIDs.isEmpty
    }

    /// True when a selection-group drag is in progress (dragged item is part of selection)
    private var isSelectionDragActive: Bool {
        guard let dragID = viewModel.draggingColumnID else { return false }
        return selectedColumnIDs.contains(dragID) || selectedWorkspaceIDs.contains(dragID)
    }

    private func clearSelection() {
        selectedColumnIDs.removeAll()
        selectedWorkspaceIDs.removeAll()
    }

    /// Move columns into a workspace, repositioning them in a row inside the workspace
    private func moveColumnsToWorkspace(_ cols: [BoardColumn], workspace ws: Workspace) {
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let movingIDs = Set(cols.map(\.id))
        let sorted = cols.sorted { $0.order < $1.order }
        let spacingX: Double = 400
        let pad = Workspace.padding

        // Existing columns already in this workspace (exclude the ones being moved)
        let existingCols = columns.filter { $0.workspace?.id == ws.id && !movingIDs.contains($0.id) }
        let existingMaxX = existingCols.map { $0.positionX + 320 }.max()

        // Start X: after existing columns, or at workspace left + padding
        let startX: Double
        if let maxX = existingMaxX {
            startX = maxX + (spacingX - 320)
        } else {
            startX = ws.positionX + pad
        }
        let startY = ws.positionY + pad + 28 - 50

        // Position columns in a row
        for (i, col) in sorted.enumerated() {
            col.workspace = ws
            col.positionX = startX + Double(i) * spacingX
            col.positionY = startY
            col.order = existingCols.count + i
        }

        // Fit workspace to all its columns (shrink + grow)
        var estimatedFrames: [UUID: CGRect] = [:]
        let allWsCols = existingCols + sorted
        for col in allWsCols {
            estimatedFrames[col.id] = CGRect(
                x: col.positionX, y: col.positionY + 50,
                width: 320, height: 300
            )
        }
        ws.fitToColumns(columnFrames: estimatedFrames)
    }

    private func createWorkspaceFromSelection() {
        let cols = selectedColumns
        guard !cols.isEmpty else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        // Calculate bounds of selected columns
        let minX = cols.map { $0.positionX }.min()!
        let minY = cols.map { $0.positionY + 50 }.min()!
        let maxX = cols.map { $0.positionX + 320 }.max()!
        let maxY = cols.map { $0.positionY + 50 + 300 }.max()!

        let pad = Workspace.padding
        let ws = Workspace(
            name: "Workspace",
            positionX: minX - pad,
            positionY: minY - pad - 28,
            width: (maxX - minX) + pad * 2,
            height: (maxY - minY) + pad * 2 + 28,
            order: workspaces.count
        )
        ws.board = board
        modelContext.insert(ws)

        for col in cols {
            col.workspace = ws
        }
        clearSelection()
    }

    /// Convert screen-space rect to canvas-space rect (accounting for pan & scale)
    private func screenToCanvasRect(_ screenRect: CGRect) -> CGRect {
        let x = (screenRect.origin.x - totalOffset.width) / currentScale
        let y = (screenRect.origin.y - totalOffset.height) / currentScale
        let w = screenRect.width / currentScale
        let h = screenRect.height / currentScale
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Update selected columns and workspaces based on selection rectangle intersection
    private func updateSelectionFromRect(_ screenRect: CGRect) {
        let canvasRect = screenToCanvasRect(screenRect)
        var colIDs = Set<UUID>()
        for col in columns {
            let colRect = columnFrames[col.id] ?? CGRect(
                x: col.positionX, y: col.positionY + 50,
                width: 320, height: 300
            )
            if canvasRect.intersects(colRect) {
                colIDs.insert(col.id)
            }
        }
        selectedColumnIDs = colIDs

        var wsIDs = Set<UUID>()
        for ws in workspaces {
            let wsRect = workspaceBounds(ws)
            if canvasRect.intersects(wsRect) {
                wsIDs.insert(ws.id)
            }
        }
        selectedWorkspaceIDs = wsIDs
    }

    // MARK: - Canvas Pan / Select & Zoom

    @State private var panStartOffset: CGSize? = nil
    @State private var shiftFlagMonitor: Any?
    @State private var shiftKeyMonitor: Any?
    @State private var isSpaceHeld = false
    @State private var spaceOpenHandPushed = false
    @State private var spaceKeyMonitor: Any?

    /// Monitor Shift key press/release to toggle pan overlay hit testing
    private func setupShiftMonitor() {
        shiftFlagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let shiftNow = event.modifierFlags.contains(.shift)
            if shiftNow != isShiftHeld {
                isShiftHeld = shiftNow
            }
            return event
        }

        // Monitor spacebar for pan mode, and Tab to prevent focus ring on buttons
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let responder = NSApp.keyWindow?.firstResponder
            let isTyping = responder is NSTextView || responder is NSTextField

            // Tab key — eat it to prevent focus ring from appearing on buttons
            if event.keyCode == 48 && event.type == .keyDown && !isTyping {
                return nil
            }

            // Spacebar
            guard event.keyCode == 49 else { return event }
            if event.type == .keyDown && event.isARepeat { return isTyping ? event : nil }
            if !isTyping {
                let spaceNow = event.type == .keyDown
                if spaceNow != isSpaceHeld {
                    isSpaceHeld = spaceNow
                    if spaceNow {
                        // Push openHand and remember we did so
                        NSCursor.openHand.push()
                        spaceOpenHandPushed = true
                    } else {
                        // Pop the space cursor only if not mid-drag (drag's onEnded will handle it)
                        if !isPanning && spaceOpenHandPushed {
                            NSCursor.pop()
                            spaceOpenHandPushed = false
                        }
                    }
                }
                return nil // consume — prevent reaching focused buttons
            }
            return event
        }
    }

    private func removeShiftMonitor() {
        if let monitor = shiftFlagMonitor {
            NSEvent.removeMonitor(monitor)
            shiftFlagMonitor = nil
        }
        if let monitor = spaceKeyMonitor {
            NSEvent.removeMonitor(monitor)
            spaceKeyMonitor = nil
        }
    }

    /// Selection gesture — runs on the canvas background (default drag = selection)
    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isSelecting {
                    isSelecting = true
                    selectionStart = value.startLocation
                }
                let origin = CGPoint(
                    x: min(selectionStart.x, value.location.x),
                    y: min(selectionStart.y, value.location.y)
                )
                let size = CGSize(
                    width: abs(value.location.x - selectionStart.x),
                    height: abs(value.location.y - selectionStart.y)
                )
                selectionRect = CGRect(origin: origin, size: size)
                updateSelectionFromRect(selectionRect!)
            }
            .onEnded { _ in
                isSelecting = false
                selectionRect = nil
            }
    }

    /// Pan gesture — activates when Shift is held, Space is held, or mid-pan
    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if panStartOffset == nil {
                    panStartOffset = currentPan
                    isPanning = true
                    NSCursor.closedHand.push()
                }
                let start = panStartOffset!
                currentPan = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
            }
            .onEnded { _ in
                panStartOffset = nil
                isPanning = false
                NSCursor.pop() // pops closedHand → reveals space's openHand (if pushed) or arrow
                // If space was released during drag, also pop the space cursor
                if !isSpaceHeld && spaceOpenHandPushed {
                    NSCursor.pop()
                    spaceOpenHandPushed = false
                }
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

    /// Mouse position converted to canvas coordinates (accounting for pan & scale)
    private func mouseCanvasPosition() -> CGPoint {
        guard let window = NSApp.keyWindow else { return .zero }
        let mouseScreen = NSEvent.mouseLocation
        let windowRect = window.convertFromScreen(NSRect(origin: mouseScreen, size: .zero))
        let x = windowRect.origin.x - viewFrame.origin.x
        let y = viewFrame.height - (windowRect.origin.y - viewFrame.origin.y)
        // Convert from screen to canvas space
        let canvasX = (x - currentPan.width) / currentScale
        let canvasY = (y - currentPan.height) / currentScale
        return CGPoint(x: canvasX, y: canvasY)
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
