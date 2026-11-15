import UIKit

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func pop() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }

    /// A little drum-roll for the celebration screen.
    static func celebrate() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                generator.impactOccurred(intensity: 0.5 + Double(i) * 0.15)
            }
        }
    }
}
