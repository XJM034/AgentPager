import Testing
@testable import AgentGridCore

@Test("像素状态使用连续强度与连续位移")
func pixelMotionIsContinuous() {
    let first = PixelMotion.sample(
        lifecycle: .running,
        activity: .editing,
        elapsed: 0.100
    )
    let second = PixelMotion.sample(
        lifecycle: .running,
        activity: .editing,
        elapsed: 0.116
    )

    #expect(first.count == 9)
    #expect(second.count == 9)
    #expect(zip(first, second).contains { lhs, rhs in
        abs(lhs.intensity - rhs.intensity) > 0.0001
            || abs(lhs.offsetX - rhs.offsetX) > 0.0001
            || abs(lhs.offsetY - rhs.offsetY) > 0.0001
    })
    #expect(zip(first, second).allSatisfy { lhs, rhs in
        abs(lhs.intensity - rhs.intensity) < 0.30
            && abs(lhs.offsetX - rhs.offsetX) < 0.30
            && abs(lhs.offsetY - rhs.offsetY) < 0.30
    })
    #expect(first.allSatisfy {
        abs($0.offsetX) <= 1 && abs($0.offsetY) <= 1
    })
}

@Test("每个亮像素拥有独立三层 Bloom")
func eachLitPixelOwnsBloomLayers() {
    let lit = PixelMotion.glowLayers(intensity: 0.82, burst: 1.0)
    let dark = PixelMotion.glowLayers(intensity: 0, burst: 1.0)

    #expect(lit.count == 3)
    #expect(lit.allSatisfy { $0.opacity > 0 && $0.blurRadius > 0 })
    #expect(lit[0].opacity > lit[1].opacity)
    #expect(lit[1].opacity > lit[2].opacity)
    #expect(dark.allSatisfy { $0.opacity == 0 })
}

@Test("同一状态只使用一个色相家族")
func lifecyclePaletteUsesSingleHueFamily() {
    #expect(PixelPalette.hex(lifecycle: .running, activity: .thinking) == 0xA78BFA)
    #expect(PixelPalette.hex(lifecycle: .running, activity: .editing) == 0x818CF8)
    #expect(PixelPalette.hex(lifecycle: .running, activity: .executing) == 0xFB923C)
    #expect(PixelPalette.hex(lifecycle: .waitingApproval, activity: nil) == 0xFDBA4A)
    #expect(PixelPalette.hex(lifecycle: .succeeded, activity: nil) == 0x4ADE80)
    #expect(PixelPalette.hex(lifecycle: .failed, activity: nil) == 0xFB7185)
}
