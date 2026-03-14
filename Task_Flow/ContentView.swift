import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.order) private var boards: [Board]
    @Query(sort: \BoardColumn.order) private var allColumns: [BoardColumn]
    @State private var viewModel = BoardViewModel()
    @State private var selectedBoardID: UUID?
    @State private var showAIAssistant = false
    @State private var showSettings = false
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240

    private var selectedBoard: Board? {
        guard let id = selectedBoardID else { return boards.first }
        return boards.first(where: { $0.id == id }) ?? boards.first
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                boards: boards,
                selectedBoardID: Binding(
                    get: { selectedBoard?.id },
                    set: {
                        selectedBoardID = $0
                        showSettings = false
                    }
                ),
                showSettings: $showSettings,
                onCreateBoard: createBoard,
                onDeleteBoard: deleteBoard
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: CGFloat(sidebarWidth), max: 360)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                if showSettings {
                    SettingsView()
                } else if let board = selectedBoard {
                    HSplitView {
                        KanbanBoardView(
                            viewModel: viewModel,
                            showAIAssistant: $showAIAssistant,
                            board: board
                        )
                        .frame(minWidth: 600)

                        if let task = viewModel.selectedTask {
                            TaskDetailView(task: task)
                                .frame(minWidth: 300, idealWidth: 350)
                        }
                    }
                } else {
                    emptyBoardState
                }

                // AI Assistant floating panel or button (hidden in settings)
                if showAIAssistant && !showSettings {
                    AIAssistantView(isPresented: $showAIAssistant)
                        .padding(20)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9, anchor: .bottomTrailing)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.95, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        ))
                } else if !showSettings {
                    aiFloatingButton
                }
            }
        }
        .navigationTitle(showSettings ? "Settings" : (selectedBoard?.name ?? "TaskFlow"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if selectedBoard != nil && !showSettings {
                    Button(action: { viewModel.showingNewColumnSheet = true }) {
                        Label("New Column", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .help("Add New Column")

                    Button(action: {
                        if viewModel.selectedTask != nil {
                            viewModel.selectedTask = nil
                        }
                    }) {
                        Label("Close Detail", systemImage: "sidebar.right")
                    }
                    .disabled(viewModel.selectedTask == nil)
                }
            }
        }
        .background {
            Button("") {
                withAnimation(.spring(response: 0.3)) {
                    showAIAssistant.toggle()
                }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .hidden()
        }
        .onAppear {
            if boards.isEmpty {
                createFirstBoard()
            } else {
                // Migrate orphan columns (from before Board model was added)
                migrateOrphanColumns()
            }
        }
    }

    // MARK: - Empty State

    private var emptyBoardState: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.5), .blue.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("No Boards Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("Create a board to get started")
                .font(.body)
                .foregroundStyle(.tertiary)

            Button(action: createBoard) {
                Label("New Board", systemImage: "plus")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                AmbientGradientView()
                GridBackgroundView()
            }
        }
    }

    // MARK: - AI Button

    private var aiFloatingButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) {
                showAIAssistant = true
            }
        }) {
            Image(systemName: "sparkles")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(20)
        .help("AI Assistant (⌘⇧A)")
    }

    // MARK: - Board CRUD

    private func createFirstBoard() {
        let board = Board(name: "My Board", iconName: "rectangle.split.3x1", colorName: "blue", order: 0)
        modelContext.insert(board)
        selectedBoardID = board.id

        // Adopt existing orphan columns (pre-Board migration)
        let orphans = allColumns.filter { $0.board == nil }
        if !orphans.isEmpty {
            for col in orphans {
                col.board = board
            }
        } else {
            // Create default columns inside a workspace
            let defaults: [(String, String, String, Int, Double, Double)] = [
                ("Backlog", "tray.full", "purple", 0, 0, 40),
                ("To Do", "checklist.unchecked", "blue", 1, 400, 40),
                ("In Progress", "hammer", "orange", 2, 800, 40),
                ("Review", "eye", "teal", 3, 1200, 40),
                ("Done", "checkmark.circle", "green", 4, 1600, 40),
            ]

            let ws = Workspace(
                name: "Work Status",
                positionX: -Workspace.padding,
                positionY: -Workspace.padding - 28,
                width: Double(defaults.count) * 400 + Workspace.padding * 2,
                height: 300 + Workspace.padding * 2 + 28,
                order: 0
            )
            ws.board = board
            modelContext.insert(ws)

            for (title, icon, color, order, x, y) in defaults {
                let column = BoardColumn(
                    title: title, order: order,
                    colorName: color, iconName: icon,
                    positionX: x, positionY: y
                )
                column.board = board
                column.workspace = ws
                modelContext.insert(column)
            }
        }
    }

    private func migrateOrphanColumns() {
        let orphans = allColumns.filter { $0.board == nil }
        guard !orphans.isEmpty, let firstBoard = boards.first else { return }
        for col in orphans {
            col.board = firstBoard
        }
    }

    private func createBoard() {
        let board = Board(
            name: "New Board",
            iconName: Board.iconOptions.randomElement() ?? "rectangle.split.3x1",
            colorName: ColorOption.allCases.randomElement()?.rawValue ?? "blue",
            order: boards.count
        )
        modelContext.insert(board)

        // Create default columns inside a "Work Status" workspace
        let defaults: [(String, String, String, Int, Double, Double)] = [
            ("Backlog", "tray.full", "purple", 0, 0, 0),
            ("To Do", "checklist.unchecked", "blue", 1, 400, 0),
            ("In Progress", "hammer", "orange", 2, 800, 0),
            ("Review", "eye", "teal", 3, 1200, 0),
            ("Done", "checkmark.circle", "green", 4, 1600, 0),
        ]

        let ws = Workspace(
            name: "Work Status",
            positionX: -Workspace.padding,
            positionY: 40 - Workspace.padding - 28,
            width: Double(defaults.count) * 400 + Workspace.padding * 2,
            height: 300 + Workspace.padding * 2 + 28,
            order: 0
        )
        ws.board = board
        modelContext.insert(ws)

        for (title, icon, color, order, x, y) in defaults {
            let column = BoardColumn(
                title: title, order: order,
                colorName: color, iconName: icon,
                positionX: x, positionY: y
            )
            column.board = board
            column.workspace = ws
            modelContext.insert(column)
        }

        withAnimation(.spring(response: 0.3)) {
            selectedBoardID = board.id
        }
    }

    private func deleteBoard(_ board: Board) {
        let wasSelected = selectedBoardID == board.id
        modelContext.delete(board)
        if wasSelected {
            selectedBoardID = boards.first(where: { $0.id != board.id })?.id
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let boards: [Board]
    @Binding var selectedBoardID: UUID?
    @Binding var showSettings: Bool
    let onCreateBoard: () -> Void
    let onDeleteBoard: (Board) -> Void

    @State private var hoveredBoardID: UUID?
    @State private var editingBoardID: UUID?
    @State private var editingName: String = ""
    @FocusState private var isNameFieldFocused: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            // App branding
            appHeader

            Divider()
                .opacity(0.3)
                .padding(.horizontal, 16)

            // Board list
            ScrollView {
                VStack(spacing: 4) {
                    sectionHeader

                    ForEach(boards) { board in
                        boardRow(board)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            Spacer()

            // Bottom section
            bottomBar
        }
        .background(sidebarBackground)
        .scrollContentBackground(.hidden)
    }

    // MARK: - App Header

    private var appHeader: some View {
        HStack(spacing: 10) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.8),
                                Color.purple.opacity(0.8),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("TaskFlow")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary.opacity(0.85))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Text("BOARDS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.7))
                .tracking(0.8)

            Spacer()

            Button(action: onCreateBoard) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .help("New Board")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: - Board Row

    private func boardRow(_ board: Board) -> some View {
        let isSelected = selectedBoardID == board.id
        let isHovered = hoveredBoardID == board.id
        let isEditing = editingBoardID == board.id

        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedBoardID = board.id
            }
        }) {
            HStack(spacing: 10) {
                // Board icon
                Image(systemName: board.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? board.displayColor : .secondary.opacity(0.7))
                    .frame(width: 22, height: 22)

                // Board name
                if isEditing {
                    TextField("Board name", text: $editingName)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .textFieldStyle(.plain)
                        .focused($isNameFieldFocused)
                        .onSubmit { finishEditing(board) }
                        .onExitCommand { cancelEditing() }
                } else {
                    Text(board.name.isEmpty ? "Untitled" : board.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(
                            isSelected
                                ? .primary.opacity(0.95)
                                : Color.primary.opacity(isHovered ? 0.8 : 0.65)
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                // Column count badge
                if !board.columns.isEmpty {
                    Text("\(board.columns.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? board.displayColor : .secondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(
                                    isSelected
                                        ? board.displayColor.opacity(0.12)
                                        : Color.primary.opacity(0.04)
                                )
                        )
                }

                // Actions on hover
                if isHovered && !isEditing {
                    Menu {
                        Button(action: { startEditing(board) }) {
                            Label("Rename", systemImage: "pencil")
                        }

                        Divider()

                        // Icon picker submenu
                        Menu("Change Icon") {
                            ForEach(Board.iconOptions, id: \.self) { icon in
                                Button(action: { board.iconName = icon }) {
                                    Label(icon, systemImage: icon)
                                }
                            }
                        }

                        // Color picker submenu
                        Menu("Change Color") {
                            ForEach(ColorOption.allCases, id: \.self) { color in
                                Button(action: { board.colorName = color.rawValue }) {
                                    Label(color.displayName, systemImage: "circle.fill")
                                }
                            }
                        }

                        Divider()

                        Button(role: .destructive, action: { onDeleteBoard(board) }) {
                            Label("Delete Board", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(boardRowBackground(isSelected: isSelected, isHovered: isHovered, color: board.displayColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? board.displayColor.opacity(isDark ? 0.25 : 0.15)
                            : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredBoardID = hovering ? board.id : nil
            }
        }
        .contextMenu {
            Button(action: { startEditing(board) }) {
                Label("Rename", systemImage: "pencil")
            }

            Menu("Change Icon") {
                ForEach(Board.iconOptions, id: \.self) { icon in
                    Button(action: { board.iconName = icon }) {
                        Label(icon, systemImage: icon)
                    }
                }
            }

            Menu("Change Color") {
                ForEach(ColorOption.allCases, id: \.self) { color in
                    Button(action: { board.colorName = color.rawValue }) {
                        Label(color.displayName, systemImage: "circle.fill")
                    }
                }
            }

            Divider()

            Button(role: .destructive, action: { onDeleteBoard(board) }) {
                Label("Delete Board", systemImage: "trash")
            }
        }
    }

    private func boardRowBackground(isSelected: Bool, isHovered: Bool, color: Color) -> some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(color.opacity(isDark ? 0.15 : 0.08))
        } else if isHovered {
            return AnyShapeStyle(Color.primary.opacity(isDark ? 0.06 : 0.04))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3).padding(.horizontal, 16)

            Button(action: onCreateBoard) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary.opacity(0.6))

                    Text("New Board")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.6))

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSettings = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(showSettings ? .primary.opacity(0.8) : Color.secondary.opacity(0.6))

                    Text("Settings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(showSettings ? .primary.opacity(0.8) : Color.secondary.opacity(0.6))

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(showSettings ? Color.primary.opacity(isDark ? 0.08 : 0.05) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Background

    private var sidebarBackground: some View {
        ZStack {
            // Subtle gradient to match the ambient vibe
            LinearGradient(
                colors: isDark
                    ? [
                        Color(red: 0.08, green: 0.05, blue: 0.14).opacity(0.5),
                        Color(red: 0.04, green: 0.08, blue: 0.13).opacity(0.5),
                    ]
                    : [
                        Color(red: 0.96, green: 0.94, blue: 0.98).opacity(0.3),
                        Color(red: 0.93, green: 0.96, blue: 0.99).opacity(0.3),
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Editing

    private func startEditing(_ board: Board) {
        editingName = board.name
        editingBoardID = board.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }

    private func finishEditing(_ board: Board) {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            board.name = trimmed
        }
        editingBoardID = nil
    }

    private func cancelEditing() {
        editingBoardID = nil
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskItem.self, SubTask.self, BoardColumn.self, CardConnection.self, Board.self, Workspace.self], inMemory: true)
}
