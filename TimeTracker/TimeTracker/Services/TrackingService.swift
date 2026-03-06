import AppKit
import ApplicationServices

class TrackingService {

    /// Called on the main thread whenever a completed entry is ready.
    var onEntryRecorded: ((TrackingEntry) -> Void)?

    /// Called on the main thread whenever the active app or domain changes.
    var onCurrentAppChanged: ((String, String?) -> Void)?

    private var workspaceObserver: Any?
    private var pollTimer: Timer?

    // Current tracking state
    private var currentApp: String?
    private var currentDomain: String?   // non-nil only when a tracked browser is frontmost
    private var currentEntryStart: Date?

    private let minimumDuration: TimeInterval = 2.0

    // MARK: - Public API

    func start() {
        // Capture initial frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            let appName = frontmost.localizedName ?? "Unknown"
            currentApp = appName
            currentEntryStart = Date()
            currentDomain = isTrackedBrowser(appName) ? fetchBrowserDomain(for: frontmost) : nil
            onCurrentAppChanged?(appName, currentDomain)
        }

        // React to app switches
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.handleAppSwitch(to: app)
        }

        // Poll browser domain every 2 s to catch tab changes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkDomainChange()
        }
    }

    func stop() {
        finalizeCurrentEntry(at: Date())
        cleanup()
    }

    // MARK: - Private

    private func handleAppSwitch(to app: NSRunningApplication) {
        let now = Date()
        finalizeCurrentEntry(at: now)

        let appName = app.localizedName ?? "Unknown"
        currentApp = appName
        currentEntryStart = now
        currentDomain = isTrackedBrowser(appName) ? fetchBrowserDomain(for: app) : nil
        onCurrentAppChanged?(appName, currentDomain)
    }

    private func checkDomainChange() {
        guard let appName = currentApp, isTrackedBrowser(appName) else { return }

        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == appName
        }) else { return }

        // Only treat as a domain change if we successfully read a domain.
        // A nil result (e.g. during page load or AX tree not yet ready) must not
        // reset currentEntryStart — otherwise the entry gets split into sub-2s
        // fragments that are silently discarded by the minimum-duration filter.
        guard let newDomain = fetchBrowserDomain(for: runningApp),
              newDomain != currentDomain else { return }

        let now = Date()
        finalizeCurrentEntry(at: now)
        currentDomain = newDomain
        currentEntryStart = now
        onCurrentAppChanged?(appName, newDomain)
    }

    private func finalizeCurrentEntry(at endTime: Date) {
        guard let app = currentApp, let start = currentEntryStart else { return }
        let duration = endTime.timeIntervalSince(start)
        guard duration >= minimumDuration else { return }

        let entry = TrackingEntry(
            startTime: start,
            endTime: endTime,
            appName: app,
            webDomain: currentDomain
        )
        onEntryRecorded?(entry)
    }

    private func cleanup() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        currentApp = nil
        currentDomain = nil
        currentEntryStart = nil
    }

    // MARK: - Browser Detection

    private func isTrackedBrowser(_ appName: String) -> Bool {
        appName == "Firefox"
    }

    // MARK: - Domain Reading via Accessibility API

    private func fetchBrowserDomain(for app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, "AXWindows" as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let mainWindow = windows.first else { return nil }

        return searchForURLField(in: mainWindow)
    }

    /// Recursively walks the AX tree to find a text field whose value looks like a URL.
    private func searchForURLField(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 10 else { return nil }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &roleRef)

        if let role = roleRef as? String, role == "AXTextField" {
            var valueRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXValue" as CFString, &valueRef)
            if let urlString = valueRef as? String, looksLikeURL(urlString) {
                return extractDomain(from: urlString)
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = searchForURLField(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private func looksLikeURL(_ string: String) -> Bool {
        string.hasPrefix("http://") ||
        string.hasPrefix("https://") ||
        string.hasPrefix("about:") ||
        string.hasPrefix("file://")
    }

    private func extractDomain(from urlString: String) -> String? {
        if urlString.hasPrefix("about:") { return urlString }
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
