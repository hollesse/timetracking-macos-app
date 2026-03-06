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

    // Prevents overlapping async domain lookups
    private var isDomainChecking = false

    // MARK: - Public API

    func start() {
        // Capture initial frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            let appName = frontmost.localizedName ?? "Unknown"
            currentApp = appName
            currentEntryStart = Date()
            currentDomain = nil
            onCurrentAppChanged?(appName, nil)
            if isTrackedBrowser(appName) {
                fetchDomainAsync(pid: frontmost.processIdentifier, forApp: appName)
            }
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

        // Poll every 2 s: domain changes + fallback app detection
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkDomainChange()
            self?.checkFrontmostApp()
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
        currentDomain = nil
        onCurrentAppChanged?(appName, nil)

        if isTrackedBrowser(appName) {
            fetchDomainAsync(pid: app.processIdentifier, forApp: appName)
        }
    }

    /// Fallback: catches app switches that the workspace notification may have missed.
    private func checkFrontmostApp() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        let appName = frontmost.localizedName ?? "Unknown"
        guard appName != currentApp else { return }
        handleAppSwitch(to: frontmost)
    }

    private func checkDomainChange() {
        guard !isDomainChecking else { return }
        guard let appName = currentApp, isTrackedBrowser(appName) else { return }

        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == appName
        }) else { return }

        let pid = runningApp.processIdentifier
        isDomainChecking = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let newDomain = self.fetchBrowserDomain(pid: pid)
            DispatchQueue.main.async {
                self.isDomainChecking = false
                guard self.currentApp == appName, newDomain != self.currentDomain else { return }
                let now = Date()
                self.finalizeCurrentEntry(at: now)
                self.currentDomain = newDomain
                self.currentEntryStart = now
                self.onCurrentAppChanged?(appName, newDomain)
            }
        }
    }

    /// Fetches the browser domain on a background thread to avoid blocking the main thread
    /// (Firefox's AX implementation can take several seconds to respond).
    private func fetchDomainAsync(pid: pid_t, forApp appName: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let domain = self.fetchBrowserDomain(pid: pid)
            DispatchQueue.main.async {
                guard self.currentApp == appName else { return }
                self.currentDomain = domain
                self.onCurrentAppChanged?(appName, domain)
            }
        }
    }

    private func finalizeCurrentEntry(at endTime: Date) {
        guard let app = currentApp, let start = currentEntryStart else { return }

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

    /// Safe to call from any thread; uses only AX IPC functions (thread-safe).
    private func fetchBrowserDomain(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let axApp = AXUIElementCreateApplication(pid)

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
