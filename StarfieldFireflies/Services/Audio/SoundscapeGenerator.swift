import AVFoundation

private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
    Swift.min(Swift.max(value, min), max)
}

// MARK: - White Noise Generator (xorshift32)

struct WhiteNoiseGenerator {
    private var state: UInt32 = 0x12345678

    mutating func nextFloat() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
}

// MARK: - Pink Noise Generator (Paul Kellet)

struct PinkNoiseGenerator {
    private var b0: Float = 0.0
    private var b1: Float = 0.0
    private var b2: Float = 0.0
    private var b3: Float = 0.0
    private var b4: Float = 0.0
    private var b5: Float = 0.0
    private var b6: Float = 0.0
    private var white: WhiteNoiseGenerator = WhiteNoiseGenerator()

    mutating func nextFloat() -> Float {
        let w = white.nextFloat()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return pink * 0.11
    }
}

// MARK: - BinauralBeatNode (improved with harmonics)

final class BinauralBeatNode: AVAudioSourceNode {
    private let baseFreqAtomic = AtomicFloat(200.0)
    private let ssvepFreqAtomic = AtomicFloat(15.0)
    private let volumeAtomic = AtomicFloat(0.0)

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let bf = baseFreqAtomic
        let sf = ssvepFreqAtomic
        let vol = volumeAtomic
        var leftPhase: Float = 0.0
        var rightPhase: Float = 0.0
        var leftPhaseH2: Float = 0.0
        var rightPhaseH2: Float = 0.0
        var leftPhaseH3: Float = 0.0
        var rightPhaseH3: Float = 0.0
        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let baseFreq = bf.load()
            let ssvepFreq = sf.load()
            let volume = vol.load()
            let sampleRate = Float(renderFormat.sampleRate)

            for frame in 0..<Int(frameCount) {
                // Fundamental
                let leftFund = sin(leftPhase)
                let rightFund = sin(rightPhase)
                // 2nd harmonic (octave) — cello-like body
                let leftH2 = sin(leftPhaseH2) * 0.30
                let rightH2 = sin(rightPhaseH2) * 0.30
                // 3rd harmonic — singing bowl shimmer
                let leftH3 = sin(leftPhaseH3) * 0.12
                let rightH3 = sin(rightPhaseH3) * 0.12

                let leftSample = volume * (leftFund + leftH2 + leftH3) * 0.7
                let rightSample = volume * (rightFund + rightH2 + rightH3) * 0.7

                // Fundamental phase
                leftPhase += 2.0 * Float.pi * baseFreq / sampleRate
                rightPhase += 2.0 * Float.pi * (baseFreq + ssvepFreq) / sampleRate
                // 2nd harmonic phase
                leftPhaseH2 += 2.0 * Float.pi * baseFreq * 2.0 / sampleRate
                rightPhaseH2 += 2.0 * Float.pi * (baseFreq * 2.0 + ssvepFreq) / sampleRate
                // 3rd harmonic phase
                leftPhaseH3 += 2.0 * Float.pi * baseFreq * 3.0 / sampleRate
                rightPhaseH3 += 2.0 * Float.pi * (baseFreq * 3.0 + ssvepFreq) / sampleRate

                if leftPhase > 65536.0 { leftPhase -= 65536.0 }
                if rightPhase > 65536.0 { rightPhase -= 65536.0 }
                if leftPhaseH2 > 65536.0 { leftPhaseH2 -= 65536.0 }
                if rightPhaseH2 > 65536.0 { rightPhaseH2 -= 65536.0 }
                if leftPhaseH3 > 65536.0 { leftPhaseH3 -= 65536.0 }
                if rightPhaseH3 > 65536.0 { rightPhaseH3 -= 65536.0 }

                if buf.count >= 2 {
                    let lPtr = buf[0].mData!.assumingMemoryBound(to: Float.self)
                    let rPtr = buf[1].mData!.assumingMemoryBound(to: Float.self)
                    lPtr[frame] = leftSample
                    rPtr[frame] = rightSample
                } else {
                    let data = buf[0].mData!.assumingMemoryBound(to: Float.self)
                    data[frame] = (leftSample + rightSample) * 0.5
                }
            }
            return noErr
        })
    }

    func setBaseFrequency(_ freq: Float) { baseFreqAtomic.store(freq) }
    func setSSVEPFrequency(_ freq: Float) { ssvepFreqAtomic.store(freq) }
    func setTargetVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}

