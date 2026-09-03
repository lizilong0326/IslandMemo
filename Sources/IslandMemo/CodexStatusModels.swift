import Foundation

// Adapted from CodexFloat's MIT-licensed CodexQuotaCore.
// See THIRD_PARTY_NOTICES.md for attribution.

enum CodexStatusFreshness: String, Codable, Sendable {
    case fresh
    case stale
}

struct CodexQuotaWindow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let limitID: String
    let limitName: String?
    let windowName: String
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: Date?

    init(
        id: String,
        limitID: String,
        limitName: String?,
        windowName: String,
        usedPercent: Double,
        windowDurationMinutes: Int?,
        resetsAt: Date?
    ) {
        self.id = id
        self.limitID = limitID
        self.limitName = limitName
        self.windowName = windowName
        self.usedPercent = min(100, max(0, usedPercent))
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    var remainingPercent: Double { max(0, 100 - usedPercent) }

    var shortName: String {
        switch windowDurationMinutes {
        case 300: return "5 小时"
        case 10_080: return "每周"
        default: return windowName
        }
    }

    var isSupplementaryGPTQuota: Bool {
        let normalizedID = limitID.lowercased()
        let normalizedName = limitName?.lowercased() ?? ""
        return normalizedID == "base_model_inference"
            || normalizedID == "codex_bengalfox"
            || normalizedID.hasPrefix("gpt")
            || normalizedName.contains("gpt-reserve")
            || normalizedName.hasPrefix("gpt-")
    }
}

struct CodexQuotaSnapshot: Codable, Equatable, Sendable {
    let planType: String?
    let windows: [CodexQuotaWindow]
    let resetCreditCount: Int?
    let observedAt: Date
    var freshness: CodexStatusFreshness

    var visibleWindows: [CodexQuotaWindow] {
        let standard = windows.filter { !$0.isSupplementaryGPTQuota }
        let exactCodex = standard.filter { $0.limitID.lowercased() == "codex" }
        return exactCodex.isEmpty ? standard : exactCodex
    }

    var preferredWindow: CodexQuotaWindow? {
        visibleWindows.first(where: { $0.id.hasSuffix(":primary") }) ?? visibleWindows.first
    }
}

enum CodexTaskState: String, Codable, Equatable, Sendable {
    case idle
    case working
    case error

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .working: return "工作中"
        case .error: return "报错"
        }
    }
}

struct CodexTaskSummary: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let state: CodexTaskState
    let updatedAt: Date
    let source: String?

    func withState(_ state: CodexTaskState) -> CodexTaskSummary {
        CodexTaskSummary(id: id, title: title, state: state, updatedAt: updatedAt, source: source)
    }

    var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(id)"
        return components.url
    }
}

enum CodexStatusDecodingError: Error, LocalizedError, Sendable {
    case invalidJSON
    case missingResult
    case missingRateLimits

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Codex 返回了无效数据"
        case .missingResult: return "Codex 响应缺少结果"
        case .missingRateLimits: return "Codex 响应没有额度窗口"
        }
    }
}

enum CodexStatusDecoder {
    static func decodeQuota(_ data: Data, observedAt: Date = .now) throws -> CodexQuotaSnapshot {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexStatusDecodingError.invalidJSON
        }
        guard let result = envelope["result"] as? [String: Any] else {
            throw CodexStatusDecodingError.missingResult
        }

        var buckets: [(String, [String: Any])] = []
        if let dynamic = result["rateLimitsByLimitId"] as? [String: Any] {
            buckets = dynamic.compactMap { key, value in
                guard let dictionary = value as? [String: Any] else { return nil }
                return (key, dictionary)
            }.sorted { $0.0 < $1.0 }
        }
        if buckets.isEmpty, let legacy = result["rateLimits"] as? [String: Any] {
            buckets = [(string(legacy["limitId"]) ?? "codex", legacy)]
        }
        guard !buckets.isEmpty else { throw CodexStatusDecodingError.missingRateLimits }

        var windows: [CodexQuotaWindow] = []
        var planType: String?
        for (fallbackID, bucket) in buckets {
            let limitID = string(bucket["limitId"]) ?? fallbackID
            let limitName = string(bucket["limitName"])
            planType = planType ?? string(bucket["planType"])
            for (key, label) in [("primary", "主窗口"), ("secondary", "次窗口")] {
                guard let raw = bucket[key] as? [String: Any], let used = double(raw["usedPercent"]) else {
                    continue
                }
                windows.append(CodexQuotaWindow(
                    id: "\(limitID):\(key)",
                    limitID: limitID,
                    limitName: limitName,
                    windowName: label,
                    usedPercent: used,
                    windowDurationMinutes: integer(raw["windowDurationMins"]),
                    resetsAt: date(raw["resetsAt"])
                ))
            }
        }

        return CodexQuotaSnapshot(
            planType: planType,
            windows: windows.sorted { $0.id < $1.id },
            resetCreditCount: integer((result["rateLimitResetCredits"] as? [String: Any])?["availableCount"]),
            observedAt: observedAt,
            freshness: .fresh
        )
    }

    static func decodeTasks(_ data: Data) throws -> [CodexTaskSummary] {
        struct Response: Decodable {
            struct Body: Decodable { let data: [Thread] }
            struct Thread: Decodable {
                struct Status: Decodable { let type: String }
                let id: String
                let name: String?
                let updatedAt: Double
                let recencyAt: Double?
                let source: String?
                let status: Status?
            }
            let result: Body
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.result.data.map { thread in
            let title = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let state: CodexTaskState
            switch thread.status?.type {
            case "active": state = .working
            case "systemError": state = .error
            default: state = .idle
            }
            return CodexTaskSummary(
                id: thread.id,
                title: title.isEmpty ? "未命名任务" : title,
                state: state,
                updatedAt: Date(timeIntervalSince1970: thread.recencyAt ?? thread.updatedAt),
                source: thread.source
            )
        }
    }

    private static func string(_ value: Any?) -> String? {
        value is NSNull || value == nil ? nil : value as? String
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        double(value).map(Date.init(timeIntervalSince1970:))
    }
}
