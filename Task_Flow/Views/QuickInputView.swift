import SwiftUI
import SwiftData

/// The SwiftUI content inside the floating quick-input panel.
/// Provides a compact AI chat for adding tasks, querying boards, etc.
struct QuickInputView: View {
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.order) private var boards: [Board]

    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("aiAPIKey") private var aiAPIKey = ""
    @AppStorage("aiModel") private var aiModel = ""

    @State private var prompt = ""
    @State private var selectedBoardID: UUID?
    @State private var messages: [QuickMessage] = []
    @State private var isLoading = false
    @State private var chatHistory: [AIChatService.ChatMessage] = []
    @FocusState private var isInputFocused: Bool

    @Query(sort: \CardConnection.id) private var allConnections: [CardConnection]

    private var selectedBoard: Board? {
        if let id = selectedBoardID {
            return boards.first { $0.id == id }
        }
        return boards.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider().opacity(0.3)

            // Board picker
            boardPicker

            Divider().opacity(0.3)

            // Messages
            messageArea

            Divider().opacity(0.3)

            // Input
            inputBar
        }
        .frame(width: 520, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .onAppear {
            isInputFocused = true
            if selectedBoardID == nil {
                selectedBoardID = boards.first?.id
            }
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Quick Input")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text("⌃⇧Space")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Board Picker

    private var boardPicker: some View {
        HStack(spacing: 8) {
            Text("Board:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { selectedBoard?.id ?? UUID() },
                set: { selectedBoardID = $0 }
            )) {
                ForEach(boards) { board in
                    HStack(spacing: 4) {
                        Image(systemName: board.iconName)
                        Text(board.name)
                    }
                    .tag(board.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            Spacer()

            if let board = selectedBoard {
                Text("\(board.columns.count) columns")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Messages

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        quickEmptyState
                    } else {
                        ForEach(messages) { msg in
                            quickBubble(msg)
                                .id(msg.id.uuidString)
                        }

                        if isLoading {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .id("loading")
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) {
                withAnimation {
                    proxy.scrollTo(messages.last?.id.uuidString ?? "loading", anchor: .bottom)
                }
            }
        }
    }

    private var quickEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Text("Quick commands")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                quickChip("Add a task \"Fix login bug\" to To Do")
                quickChip("What's overdue?")
                quickChip("Create a new column called Testing")
                quickChip("Board summary")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func quickChip(_ text: String) -> some View {
        Button(action: {
            prompt = text
            sendMessage()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9))
                Text(text)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func quickBubble(_ msg: QuickMessage) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 60) }

            VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 2) {
                Text(.init(msg.content))
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(msg.isUser
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.04))
                    )
            }

            if !msg.isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type a command or question...", text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isInputFocused)
                .onSubmit { sendMessage() }
                .disabled(isLoading)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Send

    private func sendMessage() {
        let trimmed = prompt.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        guard !aiAPIKey.isEmpty, !aiModel.isEmpty else {
            messages.append(QuickMessage(isUser: false, content: "⚠️ Please configure AI in **Settings → AI** first."))
            prompt = ""
            return
        }

        guard let board = selectedBoard else {
            messages.append(QuickMessage(isUser: false, content: "⚠️ No board selected."))
            prompt = ""
            return
        }

        messages.append(QuickMessage(isUser: true, content: trimmed))
        prompt = ""
        isLoading = true

        // Build context
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
                    handleResponse(response, board: board)
                }
            } catch {
                await MainActor.run {
                    messages.append(QuickMessage(isUser: false, content: "❌ \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }

    private func handleResponse(_ response: String, board: Board) {
        let parsed = AIResponseParser.parse(response)
        chatHistory.append(AIChatService.ChatMessage(role: "assistant", content: response))

        let executor = AIActionExecutor(context: modelContext, board: board)
        var resultLines: [String] = []
        let displayText = parsed.textSegments.joined(separator: "\n\n")

        for action in parsed.actions {
            let result = executor.execute(action)
            switch result {
            case .success(let msg): resultLines.append("✅ \(msg)")
            case .failure(let msg): resultLines.append("⚠️ \(msg)")
            case .info(let msg): resultLines.append(msg)
            }
        }

        var finalContent = displayText
        if !resultLines.isEmpty {
            if !finalContent.isEmpty { finalContent += "\n\n" }
            finalContent += resultLines.joined(separator: "\n")
        }
        if finalContent.isEmpty { finalContent = response }

        messages.append(QuickMessage(isUser: false, content: finalContent))
        isLoading = false
    }
}

// MARK: - Data

struct QuickMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let content: String
}
