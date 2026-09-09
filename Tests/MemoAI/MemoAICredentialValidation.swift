import Foundation

enum MemoAICredentialValidation {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemoAICredentialStore(fileURL: directory.appendingPathComponent("memo-ai-credentials.json"))
        try MemoAIValidation.require(try store.read() == nil, "缺少文件时应返回未配置，不能尝试自动迁移")
        try store.save("test-only-key")
        try MemoAIValidation.require(try store.read() == "test-only-key", "本地密钥无法读回")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        try MemoAIValidation.require((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "密钥文件权限应为 0600")
        try store.save("test-only-replacement")
        try MemoAIValidation.require(try store.read() == "test-only-replacement", "替换密钥未保存")
        try MemoAIValidation.require(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["memo-ai-credentials.json"], "保存遗留了临时密钥文件")

        try Data("invalid JSON".utf8).write(to: store.fileURL)
        var rejectedCorruption = false
        do { _ = try store.read() } catch { rejectedCorruption = true }
        try MemoAIValidation.require(rejectedCorruption, "损坏文件应报告读取失败")
        try store.save("test-only-repaired")
        try MemoAIValidation.require(try store.read() == "test-only-repaired", "重新填写密钥应可修复损坏文件")

        let blocker = directory.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let failed = MemoAICredentialStore(fileURL: blocker.appendingPathComponent("memo-ai-credentials.json"))
        var rejectedWrite = false
        do { try failed.save("test-only-key") } catch { rejectedWrite = true }
        try MemoAIValidation.require(rejectedWrite, "文件写入失败未报告")
        print("本地密钥验证通过：缺失、读写、替换、权限、损坏恢复、写入失败；模型流程不依赖钥匙串组件")
    }
}
