import simd

// MARK: - Level Scene Config Metal Layout (matches Shared.metal LevelSceneConfig)
// MUST match Metal struct byte-for-byte.

struct LevelSceneConfigMetal {
    var themeColor: SIMD4<Float>          // 16 bytes
    var secondaryColor: SIMD4<Float>
    var distractorColor: SIMD4<Float>
    var backgroundColor: SIMD4<Float>
    var fogColor: SIMD4<Float>

    var skyGradientTopY: Float
    var skyGradientBottomY: Float
    var mountainHeight: Float
    var mountainSmoothness: Float

    var waterLevel: Float
    var waterWaveAmplitude: Float
    var waterWaveFrequency: Float

    var fogDensity: Float
    var fogHeightFalloff: Float
    var starBrightness: Float
    var starDensity: Float

    var lotusSize: Float
    var lotusPetalCount: Float

    var monumentX: Float
    var monumentY: Float

    var treeOfLifeGrowth: Float
    var treeOfLifeX: Float

    var swallowPosX: Float
    var swallowPosY: Float

    var lightningIntensity: Float
    var moonPhase: Float
    var snowPeakHeight: Float

    var sceneMode: Int32            // 0=starfield, 1=lake, 2=forest, 3=constellation, 4=dualForest, 5=storm, 6=mountain
    var particleBehaviorMode: Int32 // 0=float, 1=guided, 2=orbital, 3=scatter, 4=rain, 5=meteor
    var attentionEffectMode: Int32  // 0=default, 1=ripples, 2=fog, 3=constellate, 4=grow, 5=flight, 6=resist

    var bloomTintR: Float
    var bloomTintG: Float
    var bloomTintB: Float

    var _pad0: Float;  var _pad1: Float;  var _pad2: Float
    var _pad3: Float;  var _pad4: Float;  var _pad5: Float
    var _pad6: Float;  var _pad7: Float;  var _pad8: Float
    var _pad9: Float;  var _pad10: Float; var _pad11: Float
    var _pad12: Float; var _pad13: Float; var _pad14: Float

    // MARK: - Factory Methods

    static func forLevel1() -> LevelSceneConfigMetal {
        LevelSceneConfigMetal(
            themeColor: SIMD4<Float>(1.0, 0.91, 0.65, 1),
            secondaryColor: SIMD4<Float>(0.4, 0.6, 0.5, 1),
            distractorColor: SIMD4<Float>(0, 0, 0, 0),
            backgroundColor: SIMD4<Float>(0.005, 0.01, 0.03, 1),
            fogColor: SIMD4<Float>(0.03, 0.04, 0.06, 0.25),
            skyGradientTopY: 0, skyGradientBottomY: 0,
            mountainHeight: 0.08, mountainSmoothness: 0.6,
            waterLevel: 0.45, waterWaveAmplitude: 0.012, waterWaveFrequency: 2.0,
            fogDensity: 0.08, fogHeightFalloff: 1.2,
            starBrightness: 0.5, starDensity: 40,
            lotusSize: 0.070, lotusPetalCount: 8,
            monumentX: 0, monumentY: 0,
            treeOfLifeGrowth: 0, treeOfLifeX: 0,
            swallowPosX: 0, swallowPosY: 0,
            lightningIntensity: 0, moonPhase: 0, snowPeakHeight: 0,
            sceneMode: 1, particleBehaviorMode: 0, attentionEffectMode: 1,
            bloomTintR: 1.0, bloomTintG: 0.91, bloomTintB: 0.65,
            _pad0: 0, _pad1: 0, _pad2: 0, _pad3: 0, _pad4: 0,
            _pad5: 0, _pad6: 0, _pad7: 0, _pad8: 0, _pad9: 0,
            _pad10: 0, _pad11: 0, _pad12: 0, _pad13: 0, _pad14: 0
        )
    }

