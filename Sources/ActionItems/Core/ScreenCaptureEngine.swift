import Foundation
import ScreenCaptureKit
import CoreImage
import AppKit
import CoreGraphics

class ScreenCaptureEngine {

    /// Returns true if screen recording permission is already granted (no prompt).
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests screen recording permission. Shows system dialog if not yet granted.
    /// Call this on app launch so the user is prompted early.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Captures the frontmost app window and returns (image, appName).
    /// Falls back to full-screen capture if the window can't be isolated.
    static func captureFrontmostWindow() async throws -> (CGImage, String) {
        // Don't preflight — CGPreflightScreenCaptureAccess() returns false until the app
        // restarts after permission is granted, causing false positives. Instead, just
        // attempt the capture and let SCShareableContent throw if truly denied.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // Map SCKit errors to our friendly error
            let ns = error as NSError
            if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
                || ns.domain == "com.apple.ScreenCaptureKit"
                || ns.code == -3801 {
                throw ScreenCaptureError.capturePermissionDenied
            }
            throw error
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Screen"

        // Don't capture ourselves
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let frontBundleID = frontApp?.bundleIdentifier ?? ""

        let targetWindows = content.windows.filter { window in
            let bid = window.owningApplication?.bundleIdentifier ?? ""
            return bid == frontBundleID
                && bid != ourBundleID
                && window.isOnScreen
                && window.frame.width > 200
                && window.frame.height > 100
        }
        .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height } // largest first

        if let targetWindow = targetWindows.first {
            return try await captureWindow(targetWindow, appName: appName)
        } else {
            // Fallback: full screen
            return try await captureDisplay(content.displays.first, appName: appName)
        }
    }

    // MARK: - Window capture

    private static func captureWindow(_ window: SCWindow, appName: String) async throws -> (CGImage, String) {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Use actual pixel size (retina-aware)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.scalesToFit = false
        config.showsCursor = false
        config.backgroundColor = .clear

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return (image, appName)
        } catch {
            // If single-window capture fails (e.g. some Electron apps), fall through to display capture
            print("Window capture failed (\(error)), falling back to display capture")
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return try await captureDisplay(content.displays.first, appName: appName)
        }
    }

    // MARK: - Full display capture

    private static func captureDisplay(_ display: SCDisplay?, appName: String) async throws -> (CGImage, String) {
        guard let display else { throw ScreenCaptureError.noDisplay }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let config = SCStreamConfiguration()
        config.width = Int(display.frame.width * scale)
        config.height = Int(display.frame.height * scale)
        config.scalesToFit = false
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return (image, appName)
    }
}

enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case capturePermissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display found to capture."
        case .capturePermissionDenied:
            return "Screen recording permission denied. Open System Settings → Privacy & Security → Screen Recording and enable ActionItems."
        }
    }
}
