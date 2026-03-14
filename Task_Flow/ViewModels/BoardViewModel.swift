import Foundation
import SwiftData
import SwiftUI

@Observable
final class BoardViewModel {
    var selectedTask: TaskItem?
    var showingNewTaskSheet = false
    var newTaskColumnTarget: BoardColumn?
    var showingNewColumnSheet = false
    var draggedTask: TaskItem?

    // Connection mode (column-to-column)
    var isConnecting = false
    var connectionSourceColumn: BoardColumn?

    // Column drag state (managed at board level to avoid gesture conflicts)
    var draggingColumnID: UUID?
    var columnDragOffset: CGSize = .zero

    // Workspace drag state
    var draggingWorkspaceID: UUID?
    var workspaceDragOffset: CGSize = .zero

    // New column spawn position (from right-click)
    var newColumnPosition: CGPoint?

    func createDefaultColumns(context: ModelContext, board: Board) {
        let defaults: [(String, String, String, Int, Double, Double)] = [
            ("Backlog", "tray.full", "purple", 0, 0, 0),
            ("To Do", "checklist.unchecked", "blue", 1, 400, 0),
            ("In Progress", "hammer", "orange", 2, 800, 0),
            ("Review", "eye", "teal", 3, 1200, 0),
            ("Done", "checkmark.circle", "green", 4, 1600, 0),
        ]

        // Create a workspace to group all default columns
        let ws = Workspace(
            name: "Work Status",
            positionX: -Workspace.padding,
            positionY: -Workspace.padding - 28,
            width: Double(defaults.count) * 400 + Workspace.padding * 2,
            height: 300 + Workspace.padding * 2 + 28,
            order: 0
        )
        ws.board = board
        context.insert(ws)

        for (title, icon, color, order, x, y) in defaults {
            let column = BoardColumn(
                title: title, order: order,
                colorName: color, iconName: icon,
                positionX: x, positionY: y
            )
            column.board = board
            column.workspace = ws
            context.insert(column)
        }
    }

    func createColumnAtPosition(context: ModelContext, columns: [BoardColumn], canvasOffset: CGSize, board: Board) {
        let order = columns.count

        let pos = newColumnPosition ?? CGPoint(x: 40, y: Double(order) * 280)
        let canvasX = pos.x - canvasOffset.width - 150
        let canvasY = pos.y - canvasOffset.height - 200

        let column = BoardColumn(
            title: "New Column",
            order: order,
            positionX: canvasX,
            positionY: canvasY
        )
        column.board = board
        context.insert(column)
        newColumnPosition = nil
    }

