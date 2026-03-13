import SwiftUI
import SwiftData

struct TaskCardView: View {
    let task: TaskItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        cardContent
            .padding(AppTheme.Spacing.cardPadding)
            .glassCard(isHovering: isHovering, isSelected: isSelected)
            .scaleEffect(isHovering ? 1.012 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovering)
            .onHover { hovering in
                withAnimation { isHovering = hovering }
            }
            .onTapGesture(perform: onSelect)
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)

                Text(task.title)
                    .font(.system(.body, weight: .medium))
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
                    .font(.caption)
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
                    .font(.caption2)
                    .foregroundStyle(overdue ? Color.red : Color.secondary.opacity(0.6))
            }

            if !task.tags.isEmpty {
                ForEach(task.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.Colors.tagBackground)
                        .clipShape(Capsule())
                }
                if task.tags.count > 2 {
                    Text("+\(task.tags.count - 2)")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }

            Spacer()

            if !task.subtasks.isEmpty {
                let completed = task.subtasks.filter(\.isCompleted).count
                Label("\(completed)/\(task.subtasks.count)", systemImage: "checklist")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    private func isDueSoon(_ date: Date) -> Bool {
        date < Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    }
}
