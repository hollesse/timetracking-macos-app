import Foundation
import Combine

class SessionManager: ObservableObject {

    @Published var isTracking = false
    @Published var entries: [TrackingEntry] = []
    @Published var currentAppName: String = "-"
    @Published var currentDomain: String? = nil

    var outputFolderURL: URL? {
        get { UserDefaults.standard.url(forKey: "outputFolderURL") }
        set { UserDefaults.standard.set(newValue, forKey: "outputFolderURL") }
    }

    var hasOutputFolder: Bool { outputFolderURL != nil }

    private let trackingService = TrackingService()

    init() {
        trackingService.onEntryRecorded = { [weak self] entry in
            self?.entries.append(entry)
        }
        trackingService.onCurrentAppChanged = { [weak self] appName, domain in
            DispatchQueue.main.async {
                self?.currentAppName = appName
                self?.currentDomain = domain
            }
        }
    }

    func startTracking() {
        guard !isTracking else { return }
        entries = []
        currentAppName = "-"
        currentDomain = nil
        trackingService.start()
        isTracking = true
    }

    func stopTracking() {
        guard isTracking else { return }
        trackingService.stop()
        isTracking = false
        currentAppName = "-"
        currentDomain = nil
        exportCSV()
    }

    private func exportCSV() {
        guard let folderURL = outputFolderURL else { return }
        CSVExporter().export(entries: entries, to: folderURL)
    }
}
