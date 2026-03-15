import Foundation

/// Structured actions the AI can return embedded in its response.
/// Format: text mixed with `[ACTION]{...}[/ACTION]` JSON blocks.
enum AIAction: Codable {
    case createTask(CreateTask)
    case updateTask(UpdateTask)
    case deleteTask(DeleteTask)
    case moveTask(MoveTask)
    case createColumn(CreateColumn)
    case deleteColumn(DeleteColumn)
    case connectColumns(ConnectColumns)
    case createBoard(CreateBoard)
    case updateBoard(UpdateBoard)
    case createWorkspace(CreateWorkspace)
    case boardSummary
    case queryTasks(QueryTasks)

    // MARK: - Action Payloads

    struct CreateTask: Codable {
        let column: String           // column title to add task to
        let title: String
        var description: String?
        var priority: String?        // "urgent", "high", "medium", "low"
        var dueDate: String?         // ISO 8601: "2026-03-20"
        var tags: [String]?
        var colorName: String?
    }

    struct UpdateTask: Codable {
        let taskTitle: String        // match by title (user-facing identifier)
        var newTitle: String?
        var description: String?
        var priority: String?
        var dueDate: String?
        var tags: [String]?
        var colorName: String?
    }

    struct DeleteTask: Codable {
        let taskTitle: String
    }

    struct MoveTask: Codable {
        let taskTitle: String
        let toColumn: String         // target column title
    }

    struct CreateColumn: Codable {
        let title: String
        var colorName: String?
        var iconName: String?
        var workspace: String?       // workspace name to place column in
    }

    struct DeleteColumn: Codable {
        let columnTitle: String
    }

    struct ConnectColumns: Codable {
        let fromColumn: String       // source column title
        let toColumn: String         // target column title
        var colorName: String?       // connection line color
    }

    struct CreateBoard: Codable {
        let name: String
        var iconName: String?
        var colorName: String?
    }

    struct UpdateBoard: Codable {
        var boardName: String?       // which board to update (nil = current)
        var newName: String?
        var iconName: String?
        var colorName: String?
    }

    struct CreateWorkspace: Codable {
        let name: String
        var width: Double?
        var height: Double?
    }

    struct QueryTasks: Codable {
        var column: String?          // filter by column title
        var priority: String?        // filter by priority
        var hasOverdue: Bool?        // only overdue tasks
        var tag: String?             // filter by tag
    }

    // MARK: - Coding

    private enum ActionType: String, Codable {
        case createTask = "create_task"
        case updateTask = "update_task"
        case deleteTask = "delete_task"
        case moveTask = "move_task"
        case createColumn = "create_column"
        case deleteColumn = "delete_column"
        case connectColumns = "connect_columns"
        case createBoard = "create_board"
        case updateBoard = "update_board"
        case createWorkspace = "create_workspace"
        case boardSummary = "board_summary"
        case queryTasks = "query_tasks"
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .createTask:
            self = .createTask(try CreateTask(from: decoder))
        case .updateTask:
            self = .updateTask(try UpdateTask(from: decoder))
        case .deleteTask:
            self = .deleteTask(try DeleteTask(from: decoder))
        case .moveTask:
            self = .moveTask(try MoveTask(from: decoder))
        case .createColumn:
            self = .createColumn(try CreateColumn(from: decoder))
        case .deleteColumn:
            self = .deleteColumn(try DeleteColumn(from: decoder))
        case .connectColumns:
            self = .connectColumns(try ConnectColumns(from: decoder))
        case .createBoard:
            self = .createBoard(try CreateBoard(from: decoder))
        case .updateBoard:
            self = .updateBoard(try UpdateBoard(from: decoder))
        case .createWorkspace:
            self = .createWorkspace(try CreateWorkspace(from: decoder))
        case .boardSummary:
            self = .boardSummary
        case .queryTasks:
            self = .queryTasks(try QueryTasks(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createTask(let payload):
            try container.encode(ActionType.createTask, forKey: .type)
            try payload.encode(to: encoder)
        case .updateTask(let payload):
            try container.encode(ActionType.updateTask, forKey: .type)
            try payload.encode(to: encoder)
        case .deleteTask(let payload):
            try container.encode(ActionType.deleteTask, forKey: .type)
            try payload.encode(to: encoder)
        case .moveTask(let payload):
            try container.encode(ActionType.moveTask, forKey: .type)
            try payload.encode(to: encoder)
        case .createColumn(let payload):
            try container.encode(ActionType.createColumn, forKey: .type)
            try payload.encode(to: encoder)
        case .deleteColumn(let payload):
            try container.encode(ActionType.deleteColumn, forKey: .type)
            try payload.encode(to: encoder)
        case .connectColumns(let payload):
            try container.encode(ActionType.connectColumns, forKey: .type)
            try payload.encode(to: encoder)
        case .createBoard(let payload):
            try container.encode(ActionType.createBoard, forKey: .type)
            try payload.encode(to: encoder)
        case .updateBoard(let payload):
            try container.encode(ActionType.updateBoard, forKey: .type)
            try payload.encode(to: encoder)
        case .createWorkspace(let payload):
            try container.encode(ActionType.createWorkspace, forKey: .type)
            try payload.encode(to: encoder)
        case .boardSummary:
            try container.encode(ActionType.boardSummary, forKey: .type)
        case .queryTasks(let payload):
            try container.encode(ActionType.queryTasks, forKey: .type)
            try payload.encode(to: encoder)
        }
    }
}

// MARK: - Response Parsing

struct AIResponseParser {
    /// Parses AI response text into display segments and actions.
    /// Actions are wrapped in `[ACTION]...[/ACTION]` blocks.
    struct ParsedResponse {
        let textSegments: [String]
        let actions: [AIAction]
    }

    static func parse(_ response: String) -> ParsedResponse {
        var segments: [String] = []
        var actions: [AIAction] = []

        let pattern = "\\[ACTION\\](.*?)\\[/ACTION\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return ParsedResponse(textSegments: [response], actions: [])
        }

        let nsRange = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, range: nsRange)

        var lastEnd = response.startIndex

        for match in matches {
            // Text before this action block
            if let beforeRange = Range(match.range, in: response) {
                let textBefore = String(response[lastEnd..<beforeRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !textBefore.isEmpty {
                    segments.append(textBefore)
                }
                lastEnd = beforeRange.upperBound
            }

            // Parse the JSON action
            if let jsonRange = Range(match.range(at: 1), in: response) {
                let jsonString = String(response[jsonRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = jsonString.data(using: .utf8),
                   let action = try? JSONDecoder().decode(AIAction.self, from: data) {
                    actions.append(action)
                }
            }
        }

        // Remaining text after last action
        let remaining = String(response[lastEnd...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            segments.append(remaining)
        }

        return ParsedResponse(textSegments: segments, actions: actions)
    }
}
