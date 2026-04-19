import SwiftUI

/// Renders a visiting peer's sprite with animation.
/// Falls back to the default built-in pet if the visitor's pet isn't available locally.
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
                Image(systemName: "pawprint.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let effectivePet = resolvePet(pet)
            engine.setPet(effectivePet)
            engine.setStatus(.visiting)
        }
        .onDisappear {
            engine.stop()
        }
    }

    /// Check if the pet exists locally. If not, fall back to default built-in.
    private func resolvePet(_ pet: String) -> String {
        // Built-in pets are always available
        if SpriteConfig.builtInPets.contains(pet) {
            return pet
        }
        // Custom pets: check if it exists in the local CustomOhhManager
        if SpriteConfig.isCustomPet(pet),
           CustomOhhManager.shared.ohh(withID: pet) != nil {
            return pet
        }
        // Fallback to default
        return SpriteConfig.builtInPets.first ?? "sprite"
    }
}
