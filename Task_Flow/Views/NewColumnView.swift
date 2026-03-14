import SwiftUI
import SwiftData

struct NewColumnView: View {
    let board: Board
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BoardColumn.order) private var columns: [BoardColumn]

    @State private var title = ""
    @State private var selectedColor: ColorOption = .blue
    @State private var iconName = "list.bullet"
    @State private var wipLimit = 0
    @FocusState private var isTitleFocused: Bool

    private let iconOptions = [
        "list.bullet", "tray.full", "checklist.unchecked",
        "hammer", "eye", "checkmark.circle",
        "star", "flag", "bolt", "lightbulb",
        "folder", "doc.text", "cube", "gear",
        "person.2", "bell", "bookmark", "tag",
    ]

    private var selectedDisplayColor: Color {
        switch selectedColor {
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

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            sheetBody
            sheetFooter
        }
        .frame(width: 420, height: 480)
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
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("New Column")
                .font(.headline)
                .fontWeight(.semibold)

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
                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextField("Column name", text: $title)
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

                // Color
                VStack(alignment: .leading, spacing: 6) {
                    Text("Color")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

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

                            Button(action: { withAnimation(.spring(response: 0.2)) { selectedColor = color } }) {
                                Circle()
                                    .fill(displayColor)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 2.5 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(displayColor.opacity(0.5), lineWidth: selectedColor == color ? 1 : 0)
                                            .padding(-2)
                                    )
                                    .scaleEffect(selectedColor == color ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Icon
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 8) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button(action: {
                                withAnimation(.spring(response: 0.2)) { iconName = icon }
                            }) {
                                Image(systemName: icon)
                                    .font(.body)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(iconName == icon ? selectedDisplayColor.opacity(0.15) : Color.primary.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(
                                                        iconName == icon ? selectedDisplayColor.opacity(0.4) : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                    .foregroundStyle(iconName == icon ? selectedDisplayColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // WIP Limit
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WIP Limit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text(wipLimit == 0 ? "No limit" : "Max \(wipLimit) tasks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Stepper("", value: $wipLimit, in: 0...50)
                        .labelsHidden()
                        .controlSize(.small)

                    Text("\(wipLimit)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(width: 30)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )
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

            // Preview
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundStyle(selectedDisplayColor)
                Text(title.isEmpty ? "Preview" : title)
                    .lineLimit(1)
                    .foregroundStyle(title.isEmpty ? .tertiary : .primary)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selectedDisplayColor.opacity(0.1))
            )

            Button(action: {
                let newColumn = BoardColumn(
                    title: title,
                    order: columns.count,
                    colorName: selectedColor.rawValue,
                    wipLimit: wipLimit,
                    iconName: iconName
                )
                newColumn.board = board
                modelContext.insert(newColumn)
                dismiss()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Add Column")
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
}
