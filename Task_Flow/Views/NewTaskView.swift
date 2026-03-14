import SwiftUI
import SwiftData

struct NewTaskView: View {
    let column: BoardColumn
    @Bindable var viewModel: BoardViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            sheetBody
            sheetFooter
        }
        .frame(width: 480, height: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .onAppear { isTitleFocused = true }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.square.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("New Task")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("in \(column.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            VStack(spacing: 20) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextField("What needs to be done?", text: $title)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                        .focused($isTitleFocused)
                }

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $description)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 70, maxHeight: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                }

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
                                isSelected: priority == p
                            ) {
                                withAnimation(.spring(response: 0.2)) {
                                    priority = p
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

                // Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Add tag...", text: $tagInput)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                            .onSubmit { addTag() }

                        Button(action: addTag) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                    Button(action: { tags.removeAll { $0 == tag } }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
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
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }

    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )

            Spacer()

            Button(action: {
                viewModel.addTask(
                    title: title,
                    description: description,
                    priority: priority,
                    dueDate: hasDueDate ? dueDate : nil,
                    tags: tags,
                    to: column,
                    context: modelContext
                )
                dismiss()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Create Task")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            title.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.accentColor.opacity(0.3)
                                : Color.accentColor
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        tagInput = ""
    }
}

// MARK: - Priority Chip

struct PriorityChip: View {
    let priority: TaskPriority
    let isSelected: Bool
    let action: () -> Void

    private var chipColor: Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(chipColor)
                    .frame(width: 8, height: 8)
                Text(priority.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? chipColor.opacity(0.15) : Color.primary.opacity(0.04))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? chipColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Due Date Button (Modern Calendar Popover)

struct DueDateButton: View {
    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date

    @State private var showCalendar = false

    private var isOverdue: Bool {
        hasDueDate && dueDate < Date()
    }

    private var dateLabel: String {
        guard hasDueDate else { return "Set date" }

        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) { return "Today" }
        if calendar.isDateInTomorrow(dueDate) { return "Tomorrow" }
        return dueDate.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
    }

    private var daysUntil: String? {
        guard hasDueDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
        if days < 0 { return "\(abs(days))d overdue" }
        if days == 0 { return nil }
        if days <= 7 { return "in \(days)d" }
        return nil
    }

    var body: some View {
        HStack(spacing: 8) {
            // Date button
            Button(action: { showCalendar.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: hasDueDate ? "calendar.badge.clock" : "calendar")
                        .font(.subheadline)
                        .foregroundStyle(isOverdue ? .red : hasDueDate ? .accentColor : .secondary)

                    Text(dateLabel)
                        .font(.subheadline)
                        .foregroundStyle(hasDueDate ? .primary : .secondary)

                    if let badge = daysUntil {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(isOverdue ? .red : .accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isOverdue ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    showCalendar ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCalendar) {
                calendarPopover
            }

            // Clear button
            if hasDueDate {
                Button(action: {
                    withAnimation(.spring(response: 0.2)) {
                        hasDueDate = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Calendar Popover

    private var calendarPopover: some View {
        VStack(spacing: 0) {
            // Quick pick shortcuts
            HStack(spacing: 6) {
                QuickDateChip(label: "Today", icon: "sun.max") {
                    dueDate = Date()
                    hasDueDate = true
                }
                QuickDateChip(label: "Tomorrow", icon: "sunrise") {
                    dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                    hasDueDate = true
                }
                QuickDateChip(label: "Next Week", icon: "calendar.badge.plus") {
                    dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())!
                    hasDueDate = true
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .opacity(0.3)

            // Custom calendar
            CustomCalendarView(selectedDate: $dueDate, onDateSelected: {
                hasDueDate = true
            })
            .padding(10)
        }
        .frame(width: 290)
    }
}

// MARK: - Custom Calendar View

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    var onDateSelected: () -> Void

    @State private var displayedMonth = Date()

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private var monthYearLabel: String {
        displayedMonth.formatted(.dateTime.year().month(.wide))
    }

    private var daysInMonth: [DateCell] {
        let range = calendar.range(of: .day, in: .month, for: displayedMonth)!
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        // Padding for days before the 1st
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [DateCell] = []

        // Previous month's trailing days
        if let prevMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) {
            let prevRange = calendar.range(of: .day, in: .month, for: prevMonth)!
            let prevDays = prevRange.count
            for i in 0..<leadingPadding {
                let day = prevDays - leadingPadding + i + 1
                let date = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: prevMonth),
                    month: calendar.component(.month, from: prevMonth),
                    day: day
                ))!
                cells.append(DateCell(date: date, isCurrentMonth: false))
            }
        }

        // Current month days
        for day in range {
            let date = calendar.date(from: DateComponents(
                year: calendar.component(.year, from: firstOfMonth),
                month: calendar.component(.month, from: firstOfMonth),
                day: day
            ))!
            cells.append(DateCell(date: date, isCurrentMonth: true))
        }

        // Trailing days to fill the grid
        let remaining = (7 - cells.count % 7) % 7
        if remaining > 0, let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) {
            for day in 1...remaining {
                let date = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: nextMonth),
                    month: calendar.component(.month, from: nextMonth),
                    day: day
                ))!
                cells.append(DateCell(date: date, isCurrentMonth: false))
            }
        }

        return cells
    }

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                        .frame(height: 24)
                }
            }

            // Day grid
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(daysInMonth) { cell in
                    let isSelected = calendar.isDate(cell.date, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(cell.date)

                    Button(action: {
                        withAnimation(.spring(response: 0.2)) {
                            selectedDate = cell.date
                        }
                        onDateSelected()
                    }) {
                        let dayColor: Color = isSelected ? .white :
                            !cell.isCurrentMonth ? .secondary.opacity(0.3) :
                            isToday ? .accentColor : .primary

                        Text("\(calendar.component(.day, from: cell.date))")
                            .font(.callout)
                            .fontWeight(isSelected ? .bold : isToday ? .semibold : .regular)
                            .foregroundStyle(dayColor)
                            .frame(width: 32, height: 32)
                            .background(
                                ZStack {
                                    if isSelected {
                                        Circle()
                                            .fill(Color.accentColor)
                                    } else if isToday {
                                        Circle()
                                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    struct DateCell: Identifiable {
        let date: Date
        let isCurrentMonth: Bool
        var id: Date { date }
    }
}

// MARK: - Quick Date Chip

struct QuickDateChip: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isHovering ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    .overlay(
                        Capsule()
                            .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .foregroundStyle(isHovering ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
