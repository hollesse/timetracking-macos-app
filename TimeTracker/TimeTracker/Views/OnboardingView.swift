import SwiftUI

struct OnboardingView: View {

    var body: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func openAccessibilitySettings() {
        // Deep link into Privacy & Security → Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
