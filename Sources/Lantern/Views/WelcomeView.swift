import SwiftUI

/// What a new conversation shows before the first message: the mark and a greeting, nothing else.
/// The greeting follows the Mac's clock.
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: Space.lg) {
            BrandMark()
                .frame(width: 48, height: 48)
            Text(greeting)
                .font(.system(.largeTitle, design: .serif))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}
