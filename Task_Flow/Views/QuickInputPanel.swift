import AppKit
import SwiftUI
import SwiftData

/// A floating panel that appears on top of all windows for quick AI task input.
/// Similar to Spotlight — press Ctrl+Shift+Space anywhere to summon it.
/// Automatically dismisses when clicking outside the panel.
final class QuickInputPanel {
    static let shared = QuickInputPanel()

    private var panel: QuickInputNSPanel?
    private var modelContainer: ModelContainer?
    private var clickMonitor: Any?

    private init() {}

    /// Must be called once with the app's model container.
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Toggles the quick input panel visibility.
    func toggle() {
        if let panel, panel.isVisible {
            animateDismiss()
        } else {
            show()
        }
    }

    func show() {
        guard let modelContainer else { return }

        // Dismiss existing panel without animation
        removeMonitor()
        panel?.close()
        panel = nil

        // Create panel
        let panel = QuickInputNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 260
            let y = screenFrame.midY + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // SwiftUI content
        let quickInputView = QuickInputView(onDismiss: { [weak self] in
            self?.animateDismiss()
        })
        .modelContainer(modelContainer)

        let hostingView = NSHostingView(rootView: quickInputView)
        panel.contentView = hostingView

        // Start with transparent for fade-in
        panel.alphaValue = 0

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fade in + scale animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel

        // Monitor clicks outside the panel to auto-dismiss
        installClickMonitor()

        // Also dismiss when panel resigns key
        panel.onResignKey = { [weak self] in
            self?.animateDismiss()
        }
    }

    func animateDismiss() {
        guard let panel, panel.isVisible else { return }

        removeMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.close()
            self?.panel = nil
        })
    }

    // MARK: - Click Outside Monitor

    private func installClickMonitor() {
        // Global monitor: clicks outside the app
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.animateDismiss()
        }
    }

    private func removeMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}

// MARK: - Custom NSPanel

/// Custom NSPanel that notifies when it loses key status (user clicked elsewhere in the app).
final class QuickInputNSPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
