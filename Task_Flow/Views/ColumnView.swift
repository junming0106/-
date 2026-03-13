import SwiftUI
import SwiftData

struct ColumnView: View {
    @Bindable var column: BoardColumn
    @Bindable var viewModel: BoardViewModel
    let allColumns: [BoardColumn]
    let onAddTask: (BoardColumn) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isTargeted = false
    @State private var isEditingTitle = false
    @State private var isEditingIcon = false

    private let iconOptions = [
        "list.bullet", "tray.full", "checklist.unchecked",
        "hammer", "eye", "checkmark.circle",
        "star", "flag", "bolt", "lightbulb",
        "folder", "doc.text", "cube", "gear",
        "person.2", "bell", "bookmark", "tag",
    ]

    var body: some View {
        VStack(spacing: 0) {
            columnHeader

            // Color accent bar
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [columnColor.opacity(0.6), columnColor.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            // Task cards — content fitting
            VStack(spacing: AppTheme.Spacing.cardGap) {
                ForEach(column.sortedTasks) { task in
                    TaskCardView(
                        task: task,
                        isSelected: viewModel.selectedTask?.id == task.id,
                        onSelect: { viewModel.selectedTask = task },
                        onDelete: { viewModel.deleteTask(task, context: modelContext) }
                    )
                }

                AddTaskInlineButton { onAddTask(column) }
            }
            .padding(AppTheme.Spacing.columnPadding)
        }
        .frame(width: 300)
        .liquidGlass(tint: columnColor.opacity(0.3))
        .overlay(alignment: .topTrailing) {
            Text("\(column.tasks.count)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(minWidth: 26, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(columnColor.opacity(0.85))
                )
                .offset(x: 10, y: -10)
        }
        .overlay(connectionModeOverlay)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.column, style: .continuous)
                .stroke(isTargeted ? AppTheme.Colors.selectedBorder : Color.clear, lineWidth: 2)
                .animation(.easeInOut(duration: 0.2), value: isTargeted)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first else { return false }
            if dropped.hasPrefix("col:") {
                let idString = String(dropped.dropFirst(4))
                guard let dragID = UUID(uuidString: idString),
                      dragID != column.id else { return false }
                reorderColumn(draggedID: dragID, targetID: column.id)
                return true
            } else {
                guard let taskID = UUID(uuidString: dropped) else { return false }
                let descriptor = FetchDescriptor<TaskItem>(
                    predicate: #Predicate { $0.id == taskID }
                )
                guard let task = try? modelContext.fetch(descriptor).first else { return false }
                viewModel.moveTask(task, to: column, at: column.tasks.count)
                return true
            }
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargeted = targeted
            }
        }
    }

    // MARK: - Connection Mode Overlay

    @ViewBuilder
    private var connectionModeOverlay: some View {
        if viewModel.isConnecting {
            RoundedRectangle(cornerRadius: AppTheme.Radius.column, style: .continuous)
                .stroke(Color.orange.opacity(0.6), lineWidth: 2.5)
                .overlay(
                    Text("Tap to connect")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(y: -16),
                    alignment: .top
                )
                .onTapGesture {
                    viewModel.finishConnecting(to: column, context: modelContext)
                }
        }
    }

    // MARK: - Column Reorder

    private func reorderColumn(draggedID: UUID, targetID: UUID) {
        var sorted = allColumns.sorted { $0.order < $1.order }
        guard let fromIdx = sorted.firstIndex(where: { $0.id == draggedID }),
              let toIdx = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = sorted.remove(at: fromIdx)
        sorted.insert(moved, at: toIdx)
        for (i, col) in sorted.enumerated() {
            col.order = i
        }
    }

    // MARK: - Header (editable)

    private var columnHeader: some View {
        HStack(spacing: 10) {
            // Tappable icon — opens icon picker
            Button(action: { isEditingIcon.toggle() }) {
                Image(systemName: column.iconName)
                    .foregroundStyle(columnColor)
                    .font(.title2)
                    .fontWeight(.medium)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditingIcon) {
                iconPicker
            }

            // Tappable title — inline edit
            if isEditingTitle {
                TextField("Name", text: $column.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)
                    .onSubmit { isEditingTitle = false }
                    .onExitCommand { isEditingTitle = false }
            } else {
                Text(column.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary.opacity(0.85))
                    .onTapGesture { isEditingTitle = true }
            }

            if column.wipLimit > 0 && column.tasks.count >= column.wipLimit {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Spacer()

            // Connect to other column
            HeaderButton(
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                tint: .orange,
                size: .title2
            ) {
                viewModel.startConnecting(from: column)
            }
            .help("Connect to another column")

            // Add task
            HeaderButton(icon: "plus.circle.fill", tint: AppTheme.Colors.addButtonTint, size: .title2) {
                onAddTask(column)
            }
            .help("Add Task")

            // Edit column
            HeaderButton(icon: "pencil.circle.fill", tint: Color.secondary.opacity(0.6), size: .title2) {
                isEditingTitle = true
            }
            .help("Edit Column")

            Menu {
                Button("Delete Column", role: .destructive) {
                    viewModel.deleteColumn(column, context: modelContext)
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Icon Picker Popover

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose Icon")
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 6), spacing: 8) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button(action: {
                        column.iconName = icon
                        isEditingIcon = false
                    }) {
                        Image(systemName: icon)
                            .font(.body)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(column.iconName == icon ? columnColor.opacity(0.2) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var columnColor: Color {
        switch column.color {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .teal: return .teal
        case .indigo: return .indigo
        }
    }
}

// MARK: - Reusable Components

struct HeaderButton: View {
    let icon: String
    var tint: Color = .secondary
    var size: Font = .body
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(size)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHovering ? tint : tint.opacity(0.7))
                .scaleEffect(isHovering ? 1.2 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct AddTaskInlineButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.body)
                    .fontWeight(.medium)
                Text("New Task")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isHovering ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                            .stroke(
                                isHovering ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                                lineWidth: 0.5
                            )
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Task Card Drag Preview

struct TaskCardDragPreview: View {
    let task: TaskItem

    var body: some View {
        Text(task.title)
            .font(.body)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            )
            .frame(width: 220)
    }
}
