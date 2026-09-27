import AVFoundation
import Foundation

/// A short, quiet tick generated in memory so the timer has no external sound asset.
@MainActor
final class PomodoroTickSound {
    private let player: AVAudioPlayer?

    init() {
        let player = try? AVAudioPlayer(data: Self.makeWAV())
        player?.volume = 0.32
        player?.prepareToPlay()
        self.player = player
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
    }

    static func makeWAV() -> Data {
        let sampleRate: UInt32 = 22_050
        let sampleCount = Int(Double(sampleRate) * 0.07)
        let audioBytes = UInt32(sampleCount * MemoryLayout<Int16>.size)
        var wav = Data(capacity: 44 + Int(audioBytes))

        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }

        wav.append(contentsOf: "RIFF".utf8)
        appendLE(UInt32(36) + audioBytes)
        wav.append(contentsOf: "WAVEfmt ".utf8)
        appendLE(UInt32(16))
        appendLE(UInt16(1)) // PCM
        appendLE(UInt16(1)) // mono
        appendLE(sampleRate)
        appendLE(sampleRate * 2)
        appendLE(UInt16(2))
        appendLE(UInt16(16))
        wav.append(contentsOf: "data".utf8)
        appendLE(audioBytes)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let attack = min(time / 0.002, 1)
            let envelope = attack * exp(-55 * time)
            let tone = sin(2 * .pi * 1_100 * time)
                + 0.35 * sin(2 * .pi * 1_750 * time)
            appendLE(Int16((tone * envelope * 0.27 * Double(Int16.max)).rounded()))
        }
        return wav
    }
}
