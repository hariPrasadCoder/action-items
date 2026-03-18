import Foundation
import WhisperKit

/// Loads WhisperKit on-demand (when a meeting starts), transcribes audio, then releases.
/// WhisperKit model is released from memory when the engine is deallocated.
class TranscriptionEngine {
    private var whisper: WhisperKit?
    private var fullTranscript: [String] = []

    var onTranscriptUpdate: ((String) -> Void)?

    // MARK: - Lifecycle

    func prepare(modelSize: String = "base") async throws {
        let config = WhisperKitConfig(model: modelSize)
        whisper = try await WhisperKit(config)
    }

    func release() {
        whisper = nil    // Releases model from RAM
        fullTranscript = []
    }

    // MARK: - Transcribe

    func transcribeChunk(at url: URL) async throws -> String {
        guard let whisper else {
            throw TranscriptionError.notPrepared
        }

        let results = try await whisper.transcribe(audioPath: url.path)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        if !text.isEmpty {
            fullTranscript.append(text)
            onTranscriptUpdate?(text)
        }

        return text
    }

    var completeTranscript: String {
        fullTranscript.joined(separator: " ")
    }
}

enum TranscriptionError: LocalizedError {
    case notPrepared
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .notPrepared: return "Transcription engine not ready. Call prepare() first."
        case .noAudioData: return "No audio data to transcribe."
        }
    }
}
