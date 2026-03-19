import Foundation

/// Watches Granola's local notes directory for new/changed meeting notes.
/// Uses FSEvents (via DispatchSource) for near-instant detection.
class GranolaService: ObservableObject {
    @Published var isWatching = false
    @Published var watchedDirectory: URL?
    @Published var lastSyncDate: Date?

    // Callback: fires with (noteText, meetingTitle, meetingDate) when new notes are detected
    var onNotesDetected: ((String, String?, Date?) -> Void)?

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?

    // Maps file path → date when it was last successfully processed.
    // A file is skipped if it was processed less than 1 hour ago (prevents
    // duplicates from Granola's live-save updates during a meeting).
    private let processedFilesKey = "granola_processed_files_v2"
    private var processedFiles: [String: Date] {
        get {
            guard let data = UserDefaults.standard.data(forKey: processedFilesKey),
                  let dict = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: processedFilesKey)
            }
        }
    }
    private let minReprocessInterval: TimeInterval = 3600 // 1 hour

    // Known Granola note locations
    static let knownPaths: [String] = [
        "\(NSHomeDirectory())/Library/Application Support/Granola",
        "\(NSHomeDirectory())/Documents/Granola"
    ]

    // MARK: - Auto-detect

    static func detectGranolaDirectory() -> URL? {
        for path in knownPaths {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }

    // MARK: - Watching

    func startWatching(directory: URL? = nil) {
        let dir = directory ?? Self.detectGranolaDirectory()
        guard let dir else {
            print("[Granola] No directory found to watch")
            return
        }
        stopWatching()
        watchedDirectory = dir

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[Granola] Could not open directory: \(dir.path)")
            return
        }
        watchedFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .background)
        )

        source.setEventHandler { [weak self] in
            self?.handleFSEvent(in: dir)
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchedFD, fd >= 0 {
                close(fd)
                self?.watchedFD = -1
            }
        }

        dispatchSource = source
        source.resume()
        isWatching = true
        print("[Granola] Watching: \(dir.path)")

        // Also do an initial scan
        handleFSEvent(in: dir)
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        isWatching = false
    }

    // MARK: - Event handling

    private func handleFSEvent(in directory: URL) {
        // Debounce — Granola may save multiple times in quick succession
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanDirectory(directory)
        }
        debounceWorkItem = work
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func scanDirectory(_ directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }

        // On initial scan at launch: only process files from the last 7 days.
        // On subsequent FS-event scans: last 5 minutes (active session only).
        let isInitialScan = lastSyncDate == nil
        let cutoff = isInitialScan
            ? Date().addingTimeInterval(-7 * 24 * 3600)   // 1 week
            : Date().addingTimeInterval(-5 * 60)           // 5 minutes

        let recentFiles = files.filter { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "txt" || ext == "json" else { return false }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (modified ?? .distantPast) > cutoff
        }

        for file in recentFiles {
            processFile(file)
        }
    }

    private func processFile(_ url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Skip if we processed this file less than 1 hour ago.
        // Granola saves the same file many times during a meeting; without this
        // guard each save triggers a new extraction producing near-duplicate items.
        var files = processedFiles
        let key = url.path
        if let lastProcessed = files[key], Date().timeIntervalSince(lastProcessed) < minReprocessInterval {
            return
        }
        files[key] = Date()
        // Prune entries older than 30 days to keep storage small
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        files = files.filter { $0.value > cutoff }
        processedFiles = files

        let title = extractTitle(from: url, content: content)
        let meetingDate = extractDate(from: url, content: content)
        let noteText = extractNoteText(from: content, url: url)

        print("[Granola] Processing: \(url.lastPathComponent), \(noteText.count) chars")

        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = Date()
            self?.onNotesDetected?(noteText, title, meetingDate)
        }
    }

    // MARK: - Parsing helpers

    private func extractTitle(from url: URL, content: String) -> String? {
        // Try markdown H1
        if let line = content.components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") }) {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        // Try JSON title field
        if url.pathExtension == "json",
           let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json["title"] as? String ?? json["name"] as? String
        }
        // Fall back to filename without extension
        return url.deletingPathExtension().lastPathComponent
    }

    private func extractDate(from url: URL, content: String) -> Date? {
        // Try NSDataDetector on first 500 chars
        let sample = String(content.prefix(500))
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(sample.startIndex..., in: sample)
        return detector.firstMatch(in: sample, options: [], range: range)?.date
    }

    private func extractNoteText(from content: String, url: URL) -> String {
        // If JSON, try to extract transcript/summary fields
        if url.pathExtension == "json",
           let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let fields = ["transcript", "summary", "notes", "content", "body"]
            for field in fields {
                if let text = json[field] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return content
    }

}
