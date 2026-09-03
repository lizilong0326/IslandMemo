import AppKit
import Combine
import Foundation

struct DetectedAIApplication: Identifiable, Equatable {
    enum Integration: String {
        case connected = "已接入"
        case available = "可接入"
        case nativeOnly = "仅应用通知"
    }

    let id: String
    let name: String
    let systemImage: String
    let location: String
    let integration: Integration
    let detail: String
}

/// 扫描本机应用、命令行工具和公开配置文件，识别常见 AI 应用及其完成通知接入状态。
/// macOS 不提供读取其他应用通知能力的统一公开接口，因此这里不会读取系统通知内容。
@MainActor
final class AIApplicationDetector: ObservableObject {
    @Published private(set) var applications: [DetectedAIApplication] = []
    @Published private(set) var lastScannedAt: Date?

    private struct Candidate {
        let id: String
        let name: String
        let aliases: [String]
        let systemImage: String
        let supportsCompletionHook: Bool
        let installHints: [String]
        let configuredFiles: [String]
        let configuredMarkers: [String]
    }

    private let candidates: [Candidate] = [
        Candidate(
            id: "codex", name: "Codex", aliases: ["codex"], systemImage: "terminal",
            supportsCompletionHook: true,
            installHints: ["~/.codex", "/Applications/ChatGPT.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"],
            configuredFiles: ["~/.codex/config.toml"],
            configuredMarkers: ["43821", "codex-notify"]
        ),
        Candidate(
            id: "claude-code", name: "Claude Code", aliases: ["claude code"], systemImage: "terminal",
            supportsCompletionHook: true,
            installHints: ["~/.claude", "~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"],
            configuredFiles: ["~/.claude/settings.json"],
            configuredMarkers: ["43821", "claude-notify"]
        ),
        Candidate(
            id: "windsurf", name: "Windsurf", aliases: ["windsurf"], systemImage: "wind",
            supportsCompletionHook: true,
            installHints: ["~/.codeium/windsurf", "~/.windsurf"],
            configuredFiles: ["~/.codeium/windsurf/hooks.json", "~/.windsurf/hooks.json"],
            configuredMarkers: ["43821", "post_cascade_response"]
        ),
        Candidate(
            id: "cursor", name: "Cursor", aliases: ["cursor"], systemImage: "cursorarrow.rays",
            supportsCompletionHook: false, installHints: ["~/.cursor"], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "chatgpt", name: "ChatGPT", aliases: ["chatgpt"], systemImage: "bubble.left.and.bubble.right",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "claude", name: "Claude", aliases: ["claude"], systemImage: "bubble.left.and.text.bubble.right",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "kimi", name: "Kimi", aliases: ["kimi"], systemImage: "moon.stars",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "doubao", name: "豆包", aliases: ["doubao", "豆包"], systemImage: "brain.head.profile",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "gemini", name: "Gemini", aliases: ["gemini"], systemImage: "sparkles",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "deepseek", name: "DeepSeek", aliases: ["deepseek"], systemImage: "magnifyingglass",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "trae", name: "Trae", aliases: ["trae"], systemImage: "hammer",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "poe", name: "Poe", aliases: ["poe"], systemImage: "ellipsis.bubble",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
        Candidate(
            id: "perplexity", name: "Perplexity", aliases: ["perplexity"], systemImage: "globe",
            supportsCompletionHook: false, installHints: [], configuredFiles: [], configuredMarkers: []
        ),
    ]

    init() {
        scan()
    }

    func scan() {
        let installedApps = applicationLocations()
        var detected: [DetectedAIApplication] = []

        for candidate in candidates {
            let matchingApp = installedApps.first { item in
                candidate.aliases.contains { item.name.localizedCaseInsensitiveContains($0) }
            }
            let matchingHint = candidate.installHints
                .map(expandPath)
                .first { FileManager.default.fileExists(atPath: $0) }
            guard matchingApp != nil || matchingHint != nil else { continue }

            let configured = candidate.supportsCompletionHook && isConfigured(candidate)
            let integration: DetectedAIApplication.Integration = configured
                ? .connected
                : (candidate.supportsCompletionHook ? .available : .nativeOnly)
            let detail: String
            switch integration {
            case .connected:
                detail = "已发现丫丫灵动任务完成通知配置"
            case .available:
                detail = "支持完成钩子，可接入丫丫灵动"
            case .nativeOnly:
                detail = "可使用应用自身通知，暂未发现公开完成钩子"
            }
            detected.append(DetectedAIApplication(
                id: candidate.id,
                name: candidate.name,
                systemImage: candidate.systemImage,
                location: matchingApp?.path ?? matchingHint ?? "",
                integration: integration,
                detail: detail
            ))
        }

        applications = detected.sorted {
            if $0.integration != $1.integration {
                let order: [DetectedAIApplication.Integration] = [.connected, .available, .nativeOnly]
                return (order.firstIndex(of: $0.integration) ?? 0) < (order.firstIndex(of: $1.integration) ?? 0)
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        lastScannedAt = .now
    }

    private func applicationLocations() -> [(name: String, path: String)] {
        let roots = ["/Applications", expandPath("~/Applications")]
        var result: [(String, String)] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                result.append((url.deletingPathExtension().lastPathComponent, url.path))
                enumerator.skipDescendants()
            }
        }
        return result
    }

    private func isConfigured(_ candidate: Candidate) -> Bool {
        for file in candidate.configuredFiles.map(expandPath) {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            if candidate.configuredMarkers.contains(where: content.contains) { return true }
        }
        return false
    }

    private func expandPath(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }
}