    static func forLevel2() -> LevelSceneConfigMetal {
        LevelSceneConfigMetal(
            themeColor: SIMD4<Float>(0.80, 0.86, 0.22, 1),
            secondaryColor: SIMD4<Float>(0, 0, 0, 0),
            distractorColor: SIMD4<Float>(0, 0, 0, 0),
            backgroundColor: SIMD4<Float>(0.01, 0.015, 0.01, 1),
            fogColor: SIMD4<Float>(0.05, 0.1, 0.05, 0.8),
            skyGradientTopY: 0, skyGradientBottomY: 0,
            mountainHeight: 0.08, mountainSmoothness: 0.7,
            waterLevel: 0, waterWaveAmplitude: 0, waterWaveFrequency: 0,
            fogDensity: 0.7, fogHeightFalloff: 2.0,
            starBrightness: 0, starDensity: 0,
            lotusSize: 0, lotusPetalCount: 0,
            monumentX: 0, monumentY: -0.3,
            treeOfLifeGrowth: 0, treeOfLifeX: 0,
            swallowPosX: 0, swallowPosY: 0,
            lightningIntensity: 0, moonPhase: 0, snowPeakHeight: 0,
            sceneMode: 2, particleBehaviorMode: 0, attentionEffectMode: 2,
            bloomTintR: 0.80, bloomTintG: 0.86, bloomTintB: 0.22,
            _pad0: 0, _pad1: 0, _pad2: 0, _pad3: 0, _pad4: 0,
            _pad5: 0, _pad6: 0, _pad7: 0, _pad8: 0, _pad9: 0,
            _pad10: 0, _pad11: 0, _pad12: 0, _pad13: 0, _pad14: 0
        )
    }

    static func forLevel3() -> LevelSceneConfigMetal {
        LevelSceneConfigMetal(
            themeColor: SIMD4<Float>(1.0, 0.91, 0.65, 1),
            secondaryColor: SIMD4<Float>(0, 0, 0, 0),
            distractorColor: SIMD4<Float>(0.541, 0.706, 0.973, 1),
            backgroundColor: SIMD4<Float>(0.02, 0.02, 0.06, 1),
            fogColor: SIMD4<Float>(0, 0, 0, 0),
            skyGradientTopY: 0, skyGradientBottomY: 0,
            mountainHeight: 0, mountainSmoothness: 0,
            waterLevel: 0, waterWaveAmplitude: 0, waterWaveFrequency: 0,
            fogDensity: 0, fogHeightFalloff: 0,
            starBrightness: 0.8, starDensity: 80,
            lotusSize: 0, lotusPetalCount: 0,
            monumentX: 0, monumentY: 0,
            treeOfLifeGrowth: 0, treeOfLifeX: 0,
            swallowPosX: 0, swallowPosY: 0,
            lightningIntensity: 0, moonPhase: 0, snowPeakHeight: 0,
            sceneMode: 3, particleBehaviorMode: 1, attentionEffectMode: 3,
            bloomTintR: 1.0, bloomTintG: 0.91, bloomTintB: 0.65,
            _pad0: 0, _pad1: 0, _pad2: 0, _pad3: 0, _pad4: 0,
            _pad5: 0, _pad6: 0, _pad7: 0, _pad8: 0, _pad9: 0,
            _pad10: 0, _pad11: 0, _pad12: 0, _pad13: 0, _pad14: 0
        )
    }

    static func forLevel4() -> LevelSceneConfigMetal {
        LevelSceneConfigMetal(
            themeColor: SIMD4<Float>(0.80, 0.86, 0.22, 1),
            secondaryColor: SIMD4<Float>(0, 0, 0, 0),
            distractorColor: SIMD4<Float>(0.541, 0.706, 0.973, 1),
            backgroundColor: SIMD4<Float>(0.02, 0.01, 0.03, 1),
            fogColor: SIMD4<Float>(0.03, 0.02, 0.04, 0.2),
            skyGradientTopY: 0, skyGradientBottomY: 0,
            mountainHeight: 0.1, mountainSmoothness: 0.6,
            waterLevel: 0, waterWaveAmplitude: 0, waterWaveFrequency: 0,
            fogDensity: 0.1, fogHeightFalloff: 1.5,
            starBrightness: 0.4, starDensity: 30,
            lotusSize: 0, lotusPetalCount: 0,
            monumentX: 0, monumentY: 0,
            treeOfLifeGrowth: 0, treeOfLifeX: 0,
            swallowPosX: 0, swallowPosY: 0,
            lightningIntensity: 0, moonPhase: 0, snowPeakHeight: 0,
            sceneMode: 4, particleBehaviorMode: 2, attentionEffectMode: 4,
            bloomTintR: 0.80, bloomTintG: 0.86, bloomTintB: 0.22,
            _pad0: 0, _pad1: 0, _pad2: 0, _pad3: 0, _pad4: 0,
            _pad5: 0, _pad6: 0, _pad7: 0, _pad8: 0, _pad9: 0,
            _pad10: 0, _pad11: 0, _pad12: 0, _pad13: 0, _pad14: 0
        )
    }

