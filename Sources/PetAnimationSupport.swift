import Foundation

/// A presentation-only yaw: ±25°, one round trip in eight minutes of idle time.
struct PetAmbientRotation {
    static let amplitude = 25.0 * Double.pi / 180
    static let period = 480.0
    private(set) var angle = 0.0
    private var phase = 0.0
    private var lastTime: Double?
    private var holdUntil = 0.0
    mutating func hold(at now: Double) { holdUntil = now + 20 }
    mutating func reset(at now: Double) { phase = 0; angle = 0; lastTime = now; hold(at: now) }
    mutating func tick(at now: Double, allowed: Bool) -> Double {
        guard now.isFinite else { return angle }
        let delta = min(0.1, max(0, now - (lastTime ?? now)))
        lastTime = now
        guard allowed, now >= holdUntil else { return angle }
        phase = (phase + delta * 2 * .pi / Self.period).truncatingRemainder(dividingBy: 2 * .pi)
        angle = Self.amplitude * sin(phase)
        return angle
    }
}

enum PetRotation {
    static func normalized(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let circle = 2 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: circle)
        if value >= .pi { return value - circle }
        if value < -.pi { return value + circle }
        return value
    }
    static func dragged(from angle: Double, horizontalPoints: Double) -> Double {
        normalized(angle + horizontalPoints * .pi / 225)
    }
}

/// Every dog gesture appears once per deck, with no repetition at the boundary.
struct MotionDeck {
    private var remaining: [Int] = []
    private var previous: Int?
    mutating func next() -> Int {
        if remaining.isEmpty {
            remaining = Array(0..<5).shuffled()
            if remaining.last == previous { remaining.swapAt(0, 4) }
        }
        let value = remaining.removeLast()
        previous = value
        return value
    }
}

struct FloatingRect: Equatable {
    var x: Double; var y: Double; var width: Double; var height: Double
    var maxX: Double { x + width }; var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
}

enum FloatingLayout {
    static func place(width: Double, height: Double, pet: FloatingRect, screen: FloatingRect) -> FloatingRect {
        let margin = 12.0, gap = 8.0
        let w = min(width, screen.width - margin * 2)
        let h = min(height, screen.height - margin * 2)
        var x = pet.midX - w / 2
        var y = pet.maxY + gap
        if y + h > screen.maxY - margin {
            if pet.y - gap - h >= screen.y + margin { y = pet.y - gap - h }
            else {
                x = pet.x - gap - w >= screen.x + margin ? pet.x - gap - w : pet.maxX + gap
                y = pet.y + pet.height / 2 - h / 2
            }
        }
        x = min(max(x, screen.x + margin), screen.maxX - margin - w)
        y = min(max(y, screen.y + margin), screen.maxY - margin - h)
        return FloatingRect(x: x, y: y, width: w, height: h)
    }
}

enum QuickMenuLayout {
    // Extra transparent space lets shortcuts travel from the Pokémon's body.
    static let width = 548.0, height = 330.0
    static let buttonCount = 7
    static let arcButtonCount = 6
    static let radiusX = width / 2 - 52
    static func buttonCenter(_ index: Int) -> (x: Double, y: Double) {
        if index == arcButtonCount { return (width / 2, 126) }
        let angle = (166 - Double(index) * 152 / Double(arcButtonCount - 1)) * .pi / 180
        return (width / 2 + radiusX * cos(angle), 151 - 104 * sin(angle))
    }
    // Coordinates use the top-left origin of the SwiftUI menu.
    static func containsControl(x: Double, y: Double) -> Bool {
        for index in 0..<arcButtonCount {
            let p = buttonCenter(index)
            if abs(x - p.x) <= 47 && abs(y - p.y) <= 38 { return true }
        }
        if abs(x - width / 2) <= 83 && abs(y - 126) <= 17 { return true }
        return hypot(x - width / 2, y - 164) <= 15
    }
    static func place(anchorX: Double, anchorY: Double, screen: FloatingRect) -> FloatingRect {
        let margin = 8.0
        return FloatingRect(x: min(max(anchorX - width / 2, screen.x + margin), screen.maxX - width - margin),
            y: min(max(anchorY - 174, screen.y + margin), screen.maxY - height - margin), width: width, height: height)
    }
    static func detail(width: Double, height: Double, menu: FloatingRect, screen: FloatingRect) -> FloatingRect {
        let margin = 12.0, gap = 8.0
        let w = min(width, screen.width - 2 * margin), h = min(height, screen.height - 2 * margin)
        var x = menu.midX - w / 2, y = menu.maxY + gap
        if y + h > screen.maxY - margin {
            if menu.x - gap - w >= screen.x + margin {
                x = menu.x - gap - w; y = menu.y + menu.height / 2 - h / 2
            } else if menu.maxX + gap + w <= screen.maxX - margin {
                x = menu.maxX + gap; y = menu.y + menu.height / 2 - h / 2
            } else { y = menu.y - gap - h }
        }
        return FloatingRect(x: min(max(x, screen.x + margin), screen.maxX - w - margin),
            y: min(max(y, screen.y + margin), screen.maxY - h - margin), width: w, height: h)
    }
}