// MARK: - IsochronicToneNode (pulsed tone at SSVEP frequency)

final class IsochronicToneNode: AVAudioSourceNode {
    private let baseFreqAtomic = AtomicFloat(200.0)
    private let ssvepFreqAtomic = AtomicFloat(15.0)
    private let volumeAtomic = AtomicFloat(0.0)

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let bf = baseFreqAtomic
        let sf = ssvepFreqAtomic
        let vol = volumeAtomic
        var tonePhase: Float = 0.0
        var modPhase: Float = 0.0
        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let baseFreq = bf.load()
            let ssvepFreq = sf.load()
            let volume = vol.load()
            let sampleRate = Float(renderFormat.sampleRate)

            for frame in 0..<Int(frameCount) {
                // Amplitude modulation: gate on/off at SSVEP frequency
                modPhase += 2.0 * Float.pi * ssvepFreq / sampleRate
                if modPhase > 2.0 * Float.pi { modPhase -= 2.0 * Float.pi }

                // Sharp gating: on during positive half-cycle
                let gate: Float = sinf(modPhase) > 0.0 ? 1.0 : 0.0

                tonePhase += 2.0 * Float.pi * baseFreq / sampleRate
                if tonePhase > 65536.0 { tonePhase -= 65536.0 }

                let sample = volume * sinf(tonePhase) * gate * 0.35

                if buf.count >= 2 {
                    let lPtr = buf[0].mData!.assumingMemoryBound(to: Float.self)
                    let rPtr = buf[1].mData!.assumingMemoryBound(to: Float.self)
                    lPtr[frame] = sample
                    rPtr[frame] = sample
                } else {
                    let data = buf[0].mData!.assumingMemoryBound(to: Float.self)
                    data[frame] = sample
                }
            }
            return noErr
        })
    }

    func setBaseFrequency(_ freq: Float) { baseFreqAtomic.store(freq) }
    func setSSVEPFrequency(_ freq: Float) { ssvepFreqAtomic.store(freq) }
    func setTargetVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}

// MARK: - AmbientWindNode (improved with multi-band noise)

final class AmbientWindNode: AVAudioSourceNode {
    private let volumeAtomic = AtomicFloat(0.0)

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let vol = volumeAtomic
        var windNoise = PinkNoiseGenerator()
        var highNoise = WhiteNoiseGenerator()
        let sampleRate: Float = 48000.0
        var currentVolume: Float = 0.0
        // Low-frequency body
        var lfoPhase: Float = 0.0
        let lfoRate: Float = 0.12
        var filterState: Float = 0.0
        // High-frequency whisper layer
        var lfoPhase2: Float = 0.0
        var highFilterL: Float = 0.0
        var highFilterR: Float = 0.0
        // Gust envelope
        var gustPhase: Float = 0.0

        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let targetVol = vol.load()
            currentVolume += (targetVol - currentVolume) * 0.005

            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buf.count >= 2,
                  let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let frames = Int(frameCount)

