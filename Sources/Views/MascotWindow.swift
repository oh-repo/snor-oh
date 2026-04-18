import AppKit
import SwiftUI

/// Transparent, always-on-top NSPanel that hosts the mascot sprite and status pill.
/// Non-activating: never steals keyboard focus from the IDE.
final class MascotWindow: NSPanel {

    private var scaleObserver: NSObjectProtocol?

    init(sessionManager: SessionManager, spriteEngine: SpriteEngine, bubbleManager: BubbleManager) {
        let scale = UserDefaults.standard.object(forKey: DefaultsKey.displayScale) as? Double ?? 1.0
        let size = NSSize(
            width: MascotView.windowWidth(scale: scale),
            height: MascotView.windowHeight(scale: scale, hasVisitors: false)
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window configuration
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        // Position near top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let origin = NSPoint(
                x: screenFrame.maxX - size.width - 40,
                y: screenFrame.maxY - size.height - 40
            )
            setFrameOrigin(origin)
        }

        // Host SwiftUI content
        let mascotView = MascotView(
            sessionManager: sessionManager,
            spriteEngine: spriteEngine,
            bubbleManager: bubbleManager
        )
        let hostingView = NSHostingView(rootView: mascotView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(origin: .zero, size: size)
        contentView = hostingView

        // Observe display scale changes to resize window
        scaleObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateSizeForScale()
        }
    }

    deinit {
        if let observer = scaleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateSizeForScale() {
        let scale = UserDefaults.standard.object(forKey: DefaultsKey.displayScale) as? Double ?? 1.0
        let newSize = NSSize(
            width: MascotView.windowWidth(scale: scale),
            height: MascotView.windowHeight(scale: scale, hasVisitors: false)
        )

        guard abs(frame.size.width - newSize.width) > 1 || abs(frame.size.height - newSize.height) > 1 else { return }

        // Keep top-right corner anchored
        var newFrame = frame
        let oldTopRight = NSPoint(x: newFrame.maxX, y: newFrame.maxY)
        newFrame.size = newSize
        newFrame.origin.x = oldTopRight.x - newSize.width
        newFrame.origin.y = oldTopRight.y - newSize.height
        setFrame(newFrame, display: true, animate: true)
    }
}
