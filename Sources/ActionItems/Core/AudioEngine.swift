import Foundation
import AVFoundation

/// Captures microphone audio and writes it to chunked WAV files at 16kHz mono.
/// Uses AVAudioRecorder for simplicity and reliability.
class AudioEngine: ObservableObject {
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var sessionURL: URL?
    private var timer: Timer?
    private var currentChunkIndex = 0

    // Callback called after each ~30s chunk is ready for transcription
    var onAudioChunkReady: ((URL) -> Void)?

    private let chunkIntervalSeconds: TimeInterval = 30

    // 16kHz mono 16-bit PCM — the format WhisperKit expects
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    func startRecording() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let sessionID = UUID().uuidString
        let dir = tempDir.appendingPathComponent("ActionItems-\(sessionID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionURL = dir
        currentChunkIndex = 0

        try startChunkRecorder(in: dir)
        isRecording = true

        // Rotate to a new chunk file every 30s
        timer = Timer.scheduledTimer(withTimeInterval: chunkIntervalSeconds, repeats: true) { [weak self] _ in
            self?.rotateChunk()
        }

        return dir
    }

    /// Stops recording and returns the final chunk URL for the caller to transcribe.
    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        let finalURL = recorder?.url
        recorder?.stop()
        recorder = nil
        isRecording = false
        sessionURL = nil
        return finalURL
    }

    // MARK: - Private

    private func startChunkRecorder(in dir: URL) throws {
        let url = dir.appendingPathComponent("chunk_\(currentChunkIndex).wav")
        recorder = try AVAudioRecorder(url: url, settings: recordingSettings)
        guard recorder?.record() == true else {
            throw AudioError.recordingFailed
        }
    }

    private func rotateChunk() {
        guard let dir = sessionURL else { return }
        let finishedURL = recorder?.url
        recorder?.stop()
        recorder = nil

        if let url = finishedURL {
            onAudioChunkReady?(url)
        }

        currentChunkIndex += 1
        try? startChunkRecorder(in: dir)
    }
}

enum AudioError: LocalizedError {
    case recordingFailed

    var errorDescription: String? {
        "Failed to start microphone recording. Check microphone permission in System Settings → Privacy → Microphone."
    }
}