            for i in 0..<frames {
                let dt: Float = 1.0 / sampleRate

                // Slow gust envelope (0.04Hz = ~25 second cycle)
                gustPhase += 2.0 * .pi * 0.04 / sampleRate
                if gustPhase > 2.0 * .pi { gustPhase -= 2.0 * .pi }
                let gustMod = sinf(gustPhase) * 0.3 + 0.7

                // Low-frequency body — filtered pink noise with slow modulation
                lfoPhase += 2.0 * .pi * lfoRate / sampleRate
                if lfoPhase > 2.0 * .pi { lfoPhase -= 2.0 * .pi }
                let lfoValue = sinf(lfoPhase) * 0.5 + 0.5
                let modulatedCutoff: Float = 600.0 * (1.0 + 0.6 * lfoValue * gustMod)
                let rc = 1.0 / (2.0 * .pi * modulatedCutoff)
                let alpha = rc / (rc + 1.0 / sampleRate)

                let noise = windNoise.nextFloat()
                filterState = filterState + alpha * (noise - filterState)
                let bodyL = filterState * currentVolume * 0.25 * gustMod

                // High-frequency whisper layer
                lfoPhase2 += 2.0 * .pi * 0.07 / sampleRate
                if lfoPhase2 > 2.0 * .pi { lfoPhase2 -= 2.0 * .pi }
                let whisperMod = powf(sinf(lfoPhase2) * 0.5 + 0.5, 3.0)

                let highRaw = highNoise.nextFloat()
                let highAlpha: Float = 4000.0 / (4000.0 + sampleRate * 0.5)
                highFilterL = highFilterL + highAlpha * (highRaw - highFilterL)
                highFilterR = highFilterR + highAlpha * (highRaw * 0.95 + highNoise.nextFloat() * 0.05 - highFilterR)
                let whisperL = highFilterL * whisperMod * currentVolume * 0.06
                let whisperR = highFilterR * whisperMod * currentVolume * 0.06

                // Stereo spread
                let stereoOffset = sinf(lfoPhase * 0.7) * 0.08
                lPtr[i] = bodyL * (1.0 + stereoOffset) + whisperL
                rPtr[i] = bodyL * (1.0 - stereoOffset) + whisperR
            }
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}

// MARK: - AmbientWaterNode

final class AmbientWaterNode: AVAudioSourceNode {
    private let volumeAtomic = AtomicFloat(0.0)

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let vol = volumeAtomic
        var whiteNoise = WhiteNoiseGenerator()
        let sampleRate: Float = 48000.0
        var currentVolume: Float = 0.0
        var dripTimer: Float = 0.0
        var dripPhase: Float = 0.0
        var dripFreq: Float = 0.0
        var dripAmplitude: Float = 0.0
        var dripDecay: Float = 0.0
        var streamFilterL: Float = 0.0
        var streamFilterR: Float = 0.0
        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let targetVol = vol.load()
            currentVolume += (targetVol - currentVolume) * 0.005

            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buf.count >= 2,
                  let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let frames = Int(frameCount)
            let dt: Float = 1.0 / sampleRate

            for i in 0..<frames {
                let rawNoise = whiteNoise.nextFloat()
                let lpAlpha: Float = 1200.0 / (1200.0 + sampleRate * 0.5)

                streamFilterL = streamFilterL + lpAlpha * (rawNoise - streamFilterL)
                streamFilterR = streamFilterR + lpAlpha * (rawNoise * 0.98 + whiteNoise.nextFloat() * 0.02 - streamFilterR)

                let streamL = streamFilterL * currentVolume * 0.15
                let streamR = streamFilterR * currentVolume * 0.15

                dripTimer -= dt
                if dripTimer <= 0.0 {
                    dripFreq = 1800.0 + Float.random(in: -400...400)
                    dripAmplitude = Float.random(in: 0.15...0.35)
                    dripDecay = 0.003 + Float.random(in: 0...0.002)
                    dripPhase = 0.0
                    dripTimer = 0.2 + Float.random(in: 0...0.8)
                }

                dripPhase += 2.0 * .pi * dripFreq * dt
                dripAmplitude *= (1.0 - dripDecay)
                if dripAmplitude < 0.001 { dripAmplitude = 0.0 }

                let drip = sinf(dripPhase) * dripAmplitude * currentVolume
                let pan = Float.random(in: -0.6...0.6)

                lPtr[i] = streamL + drip * (0.5 - pan * 0.5)
                rPtr[i] = streamR + drip * (0.5 + pan * 0.5)
            }
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}

// MARK: - AmbientForestNode

