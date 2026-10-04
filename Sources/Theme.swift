import SwiftUI

enum Theme {
    static let focus = Color(red: 0.40, green: 0.40, blue: 0.95)
    static let rest = Color(red: 0.08, green: 0.66, blue: 0.60)
    static let flame = Color.orange

    /// Heatmap shade for a day, relative to the daily goal.
    static func heat(minutes: Double, goal: Double) -> Color {
        guard minutes > 0 else { return Color.primary.opacity(0.07) }
        let r = minutes / max(goal, 1)
        let opacity = r >= 1 ? 1.0 : r >= 0.5 ? 0.7 : r >= 0.25 ? 0.45 : 0.25
        return focus.opacity(opacity)
    }
}