    static func forLevel5() -> LevelSceneConfigMetal {
        LevelSceneConfigMetal(
            themeColor: SIMD4<Float>(1.0, 0.91, 0.65, 1),
            secondaryColor: SIMD4<Float>(0.29, 0.08, 0.55, 1),
            distractorColor: SIMD4<Float>(0.7, 0.7, 1.0, 1),
            backgroundColor: SIMD4<Float>(0.02, 0.01, 0.04, 1),
            fogColor: SIMD4<Float>(0.05, 0.02, 0.08, 0.4),
            skyGradientTopY: 0, skyGradientBottomY: 0,
            mountainHeight: 0.15, mountainSmoothness: 0.4,
            waterLevel: 0, waterWaveAmplitude: 0, waterWaveFrequency: 0,
            fogDensity: 0.2, fogHeightFalloff: 1.0,
            starBrightness: 0, starDensity: 0,
            lotusSize: 0, lotusPetalCount: 0,
            monumentX: 0, monumentY: 0,
            treeOfLifeGrowth: 0, treeOfLifeX: 0,
            swallowPosX: 0, swallowPosY: 0.2,
            lightningIntensity: 0.5, moonPhase: 0, snowPeakHeight: 0,
            sceneMode: 5, particleBehaviorMode: 3, attentionEffectMode: 5,
            bloomTintR: 0.60, bloomTintG: 0.76, bloomTintB: 0.92,
            _pad0: 0, _pad1: 0, _pad2: 0, _pad3: 0, _pad4: 0,
            _pad5: 0, _pad6: 0, _pad7: 0, _pad8: 0, _pad9: 0,
            _pad10: 0, _pad11: 0, _pad12: 0, _pad13: 0, _pad14: 0
        )
    }

    static func forLevel6() -> LevelSceneConfigMetal {
        LevelSceneConfigMetal(
            themeColor: SIMD4<Float>(0.9, 0.7, 0.3, 1),
            secondaryColor: SIMD4<Float>(0, 0, 0, 0),
            distractorColor: SIMD4<Float>(0.9, 0.5, 0.2, 1),
            backgroundColor: SIMD4<Float>(0.01, 0.01, 0.03, 1),
            fogColor: SIMD4<Float>(0.02, 0.02, 0.04, 0.1),
            skyGradientTopY: 0, skyGradientBottomY: 0,
            mountainHeight: 0.2, mountainSmoothness: 0.3,
            waterLevel: 0, waterWaveAmplitude: 0, waterWaveFrequency: 0,
            fogDensity: 0.05, fogHeightFalloff: 1.0,
            starBrightness: 0.6, starDensity: 60,
            lotusSize: 0, lotusPetalCount: 0,
            monumentX: 0, monumentY: 0,
            treeOfLifeGrowth: 0, treeOfLifeX: 0,
            swallowPosX: 0, swallowPosY: 0,
            lightningIntensity: 0, moonPhase: 0, snowPeakHeight: 0.25,
            sceneMode: 6, particleBehaviorMode: 5, attentionEffectMode: 6,
            bloomTintR: 0.9, bloomTintG: 0.7, bloomTintB: 0.3,
            _pad0: 0, _pad1: 0, _pad2: 0, _pad3: 0, _pad4: 0,
            _pad5: 0, _pad6: 0, _pad7: 0, _pad8: 0, _pad9: 0,
            _pad10: 0, _pad11: 0, _pad12: 0, _pad13: 0, _pad14: 0
        )
    }

    static func forLevel(_ id: LevelID) -> LevelSceneConfigMetal {
        switch id {
        case .level1: return forLevel1()
        case .level2: return forLevel2()
        case .level3: return forLevel3()
        case .level4: return forLevel4()
        case .level5: return forLevel5()
        case .level6: return forLevel6()
        }
    }
}