final class AmbientForestNode: AVAudioSourceNode {
    private let volumeAtomic = AtomicFloat(0.0)

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let vol = volumeAtomic
        var pinkNoise = PinkNoiseGenerator()
        let sampleRate: Float = 48000.0
        var currentVolume: Float = 0.0
        var birdTimer: Float = 2.0
        var birdPhase: Float = 0.0
        var birdFreq: Float = 0.0
        var birdAmplitude: Float = 0.0
        var birdDuration: Float = 0.0
        var birdElapsed: Float = 0.0
        var birdActive: Bool = false
        var rustleFilter: Float = 0.0
        var rustleLFOPhase: Float = 0.0
        // Cricket layer (constant background chirping)
        var cricketPhase: Float = 0.0
        var cricketTimer: Float = 1.0
        var cricketBurstPhase: Float = 0.0
        var cricketActive: Bool = false
        var cricketBurstCount: Int = 0

        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let targetVol = vol.load()
            currentVolume += (targetVol - currentVolume) * 0.005

            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buf.count >= 2,
                  let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let frames = Int(frameCount)
            let dt: Float = 1.0 / sampleRate

            for i in 0..<frames {
                // Rustling leaves
                rustleLFOPhase += 2.0 * .pi * 0.3 / sampleRate
                if rustleLFOPhase > 2.0 * .pi { rustleLFOPhase -= 2.0 * .pi }

                let rustleMod = powf(sinf(rustleLFOPhase) * 0.5 + 0.5, 2.0)
                let rustleNoise = pinkNoise.nextFloat()

                let rustleAlpha: Float = 2000.0 / (2000.0 + sampleRate * 0.5)
                rustleFilter = rustleFilter + rustleAlpha * (rustleNoise - rustleFilter)
                let rustle = rustleFilter * rustleMod * currentVolume * 0.08

                // Bird calls
                var birdSample: Float = 0.0

                if !birdActive {
                    birdTimer -= dt
                    if birdTimer <= 0.0 {
                        birdActive = true
                        birdFreq = 2200.0 + Float.random(in: -600...800)
                        birdDuration = 0.15 + Float.random(in: 0...0.4)
                        birdElapsed = 0.0
                        birdAmplitude = 0.2 + Float.random(in: 0...0.15)
                        birdPhase = 0.0
                        birdTimer = 3.0 + Float.random(in: 0...8.0)
                    }
                }

                if birdActive {
                    birdElapsed += dt
                    let progress = birdElapsed / birdDuration
                    let freqMod = 1.0 + 0.3 * sinf(2.0 * .pi * 8.0 * progress)
                    birdPhase += 2.0 * .pi * birdFreq * freqMod * dt

                    let env: Float
                    if progress < 0.1 {
                        env = progress / 0.1
                    } else {
                        env = 1.0 - (progress - 0.1) / 0.9
                    }
                    let clampedEnv = max(env, 0.0)
                    birdSample = sinf(birdPhase) * birdAmplitude * clampedEnv * currentVolume

                    if birdElapsed >= birdDuration {
                        birdActive = false
                    }
                }

                // Cricket chirping (high-frequency bursts)
                var cricketSample: Float = 0.0
                cricketTimer -= dt
                if cricketTimer <= 0.0 && !cricketActive {
                    cricketActive = true
                    cricketBurstCount = Int.random(in: 3...6)
                    cricketBurstPhase = 0.0
                    cricketTimer = 2.0 + Float.random(in: 0...4.0)
                }

                if cricketActive {
                    cricketBurstPhase += 2.0 * .pi * 4200.0 * dt  // cricket frequency ~4200Hz
                    cricketPhase += 2.0 * .pi * 30.0 * dt          // 30Hz on/off rate within burst
                    if cricketPhase > 2.0 * .pi { cricketPhase -= 2.0 * .pi }

                    let chirpGate: Float = sinf(cricketPhase) > 0.0 ? 1.0 : 0.0
                    cricketSample = sinf(cricketBurstPhase) * chirpGate * 0.04 * currentVolume

                    cricketBurstCount -= 1
                    if cricketBurstCount <= 0 {
                        cricketActive = false
                        cricketPhase = 0.0
                    }
                }

                let birdPan = Float.random(in: -0.4...0.4)
                lPtr[i] = rustle * 0.7 + birdSample * (0.5 - birdPan * 0.5) + cricketSample * 0.7
                rPtr[i] = rustle * 1.0 + birdSample * (0.5 + birdPan * 0.5) + cricketSample * 0.3
            }
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}

// MARK: - AmbientRainNode (storm / heavy rain)

