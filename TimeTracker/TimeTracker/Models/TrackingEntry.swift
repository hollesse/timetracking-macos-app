import Foundation

struct TrackingEntry {
    let startTime: Date
    let endTime: Date
    let appName: String
    let webDomain: String?

    var durationSeconds: Int {
        Int(endTime.timeIntervalSince(startTime))
    }

    var durationFormatted: String {
        let total = durationSeconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
