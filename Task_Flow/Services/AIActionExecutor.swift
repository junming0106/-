import Foundation
import SwiftData

/// Executes parsed AIActions against the board's data model.
struct AIActionExecutor {

    let context: ModelContext
    let board: Board

    /// Callback to notify the UI when a new board is created (so sidebar can update)
    var onBoardCreated: ((Board) -> Void)?

    /// Executes an action and returns a user-facing result description.
    @discardableResult
    func execute(_ action: AIAction) -> ActionResult {
        context.undoManager?.beginUndoGrouping()
        defer { context.undoManager?.endUndoGrouping() }

        switch action {
        case .createTask(let payload):
            return executeCreateTask(payload)
        case .updateTask(let payload):
            return executeUpdateTask(payload)
        case .deleteTask(let payload):
            return executeDeleteTask(payload)
        case .moveTask(let payload):
            return executeMoveTask(payload)
        case .createColumn(let payload):
            return executeCreateColumn(payload)
        case .deleteColumn(let payload):
            return executeDeleteColumn(payload)
        case .connectColumns(let payload):
            return executeConnectColumns(payload)
        case .createBoard(let payload):
            return executeCreateBoard(payload)
        case .updateBoard(let payload):
            return executeUpdateBoard(payload)
        case .createWorkspace(let payload):
            return executeCreateWorkspace(payload)
        case .boardSummary:
            return executeBoardSummary()
        case .queryTasks(let payload):
            return executeQueryTasks(payload)
        }
    }

    // MARK: - Create Task

    private func executeCreateTask(_ payload: AIAction.CreateTask) -> ActionResult {
        guard let column = findColumn(titled: payload.column) else {
            return .failure("Column \"\(payload.column)\" not found.")
        }

        let priority = parsePriority(payload.priority)
        let dueDate = parseDate(payload.dueDate)

        let task = TaskItem(
            title: payload.title,
            taskDescription: payload.description ?? "",
            priority: priority,
            dueDate: dueDate,
            tags: payload.tags ?? [],
            order: column.tasks.count
        )
        if let color = payload.colorName {
            task.colorName = color
        }
        task.column = column
        context.insert(task)

        return .success("Created task \"\(payload.title)\" in \(column.title).")
    }

    // MARK: - Update Task

    private func executeUpdateTask(_ payload: AIAction.UpdateTask) -> ActionResult {
        guard let task = findTask(titled: payload.taskTitle) else {
            return .failure("Task \"\(payload.taskTitle)\" not found.")
        }

        if let newTitle = payload.newTitle { task.title = newTitle }
        if let desc = payload.description { task.taskDescription = desc }
        if let p = payload.priority { task.priority = parsePriority(p) }
        if let d = payload.dueDate { task.dueDate = parseDate(d) }
        if let tags = payload.tags { task.tags = tags }
        if let color = payload.colorName { task.colorName = color }
        task.updatedAt = Date()

        return .success("Updated task \"\(task.title)\".")
    }

    // MARK: - Delete Task

    private func executeDeleteTask(_ payload: AIAction.DeleteTask) -> ActionResult {
        guard let task = findTask(titled: payload.taskTitle) else {
            return .failure("Task \"\(payload.taskTitle)\" not found.")
        }

        let title = task.title
        context.delete(task)
        return .success("Deleted task \"\(title)\".")
    }

    // MARK: - Move Task

    private func executeMoveTask(_ payload: AIAction.MoveTask) -> ActionResult {
        guard let task = findTask(titled: payload.taskTitle) else {
            return .failure("Task \"\(payload.taskTitle)\" not found.")
        }
        guard let targetColumn = findColumn(titled: payload.toColumn) else {
            return .failure("Column \"\(payload.toColumn)\" not found.")
        }

        task.column = targetColumn
        task.order = targetColumn.tasks.count
        task.updatedAt = Date()

        return .success("Moved \"\(task.title)\" to \(targetColumn.title).")
    }

    // MARK: - Create Column

