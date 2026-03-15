import Foundation
import SwiftData

/// Handles AI chat API calls with board context and structured action responses.
actor AIChatService {
    static let shared = AIChatService()

    // MARK: - System Prompt

    /// Builds the system prompt with current board context.
    static func buildSystemPrompt(boardContext: String) -> String {
        """
        You are TaskFlow AI Assistant — a smart helper embedded in a Kanban board app.

        ## Your Capabilities
        You can answer questions about the user's board AND perform actions on it.
        Always respond in the same language the user uses.

        ## Current Board State
        \(boardContext)

        ## Action Format
        When you need to perform actions (create, update, delete, move tasks/columns), wrap EACH action in `[ACTION]...[/ACTION]` tags containing valid JSON.
        You can include multiple actions in one response. Always include friendly explanation text around your actions.

        ### Available Actions

        **Create Task:**
        ```
        [ACTION]{"type":"create_task","column":"<column title>","title":"<task title>","description":"<optional>","priority":"<urgent|high|medium|low>","dueDate":"<YYYY-MM-DD>","tags":["tag1"],"colorName":"<optional>"}[/ACTION]
        ```

        **Update Task:**
        ```
        [ACTION]{"type":"update_task","taskTitle":"<existing task title>","newTitle":"<optional>","description":"<optional>","priority":"<optional>","dueDate":"<optional>","tags":["optional"],"colorName":"<optional>"}[/ACTION]
        ```

        **Delete Task:**
        ```
        [ACTION]{"type":"delete_task","taskTitle":"<task title>"}[/ACTION]
        ```

        **Move Task:**
        ```
        [ACTION]{"type":"move_task","taskTitle":"<task title>","toColumn":"<target column title>"}[/ACTION]
        ```

        **Create Column** (optionally assign to a workspace):
        ```
        [ACTION]{"type":"create_column","title":"<column title>","colorName":"<optional>","iconName":"<optional SF Symbol>","workspace":"<optional workspace name>"}[/ACTION]
        ```

        **Delete Column:**
        ```
        [ACTION]{"type":"delete_column","columnTitle":"<column title>"}[/ACTION]
        ```

        **Connect Columns** (create a visual connection/arrow between two columns):
        ```
        [ACTION]{"type":"connect_columns","fromColumn":"<source column title>","toColumn":"<target column title>","colorName":"<optional>"}[/ACTION]
        ```

        **Create Board** (create a new board in the sidebar):
        ```
        [ACTION]{"type":"create_board","name":"<board name>","iconName":"<optional SF Symbol>","colorName":"<optional>"}[/ACTION]
        ```

        **Update Board** (rename or change board appearance):
        ```
        [ACTION]{"type":"update_board","boardName":"<optional, defaults to current board>","newName":"<optional>","iconName":"<optional>","colorName":"<optional>"}[/ACTION]
        ```

        **Create Workspace** (a container that groups columns visually on the canvas):
        ```
        [ACTION]{"type":"create_workspace","name":"<workspace name>","width":<optional number>,"height":<optional number>}[/ACTION]
        ```

        **Query Tasks** (returns filtered task list to user):
        ```
        [ACTION]{"type":"query_tasks","column":"<optional>","priority":"<optional>","hasOverdue":true,"tag":"<optional>"}[/ACTION]
        ```

        **Board Summary** (returns full board overview):
        ```
        [ACTION]{"type":"board_summary"}[/ACTION]
        ```

        ## Terminology
        - **Board**: A top-level project container shown in the sidebar. Each board has its own columns, workspaces, and connections.
        - **Column** (字卡集): A vertical list that holds task cards. Columns are the main organizational unit.
        - **Task** (待辦項目/todo): An individual work item inside a column.
        - **Workspace**: A visual container on the canvas that groups columns together.
        - **Connection**: A visual arrow linking one column to another, representing workflow or dependency.
        - When user says "connect A to B", use connect_columns (NOT move_task).
        - When user says "move task X to column Y", use move_task.

        ## Rules
        1. If the user asks a question (e.g. "what tasks are in progress?"), answer with text. Use query_tasks action only if you need to highlight specific filtered results.
        2. If the user asks to change something, use the appropriate action AND explain what you did.
        3. For destructive actions (delete), confirm with the user first unless they're explicit.
        4. Match task/column names case-insensitively. If ambiguous, ask the user to clarify.
        5. Keep responses concise and helpful.
        6. Never fabricate tasks that don't exist in the board state above.
        7. You can chain multiple actions in one response (e.g. create workspace + create column in it + create task in it).
        8. When creating a column inside a newly created workspace in the same response, use the workspace name you just created.
        """
    }

    /// Builds a snapshot of the current board for the system prompt.
    static func buildBoardContext(
        boardName: String,
        columns: [BoardColumn],
        connections: [CardConnection],
        workspaces: [Workspace] = []
    ) -> String {
        var lines: [String] = []
        lines.append("Board: \(boardName)")
        lines.append("Columns: \(columns.count)")
        if !workspaces.isEmpty {
            lines.append("Workspaces: \(workspaces.map(\.name).joined(separator: ", "))")
        }
        lines.append("")

        let sorted = columns.sorted { $0.order < $1.order }
        for col in sorted {
            let tasks = col.sortedTasks
            var colHeader = "### Column: \(col.title) (\(tasks.count) tasks)"
            if let ws = col.workspace {
                colHeader += " [in workspace: \(ws.name)]"
            }
            lines.append(colHeader)
            if col.wipLimit > 0 {
                lines.append("  WIP Limit: \(col.wipLimit)")
            }
            for task in tasks {
                var taskLine = "  - [\(task.priority.rawValue)] \(task.title)"
                if let due = task.dueDate {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    taskLine += " (due: \(formatter.string(from: due)))"
                    if due < Date() {
                        taskLine += " ⚠️ OVERDUE"
                    }
                }
                if !task.tags.isEmpty {
                    taskLine += " #\(task.tags.joined(separator: " #"))"
                }
                if !task.taskDescription.isEmpty {
                    taskLine += "\n    Description: \(task.taskDescription)"
                }
                // Sub-tasks
                let subs = task.subtasks
                if !subs.isEmpty {
                    let done = subs.filter { $0.isCompleted }.count
                    taskLine += "\n    Sub-tasks: \(done)/\(subs.count) completed"
                }
                lines.append(taskLine)
            }
            lines.append("")
        }

        if !connections.isEmpty {
            lines.append("### Connections")
            for conn in connections {
                let from = sorted.first(where: { $0.id == conn.fromColumnID })?.title ?? "?"
                let to = sorted.first(where: { $0.id == conn.toColumnID })?.title ?? "?"
                lines.append("  \(from) → \(to)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Send Message

    struct ChatMessage {
        let role: String  // "system", "user", "assistant"
        let content: String
    }

    /// Sends a chat request to the configured AI provider.
    func sendMessage(
        messages: [ChatMessage],
        provider: AIModelService.Provider,
        apiKey: String,
        model: String
    ) async throws -> String {
        switch provider {
        case .openai:
            return try await sendOpenAI(messages: messages, apiKey: apiKey, model: model)
        case .anthropic:
            return try await sendAnthropic(messages: messages, apiKey: apiKey, model: model)
        case .gemini:
            return try await sendGemini(messages: messages, apiKey: apiKey, model: model)
        case .custom:
            throw ChatError.unsupportedProvider
        }
    }

    // MARK: - OpenAI

    private func sendOpenAI(messages: [ChatMessage], apiKey: String, model: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatError.invalidResponse
        }
        return content
    }

    // MARK: - Anthropic

    private func sendAnthropic(messages: [ChatMessage], apiKey: String, model: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        // Anthropic: system is separate, messages are user/assistant only
        let systemMsg = messages.first(where: { $0.role == "system" })?.content ?? ""
        let chatMessages = messages.filter { $0.role != "system" }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemMsg,
            "messages": chatMessages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ChatError.invalidResponse
        }
        return text
    }

    // MARK: - Gemini

    private func sendGemini(messages: [ChatMessage], apiKey: String, model: String) async throws -> String {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        // Gemini: system instruction separate, contents are user/model
        let systemMsg = messages.first(where: { $0.role == "system" })?.content ?? ""
        let chatMessages = messages.filter { $0.role != "system" }

        var body: [String: Any] = [
            "contents": chatMessages.map {
                [
                    "role": $0.role == "assistant" ? "model" : "user",
                    "parts": [["text": $0.content]]
                ]
            }
        ]
        if !systemMsg.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemMsg]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw ChatError.invalidResponse
        }
        return text
    }

    // MARK: - Helpers

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return
        case 401: throw ChatError.invalidAPIKey
        case 429: throw ChatError.rateLimited
        default: throw ChatError.httpError(http.statusCode)
        }
    }

    enum ChatError: LocalizedError {
        case unsupportedProvider
        case invalidAPIKey
        case rateLimited
        case invalidResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedProvider: return "This provider is not supported for chat."
            case .invalidAPIKey: return "Invalid API key."
            case .rateLimited: return "Rate limited. Please wait and try again."
            case .invalidResponse: return "Unexpected response from AI."
            case .httpError(let code): return "Server error (HTTP \(code))."
            }
        }
    }
}
