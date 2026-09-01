import AppKit
import Carbon.HIToolbox

struct ShortcutConfiguration: Equatable {
    static let keyCodeDefaultsKey = "global-shortcut-key-code"
    static let modifiersDefaultsKey = "global-shortcut-modifiers"
    static let defaultValue = ShortcutConfiguration(
        keyCode: UInt32(kVK_ANSI_Equal),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    let keyCode: UInt32
    let modifiers: UInt32

    static func load() -> ShortcutConfiguration {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeDefaultsKey) != nil,
              defaults.object(forKey: modifiersDefaultsKey) != nil else {
            return .defaultValue
        }
        return ShortcutConfiguration(
            keyCode: UInt32(defaults.integer(forKey: keyCodeDefaultsKey)),
            modifiers: UInt32(defaults.integer(forKey: modifiersDefaultsKey))
        )
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        UserDefaults.standard.set(Int(modifiers), forKey: Self.modifiersDefaultsKey)
    }

    var displayText: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        text += Self.keyName(for: keyCode, shifted: modifiers & UInt32(shiftKey) != 0)
        return text
    }

    var recorderDisplayText: String {
        (modifierSymbols + [Self.keyName(for: keyCode, shifted: modifiers & UInt32(shiftKey) != 0)])
            .joined(separator: " + ")
    }

    private var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers & UInt32(controlKey) != 0 { symbols.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { symbols.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { symbols.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { symbols.append("⌘") }
        return symbols
    }

    private static func keyName(for keyCode: UInt32, shifted: Bool) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_Equal: return shifted ? "+" : "="
        case kVK_ANSI_Minus: return shifted ? "_" : "-"
        case kVK_Space: return "空格"
        case kVK_Return: return "回车"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return "键\(keyCode)"
            }
            let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status: OSStatus = data.withUnsafeBytes { bytes in
                guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                    return OSStatus(paramErr)
                }
                return UCKeyTranslate(
                    layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, characters.count, &length, &characters
                )
            }
            guard status == noErr, length > 0 else { return "键\(keyCode)" }
            return String(utf16CodeUnits: characters, count: length).uppercased()
        }
    }
}

@MainActor
final class ShortcutRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var capturedConfiguration: ShortcutConfiguration?
    private var awaitingPrefix = ""
    private var cursorIsVisible = true
    private var cursorTimer: Timer?
    private var completedCombinationIsReleasing = false

    init(initial: ShortcutConfiguration) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 52))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.stringValue = "按下新的快捷键"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopCursorBlinking()
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopCursorBlinking() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let parts = modifierParts(for: flags)

        if completedCombinationIsReleasing {
            if parts.isEmpty { completedCombinationIsReleasing = false }
            return
        }

        guard !parts.isEmpty else {
            stopCursorBlinking()
            showPlaceholder()
            return
        }

        capturedConfiguration = nil
        awaitingPrefix = parts.joined(separator: " + ") + " + "
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .controlAccentColor
        startCursorBlinking()
        renderAwaitingInput()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }

        let strongModifiers = UInt32(cmdKey | optionKey | controlKey)
        guard modifiers & strongModifiers != 0 else {
            NSSound.beep()
            stopCursorBlinking()
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.stringValue = "请先按 Command、Option 或 Control"
            return
        }

        let configuration = ShortcutConfiguration(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        capturedConfiguration = configuration
        completedCombinationIsReleasing = true
        stopCursorBlinking()
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .controlAccentColor
        label.stringValue = configuration.recorderDisplayText
    }

    private func modifierParts(for flags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts
    }

    private func startCursorBlinking() {
        guard cursorTimer == nil else { return }
        cursorIsVisible = true
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cursorIsVisible.toggle()
                self.renderAwaitingInput()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    private func stopCursorBlinking() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursorIsVisible = false
    }

    private func renderAwaitingInput() {
        label.stringValue = awaitingPrefix + (cursorIsVisible ? "│" : " ")
    }

    private func showPlaceholder() {
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.stringValue = "按下新的快捷键"
    }
}
