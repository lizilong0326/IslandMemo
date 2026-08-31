import Foundation

struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let fingerprint: String
    var text: String?
    var imageFileName: String?
    var copiedAt: Date
    var sourceApplication: String?
}
