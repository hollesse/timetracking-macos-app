import SwiftUI
import ApplicationServices

struct OnboardingView: View {

    /// Called when the polling loop detects that the permission was granted.
    var onPermissionGranted: (() -> Void)?

    /// `true` once we detect the permission in TCC — but the process still needs a restart.
    @State private var permissionSeenInTCC = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if permissionSeenInTCC {
                restartRequiredView
            } else {
                grantPermissionView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Poll AXIsProcessTrusted() once per second until it flips to true.
        .task {
            await pollForPermission()
        }
    }

    // MARK: - Sub-views

    private var grantPermissionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Berechtigung erforderlich", systemImage: "hand.raised.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)

            Text(
                "TimeTracker benötigt Zugriff auf **Bedienungshilfen**, um die aktive URL in Firefox auszulesen.\n\n" +
                "1. Klicke auf den Button unten\n" +
                "2. Klicke auf das **+** und füge TimeTracker hinzu\n" +
                "3. Aktiviere den Schalter neben TimeTracker\n" +
                "4. Öffne das Menü erneut"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                openAccessibilitySettings()
            } label: {
                Label("Systemeinstellungen öffnen", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Shown after TCC has the permission but before the process has been restarted.
    private var restartRequiredView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Neustart erforderlich", systemImage: "arrow.clockwise.circle.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)

            Text(
                "Die Berechtigung wurde erkannt.\n\n" +
                "macOS aktiviert Bedienungshilfen-Zugriff erst nach einem Neustart der App. " +
                "Bitte starte TimeTracker neu."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                restartApp()
            } label: {
                Label("TimeTracker neu starten", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }

    // MARK: - Logic

    /// Polls `AXIsProcessTrusted()` every second. When it returns `true`, either we
    /// directly signal `onPermissionGranted` (if the process already sees it) or we
    /// show the restart-required banner.
    private func pollForPermission() async {
        while !Task.isCancelled {
            let trusted = AXIsProcessTrusted()
            if trusted {
                await MainActor.run {
                    // The process sees the permission — propagate upwards immediately.
                    onPermissionGranted?()
                }
                return
            }

            // Check TCC via prompt-less options call; if macOS already recorded the
            // grant but the process hasn't reloaded yet, the flag flips here.
            let options = [kAXTrustedCheckOptionPrompt: false] as CFDictionary
            let tccGranted = AXIsProcessTrustedWithOptions(options)
            if tccGranted && !permissionSeenInTCC {
                await MainActor.run {
                    permissionSeenInTCC = true
                }
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func restartApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            NSApplication.shared.terminate(nil)
        }
    }
}