final class AmbientRainNode: AVAudioSourceNode {
    private let volumeAtomic = AtomicFloat(0.0)

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let vol = volumeAtomic
        var whiteNoise = WhiteNoiseGenerator()
        let sampleRate: Float = 48000.0
        var currentVolume: Float = 0.0
        var rainFilterL: Float = 0.0
        var rainFilterR: Float = 0.0
        var intensityLFO: Float = 0.0
        // Individual drops
        var dripTimer: Float = 0.0
        var dripPhase: Float = 0.0
        var dripFreq: Float = 0.0
        var dripAmplitude: Float = 0.0
        var dripDecay: Float = 0.0

        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let targetVol = vol.load()
            currentVolume += (targetVol - currentVolume) * 0.005

            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buf.count >= 2,
                  let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let frames = Int(frameCount)
            let dt: Float = 1.0 / sampleRate

            for i in 0..<frames {
                // Slow intensity variation
                intensityLFO += 2.0 * .pi * 0.08 / sampleRate
                if intensityLFO > 2.0 * .pi { intensityLFO -= 2.0 * .pi }
                let intensityMod = sinf(intensityLFO) * 0.3 + 0.7

                let rawNoise = whiteNoise.nextFloat()
                // Band-pass-ish filter for rain (centered ~4000Hz)
                let lpAlpha: Float = 5000.0 / (5000.0 + sampleRate * 0.5)

                rainFilterL = rainFilterL + lpAlpha * (rawNoise - rainFilterL)
                rainFilterR = rainFilterR + lpAlpha * (rawNoise * 0.97 + whiteNoise.nextFloat() * 0.03 - rainFilterR)

                let rainL = rainFilterL * currentVolume * 0.22 * intensityMod
                let rainR = rainFilterR * currentVolume * 0.22 * intensityMod

                // Individual heavy drops
                dripTimer -= dt
                if dripTimer <= 0.0 {
                    dripFreq = 2500.0 + Float.random(in: -800...1500)
                    dripAmplitude = Float.random(in: 0.12...0.30)
                    dripDecay = 0.006 + Float.random(in: 0...0.004)
                    dripPhase = 0.0
                    dripTimer = 0.01 + Float.random(in: 0...0.04)
                }

                dripPhase += 2.0 * .pi * dripFreq * dt
                dripAmplitude *= (1.0 - dripDecay)
                if dripAmplitude < 0.001 { dripAmplitude = 0.0 }

                let drip = sinf(dripPhase) * dripAmplitude * currentVolume
                let pan = Float.random(in: -0.8...0.8)

                lPtr[i] = rainL + drip * (0.5 - pan * 0.5)
                rPtr[i] = rainR + drip * (0.5 + pan * 0.5)
            }
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}

// MARK: - WindChimeNode (pentatonic chime simulation)

final class WindChimeNode: AVAudioSourceNode {
    private let volumeAtomic = AtomicFloat(0.0)

    // C-major pentatonic across two octaves
    private static let pentatonicFreqs: [Float] = [
        523.25, 587.33, 659.25, 783.99, 880.00,
        1046.50, 1174.66, 1318.51
    ]

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let vol = volumeAtomic
        let sampleRate: Float = 48000.0
        var currentVolume: Float = 0.0
        var chimeTimer: Float = 2.0
        // 4 simultaneous chime voices
        var chimePhases: [Float] = Array(repeating: 0.0, count: 4)
        var chimeFreqs: [Float] = Array(repeating: 0.0, count: 4)
        var chimeAmps: [Float] = Array(repeating: 0.0, count: 4)
        var chimeDecays: [Float] = Array(repeating: 0.0, count: 4)
        var chimePans: [Float] = Array(repeating: 0.0, count: 4)
        let pentatonic = WindChimeNode.pentatonicFreqs

        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let targetVol = vol.load()
            currentVolume += (targetVol - currentVolume) * 0.005

            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buf.count >= 2,
                  let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let frames = Int(frameCount)
            let dt: Float = 1.0 / sampleRate

