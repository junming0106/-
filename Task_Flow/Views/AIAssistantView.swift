import SwiftUI

struct AIAssistantView: View {
    @Binding var isPresented: Bool
    @State private var prompt = ""
    @State private var messages: [AIMessage] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            messageArea
            Divider().opacity(0.3)
            inputBar
        }
        .frame(width: 380, height: 480)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if messages.isEmpty {
                    emptyState
                } else {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
            }
            .padding(16)
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

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(prompt.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
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
                suggestionChip("Summarize my tasks")
                suggestionChip("What's overdue?")
                suggestionChip("Suggest next priorities")
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
    }

    private func sendMessage() {
        let trimmed = prompt.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        messages.append(AIMessage(role: .user, content: trimmed))
        prompt = ""

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            messages.append(AIMessage(
                role: .assistant,
                content: "This is a placeholder response. AI integration coming soon — you'll be able to ask about tasks, get summaries, and manage your board with natural language."
            ))
        }
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

            Text(message.content)
                .font(.body)
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
