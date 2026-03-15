import SwiftUI
import SwiftData

/// Wrapper that resolves "system" appearance mode using the actual system colorScheme
struct AppearanceWrapper<Content: View>: View {
    let appearanceMode: String
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var systemScheme

    private var resolved: ColorScheme {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return systemScheme
        }
    }

    var body: some View {
        content
            .preferredColorScheme(resolved)
    }
}

@main
struct Task_FlowApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TaskItem.self,
            SubTask.self,
            BoardColumn.self,
            CardConnection.self,
            Workspace.self,
            Board.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        let undoManager = UndoManager()
        undoManager.levelsOfUndo = 10

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            container.mainContext.undoManager = undoManager
            return container
        } catch {
            // Schema migration failed — remove old store and retry
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupport.appendingPathComponent("default.store")
            for ext in ["", "-wal", "-shm"] {
                let url = storeURL.deletingLastPathComponent()
                    .appendingPathComponent(storeURL.lastPathComponent + ext)
                try? FileManager.default.removeItem(at: url)
            }
            do {
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                container.mainContext.undoManager = undoManager
                return container
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    @AppStorage("appearanceMode") private var appearanceMode = "system"

    init() {
        // Configure quick input panel with model container
        QuickInputPanel.shared.configure(modelContainer: sharedModelContainer)

        // Register global hotkey: Ctrl + Shift + Space
        GlobalHotkeyManager.shared.onHotkeyPressed = {
            DispatchQueue.main.async {
                QuickInputPanel.shared.toggle()
            }
        }
        GlobalHotkeyManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            AppearanceWrapper(appearanceMode: appearanceMode) {
                ContentView()
            }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 750)

        Settings {
            AppearanceWrapper(appearanceMode: appearanceMode) {
                SettingsView()
                    .frame(width: 680, height: 480)
            }
        }
    }
}
