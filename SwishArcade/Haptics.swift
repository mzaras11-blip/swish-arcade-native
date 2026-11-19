import UIKit

/// Tactile pulses for the ad's physical beats: the tile SET is the big one.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare(); medium.prepare(); heavy.prepare(); notify.prepare()
    }
    /// The tile snaps onto the square.
    static func tileSet() { medium.impactOccurred() }
    /// A tile is lifted off the rack or the board.
    static func lift() { light.impactOccurred() }
    /// A word lands.
    static func word() { heavy.impactOccurred() }
    /// A drag is rejected / a wrong letter.
    static func reject() { notify.notificationOccurred(.error) }
    /// Combo tier up.
    static func comboUp() { notify.notificationOccurred(.success) }
    /// Match won.
    static func win() { notify.notificationOccurred(.success); heavy.impactOccurred() }
}
