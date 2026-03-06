import SwiftUI
import ApplicationServices

struct MenuBarView: View {

    @ObservedObject var sessionManager: SessionManager

    /// Re-check permission every time the view appears (e.g. user returns from System Settings).
    @State private var hasAccessibility = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !hasAccessibility {
                OnboardingView(onPermissionGranted: {
                    hasAccessibility = true
                })
            } else if !sessionManager.hasOutputFolder {
                folderRequiredView
            } else {
                statusSection
                Divider()
                controlButton
            }

            Divider()
            footerActions
        }
        .frame(width: 280)
        .onAppear {
            hasAccessibility = AXIsProcessTrusted()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "stopwatch")
                .font(.title3)
                .foregroundColor(.accentColor)
            Text("TimeTracker")
                .font(.headline)
            Spacer()
            if sessionManager.isTracking {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(Color.green.opacity(0.4), lineWidth: 3)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(
                label: "Status",
                value: sessionManager.isTracking ? "Aufnahme läuft" : "Bereit"
            )
            if sessionManager.isTracking {
                statusRow(label: "App", value: sessionManager.currentAppName)
                if let domain = sessionManager.currentDomain {
                    statusRow(label: "Domain", value: domain)
                }
                statusRow(label: "Einträge", value: "\(sessionManager.entries.count)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
        }
    }

    private var controlButton: some View {
        Button {
            if sessionManager.isTracking {
                sessionManager.stopTracking()
            } else {
                sessionManager.startTracking()
            }
        } label: {
            HStack {
                Image(systemName: sessionManager.isTracking ? "stop.circle.fill" : "play.circle.fill")
                Text(sessionManager.isTracking ? "Stopp" : "Start")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(sessionManager.isTracking ? .red : .green)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var folderRequiredView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Kein Ausgabe-Ordner gesetzt", systemImage: "folder.badge.questionmark")
                .font(.subheadline)
                .foregroundColor(.orange)
            Button("Ordner auswählen…") { selectOutputFolder() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footerActions: some View {
        VStack(spacing: 0) {
            menuButton("Ausgabe-Ordner ändern…", icon: "folder") {
                selectOutputFolder()
            }
            Divider()
            menuButton("Beenden", icon: "power", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func menuButton(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Folder Selection

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.message = "Ordner für die CSV-Dateien wählen"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            sessionManager.outputFolderURL = url
        }
    }
}
