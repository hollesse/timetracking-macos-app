import SwiftUI

@main
struct TimeTrackerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        MenuBarExtra("TimeTracker", systemImage: "stopwatch") {
            MenuBarView(sessionManager: sessionManager)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First-run: ask user to pick an output folder before they need it.
        if UserDefaults.standard.url(forKey: "outputFolderURL") == nil {
            DispatchQueue.main.async {
                self.promptForOutputFolder()
            }
        }
    }

    func promptForOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.message = "Bitte wähle einen Ordner, in dem TimeTracker die CSV-Dateien speichern soll."
        panel.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url, forKey: "outputFolderURL")
        }
    }
}
