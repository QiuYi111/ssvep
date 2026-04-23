import AVFoundation
import Combine

struct LevelAudioConfig {
    let level: Int
    let name: String
    let ssvepFrequency: Float
    let distractorFrequency: Float
    let baseFrequency: Float
    let binauralVolume: Float
    let ambientType: AmbientType
    let rewardChimeBaseFreq: Float
    let filterMinCutoff: Float
    let filterMaxCutoff: Float
    let levelTransitionDuration: Float

    static func forLevel(_ levelID: LevelID) -> LevelAudioConfig {
        switch levelID {
        case .level1:
            return LevelAudioConfig(level: 1, name: "初识星空", ssvepFrequency: 15.0,
                                    distractorFrequency: 20.0, baseFrequency: 150.0,
                                    binauralVolume: 0.45, ambientType: .lake,
                                    rewardChimeBaseFreq: 396.0, filterMinCutoff: 300.0,
                                    filterMaxCutoff: 16000.0, levelTransitionDuration: 3.0)
        case .level2:
            return LevelAudioConfig(level: 2, name: "萤火低语", ssvepFrequency: 15.0,
                                    distractorFrequency: 20.0, baseFrequency: 174.0,
                                    binauralVolume: 0.5, ambientType: .forest,
                                    rewardChimeBaseFreq: 432.0, filterMinCutoff: 300.0,
                                    filterMaxCutoff: 16000.0, levelTransitionDuration: 3.0)
        case .level3:
            return LevelAudioConfig(level: 3, name: "星河漫步", ssvepFrequency: 15.0,
                                    distractorFrequency: 20.0, baseFrequency: 196.0,
                                    binauralVolume: 0.5, ambientType: .constellation,
                                    rewardChimeBaseFreq: 528.0, filterMinCutoff: 300.0,
                                    filterMaxCutoff: 17000.0, levelTransitionDuration: 4.0)
        case .level4:
            return LevelAudioConfig(level: 4, name: "深空冥想", ssvepFrequency: 15.0,
                                    distractorFrequency: 20.0, baseFrequency: 220.0,
                                    binauralVolume: 0.55, ambientType: .dualForest,
                                    rewardChimeBaseFreq: 639.0, filterMinCutoff: 300.0,
                                    filterMaxCutoff: 17000.0, levelTransitionDuration: 5.0)
        case .level5:
            return LevelAudioConfig(level: 5, name: "量子涟漪", ssvepFrequency: 15.0,
                                    distractorFrequency: 20.0, baseFrequency: 200.0,
                                    binauralVolume: 0.5, ambientType: .storm,
                                    rewardChimeBaseFreq: 741.0, filterMinCutoff: 300.0,
                                    filterMaxCutoff: 18000.0, levelTransitionDuration: 5.0)
        case .level6:
            return LevelAudioConfig(level: 6, name: "永恒之息", ssvepFrequency: 15.0,
                                    distractorFrequency: 15.0, baseFrequency: 256.0,
                                    binauralVolume: 0.5, ambientType: .mountain,
                                    rewardChimeBaseFreq: 852.0, filterMinCutoff: 300.0,
                                    filterMaxCutoff: 18000.0, levelTransitionDuration: 5.0)
        }
    }
}

enum AmbientType {
    case lake
    case forest
    case constellation
    case dualForest
    case storm
    case mountain
}

struct AudioParameters {
    let filterCutoff: Float
    let reverbWetDry: Float
    let binauralVolume: Float
    let ambientMasterVolume: Float
    let windMix: Float
    let waterMix: Float
    let forestMix: Float
    let cosmicMix: Float
    let isochronicVolume: Float
    let rainMix: Float
    let chimeMix: Float
}

struct AudioParameterMapper {
    static func map(attention: Float) -> AudioParameters {
        let a = clamp(attention, 0.0, 1.0)
        return AudioParameters(
            filterCutoff: 300.0 * powf(60.0, a),
            reverbWetDry: lerp(0.7, 0.12, a),
            binauralVolume: lerp(0.15, 0.7, sqrtf(a)),
            ambientMasterVolume: lerp(0.2, 0.55, powf(a, 0.7)),
            windMix: lerp(0.85, 0.15, a),
            waterMix: lerp(0.05, 0.55, a),
            forestMix: lerp(0.05, 0.55, a),
            cosmicMix: lerp(0.05, 0.5, a),
            isochronicVolume: lerp(0.0, 0.35, powf(a, 1.5)),
            rainMix: lerp(0.5, 0.1, a),
            chimeMix: lerp(0.0, 0.5, powf(a, 1.5))
        )
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}

private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
    Swift.min(Swift.max(value, min), max)
}

