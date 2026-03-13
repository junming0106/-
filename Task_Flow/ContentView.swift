import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel = BoardViewModel()
    @State private var selectedSection: SidebarSection = .board
    @State private var showAIAssistant = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                switch selectedSection {
                case .board:
                    HSplitView {
                        KanbanBoardView(viewModel: viewModel, showAIAssistant: $showAIAssistant)
                            .frame(minWidth: 600)

                        if let task = viewModel.selectedTask {
                            TaskDetailView(task: task)
                                .frame(minWidth: 300, idealWidth: 350)
                        }
                    }
                }

                // AI Assistant floating panel or button
                if showAIAssistant {
                    AIAssistantView(isPresented: $showAIAssistant)
                        .padding(20)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9, anchor: .bottomTrailing)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.95, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        ))
                } else {
                    // Floating AI button — bottom right
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
            }
        }
        .navigationTitle("TaskFlow")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
        .background {
            Button("") {
                withAnimation(.spring(response: 0.3)) {
                    showAIAssistant.toggle()
                }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .hidden()
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case board = "Board"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .board: return "kanban.rectangle"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        List {
            ForEach(SidebarSection.allCases) { section in
                Button(action: { selection = section }) {
                    Label(section.rawValue, systemImage: section.icon)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selection == section ? Color.accentColor.opacity(0.12) : Color.clear)
                )
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskItem.self, SubTask.self, BoardColumn.self, CardConnection.self], inMemory: true)
}