    func autoArrangeColumns(_ columns: [BoardColumn], connections: [CardConnection], workspaces: [Workspace]) {
        guard !columns.isEmpty else { return }

        let spacingX: Double = 400
        let spacingY: Double = 300
        let colWidth: Double = 320
        let groupGap: Double = 120  // vertical gap between workspace groups

        // Group columns by workspace (nil = free on canvas)
        var groups: [UUID?: [BoardColumn]] = [:]
        for col in columns {
            groups[col.workspace?.id, default: []].append(col)
        }

        // Sort workspace groups by order, free columns last
        let sortedWorkspaces = workspaces
            .filter { groups[$0.id] != nil }
            .sorted { $0.order < $1.order }

        // Track cumulative Y for stacking workspace groups vertically
        var nextGroupY: Double = 0

        // Arrange workspace groups first, then free columns
        var orderedKeys: [UUID?] = sortedWorkspaces.map { $0.id }
        if groups[nil] != nil { orderedKeys.append(nil) }

        for wsID in orderedKeys {
            guard let groupCols = groups[wsID] else { continue }
            let ws = wsID.flatMap { id in workspaces.first(where: { $0.id == id }) }

            let originX: Double
            let originY: Double
            let maxWidth: Double

            if let ws = ws {
                let pad = Workspace.padding
                originX = ws.positionX + pad
                // Stable origin from current workspace position
                let stableY = ws.positionY + pad + 28 - 50
                if sortedWorkspaces.count > 1 && nextGroupY > 0 && nextGroupY > ws.positionY {
                    // Multiple workspaces: reposition to stack below previous group
                    ws.positionY = nextGroupY
                    originY = nextGroupY + pad + 28 - 50
                } else {
                    originY = stableY
                }
                maxWidth = ws.width - pad * 2
            } else {
                // Free columns: below all workspace groups
                originX = 60
                originY = max(0, nextGroupY > 0 ? nextGroupY - 200 : 0)
                maxWidth = .infinity
            }

            let groupIDs = Set(groupCols.map(\.id))
            let colMap = Dictionary(uniqueKeysWithValues: groupCols.map { ($0.id, $0) })
            let validConns = connections.filter { groupIDs.contains($0.fromColumnID) && groupIDs.contains($0.toColumnID) }

            // Build adjacency
            var children: [UUID: [UUID]] = [:]
            var inDegree: [UUID: Int] = [:]
            for col in groupCols {
                children[col.id] = []
                inDegree[col.id] = 0
            }
            for conn in validConns {
                children[conn.fromColumnID, default: []].append(conn.toColumnID)
                inDegree[conn.toColumnID, default: 0] += 1
            }

            let connectedIDs = Set(validConns.flatMap { [$0.fromColumnID, $0.toColumnID] })
            let isolated = groupCols.filter { !connectedIDs.contains($0.id) }.sorted { $0.order < $1.order }

            // No connections → grid layout with wrapping
            if validConns.isEmpty {
                let perRow = maxWidth.isInfinite ? groupCols.count : max(1, 1 + Int((maxWidth - colWidth) / spacingX))
                for (i, col) in groupCols.sorted(by: { $0.order < $1.order }).enumerated() {
                    col.positionX = originX + Double(i % perRow) * spacingX
                    col.positionY = originY + Double(i / perRow) * spacingY
                    col.order = i
                }
            } else {
                // Tree layout via DFS
                var positions: [UUID: CGPoint] = [:]
                var nextYSlot: Double = originY
                var visited = Set<UUID>()

                let roots = groupCols
                    .filter { connectedIDs.contains($0.id) && inDegree[$0.id] == 0 }
                    .sorted { $0.order < $1.order }

                func layoutNode(_ id: UUID, depth: Int) {
                    guard !visited.contains(id) else { return }
                    visited.insert(id)
                    let childIDs = (children[id] ?? []).sorted { (colMap[$0]?.order ?? 0) < (colMap[$1]?.order ?? 0) }
                    let unvisited = childIDs.filter { !visited.contains($0) }
                    if unvisited.isEmpty {
                        positions[id] = CGPoint(x: originX + Double(depth) * spacingX, y: nextYSlot)
                        nextYSlot += spacingY
                    } else {
                        for childID in unvisited { layoutNode(childID, depth: depth + 1) }
                        let firstY = positions[unvisited.first!].map { Double($0.y) } ?? nextYSlot
                        let lastY = positions[unvisited.last!].map { Double($0.y) } ?? nextYSlot
                        positions[id] = CGPoint(x: originX + Double(depth) * spacingX, y: (firstY + lastY) / 2)
                    }
                }

                for root in roots { layoutNode(root.id, depth: 0) }

                // Cycle fallback
                for col in groupCols where connectedIDs.contains(col.id) && !visited.contains(col.id) {
                    positions[col.id] = CGPoint(x: originX, y: nextYSlot)
                    nextYSlot += spacingY
                }

                // Isolated: grid below tree with wrapping
                let maxTreeY = positions.values.map { Double($0.y) }.max() ?? originY
                let isolatedY = maxTreeY + spacingY
                let perRow = maxWidth.isInfinite ? max(isolated.count, 1) : max(1, 1 + Int((maxWidth - colWidth) / spacingX))
                for (i, col) in isolated.enumerated() {
                    positions[col.id] = CGPoint(x: originX + Double(i % perRow) * spacingX, y: isolatedY + Double(i / perRow) * spacingY)
                }

                // Write back
                let sorted = groupCols.sorted {
                    let pa = positions[$0.id] ?? .zero; let pb = positions[$1.id] ?? .zero
                    return pa.x != pb.x ? pa.x < pb.x : pa.y < pb.y
                }
                for (i, col) in sorted.enumerated() {
                    col.positionX = positions[col.id].map { Double($0.x) } ?? originX
                    col.positionY = positions[col.id].map { Double($0.y) } ?? originY
                    col.order = i
                }
            }

            // Fit workspace exactly to arranged columns (shrink + grow)
            if let ws = ws {
                var estimatedFrames: [UUID: CGRect] = [:]
                for col in groupCols {
                    let cx = col.positionX + 160
                    let cy = col.positionY + 200
                    estimatedFrames[col.id] = CGRect(x: cx - 160, y: cy - 150, width: 320, height: 300)
                }
                ws.fitToColumns(columnFrames: estimatedFrames)
                nextGroupY = ws.positionY + ws.height + groupGap
            } else {
                // Track bottom of free columns for potential future use
                let maxY = groupCols.map { $0.positionY + 200 + 150 }.max() ?? 0
                nextGroupY = maxY + groupGap
            }
        }
    }

