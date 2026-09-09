import AppKit

@MainActor
enum ApplicationMenus {
    static func install() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "丫丫灵动")
        appMenu.addItem(withTitle: "隐藏丫丫灵动", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出丫丫灵动", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = mainMenu.addItem(withTitle: "丫丫灵动", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu

        // Status-item menus do not route editing shortcuts to a window's field editor.
        // Leave targets nil so AppKit resolves the focused text or secure field.
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = mainMenu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }
}
