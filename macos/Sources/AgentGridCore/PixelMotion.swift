import Foundation

public struct PixelSample: Equatable, Sendable {
    public var index: Int
    public var intensity: Double
    public var offsetX: Double
    public var offsetY: Double
    public var scale: Double

    public init(
        index: Int,
        intensity: Double,
        offsetX: Double,
        offsetY: Double,
        scale: Double
    ) {
        self.index = index
        self.intensity = intensity
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }
}

public struct PixelGlowLayer: Equatable, Sendable {
    public var opacity: Double
    public var blurRadius: Double

    public init(opacity: Double, blurRadius: Double) {
        self.opacity = opacity
        self.blurRadius = blurRadius
    }
}

public enum PixelPalette {
    public static func hex(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?
    ) -> UInt32 {
        switch lifecycle {
        case .waitingApproval: 0xFDBA4A
        case .waitingAnswer: 0xFACC15
        case .succeeded: 0x4ADE80
        case .failed: 0xFB7185
        case .interrupted, .offline: 0x64748B
        case .idle: 0x5EEAD4
        case .starting: 0xA78BFA
        case .running:
            switch activity {
            case .reading, .searching, .browsing: 0x5EEAD4
            case .editing: 0x818CF8
            case .executing: 0xFB923C
            case .testing: 0x60A5FA
            case .delegating: 0xA78BFA
            case .thinking, nil: 0xA78BFA
            }
        }
    }
}

public enum PixelMotion {
    public static func sample(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        elapsed: TimeInterval
    ) -> [PixelSample] {
        (0..<9).map { index in
            let row = Double(index / 3 - 1)
            let column = Double(index % 3 - 1)
            let phase = Double(index) * 0.73
            let t = max(0, elapsed)
            let values = motion(
                lifecycle: lifecycle,
                activity: activity,
                row: row,
                column: column,
                phase: phase,
                elapsed: t
            )
            return PixelSample(
                index: index,
                intensity: clamp(values.intensity, 0, 1),
                offsetX: clamp(values.offsetX, -1, 1),
                offsetY: clamp(values.offsetY, -1, 1),
                scale: clamp(values.scale, 0.62, 1.28)
            )
        }
    }

    /// 每个亮格独立计算三层 Bloom；暗格返回三层零透明度。
    public static func glowLayers(
        intensity: Double,
        burst: Double
    ) -> [PixelGlowLayer] {
        let energy = clamp(intensity * burst, 0, 1.4)
        return [
            PixelGlowLayer(opacity: energy * 0.46, blurRadius: 2.8),
            PixelGlowLayer(opacity: energy * 0.22, blurRadius: 6.5),
            PixelGlowLayer(opacity: energy * 0.09, blurRadius: 12.0),
        ]
    }

    public static func burst(
        lifecycle: AgentLifecycle,
        elapsed: TimeInterval
    ) -> Double {
        guard elapsed < 1.2 else { return 1 }
        switch lifecycle {
        case .waitingApproval, .waitingAnswer, .succeeded, .failed:
            return 1 + 0.4 * easeOutCubic(1 - elapsed / 1.2)
        default:
            return 1
        }
    }

