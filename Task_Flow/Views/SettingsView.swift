import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    // AI
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("aiAPIKey") private var aiAPIKey = ""
    @AppStorage("aiModel") private var aiModel = "gpt-4o"

    // Appearance
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentColorName") private var accentColorName = "blue"
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("showGridBackground") private var showGridBackground = true

    // Canvas
    @AppStorage("defaultColumnWidth") private var defaultColumnWidth: Double = 320
    @AppStorage("snapToGrid") private var snapToGrid = false
    @AppStorage("gridSize") private var gridSize: Double = 20

    // General
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30

    @State private var selectedTab: SettingsTab = .general
    @State private var showAPIKey = false
    @State private var showSaveConfirmation = false
    @State private var availableModels: [AIModelService.AIModel] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [TaskItem]
    private var isDark: Bool { colorScheme == .dark }

    /// Called when the tutorial board is created, passing the new board's ID
    var onTutorialCreated: ((UUID) -> Void)?

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case canvas = "Canvas"
        case ai = "AI"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .canvas: return "rectangle.3.group"
            case .ai: return "sparkles"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Settings sidebar
            settingsSidebar
                .frame(width: 180)

            Divider().opacity(0.3)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    settingsHeader

                    switch selectedTab {
                    case .general:
                        generalSettings
                    case .appearance:
                        appearanceSettings
                    case .canvas:
                        canvasSettings
                    case .ai:
                        aiSettings
                    }
                }
                .padding(32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settingsBackground)
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        VStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                settingsTabButton(tab)
            }
            Spacer()
        }
        .padding(12)
        .background(
            isDark
                ? Color(red: 0.08, green: 0.06, blue: 0.12).opacity(0.5)
                : Color(red: 0.95, green: 0.94, blue: 0.97).opacity(0.5)
        )
    }

    @State private var hoveredTab: SettingsTab?

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : isHovered ? .primary.opacity(0.8) : .secondary)
                    .frame(width: 22)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary.opacity(isHovered ? 0.85 : 0.7))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                          )
                          : LinearGradient(
                            colors: [isHovered ? Color.primary.opacity(isDark ? 0.08 : 0.05) : .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                          )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredTab = hovering ? tab : nil
            }
        }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedTab.rawValue)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary.opacity(0.9))

            Text(headerSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.bottom, 24)
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .general: return "App behavior and preferences"
        case .appearance: return "Customize the look and feel"
        case .canvas: return "Configure canvas and column layout"
        case .ai: return "AI assistant configuration"
        }
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Behavior") {
                settingsToggle(
                    title: "Confirm before delete",
                    subtitle: "Show confirmation dialog when deleting boards, columns, or tasks",
                    isOn: $confirmBeforeDelete
                )
            }

            settingsSection("Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quick Input (Global)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.8))
                            Text("Open AI quick input from anywhere, even when the app is in the background")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }

                        Spacer()

                        Text("⌃⇧Space")
                            .font(.system(size: 12, weight: .medium).monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }

                }
            }

            settingsSection("Tutorial") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("操作教學")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                        Text("建立一個教學看板，了解 TaskFlow 的各項功能")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }

                    Spacer()

                    Button(action: createTutorialBoard) {
                        Text("開啟教學")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            settingsSection("Tag Management") {
                VStack(alignment: .leading, spacing: 10) {
                    let allTags = Array(Set(allTasks.flatMap(\.tags))).sorted()

                    if allTags.isEmpty {
                        Text("No tags yet")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.6))
                    } else {
                        Text("Click the delete button to permanently remove a tag from all tasks.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.6))

                        FlowLayout(spacing: 6) {
                            ForEach(allTags, id: \.self) { tag in
                                HStack(spacing: 5) {
                                    Text(tag)
                                        .font(.system(size: 12, weight: .medium))

                                    let count = allTasks.filter { $0.tags.contains(tag) }.count
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule().fill(Color.primary.opacity(0.06))
                                        )

                                    Button(action: {
                                        deleteTagGlobally(tag)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.08))
                                        .overlay(
                                            Capsule().stroke(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                                        )
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Appearance Settings

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Theme") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Appearance")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))

                    Picker("", selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }
            }

            settingsSection("Canvas") {
                settingsToggle(
                    title: "Show grid background",
                    subtitle: "Display dot grid on the canvas",
                    isOn: $showGridBackground
                )
            }

            settingsSection("Sidebar") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sidebar width")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))

                        Spacer()

                        Text("\(Int(sidebarWidth))px")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $sidebarWidth, in: 180...360, step: 10)
                        .frame(maxWidth: 300)
                }
            }
        }
    }

    // MARK: - Canvas Settings

    private var canvasSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Column Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Default column width")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))

                        Spacer()

                        Text("\(Int(defaultColumnWidth))px")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $defaultColumnWidth, in: 240...480, step: 20)
                        .frame(maxWidth: 300)
                }
            }

            settingsSection("Snapping") {
                settingsToggle(
                    title: "Snap to grid",
                    subtitle: "Columns and workspaces snap to grid when dragged",
                    isOn: $snapToGrid
                )

                if snapToGrid {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Grid size")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.8))

                            Spacer()

                            Text("\(Int(gridSize))px")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $gridSize, in: 10...50, step: 5)
                            .frame(maxWidth: 300)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - AI Settings

    private var currentProvider: AIModelService.Provider {
        AIModelService.Provider(rawValue: aiProvider) ?? .openai
    }

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Provider") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Provider")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))

                    Picker("", selection: $aiProvider) {
                        ForEach(AIModelService.Provider.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    .onChange(of: aiProvider) {
                        // Clear models when provider changes
                        availableModels = []
                        aiModel = ""
                        modelFetchError = nil
                    }
                }
            }

            settingsSection("API Key") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))

                    HStack(spacing: 8) {
                        Group {
                            if showAPIKey {
                                TextField(currentProvider.apiKeyPlaceholder, text: $aiAPIKey)
                            } else {
                                SecureField(currentProvider.apiKeyPlaceholder, text: $aiAPIKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13).monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                        .frame(maxWidth: 360)

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help(showAPIKey ? "Hide API Key" : "Show API Key")
                    }

                    Text("Your API key is stored locally and never sent to third parties.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }

            settingsSection("Model") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Model")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))

                        Spacer()

                        // Fetch models button
                        Button(action: fetchModels) {
                            HStack(spacing: 5) {
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                }
                                Text(availableModels.isEmpty ? "Fetch Models" : "Refresh")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(aiAPIKey.isEmpty || isFetchingModels || currentProvider == .custom)
                    }

                    if !availableModels.isEmpty {
                        // Dynamic model picker from API
                        Picker("", selection: $aiModel) {
                            Text("Select a model...").tag("")
                            ForEach(availableModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 300)
                    } else if currentProvider == .custom {
                        // Custom provider: free-text model input
                        TextField("Enter model name", text: $aiModel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13).monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                            .frame(maxWidth: 300)
                    } else if aiAPIKey.isEmpty {
                        Text("Enter your API key, then click \"Fetch Models\" to load available models.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                    } else {
                        Text("Click \"Fetch Models\" to load available models from \(currentProvider.displayName).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }

                    // Error message
                    if let error = modelFetchError {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    }

                    // Show selected model if set
                    if !aiModel.isEmpty && availableModels.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                            Text("Current: \(aiModel)")
                                .font(.system(size: 12).monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        modelFetchError = nil

        Task {
            do {
                let models = try await AIModelService.shared.fetchModels(
                    provider: currentProvider,
                    apiKey: aiAPIKey
                )
                await MainActor.run {
                    availableModels = models
                    isFetchingModels = false
                    // If current model not in list, clear it
                    if !models.contains(where: { $0.id == aiModel }) {
                        aiModel = ""
                    }
                }
            } catch {
                await MainActor.run {
                    modelFetchError = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }

    // MARK: - Tag Management

    private func deleteTagGlobally(_ tag: String) {
        for task in allTasks where task.tags.contains(tag) {
            task.tags.removeAll { $0 == tag }
        }
    }

    // MARK: - Tutorial

    private func createTutorialBoard() {
        let board = Board(
            name: "TaskFlow 操作說明",
            iconName: "lightbulb",
            colorName: "purple",
            order: 0
        )
        modelContext.insert(board)

        // Column definitions
        let colDefs: [(String, String, String)] = [
            ("待辦事項", "list.bullet", "blue"),
            ("進行中", "figure.run", "yellow"),
            ("已完成", "checkmark.circle.fill", "green"),
        ]

        var cols: [BoardColumn] = []
        for (i, (title, icon, color)) in colDefs.enumerated() {
            let col = BoardColumn(
                title: title, order: i,
                colorName: color, iconName: icon,
                positionX: 60 + Double(i) * 400,
                positionY: 0
            )
            col.board = board
            modelContext.insert(col)
            cols.append(col)
        }

        // 待辦事項
        let todoTasks: [(String, String, TaskPriority)] = [
            ("歡迎使用 TaskFlow！",
             "這是您的任務看板。您可以在這裡管理所有待辦事項。\n\n試試以下操作：\n• 按住 Space 拖曳來平移畫布\n• 雙指捏合或滾輪來縮放\n• 右鍵點擊畫布空白處新增欄位",
             .medium),
            ("點擊我查看詳細資訊",
             "每張卡片都可以設定截止日期、優先級和標籤。\n\n更多操作：\n• 拖放卡片到其他欄位來移動\n• 右鍵欄位可連線、複製、刪除\n• 框選多個欄位，右鍵群組為 Workspace",
             .low),
            ("試試復原功能",
             "TaskFlow 支援 ⌘Z 復原、⌘⇧Z 重做。\n最多可回溯 10 步操作，包含拖曳、刪除、自動排列等。",
             .low),
        ]
        for (i, (title, desc, priority)) in todoTasks.enumerated() {
            let task = TaskItem(title: title, taskDescription: desc, priority: priority, order: i)
            task.column = cols[0]
            modelContext.insert(task)
        }

        // 進行中
        let inProgressTasks: [(String, String, TaskPriority)] = [
            ("探索 AI 助手功能",
             "按 ⌃⇧Space 開啟 AI 面板。\n\n試試看說：\n• 「幫我新增一個待辦項目」\n• 「將某個任務移到已完成」\n• 「看板摘要」\n\n記得先到 Settings 設定 API Key。",
             .high),
        ]
        for (i, (title, desc, priority)) in inProgressTasks.enumerated() {
            let task = TaskItem(title: title, taskDescription: desc, priority: priority, order: i)
            task.column = cols[1]
            modelContext.insert(task)
        }

        // 已完成
        let doneTasks: [(String, String, TaskPriority)] = [
            ("開啟 TaskFlow",
             "恭喜您已經完成第一步！\n\n準備好了嗎？您可以隨時刪除這個看板，開始建立自己的工作流程。",
             .medium),
        ]
        for (i, (title, desc, priority)) in doneTasks.enumerated() {
            let task = TaskItem(title: title, taskDescription: desc, priority: priority, order: i)
            task.column = cols[2]
            modelContext.insert(task)
        }

        onTutorialCreated?(board.id)
    }

    // MARK: - Reusable Components

    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .toggleStyle(.switch)
        .tint(.blue)
    }

    // MARK: - Background

    private var settingsBackground: some View {
        ZStack {
            (isDark
                ? Color(red: 0.11, green: 0.11, blue: 0.12)
                : Color(red: 0.95, green: 0.95, blue: 0.97))

            LinearGradient(
                colors: isDark
                    ? [Color.purple.opacity(0.03), Color.blue.opacity(0.03)]
                    : [Color.purple.opacity(0.02), Color.blue.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
