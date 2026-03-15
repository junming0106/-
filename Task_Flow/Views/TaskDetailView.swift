import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TaskItem]
    @State private var newSubtaskTitle = ""
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.3)
            sheetBody
        }
        .frame(width: 480, height: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .onAppear {
            hasDueDate = task.dueDate != nil
            dueDate = task.dueDate ?? Date()
        }
        .onChange(of: task.title) { task.updatedAt = Date() }
        .onChange(of: task.taskDescription) { task.updatedAt = Date() }
        .onChange(of: task.priority) { task.updatedAt = Date() }
        .onChange(of: hasDueDate) {
            task.dueDate = hasDueDate ? dueDate : nil
            task.updatedAt = Date()
        }
        .onChange(of: dueDate) {
            if hasDueDate {
                task.dueDate = dueDate
                task.updatedAt = Date()
            }
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.text.square")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Task Detail")
                    .font(.headline)
                    .fontWeight(.semibold)

                if let col = task.column {
                    Text("in \(col.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Body

    private var sheetBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                TextField("Task Title", text: $task.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.9))

                // Priority
                VStack(alignment: .leading, spacing: 6) {
                    Text("Priority")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            PriorityChip(
                                priority: p,
                                isSelected: task.priority == p
                            ) {
                                withAnimation(.spring(response: 0.2)) {
                                    task.priority = p
                                }
                            }
                        }
                    }
                }

                // Due Date
                VStack(alignment: .leading, spacing: 6) {
                    Text("Due Date")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    DueDateButton(
                        hasDueDate: $hasDueDate,
                        dueDate: $dueDate
                    )
                }

                // Created
                VStack(alignment: .leading, spacing: 6) {
                    Text("Created")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(task.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Label("Description", systemImage: "text.alignleft")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $task.taskDescription)
                        .frame(minHeight: 80)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                }
                .padding(12)
                .liquidGlass(cornerRadius: AppTheme.Radius.card)

                // Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    // Dropdown to select from existing tags
                    let allExistingTags = Array(Set(allTasks.flatMap(\.tags))).sorted()
                    let availableTags = allExistingTags.filter { !task.tags.contains($0) }

                    if !availableTags.isEmpty {
                        Menu {
                            ForEach(availableTags, id: \.self) { tag in
                                Button(action: {
                                    withAnimation(.spring(response: 0.2)) {
                                        task.tags.append(tag)
                                    }
                                }) {
                                    Label(tag, systemImage: "tag")
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("Add Tag")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    // Show currently assigned tags
                    if !task.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(task.tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                    Button(action: {
                                        withAnimation(.spring(response: 0.2)) {
                                            task.tags.removeAll { $0 == tag }
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .overlay(
                                            Capsule().stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                                        )
                                )
                            }
                        }
                    }
                }

                // Subtasks
                VStack(alignment: .leading, spacing: 8) {
                    Label("Subtasks", systemImage: "checklist")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(task.subtasks) { subtask in
                            HStack {
                                Button(action: { subtask.isCompleted.toggle() }) {
                                    Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(subtask.title)
                                    .strikethrough(subtask.isCompleted)
                                    .foregroundStyle(subtask.isCompleted ? .secondary : .primary)

                                Spacer()

                                Button(action: {
                                    task.subtasks.removeAll { $0.id == subtask.id }
                                    modelContext.delete(subtask)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            TextField("New subtask...", text: $newSubtaskTitle)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addSubtask() }
                            Button("Add") { addSubtask() }
                                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(12)
                .liquidGlass(cornerRadius: AppTheme.Radius.card)
            }
            .padding(24)
        }
    }

    // MARK: - Helpers

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let subtask = SubTask(title: trimmed)
        subtask.parentTask = task
        task.subtasks.append(subtask)
        modelContext.insert(subtask)
        newSubtaskTitle = ""
    }
}