final class AudioEngineManager: @unchecked Sendable {
    static let shared = AudioEngineManager()

    let engine = AVAudioEngine()
    let mainMixer: AVAudioMixerNode
    let lowPassFilter: AVAudioUnitEQ
    let reverbNode: AVAudioUnitReverb

    let binauralNode: BinauralBeatNode
    let isochronicNode: IsochronicToneNode
    let ambientWindNode: AmbientWindNode
    let ambientWaterNode: AmbientWaterNode
    let ambientForestNode: AmbientForestNode
    let ambientRainNode: AmbientRainNode
    let windChimeNode: WindChimeNode
    let ambientCosmicNode: AmbientCosmicNode
    let feedbackNode: FeedbackNode

    private var levelWindBase: Float = 0.0
    private var levelWaterBase: Float = 0.0
    private var levelForestBase: Float = 0.0
    private var levelCosmicBase: Float = 0.0
    private var levelRainBase: Float = 0.0
    private var levelChimeBase: Float = 0.0

    private var _attentionLevel: AtomicFloat = AtomicFloat(0.5)
    var attentionLevel: Float {
        get { _attentionLevel.atomicValue }
        set { _attentionLevel.store(newValue) }
    }

    private var _targetFilterCutoff: Float = 5000.0
    private var _currentFilterCutoff: Float = 5000.0
    private var _targetReverbWetDry: Float = 0.3
    private var _currentReverbWetDry: Float = 0.3

    private var parameterTimer: Timer?
    private var currentConfig: LevelAudioConfig?

    private init() {
        mainMixer = engine.mainMixerNode
        lowPassFilter = AVAudioUnitEQ(numberOfBands: 1)
        reverbNode = AVAudioUnitReverb()

        binauralNode = BinauralBeatNode()
        isochronicNode = IsochronicToneNode()
        ambientWindNode = AmbientWindNode()
        ambientWaterNode = AmbientWaterNode()
        ambientForestNode = AmbientForestNode()
        ambientRainNode = AmbientRainNode()
        windChimeNode = WindChimeNode()
        ambientCosmicNode = AmbientCosmicNode()
        feedbackNode = FeedbackNode()

        configureFilter()
        configureReverb()
        connectAudioGraph()
    }

    private func configureFilter() {
        engine.attach(lowPassFilter)
        let filterParams = lowPassFilter.bands[0]
        filterParams.filterType = .lowPass
        filterParams.frequency = 5000.0
        filterParams.bandwidth = 1.2
        filterParams.gain = 0.0
        filterParams.bypass = false
    }

    private func configureReverb() {
        engine.attach(reverbNode)
        reverbNode.loadFactoryPreset(.largeHall)
        reverbNode.wetDryMix = 30.0
    }

    private func connectAudioGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

        engine.attach(binauralNode)
        engine.attach(isochronicNode)
        engine.attach(ambientWindNode)
        engine.attach(ambientWaterNode)
        engine.attach(ambientForestNode)
        engine.attach(ambientRainNode)
        engine.attach(windChimeNode)
        engine.attach(ambientCosmicNode)
        engine.attach(feedbackNode.node)

        engine.connect(binauralNode, to: lowPassFilter, format: format)
        engine.connect(isochronicNode, to: lowPassFilter, format: format)
        engine.connect(ambientWindNode, to: lowPassFilter, format: format)
        engine.connect(ambientWaterNode, to: lowPassFilter, format: format)
        engine.connect(ambientForestNode, to: lowPassFilter, format: format)
        engine.connect(ambientRainNode, to: lowPassFilter, format: format)
        engine.connect(windChimeNode, to: lowPassFilter, format: format)
        engine.connect(ambientCosmicNode, to: lowPassFilter, format: format)
        engine.connect(feedbackNode.node, to: lowPassFilter, format: format)