    private func executeCreateColumn(_ payload: AIAction.CreateColumn) -> ActionResult {
        let columns = board.columns
        let column = BoardColumn(
            title: payload.title,
            order: columns.count,
            colorName: payload.colorName ?? "blue",
            iconName: payload.iconName ?? "list.bullet"
        )
        column.board = board

        // Assign to workspace if specified
        if let wsName = payload.workspace {
            if let ws = findWorkspace(titled: wsName) {
                column.workspace = ws
            }
            // If workspace not found, column is placed free on canvas
        }

        context.insert(column)

        var msg = "Created column \"\(payload.title)\""
        if let wsName = payload.workspace {
            msg += " in workspace \"\(wsName)\""
        }
        return .success(msg + ".")
    }

    // MARK: - Delete Column

    private func executeDeleteColumn(_ payload: AIAction.DeleteColumn) -> ActionResult {
        guard let column = findColumn(titled: payload.columnTitle) else {
            return .failure("Column \"\(payload.columnTitle)\" not found.")
        }

        let title = column.title
        let taskCount = column.tasks.count
        for task in column.tasks {
            for sub in task.subtasks {
                context.delete(sub)
            }
            context.delete(task)
        }
        context.delete(column)

        var msg = "Deleted column \"\(title)\""
        if taskCount > 0 {
            msg += " and its \(taskCount) task\(taskCount == 1 ? "" : "s")"
        }
        return .success(msg + ".")
    }

    // MARK: - Connect Columns

    private func executeConnectColumns(_ payload: AIAction.ConnectColumns) -> ActionResult {
        guard let fromCol = findColumn(titled: payload.fromColumn) else {
            return .failure("Column \"\(payload.fromColumn)\" not found.")
        }
        guard let toCol = findColumn(titled: payload.toColumn) else {
            return .failure("Column \"\(payload.toColumn)\" not found.")
        }
        if fromCol.id == toCol.id {
            return .failure("Cannot connect a column to itself.")
        }

        // Check if connection already exists
        let fromID = fromCol.id
        let toID = toCol.id
        let descriptor = FetchDescriptor<CardConnection>(
            predicate: #Predicate<CardConnection> {
                ($0.fromColumnID == fromID && $0.toColumnID == toID) ||
                ($0.fromColumnID == toID && $0.toColumnID == fromID)
            }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return .failure("Connection between \"\(payload.fromColumn)\" and \"\(payload.toColumn)\" already exists.")
        }

        let connection = CardConnection(
            fromColumnID: fromCol.id,
            toColumnID: toCol.id,
            colorName: payload.colorName ?? "gray"
        )
        connection.board = board
        context.insert(connection)

