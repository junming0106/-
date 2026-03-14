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

    func createDefaultColumns(context: ModelContext) {
        let defaults: [(String, String, String, Int, Double, Double)] = [
            ("Backlog", "tray.full", "purple", 0, 0, 40),
            ("To Do", "checklist.unchecked", "blue", 1, 400, 40),
            ("In Progress", "hammer", "orange", 2, 800, 40),
            ("Review", "eye", "teal", 3, 1200, 40),
            ("Done", "checkmark.circle", "green", 4, 1600, 40),
        ]

        for (title, icon, color, order, x, y) in defaults {
            let column = BoardColumn(
                title: title, order: order,
                colorName: color, iconName: icon,
                positionX: x, positionY: y
            )
            context.insert(column)
        }
    }

    func createColumnAtPosition(context: ModelContext, columns: [BoardColumn], canvasOffset: CGSize) {
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
        context.insert(column)
        newColumnPosition = nil
    }

    func autoArrangeColumns(_ columns: [BoardColumn], connections: [CardConnection]) {
        guard !columns.isEmpty else { return }

        let spacingX: Double = 400
        let spacingY: Double = 300
        let originX: Double = 60
        let originY: Double = 60

        let ids = Set(columns.map(\.id))
        let colMap = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })

        // Filter valid connections within this board
        let validConns = connections.filter { ids.contains($0.fromColumnID) && ids.contains($0.toColumnID) }

        // Build adjacency (parent → children) and inDegree
        var children: [UUID: [UUID]] = [:]
        var inDegree: [UUID: Int] = [:]
        for col in columns {
            children[col.id] = []
            inDegree[col.id] = 0
        }
        for conn in validConns {
            children[conn.fromColumnID, default: []].append(conn.toColumnID)
            inDegree[conn.toColumnID, default: 0] += 1
        }

        // Columns that participate in at least one connection
        let connectedIDs = Set(validConns.flatMap { [$0.fromColumnID, $0.toColumnID] })
        let isolated = columns.filter { !connectedIDs.contains($0.id) }
            .sorted { $0.order < $1.order }

        // No connections → all columns in a horizontal row (left to right)
        if validConns.isEmpty {
            for (i, col) in columns.sorted(by: { $0.order < $1.order }).enumerated() {
                col.positionX = originX + Double(i) * spacingX
                col.positionY = originY
                col.order = i
            }
            return
        }

        // Roots = connected columns with no incoming edges
        let roots = columns
            .filter { connectedIDs.contains($0.id) && inDegree[$0.id] == 0 }
            .sorted { $0.order < $1.order }

        // Tree layout via DFS: assign Y slots bottom-up so siblings are vertically stacked
        // and parent is vertically centred between its first and last child.
        var positions: [UUID: CGPoint] = [:]
        var nextYSlot: Double = originY
        var visited = Set<UUID>()

        func layoutNode(_ id: UUID, depth: Int) {
            guard !visited.contains(id) else { return }
            visited.insert(id)

            let childIDs = (children[id] ?? []).sorted {
                (colMap[$0]?.order ?? 0) < (colMap[$1]?.order ?? 0)
            }

            // Only consider children not yet placed by another parent's subtree
            let unvisitedChildren = childIDs.filter { !visited.contains($0) }

            if unvisitedChildren.isEmpty {
                // Leaf or all children already placed → claim own Y slot
                positions[id] = CGPoint(x: originX + Double(depth) * spacingX, y: nextYSlot)
                nextYSlot += spacingY
            } else {
                // Recurse into unvisited children first
                for childID in unvisitedChildren {
                    layoutNode(childID, depth: depth + 1)
                }
                // Centre this node between its first and last newly-placed child
                let firstY = positions[unvisitedChildren.first!].map { Double($0.y) } ?? nextYSlot
                let lastY  = positions[unvisitedChildren.last!].map { Double($0.y) } ?? nextYSlot
                positions[id] = CGPoint(x: originX + Double(depth) * spacingX, y: (firstY + lastY) / 2)
            }
        }

        for root in roots { layoutNode(root.id, depth: 0) }

        // Any connected node not yet visited (cycle fallback) — place sequentially
        for col in columns where connectedIDs.contains(col.id) && !visited.contains(col.id) {
            positions[col.id] = CGPoint(x: originX, y: nextYSlot)
            nextYSlot += spacingY
        }

        // Isolated columns: horizontal row below the tree (left to right)
        let maxTreeY = positions.values.map { Double($0.y) }.max() ?? originY
        let isolatedY = maxTreeY + spacingY

        for (i, col) in isolated.enumerated() {
            positions[col.id] = CGPoint(x: originX + Double(i) * spacingX, y: isolatedY)
        }

        // Write back positions and order
        let allSorted = columns.sorted {
            let pa = positions[$0.id] ?? .zero
            let pb = positions[$1.id] ?? .zero
            return pa.x != pb.x ? pa.x < pb.x : pa.y < pb.y
        }
        for (i, col) in allSorted.enumerated() {
            col.positionX = positions[col.id].map { Double($0.x) } ?? originX
            col.positionY = positions[col.id].map { Double($0.y) } ?? originY
            col.order = i
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
