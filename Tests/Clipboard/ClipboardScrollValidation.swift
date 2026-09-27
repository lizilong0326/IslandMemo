import AppKit
import SwiftUI

@main
struct ClipboardScrollValidation {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                print("PASS: clipboard layout and scrolling remain responsive")
                app.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        // Separate bundle defaults and a temporary data directory: never modify
        // the user's clipboard history, preferences, or general pasteboard.
        UserDefaults.standard.set(100, forKey: "clipboard-max-items")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardScrollValidation-\(UUID())")
        let images = directory.appendingPathComponent("ClipboardImages")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 900,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: images.appendingPathComponent("fixture.png"))
        let settings = AppSettingsStore()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 868, height: 413),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "复制记录滚动验证（测试数据）"
        defer { window.close() }
        for count in [0, 1, 20, 100] {
            let entries = (0..<count).map { index in
                ClipboardEntry(id: UUID(), kind: index % 7 == 0 ? .image : .text,
                               fingerprint: "fixture-\(index)",
                               text: String(repeating: "记录 \(index)：中英文 mixed text 长度与换行测试。\n", count: index % 9 == 0 ? 120 : index % 5 + 1),
                               imageFileName: index % 7 == 0 ? "fixture.png" : nil,
                               copiedAt: .now, sourceApplication: index % 3 == 0 ? "较长的应用名称 Source Application" : "测试")
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: directory.appendingPathComponent("clipboard-history.json"))
            let store = ClipboardStore(dataDirectory: directory)
            precondition(store.entries.count == count)
            let host = NSHostingView(rootView: ClipboardHistoryView(store: store, settings: settings, onGenerateMemo: { _, _ in })
                .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).preferredColorScheme(.dark))
            window.contentView = host
            window.orderFront(nil)
            for width in [720.0, 868.0, 1200.0] {
                window.setContentSize(NSSize(width: width, height: 413))
                settings.clipboardPreviewLines = width == 720 ? 1 : 8
                try await Task.sleep(for: .milliseconds(60))
                host.layoutSubtreeIfNeeded()
                let scrollers = descendants(host).compactMap { $0 as? NSScrollView }
                precondition(count == 0 || scrollers.count == 1, "Nonempty history must have one scroll view")
                let initialHeight = scrollers.first?.documentView?.bounds.height ?? 0
                if count >= 20 {
                    precondition(initialHeight > scrollers[0].contentView.bounds.height, "Fixture must overflow")
                }
                print("fixture=\(count) width=\(width) nativeScrollViews=\(scrollers.count)")
                for step in 0..<(count == 0 ? 0 : 80) {
                    if let scroll = scrollers.first, let document = scroll.documentView {
                        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
                        let fraction = CGFloat(step % 20) / 19
                        let y = maximum * (step / 20 % 2 == 0 ? fraction : 1 - fraction)
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                    try await Task.sleep(for: .milliseconds(5))
                    host.layoutSubtreeIfNeeded()
                    if let scroll = scrollers.first, let document = scroll.documentView {
                        precondition(abs(document.bounds.height - initialHeight) < 1, "Scrolling changed the content height")
                        if step == 19 {
                            let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
                            precondition(abs(scroll.contentView.bounds.minY - maximum) < 1, "Cannot reach the last record")
                        }
                        if step == 39 {
                            precondition(abs(scroll.contentView.bounds.minY) < 1, "Cannot scroll back to the first record")
                        }
                    }
                }
            }
        }
    }

    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
