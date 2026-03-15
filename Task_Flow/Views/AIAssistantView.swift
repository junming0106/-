import SwiftUI
import SwiftData

struct AIAssistantView: View {
    @Binding var isPresented: Bool
    let board: Board

    @Environment(\.modelContext) private var modelContext

    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("aiAPIKey") private var aiAPIKey = ""
    @AppStorage("aiModel") private var aiModel = ""

    @State private var prompt = ""
    @State private var messages: [AIMessage] = []
    @State private var isLoading = false
    @State private var chatHistory: [AIChatService.ChatMessage] = []
    @FocusState private var isInputFocused: Bool

    @Query(sort: \CardConnection.id) private var allConnections: [CardConnection]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            messageArea
            Divider().opacity(0.3)
            inputBar
        }
        .frame(width: 400, height: 520)
        .liquidGlass(cornerRadius: 20, elevated: true)
        .onAppear { isInputFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("AI Assistant")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            // Config status indicator
            if aiAPIKey.isEmpty || aiModel.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Please configure AI provider, API key, and model in Settings.")
            } else {
                Text(aiModel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 80)
            }

            Text("⌘⇧A")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button(action: { withAnimation(.spring(response: 0.3)) { isPresented = false } }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Messages

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id.uuidString)
                        }

                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .id("loading")
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: messages.count) {
                withAnimation {
                    proxy.scrollTo(messages.last?.id.uuidString ?? "loading", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything about your tasks...", text: $prompt)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }
                .disabled(isLoading)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        prompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
                            ? Color.secondary.opacity(0.3)
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("How can I help?")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                suggestionChip("Summarize my board")
                suggestionChip("What tasks are overdue?")
                suggestionChip("Move all Done tasks to Backlog")
                suggestionChip("Create a task in To Do")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button(action: {
            prompt = text
            sendMessage()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                Text(text)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let trimmed = prompt.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Check configuration
        guard !aiAPIKey.isEmpty, !aiModel.isEmpty else {
            messages.append(AIMessage(role: .assistant, content: "⚠️ Please configure your AI provider, API key, and model in **Settings → AI** first."))
            prompt = ""
            return
        }

        // Add user message
        messages.append(AIMessage(role: .user, content: trimmed))
        prompt = ""
        isLoading = true

        // Build board context for system prompt
        let boardConnections = allConnections.filter { conn in
            board.columns.contains(where: { $0.id == conn.fromColumnID || $0.id == conn.toColumnID })
        }
        let boardContext = AIChatService.buildBoardContext(
            boardName: board.name,
            columns: board.columns,
            connections: boardConnections,
            workspaces: board.workspaces
        )
        let systemPrompt = AIChatService.buildSystemPrompt(boardContext: boardContext)

        // Build chat history for API
        chatHistory.append(AIChatService.ChatMessage(role: "user", content: trimmed))

        let apiMessages = [AIChatService.ChatMessage(role: "system", content: systemPrompt)] + chatHistory

        let provider = AIModelService.Provider(rawValue: aiProvider) ?? .openai
        let key = aiAPIKey
        let model = aiModel

        Task {
            do {
                let response = try await AIChatService.shared.sendMessage(
                    messages: apiMessages,
                    provider: provider,
                    apiKey: key,
                    model: model
                )

                await MainActor.run {
                    handleAIResponse(response)
                }
            } catch {
                await MainActor.run {
                    messages.append(AIMessage(role: .assistant, content: "❌ \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Handle AI Response

    private func handleAIResponse(_ response: String) {
        let parsed = AIResponseParser.parse(response)

        // Add assistant text to chat history
        chatHistory.append(AIChatService.ChatMessage(role: "assistant", content: response))

        // Execute actions and collect results
        let executor = AIActionExecutor(context: modelContext, board: board)
        var resultLines: [String] = []

        // Display text segments
        let displayText = parsed.textSegments.joined(separator: "\n\n")

        for action in parsed.actions {
            let result = executor.execute(action)
            switch result {
            case .success(let msg):
                resultLines.append("✅ \(msg)")
            case .failure(let msg):
                resultLines.append("⚠️ \(msg)")
            case .info(let msg):
                resultLines.append(msg)
            }
        }

        // Compose final message
        var finalContent = displayText
        if !resultLines.isEmpty {
            if !finalContent.isEmpty { finalContent += "\n\n" }
            finalContent += resultLines.joined(separator: "\n")
        }

        if finalContent.isEmpty {
            finalContent = response // Fallback to raw response
        }

        messages.append(AIMessage(role: .assistant, content: finalContent))
        isLoading = false
    }
}

// MARK: - Data

struct AIMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role { case user, assistant }
}

// MARK: - Bubble

struct MessageBubble: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(.init(message.content)) // Supports Markdown
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(message.role == .user
                            ? Color.accentColor.opacity(0.12)
                            : Color.primary.opacity(0.04))
                )

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
