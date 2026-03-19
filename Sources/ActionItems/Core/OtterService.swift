import Foundation

/// Otter.ai integration — watches Downloads folder for Otter text exports.
/// Otter doesn't have a stable public API, so v1 uses file detection.
/// Users export from Otter → auto-detected and processed by Flaxie.
class OtterService: ObservableObject {
    @Published var isWatching = false
    @Published var lastSyncDate: Date?

    var onTranscriptReady: ((String, String?, Date?) -> Void)?

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    private var processedHashes: Set<String> = []

    // Watch Downloads for Otter exports (txt files matching Otter naming patterns)
    private var watchDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    // MARK: - Watching

    func startWatching() {
        let dir = watchDirectory
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
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
            if let fd = self?.watchedFD, fd >= 0 { close(fd) }
        }
        dispatchSource = source
        source.resume()
        isWatching = true
        print("[Otter] Watching Downloads for exports")
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        isWatching = false
    }

    // MARK: - Event handling

    private func handleFSEvent(in directory: URL) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanForOtterFiles(in: directory)
        }
        debounceWorkItem = work
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func scanForOtterFiles(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let cutoff = Date().addingTimeInterval(-10 * 60) // last 10 minutes
        let otterFiles = files.filter { url in
            guard url.pathExtension.lowercased() == "txt" else { return false }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            // Otter exports typically contain "otter" in the name or follow "Speaker Name - date" pattern
            let isOtterLike = name.contains("otter") || name.contains("transcript") || name.contains("meeting")
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return isOtterLike && (modified ?? .distantPast) > cutoff
        }

        for file in otterFiles {
            processFile(file)
        }
    }

    private func processFile(_ url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              content.count > 100 else { return }

        let hash = simpleHash(content)
        guard !processedHashes.contains(hash) else { return }
        processedHashes.insert(hash)
        if processedHashes.count > 100 { processedHashes = Set(processedHashes.prefix(80)) }

        let title = url.deletingPathExtension().lastPathComponent
        let meetingDate = extractDate(from: content)

        print("[Otter] Processing export: \(url.lastPathComponent)")
        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = Date()
            self?.onTranscriptReady?(content, title, meetingDate)
        }
    }

    private func extractDate(from content: String) -> Date? {
        let sample = String(content.prefix(300))
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(sample.startIndex..., in: sample)
        return detector.firstMatch(in: sample, options: [], range: range)?.date
    }

    private func simpleHash(_ string: String) -> String {
        var hash = 5381
        for scalar in string.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        return "\(hash)"
    }
}