    func addTask(
        title: String,
        description: String,
        priority: TaskPriority,
        dueDate: Date?,
        tags: [String],
        to column: BoardColumn,
        context: ModelContext
    ) {
        let order = column.tasks.count
        let task = TaskItem(
            title: title,
            taskDescription: description,
            priority: priority,
            dueDate: dueDate,
            tags: tags,
            order: order
        )
        task.column = column
        context.insert(task)
    }

    func moveTask(_ task: TaskItem, to targetColumn: BoardColumn, at index: Int) {
        task.column = targetColumn
        task.updatedAt = Date()

        let sorted = targetColumn.sortedTasks.filter { $0.id != task.id }
        var reordered = Array(sorted)
        let clampedIndex = min(index, reordered.count)
        reordered.insert(task, at: clampedIndex)

        for (i, t) in reordered.enumerated() {
            t.order = i
        }
    }

    func deleteTask(_ task: TaskItem, context: ModelContext) {
        context.delete(task)
        if selectedTask?.id == task.id {
            selectedTask = nil
        }
    }

    func deleteColumn(_ column: BoardColumn, context: ModelContext) {
        let colID = column.id
        let descriptor = FetchDescriptor<CardConnection>(
            predicate: #Predicate<CardConnection> {
                $0.fromColumnID == colID || $0.toColumnID == colID
            }
        )
        if let connections = try? context.fetch(descriptor) {
            for conn in connections {
                context.delete(conn)
            }
        }
        context.delete(column)
    }

    // MARK: - Column Connections

    func startConnecting(from column: BoardColumn) {
        isConnecting = true
        connectionSourceColumn = column
    }

    func finishConnecting(to column: BoardColumn, context: ModelContext) {
        guard let source = connectionSourceColumn, source.id != column.id else {
            cancelConnecting()
            return
        }

        let fromID = source.id
        let toID = column.id
        let descriptor = FetchDescriptor<CardConnection>(
            predicate: #Predicate<CardConnection> {
                ($0.fromColumnID == fromID && $0.toColumnID == toID) ||
                ($0.fromColumnID == toID && $0.toColumnID == fromID)
            }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            cancelConnecting()
            return
        }

        let connection = CardConnection(fromColumnID: source.id, toColumnID: column.id)
        context.insert(connection)
        isConnecting = false
        connectionSourceColumn = nil
    }

    func cancelConnecting() {
        isConnecting = false
        connectionSourceColumn = nil
    }
}