    private static func motion(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        row: Double,
        column: Double,
        phase: Double,
        elapsed t: Double
    ) -> (intensity: Double, offsetX: Double, offsetY: Double, scale: Double) {
        switch lifecycle {
        case .offline:
            return (0.16, 0, 0, 0.82)
        case .idle:
            let breath = wave(t * 1.25 + phase * 0.28)
            return (0.22 + breath * 0.26, 0, -0.05 * breath, 0.88 + breath * 0.08)
        case .starting:
            let rise = easeOutCubic(min(1, t / 0.55))
            let orbit = t * 4.8 + phase
            return (
                0.28 + 0.72 * rise,
                cos(orbit) * (1 - rise) * 0.65,
                sin(orbit) * (1 - rise) * 0.65,
                0.70 + 0.30 * rise
            )
        case .waitingApproval:
            let pulse = wave(t * 5.2 + phase * 0.18)
            let outward = 0.10 + 0.16 * pulse
            return (
                0.46 + 0.54 * pulse,
                column * outward,
                row * outward,
                0.92 + 0.14 * pulse
            )
        case .waitingAnswer:
            let pulse = wave(t * 4.3 + phase * 0.62)
            return (
                0.34 + 0.66 * pulse,
                sin(t * 2.8 + phase) * 0.12,
                -0.12 * pulse,
                0.88 + 0.16 * pulse
            )
        case .succeeded:
            let progress = min(1, t / 1.2)
            let explosion = sin(progress * .pi) * 0.64
            let settled = progress >= 1 ? 1.0 : 0.72 + 0.28 * easeOutCubic(progress)
            return (
                settled,
                column * explosion,
                row * explosion,
                0.82 + 0.26 * sin(progress * .pi)
            )
        case .failed:
            let progress = min(1, t)
            let jitter = (1 - progress) * sin(t * 55 + phase) * 0.16
            let fall = easeInCubic(progress) * (0.26 + max(0, row) * 0.10)
            let broken = progress >= 1 ? ((Int(phase * 10) % 3) - 1).double * 0.10 : jitter
            return (
                progress >= 1 ? 0.64 : 0.42 + wave(t * 10 + phase) * 0.58,
                broken,
                fall,
                1 - progress * 0.14
            )
        case .interrupted:
            let progress = min(1, t / 0.8)
            return (
                0.62 - progress * 0.24,
                sin(t * 5 + phase) * 0.10 * (1 - progress),
                0,
                0.96 - progress * 0.08
            )
        case .running:
            return activityMotion(
                activity: activity,
                row: row,
                column: column,
                phase: phase,
                elapsed: t
            )
        }
    }

    private static func activityMotion(
        activity: AgentActivity?,
        row: Double,
        column: Double,
        phase: Double,
        elapsed t: Double
    ) -> (intensity: Double, offsetX: Double, offsetY: Double, scale: Double) {
        switch activity {
        case .reading:
            let scan = wave(t * 4.2 - row * 1.2 + phase * 0.12)
            return (0.22 + 0.78 * scan, column * 0.04, -0.16 + 0.32 * scan, 0.88 + 0.14 * scan)
        case .searching, .browsing:
            let orbit = t * 3.8 + phase
            let energy = wave(orbit)
            return (0.20 + 0.80 * energy, cos(orbit) * 0.24, sin(orbit) * 0.24, 0.86 + 0.16 * energy)
        case .editing:
            let exchange = sin(t * 4.6 + row * 1.35 + phase * 0.16)
            let energy = wave(t * 5.0 + phase * 0.72)
            return (0.24 + 0.76 * energy, exchange * 0.42, -exchange * 0.08, 0.86 + 0.18 * energy)
        case .executing:
            let stream = positiveModulo(t * 2.4 + Double(Int(phase * 10) % 3) / 3, 1)
            let energy = sin(.pi * stream)
            return (0.24 + 0.76 * energy, column * 0.05, 0.48 - stream * 0.96, 0.86 + 0.17 * energy)
        case .testing:
            let scan = wave(t * 5.4 + (row + column) * 1.35)
            return (0.18 + 0.82 * scan, column * 0.10 * scan, row * 0.10 * scan, 0.84 + 0.18 * scan)
        case .delegating:
            let split = sin(t * 3.5 + phase * 0.44)
            return (0.28 + 0.72 * wave(t * 3.9 + phase), column * 0.30 * split, row * 0.22 * split, 0.88 + 0.12 * abs(split))
        case .thinking, nil:
            let orbit = t * 3.25 + phase
            let energy = wave(t * 3.9 + phase * 0.74)
            return (0.20 + 0.80 * energy, cos(orbit) * 0.22, sin(orbit) * 0.22, 0.86 + 0.16 * energy)
        }
    }

    private static func wave(_ value: Double) -> Double {
        (sin(value) + 1) / 2
    }

    private static func positiveModulo(_ value: Double, _ divisor: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: divisor)
        return result >= 0 ? result : result + divisor
    }

    private static func easeOutCubic(_ value: Double) -> Double {
        1 - pow(1 - clamp(value, 0, 1), 3)
    }

    private static func easeInCubic(_ value: Double) -> Double {
        pow(clamp(value, 0, 1), 3)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

private extension Int {
    var double: Double { Double(self) }
}
