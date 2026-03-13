import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var modelContext
    @State private var newSubtaskTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                TextField("Task Title", text: $task.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.9))

                // Metadata
                VStack(spacing: 12) {
                    metadataRow(icon: "flag", label: "Priority") {
                        Picker("", selection: $task.priority) {
                            ForEach(TaskPriority.allCases, id: \.self) { p in
                                Label(p.rawValue, systemImage: p.icon).tag(p)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    Divider().opacity(0.3)

                    metadataRow(icon: "calendar", label: "Due Date") {
                        if let dueDate = task.dueDate {
                            DatePicker("", selection: Binding(
                                get: { dueDate },
                                set: { task.dueDate = $0 }
                            ), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()

                            Button(action: { task.dueDate = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button("Set Date") { task.dueDate = Date() }
                                .buttonStyle(.bordered)
                        }
                    }

                    Divider().opacity(0.3)

                    metadataRow(icon: "rectangle.split.3x1", label: "Column") {
                        Text(task.column?.title ?? "—")
                            .foregroundStyle(.primary)
                    }

                    Divider().opacity(0.3)

                    metadataRow(icon: "clock", label: "Created") {
                        Text(task.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .liquidGlass(cornerRadius: AppTheme.Radius.card)

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
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tags", systemImage: "tag")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(task.tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                Button(action: { task.tags.removeAll { $0 == tag } }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.Colors.tagBackground)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(12)
                .liquidGlass(cornerRadius: AppTheme.Radius.card)

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
            .padding(20)
        }
        .onChange(of: task.title) { task.updatedAt = Date() }
        .onChange(of: task.taskDescription) { task.updatedAt = Date() }
        .onChange(of: task.priority) { task.updatedAt = Date() }
    }

    // MARK: - Helpers

    private func metadataRow<Content: View>(
        icon: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }

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