        return .success("Connected \"\(fromCol.title)\" → \"\(toCol.title)\".")
    }

    // MARK: - Create Board

    private func executeCreateBoard(_ payload: AIAction.CreateBoard) -> ActionResult {
        let newBoard = Board(
            name: payload.name,
            iconName: payload.iconName ?? Board.iconOptions.randomElement() ?? "rectangle.split.3x1",
            colorName: payload.colorName ?? "blue",
            order: 0 // Will be adjusted
        )
        context.insert(newBoard)
        onBoardCreated?(newBoard)

        return .success("Created new board \"\(payload.name)\".")
    }

    // MARK: - Update Board

    private func executeUpdateBoard(_ payload: AIAction.UpdateBoard) -> ActionResult {
        // If boardName specified, find that board; otherwise update current board
        let targetBoard: Board
        if let name = payload.boardName {
            // Try to find by name in current context
            let lower = name.lowercased()
            let descriptor = FetchDescriptor<Board>()
            guard let boards = try? context.fetch(descriptor),
                  let found = boards.first(where: { $0.name.lowercased() == lower }) else {
                return .failure("Board \"\(name)\" not found.")
            }
            targetBoard = found
        } else {
            targetBoard = board
        }

        if let newName = payload.newName { targetBoard.name = newName }
        if let icon = payload.iconName { targetBoard.iconName = icon }
        if let color = payload.colorName { targetBoard.colorName = color }

        return .success("Updated board \"\(targetBoard.name)\".")
    }

    // MARK: - Create Workspace

    private func executeCreateWorkspace(_ payload: AIAction.CreateWorkspace) -> ActionResult {
        let ws = Workspace(
            name: payload.name,
            positionX: -Workspace.padding,
            positionY: -Workspace.padding - 28,
            width: payload.width ?? Workspace.defaultWidth,
            height: payload.height ?? Workspace.defaultHeight,
            order: board.workspaces.count
        )
        ws.board = board
        context.insert(ws)

        return .success("Created workspace \"\(payload.name)\".")
    }

    // MARK: - Board Summary

    private func executeBoardSummary() -> ActionResult {
        let columns = board.columns.sorted { $0.order < $1.order }
        let totalTasks = columns.reduce(0) { $0 + $1.tasks.count }
        let overdue = columns.flatMap(\.tasks).filter {
            guard let due = $0.dueDate else { return false }
            return due < Date()
        }

        var lines: [String] = []
        lines.append("**\(board.name)** — \(columns.count) columns, \(totalTasks) tasks")
        if !overdue.isEmpty {
            lines.append("⚠️ \(overdue.count) overdue task\(overdue.count == 1 ? "" : "s")")
        }
        lines.append("")

        for col in columns {
            let tasks = col.sortedTasks
            lines.append("**\(col.title)** (\(tasks.count))")
            for task in tasks.prefix(10) {
                var line = "  • \(task.title)"
                if task.priority == .urgent || task.priority == .high {
                    line += " [\(task.priority.rawValue)]"
                }
                if let due = task.dueDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    line += " — due \(formatter.string(from: due))"
                    if due < Date() { line += " ⚠️" }
                }
                lines.append(line)
            }
            if tasks.count > 10 {
                lines.append("  ... and \(tasks.count - 10) more")
            }
        }

        return .info(lines.joined(separator: "\n"))
    }

    // MARK: - Query Tasks

    private func executeQueryTasks(_ payload: AIAction.QueryTasks) -> ActionResult {
        var tasks = board.columns.flatMap(\.tasks)

        // Filter by column
        if let colName = payload.column {
            if let col = findColumn(titled: colName) {
                tasks = Array(col.tasks)
            } else {
                return .failure("Column \"\(colName)\" not found.")
            }
        }

        // Filter by priority
        if let p = payload.priority {
            let priority = parsePriority(p)
            tasks = tasks.filter { $0.priority == priority }
        }

        // Filter overdue
        if payload.hasOverdue == true {
            tasks = tasks.filter {
                guard let due = $0.dueDate else { return false }
                return due < Date()
            }
        }

        // Filter by tag
        if let tag = payload.tag {
            let lower = tag.lowercased()
            tasks = tasks.filter { $0.tags.contains(where: { $0.lowercased() == lower }) }
        }

        if tasks.isEmpty {
            return .info("No matching tasks found.")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        var lines: [String] = ["Found \(tasks.count) task\(tasks.count == 1 ? "" : "s"):"]
        for task in tasks.sorted(by: { $0.order < $1.order }) {
            var line = "• **\(task.title)** [\(task.priority.rawValue)]"
            if let col = task.column {
                line += " in \(col.title)"
            }
            if let due = task.dueDate {
                line += " — due \(formatter.string(from: due))"
                if due < Date() { line += " ⚠️ OVERDUE" }
            }
            lines.append(line)
        }

        return .info(lines.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private func findColumn(titled title: String) -> BoardColumn? {
        let lower = title.lowercased()
        return board.columns.first { $0.title.lowercased() == lower }
    }

    private func findWorkspace(titled title: String) -> Workspace? {
        let lower = title.lowercased()
        return board.workspaces.first { $0.name.lowercased() == lower }
    }

    private func findTask(titled title: String) -> TaskItem? {
        let lower = title.lowercased()
        return board.columns
            .flatMap(\.tasks)
            .first { $0.title.lowercased() == lower }
    }

    private func parsePriority(_ value: String?) -> TaskPriority {
        guard let value else { return .medium }
        switch value.lowercased() {
        case "urgent": return .urgent
        case "high": return .high
        case "low": return .low
        default: return .medium
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }

    // MARK: - Result

    enum ActionResult {
        case success(String)   // Action executed, show confirmation
        case failure(String)   // Action failed, show error
        case info(String)      // Query result, display to user
    }
}
