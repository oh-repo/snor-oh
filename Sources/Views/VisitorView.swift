import SwiftUI

/// Renders a visiting peer's sprite with animation.
/// Falls back to the default built-in pet if the visitor's pet isn't available locally.
struct VisitorSprite: View {
    let pet: String
    @State private var engine: SpriteEngine?

    var body: some View {
        Group {
            if let engine {
                AnimatedSpriteView(engine: engine)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let e = SpriteEngine()
            e.setPet(resolvePet(pet))
            e.setStatus(.visiting)
            engine = e
        }
        .onDisappear {
            engine?.stop()
            engine = nil
        }
    }

    private func resolvePet(_ pet: String) -> String {
        if SpriteConfig.builtInPets.contains(pet) { return pet }
        if SpriteConfig.isCustomPet(pet),
           CustomOhhManager.shared.ohh(withID: pet) != nil { return pet }
        return SpriteConfig.builtInPets.first ?? "sprite"
    }
}