            for i in 0..<frames {
                chimeTimer -= dt

                // Trigger a new chime when timer expires (only if audible)
                if chimeTimer <= 0.0 && currentVolume > 0.01 {
                    for v in 0..<4 {
                        if chimeAmps[v] < 0.001 {
                            let freqIdx = Int.random(in: 0..<pentatonic.count)
                            chimeFreqs[v] = pentatonic[freqIdx] * Float.random(in: 0.98...1.02)
                            chimeAmps[v] = Float.random(in: 0.25...0.55)
                            chimeDecays[v] = 0.4 + Float.random(in: 0...0.6)
                            chimePans[v] = Float.random(in: -0.8...0.8)
                            chimePhases[v] = 0.0
                            break
                        }
                    }
                    chimeTimer = 1.5 + Float.random(in: 0...4.0)
                }

                var sampleL: Float = 0.0
                var sampleR: Float = 0.0

                for v in 0..<4 {
                    guard chimeAmps[v] > 0.001 else { continue }

                    chimePhases[v] += 2.0 * .pi * chimeFreqs[v] * dt
                    if chimePhases[v] > 65536.0 { chimePhases[v] -= 65536.0 }

                    // Bell-like timbre: fundamental + inharmonic partials
                    let fund = sinf(chimePhases[v])
                    let h2 = sinf(chimePhases[v] * 2.756) * 0.4   // inharmonic for bell character
                    let h3 = sinf(chimePhases[v] * 5.404) * 0.15  // higher inharmonic

                    chimeAmps[v] *= (1.0 - chimeDecays[v] * dt)

                    let sample = (fund + h2 + h3) * chimeAmps[v] * currentVolume * 0.22
                    sampleL += sample * (0.5 - chimePans[v] * 0.5)
                    sampleR += sample * (0.5 + chimePans[v] * 0.5)
                }

                lPtr[i] = sampleL
                rPtr[i] = sampleR
            }
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}

// MARK: - AmbientCosmicNode (FM Synthesis, Level 3/6)

final class AmbientCosmicNode: AVAudioSourceNode {
    private let volumeAtomic = AtomicFloat(0.0)

    init(renderFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) {
        let vol = volumeAtomic
        let sampleRate: Float = 48000.0
        var currentVolume: Float = 0.0
        var carrierPhase: Float = 0.0
        var modulatorPhase: Float = 0.0
        var lfoPhase: Float = 0.0
        let carrierFreq: Float = 80.0
        let modulatorFreq: Float = 0.3
        let modIndex: Float = 150.0
        var noiseGen = PinkNoiseGenerator()
        var noiseFilter: Float = 0.0
        super.init(format: renderFormat, renderBlock: { _, _, frameCount, audioBufferList in
            let targetVol = vol.load()
            currentVolume += (targetVol - currentVolume) * 0.003

            let buf = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buf.count >= 2,
                  let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let frames = Int(frameCount)
            let dt: Float = 1.0 / sampleRate

            for i in 0..<frames {
                lfoPhase += 2.0 * .pi * 0.05 / sampleRate
                if lfoPhase > 2.0 * .pi { lfoPhase -= 2.0 * .pi }
                let lfoMod = sinf(lfoPhase) * 0.5 + 0.5

                modulatorPhase += 2.0 * .pi * modulatorFreq * dt
                if modulatorPhase > 2.0 * .pi { modulatorPhase -= 2.0 * .pi }

                let modSignal = sinf(modulatorPhase) * modIndex * (0.5 + lfoMod * 0.5)
                carrierPhase += 2.0 * .pi * (carrierFreq + modSignal) * dt
                if carrierPhase > 65536.0 { carrierPhase -= 65536.0 }

                let fmTone = sinf(carrierPhase) * 0.15

                let noise = noiseGen.nextFloat()
                let noiseAlpha: Float = 150.0 / (150.0 + sampleRate * 0.5)
                noiseFilter = noiseFilter + noiseAlpha * (noise - noiseFilter)
                let noiseLayer = noiseFilter * 0.08

                let sample = (fmTone + noiseLayer) * currentVolume

                let stereoPhase = carrierPhase * 0.001
                lPtr[i] = sample * (1.0 + sinf(stereoPhase) * 0.3)
                rPtr[i] = sample * (1.0 - sinf(stereoPhase) * 0.3)
            }
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }
}
