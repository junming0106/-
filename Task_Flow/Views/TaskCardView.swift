import SwiftUI
import SwiftData

struct TaskCardView: View {
    @Bindable var task: TaskItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showColorPicker = false

    var body: some View {
        cardContent
            .padding(AppTheme.Spacing.cardPadding)
            .glassCard(isHovering: isHovering, isSelected: isSelected)
            .overlay(alignment: .leading) {
                // Color accent bar on left edge
                RoundedRectangle(cornerRadius: 2)
                    .fill(task.displayColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
            .scaleEffect(isHovering ? 1.012 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovering)
            .onHover { hovering in
                withAnimation { isHovering = hovering }
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture(perform: onSelect)
            .onTapGesture(count: 2) { showColorPicker = true }
            .popover(isPresented: $showColorPicker) {
                TaskColorPicker(task: task)
            }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
//                Circle()
//                    .fill(task.displayColor)
//                    .frame(width: 9, height: 9)
//                    .padding(.top, 6)

                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary.opacity(0.9))
                Spacer()

                if isHovering {
                    HeaderButton(icon: "xmark.circle.fill", tint: Color.secondary, size: .caption) {
                        onDelete()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            if !task.taskDescription.isEmpty {
                Text(task.taskDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            metadataRow
        }
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let dueDate = task.dueDate {
                let overdue = isDueSoon(dueDate)
                Label(dueDate.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(overdue ? Color.red : Color.secondary.opacity(0.6))
            }

            if !task.tags.isEmpty {
                ForEach(task.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.Colors.tagBackground)
                        .clipShape(Capsule())
                }
                if task.tags.count > 2 {
                    Text("+\(task.tags.count - 2)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }

            Spacer()

            if !task.subtasks.isEmpty {
                let completed = task.subtasks.filter(\.isCompleted).count
                Label("\(completed)/\(task.subtasks.count)", systemImage: "checklist")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
        }
    }

    private func isDueSoon(_ date: Date) -> Bool {
        date < Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    }
}

// MARK: - Task Color Picker

struct TaskColorPicker: View {
    @Bindable var task: TaskItem

    private func displayColor(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "yellow": return .yellow
        case "cyan": return .cyan
        default: return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Card Color")
                .font(.system(size: 11))
                .fontWeight(.semibold)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 6), spacing: 8) {
                // "Default" option — uses priority color
                Button(action: { task.colorName = "default" }) {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                    center: .center
                                )
                            )
                            .frame(width: 22, height: 22)

                        if task.colorName == "default" {
                            Circle()
                                .stroke(Color.white, lineWidth: 2.5)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .scaleEffect(task.colorName == "default" ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)

                ForEach(TaskItem.taskColorOptions.dropFirst(), id: \.self) { name in
                    Button(action: { task.colorName = name }) {
                        Circle()
                            .fill(displayColor(for: name))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: task.colorName == name ? 2.5 : 0)
                            )
                            .scaleEffect(task.colorName == name ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
    }
}
