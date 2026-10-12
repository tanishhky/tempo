import SwiftUI

enum Theme {
    static let focus = Color(red: 0.40, green: 0.40, blue: 0.95)
    static let rest = Color(red: 0.08, green: 0.66, blue: 0.60)
    static let flame = Color.orange

    /// Colours an activity can use. The name is what activities.json stores, so keep these names stable.
    static let activityColors: [(name: String, color: Color)] = [
        ("blue", focus),
        ("teal", rest),
        ("green", Color(red: 0.25, green: 0.70, blue: 0.36)),
        ("amber", Color(red: 0.95, green: 0.72, blue: 0.20)),
        ("orange", Color(red: 0.98, green: 0.52, blue: 0.16)),
        ("rose", Color(red: 0.90, green: 0.36, blue: 0.52)),
        ("violet", Color(red: 0.60, green: 0.40, blue: 0.92)),
        ("slate", Color(red: 0.45, green: 0.50, blue: 0.60)),
    ]

    static func activityColor(_ name: String) -> Color {
        activityColors.first { $0.name == name }?.color ?? focus
    }

    /// Heatmap shade for a day, relative to the daily goal.
    static func heat(minutes: Double, goal: Double) -> Color {
        guard minutes > 0 else { return Color.primary.opacity(0.07) }
        let r = minutes / max(goal, 1)
        let opacity = r >= 1 ? 1.0 : r >= 0.5 ? 0.7 : r >= 0.25 ? 0.45 : 0.25
        return focus.opacity(opacity)
    }

    /// Shade for a journal day: how much of its checklist is done, in the activity's colour.
    static func progress(_ fraction: Double, color: Color) -> Color {
        guard fraction > 0 else { return Color.primary.opacity(0.07) }
        return color.opacity(0.25 + 0.75 * min(1, fraction))
    }
}
