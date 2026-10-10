import Foundation

enum PetSummonPhase: String, CaseIterable {
    case release, recall
    var duration: Double { self == .release ? 2.35 : 1.85 }
}

/// A clock-driven sequence shared by live playback and deterministic previews.
/// All channels settle to exact endpoints, so interruption never leaves a pet
/// miniature, invisible or emissive. No timers or completion callbacks live here.
struct PetSummonFrame {
    let petAmount: Double
    let petOpacity: Double
    let whiten: Double
    let lidOpen: Double
    let ballOpacity: Double
    let ballLift: Double
    let glow: Double
    let beam: Double
    let sparks: Double
    let progress: Double

    static func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0))
        return x*x*x*(x*(x*6-15)+10)
    }
    static func ramp(_ time: Double, _ from: Double, _ to: Double) -> Double {
        smooth((time-from)/(to-from))
    }
    init(phase: PetSummonPhase, time: Double) {
        let t = min(phase.duration, max(0, time.isFinite ? time : 0))
        let r = Self.ramp
        progress = t/phase.duration
        if phase == .release {
            petAmount = r(t, 0.78, 1.56)
            petOpacity = r(t, 0.78, 0.96)
            whiten = (1-r(t, 1.40, 1.96))*r(t, 0.65, 0.82)
            lidOpen = r(t, 0.38, 0.78)*(1-r(t, 1.68, 2.02))
            ballOpacity = 1-r(t, 2.02, 2.35)
            ballLift = 0.45*(1-r(t, 0, 0.38)) + 0.055*sin(.pi*r(t, 0.38, 0.63))
            glow = r(t, 0.55, 0.83)*(1-r(t, 1.35, 1.98))
            beam = r(t, 0.72, 0.88)*(1-r(t, 1.36, 1.66))
            sparks = r(t, 0.78, 1.03)*(1-r(t, 1.56, 2.14))
        } else {
            petAmount = 1-r(t, 0.60, 1.26)
            petOpacity = 1-r(t, 1.13, 1.28)
            whiten = r(t, 0.38, 0.69)*(1-r(t, 1.25, 1.50))
            lidOpen = r(t, 0.23, 0.56)*(1-r(t, 1.28, 1.57))
            ballOpacity = 1-r(t, 1.58, 1.85)
            ballLift = 0.34*(1-r(t, 0, 0.32))-0.16*r(t, 1.58, 1.85)
            glow = r(t, 0.37, 0.67)*(1-r(t, 1.24, 1.55))
            beam = r(t, 0.44, 0.65)*(1-r(t, 1.17, 1.33))
            sparks = r(t, 0.40, 0.70)*(1-r(t, 1.23, 1.54))
        }
    }
}