        engine.connect(lowPassFilter, to: reverbNode, format: format)
        engine.connect(reverbNode, to: mainMixer, format: format)
        engine.connect(mainMixer, to: engine.outputNode, format: format)
    }

    func startEngine() throws {
        try engine.start()
        startParameterSmoothing()
    }

    func stopEngine() {
        engine.stop()
        parameterTimer?.invalidate()
        parameterTimer = nil
    }

    private func startParameterSmoothing() {
        parameterTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            self?.smoothParameters()
        }
        RunLoop.current.add(parameterTimer!, forMode: .common)
    }

    private func smoothParameters() {
        let smoothingFactor: Float = 0.15

        _currentFilterCutoff += (_targetFilterCutoff - _currentFilterCutoff) * smoothingFactor
        _currentReverbWetDry += (_targetReverbWetDry - _currentReverbWetDry) * smoothingFactor

        lowPassFilter.bands[0].frequency = _currentFilterCutoff
        reverbNode.wetDryMix = _currentReverbWetDry * 100.0
    }

    func updateFromAttention(_ attention: Float) {
        attentionLevel = attention
        let params = AudioParameterMapper.map(attention: attention)

        _targetFilterCutoff = clamp(params.filterCutoff, 300.0, 18000.0)
        _targetReverbWetDry = params.reverbWetDry

        binauralNode.setTargetVolume(params.binauralVolume)

        isochronicNode.setTargetVolume(params.isochronicVolume)

        let ambMaster = params.ambientMasterVolume
        ambientWindNode.setMixVolume(levelWindBase * params.windMix * ambMaster)
        ambientWaterNode.setMixVolume(levelWaterBase * params.waterMix * ambMaster)
        ambientForestNode.setMixVolume(levelForestBase * params.forestMix * ambMaster)
        ambientCosmicNode.setMixVolume(levelCosmicBase * params.cosmicMix * ambMaster)
        ambientRainNode.setMixVolume(levelRainBase * params.rainMix * ambMaster)
        windChimeNode.setMixVolume(levelChimeBase * params.chimeMix * ambMaster)
    }

    func switchToLevel(_ config: LevelAudioConfig, animate: Bool = true) {
        currentConfig = config

        binauralNode.setBaseFrequency(config.baseFrequency)
        binauralNode.setSSVEPFrequency(config.ssvepFrequency)
        isochronicNode.setBaseFrequency(config.baseFrequency)
        isochronicNode.setSSVEPFrequency(config.ssvepFrequency)
        feedbackNode.setBowlBaseFrequency(config.rewardChimeBaseFreq)

        if animate {
            binauralNode.setTargetVolume(0.0)
            isochronicNode.setTargetVolume(0.0)
        } else {
            binauralNode.setTargetVolume(config.binauralVolume)
        }

        switch config.ambientType {
        case .lake:
            levelWindBase = 0.15
            levelWaterBase = 0.6
            levelForestBase = 0.0
            levelCosmicBase = 0.1
            levelRainBase = 0.0
            levelChimeBase = 0.35
        case .forest:
            levelWindBase = 0.1
            levelWaterBase = 0.0
            levelForestBase = 0.7
            levelCosmicBase = 0.0
            levelRainBase = 0.0
            levelChimeBase = 0.0
        case .constellation:
            levelWindBase = 0.05
            levelWaterBase = 0.0
            levelForestBase = 0.0
            levelCosmicBase = 0.7
            levelRainBase = 0.0
            levelChimeBase = 0.1
        case .dualForest:
            levelWindBase = 0.4
            levelWaterBase = 0.0
            levelForestBase = 0.6
            levelCosmicBase = 0.0
            levelRainBase = 0.0
            levelChimeBase = 0.0
        case .storm:
            levelWindBase = 0.5
            levelWaterBase = 0.0
            levelForestBase = 0.0
            levelCosmicBase = 0.0
            levelRainBase = 0.7
            levelChimeBase = 0.0
        case .mountain:
            levelWindBase = 0.4
            levelWaterBase = 0.0
            levelForestBase = 0.0
            levelCosmicBase = 0.4
            levelRainBase = 0.0
            levelChimeBase = 0.3
        }

        if animate {
            ambientWindNode.setMixVolume(0.0)
            ambientWaterNode.setMixVolume(0.0)
            ambientForestNode.setMixVolume(0.0)
            ambientCosmicNode.setMixVolume(0.0)
            ambientRainNode.setMixVolume(0.0)
            windChimeNode.setMixVolume(0.0)
        }

        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(config.levelTransitionDuration) * 0.5) { [weak self] in
                self?.binauralNode.setTargetVolume(config.binauralVolume)
            }
        }
    }
}
