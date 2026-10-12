import AppKit

@MainActor
enum WindowInteractionPolicy {
    static let drawer = NSUserInterfaceItemIdentifier("islandmemo.drawer")
    static let settings = NSUserInterfaceItemIdentifier("islandmemo.settings")
    static let capture = NSUserInterfaceItemIdentifier("islandmemo.capture")
    static let memo = NSUserInterfaceItemIdentifier("islandmemo.memo-window")
    static let orb = NSUserInterfaceItemIdentifier("islandmemo.memo-orb")

    static func rootRole(of window: NSWindow) -> NSUserInterfaceItemIdentifier? {
        var candidate: NSWindow? = window
        while let current = candidate {
            if [drawer, settings, capture, memo, orb].contains(current.identifier) { return current.identifier }
            candidate = current.parent
        }
        return nil
    }

    static func isRelated(_ window: NSWindow, to root: NSWindow) -> Bool {
        if window === root || window.sheetParent === root { return true }
        var parent = window.parent
        while let current = parent {
            if current === root { return true }
            parent = current.parent
        }
        guard rootRole(of: window) == nil else { return false }
        // SwiftUI/AppKit transient windows can have no public parent. Only anchored
        // popovers or menus intersecting this root qualify; ordinary app windows do not.
        let type = NSStringFromClass(type(of: window))
        return (type.contains("Popover") || type.contains("Menu")) && root.frame.intersects(window.frame)
    }

    static func contains(_ point: NSPoint, in root: NSWindow) -> Bool {
        NSApp.windows.contains { $0.isVisible && $0.frame.contains(point) && isRelated($0, to: root) }
    }
}
