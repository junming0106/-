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
    @State private var isEditingColor = false
    @FocusState private var isTitleFieldFocused: Bool
    @State private var clickMonitor: Any?

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
                    .draggable(task.id.uuidString) {
                        TaskCardDragPreview(task: task)
                    }
                }

                AddTaskInlineButton { onAddTask(column) }
            }
            .padding(AppTheme.Spacing.columnPadding)
        }
        .frame(width: 320)
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
                    Image(systemName: "bolt.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                        .offset(y: -18),
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
            // Color dot — tap to change column color
            Button(action: { isEditingColor.toggle() }) {
                Circle()
                    .fill(columnColor)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditingColor) {
                columnColorPicker
            }

            // Tappable icon — opens icon picker
            Button(action: { isEditingIcon.toggle() }) {
                Image(systemName: column.iconName)
                    .foregroundStyle(columnColor)
                    .font(.system(size: 18))
                    .fontWeight(.medium)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditingIcon) {
                iconPicker
            }

            // Tappable title — inline edit (click outside or Enter to finish)
            if isEditingTitle {
                TextField("Name", text: $column.title)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focused($isTitleFieldFocused)
                    .onSubmit { finishEditingTitle() }
                    .onExitCommand { finishEditingTitle() }
                    .onAppear {
                        isTitleFieldFocused = true
                        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                            // Check if click is outside the text field
                            DispatchQueue.main.async { finishEditingTitle() }
                            return event
                        }
                    }
                    .onDisappear {
                        removeClickMonitor()
                    }
            } else {
                Text(column.title.isEmpty ? "Untitled" : column.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(column.title.isEmpty ? Color.secondary.opacity(0.4) : Color.primary.opacity(0.85))
                    .frame(minWidth: 60, alignment: .leading)
                    .contentShape(Rectangle())
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
                size: .system(size: 16)
            ) {
                viewModel.startConnecting(from: column)
            }
            .help("Connect to another column")

            // Delete column
            HeaderButton(icon: "xmark.circle.fill", tint: Color.secondary.opacity(0.5), size: .system(size: 18)) {
                viewModel.deleteColumn(column, context: modelContext)
            }
            .help("Delete Column")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
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

    // MARK: - Title Editing

    private func finishEditingTitle() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        isTitleFieldFocused = false
        removeClickMonitor()
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Column Color Picker

    private var columnColorPicker: some View {
        VStack(spacing: 10) {
            Text("Column Color")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                ForEach(ColorOption.allCases, id: \.self) { color in
                    let displayColor: Color = {
                        switch color {
                        case .blue: return .blue
                        case .purple: return .purple
                        case .green: return .green
                        case .orange: return .orange
                        case .red: return .red
                        case .pink: return .pink
                        case .teal: return .teal
                        case .indigo: return .indigo
                        }
                    }()

                    Button(action: {
                        column.colorName = color.rawValue
                    }) {
                        Circle()
                            .fill(displayColor)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: column.colorName == color.rawValue ? 2.5 : 0)
                            )
                            .scaleEffect(column.colorName == color.rawValue ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
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
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("New Task")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isHovering ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
