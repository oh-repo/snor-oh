import SwiftUI

/// Displays a visiting peer's sprite in the bottom-right of the mascot window.
/// Shows a small label with the visitor's nickname.
struct VisitorView: View {
    let visitors: [VisitingDog]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visitors.prefix(3)) { visitor in
                VStack(spacing: 2) {
                    // Visitor sprite (idle animation for their pet)
                    VisitorSprite(pet: visitor.pet)
                        .frame(width: 48, height: 48)

                    Text(visitor.nickname)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Renders an idle sprite for a visiting pet at small scale.
struct VisitorSprite: View {
    let pet: String
    @State private var engine = SpriteEngine()

    var body: some View {
        Group {
            if let frame = engine.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(.gray.opacity(0.3))
            }
        }
        .onAppear {
            engine.setPet(pet)
            engine.setStatus(.visiting)
        }
        .onDisappear {
            engine.stop()
        }
    }
}
