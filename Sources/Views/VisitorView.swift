import SwiftUI

/// Renders a visiting peer's sprite with animation and nickname label.
/// Falls back to the default built-in pet if the visitor's pet isn't available locally
/// (e.g., custom pets that only exist on the visitor's machine).
struct VisitorSprite: View {
    let pet: String
    @State private var engine = SpriteEngine()
    @State private var useFallback = false

    /// The pet to actually render — original or fallback.
    private var effectivePet: String {
        if useFallback {
            return SpriteConfig.builtInPets.first ?? "sprite"
        }
        return pet
    }

    var body: some View {
        Group {
            if let frame = engine.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Check if the pet's sprites are available locally
            let frames = SpriteCache.shared.frames(pet: pet, status: .idle)
            if frames.isEmpty && !SpriteConfig.builtInPets.contains(pet) {
                useFallback = true
            }
            engine.setPet(effectivePet)
            engine.setStatus(.visiting)
        }
        .onDisappear {
            engine.stop()
        }
    }
}
