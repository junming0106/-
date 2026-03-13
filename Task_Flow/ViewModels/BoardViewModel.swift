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

    // New column spawn position (from right-click)
    var newColumnPosition: CGPoint?

    func createDefaultColumns(context: ModelContext) {
        let defaults: [(String, String, String, Int, Double, Double)] = [
            ("Backlog", "tray.full", "purple", 0, 40, 0),
            ("To Do", "checklist.unchecked", "blue", 1, 40, 280),
            ("In Progress", "hammer", "orange", 2, 40, 560),
            ("Review", "eye", "teal", 3, 40, 840),
            ("Done", "checkmark.circle", "green", 4, 40, 1120),
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
        let colors = ColorOption.allCases
        let color = colors[order % colors.count]

        let pos = newColumnPosition ?? CGPoint(x: 40, y: Double(order) * 280)
        // Convert screen position to canvas position by removing canvas offset and column center offset
        let canvasX = pos.x - canvasOffset.width - 150
        let canvasY = pos.y - canvasOffset.height - 200

        let column = BoardColumn(
            title: "New Column",
            order: order,
            colorName: color.rawValue,
            positionX: canvasX,
            positionY: canvasY
        )
        context.insert(column)
        newColumnPosition = nil
    }

    func autoArrangeColumns(_ columns: [BoardColumn], connections: [CardConnection]) {
        let sorted = topologicalSort(columns: columns, connections: connections)
        let spacingX: Double = 380
        let spacingY: Double = 60

        // Lay out in a horizontal flow following connection order
        for (i, col) in sorted.enumerated() {
            col.positionX = 40 + Double(i) * spacingX
            col.positionY = spacingY
            col.order = i
        }
    }

    /// Topological sort: columns with no incoming edges first, following connection direction.
    /// Falls back to original order for disconnected columns.
    private func topologicalSort(columns: [BoardColumn], connections: [CardConnection]) -> [BoardColumn] {
        guard !connections.isEmpty else {
            return columns.sorted { $0.order < $1.order }
        }

        let ids = Set(columns.map(\.id))
        var inDegree: [UUID: Int] = [:]
        var adjacency: [UUID: [UUID]] = [:]
        for col in columns {
            inDegree[col.id] = 0
            adjacency[col.id] = []
        }
        for conn in connections {
            guard ids.contains(conn.fromColumnID), ids.contains(conn.toColumnID) else { continue }
            adjacency[conn.fromColumnID, default: []].append(conn.toColumnID)
            inDegree[conn.toColumnID, default: 0] += 1
        }

        // Kahn's algorithm
        var queue = columns.filter { inDegree[$0.id] == 0 }.sorted { $0.order < $1.order }
        var result: [BoardColumn] = []
        let colMap = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })

        while !queue.isEmpty {
            let col = queue.removeFirst()
            result.append(col)
            for nextID in adjacency[col.id] ?? [] {
                inDegree[nextID, default: 1] -= 1
                if inDegree[nextID] == 0, let next = colMap[nextID] {
                    queue.append(next)
                }
            }
        }

        // Append any remaining (cycle or disconnected)
        let resultIDs = Set(result.map(\.id))
        let remaining = columns.filter { !resultIDs.contains($0.id) }.sorted { $0.order < $1.order }
        result.append(contentsOf: remaining)

        return result
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
