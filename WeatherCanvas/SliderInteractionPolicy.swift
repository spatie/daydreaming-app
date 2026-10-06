import Foundation

enum SliderInteractionPolicy {
    static func clampedHour(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(23, max(0, value.rounded())))
    }

    static func shouldEnqueue(isDragging: Bool, userRequested: Bool) -> Bool {
        userRequested && !isDragging
    }
}
