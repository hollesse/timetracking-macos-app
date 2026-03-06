import Foundation

class CSVExporter {

    func export(entries: [TrackingEntry], to folderURL: URL) {
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let fileNameFormatter = DateFormatter()
        fileNameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "session_\(fileNameFormatter.string(from: Date())).csv"
        let fileURL = folderURL.appendingPathComponent(fileName)

        var lines = ["start_time,end_time,duration_seconds,duration_formatted,app_name,web_domain"]

        for entry in entries {
            let start = timestampFormatter.string(from: entry.startTime)
            let end   = timestampFormatter.string(from: entry.endTime)
            let domain = entry.webDomain ?? ""
            // Wrap app name in quotes to handle names that contain commas
            let appName = "\"\(entry.appName)\""
            lines.append("\(start),\(end),\(entry.durationSeconds),\(entry.durationFormatted),\(appName),\(domain)")
        }

        let csv = lines.joined(separator: "\n")
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("CSVExporter: failed to write \(fileURL.path) — \(error)")
        }
    }
}
