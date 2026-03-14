import SwiftUI
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

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

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

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Provider") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Provider")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))

                    Picker("", selection: $aiProvider) {
                        Text("OpenAI").tag("openai")
                        Text("Anthropic").tag("anthropic")
                        Text("Google Gemini").tag("gemini")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
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
                                TextField("Enter your API key", text: $aiAPIKey)
                            } else {
                                SecureField("Enter your API key", text: $aiAPIKey)
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
                    Text("Model")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.8))

                    Picker("", selection: $aiModel) {
                        Group {
                            if aiProvider == "openai" {
                                Text("GPT-4o").tag("gpt-4o")
                                Text("GPT-4o mini").tag("gpt-4o-mini")
                                Text("GPT-4 Turbo").tag("gpt-4-turbo")
                                Text("o1").tag("o1")
                            } else if aiProvider == "anthropic" {
                                Text("Claude Opus 4").tag("claude-opus-4-0")
                                Text("Claude Sonnet 4").tag("claude-sonnet-4-0")
                                Text("Claude Haiku 3.5").tag("claude-3-5-haiku")
                            } else if aiProvider == "gemini" {
                                Text("Gemini 2.5 Pro").tag("gemini-2.5-pro")
                                Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                            } else {
                                Text("Custom Model").tag("custom")
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
            }
        }
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
