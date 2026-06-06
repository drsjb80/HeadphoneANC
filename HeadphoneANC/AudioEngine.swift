import AVFoundation
import Accelerate

class AudioEngine {
    private let audioEngine = AVAudioEngine()
    private let musicPlayerNode = AVAudioPlayerNode()
    private let antiNoisePlayerNode = AVAudioPlayerNode()
    private let mixerNode = AVAudioMixerNode()

    // ANC parameters
    var isEnabled = false
    var gain: Float = 1.0

    // Latency tracking
    private(set) var roundTripLatencyMs: Double = 0.0

    // LMS adaptive filter for ANC
    private let lmsFilter: LMSAdaptiveFilter = LMSAdaptiveFilter(
        filterOrder: 256,
        learningRate: 0.00005,
        regularization: 1e-6
    )

    // Buffers for accumulating anti-noise samples to play back
    private var antiNoiseSampleBuffer: [Float] = []
    private let antiNoiseBufferCapacity = 2400  // 0.05 seconds at 48kHz

    private let audioFormat: AVAudioFormat

    init() {
        // Configure audio format: 48 kHz, mono
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) else {
            fatalError("Failed to create audio format")
        }
        self.audioFormat = format

        configureAudioSession()
        setupAudioEngine()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Full-duplex audio: simultaneous mic input + headphone output
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker])

            // Measurement mode: disables AGC, noise suppression, and other processing
            // that adds latency. This is essential for ANC to work.
            try session.setMode(.measurement)

            // 64-frame buffer at 48 kHz = ~1.33ms buffer latency
            try session.setPreferredIOBufferDuration(64.0 / 48000.0)

            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputLatency = session.inputLatency
            let outputLatency = session.outputLatency
            let bufferDuration = session.ioBufferDuration
            roundTripLatencyMs = (inputLatency + outputLatency + 2 * bufferDuration) * 1000

            print("Audio Session Latency:")
            print("  Input: \(inputLatency * 1000)ms")
            print("  Output: \(outputLatency * 1000)ms")
            print("  Buffer: \(bufferDuration * 1000)ms")
            print("  Total round-trip: \(roundTripLatencyMs)ms")

        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func setupAudioEngine() {
        do {
            // Attach nodes to the audio engine
            audioEngine.attach(musicPlayerNode)
            audioEngine.attach(antiNoisePlayerNode)
            audioEngine.attach(mixerNode)

            // Connect nodes: both players -> mixer -> output
            try audioEngine.connect(musicPlayerNode, to: mixerNode, format: audioFormat)
            try audioEngine.connect(antiNoisePlayerNode, to: mixerNode, format: audioFormat)
            try audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: audioFormat)

            // Tap the input node to process microphone audio through the LMS filter
            let inputNode = audioEngine.inputNode
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: audioFormat) { [weak self] buffer, _ in
                self?.processMicrophoneInput(buffer)
            }

            try audioEngine.start()
            print("Audio engine started successfully")

        } catch {
            print("Failed to setup audio engine: \(error)")
        }
    }

    /// Process microphone input through the LMS adaptive filter.
    /// Accumulates anti-noise samples and schedules them for playback.
    private func processMicrophoneInput(_ buffer: AVAudioPCMBuffer) {
        guard isEnabled, let floatData = buffer.floatChannelData?[0] else { return }

        // Process each microphone sample through the LMS filter
        for i in 0..<Int(buffer.frameLength) {
            let antiNoise = lmsFilter.processSample(floatData[i]) * gain
            antiNoiseSampleBuffer.append(antiNoise)

            // When buffer accumulates enough samples, schedule them for playback
            if antiNoiseSampleBuffer.count >= antiNoiseBufferCapacity {
                scheduleAntiNoisePlayback()
            }
        }
    }

    /// Schedule accumulated anti-noise samples to be played back.
    private func scheduleAntiNoisePlayback() {
        guard antiNoiseSampleBuffer.count > 0 else { return }

        // Create an AVAudioPCMBuffer with the anti-noise samples
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: UInt32(antiNoiseSampleBuffer.count)) else {
            antiNoiseSampleBuffer.removeAll()
            return
        }

        pcmBuffer.frameLength = UInt32(antiNoiseSampleBuffer.count)
        let floatData = pcmBuffer.floatChannelData![0]
        for i in 0..<antiNoiseSampleBuffer.count {
            floatData[i] = antiNoiseSampleBuffer[i]
        }

        // Schedule the buffer for playback through the anti-noise player node
        antiNoisePlayerNode.scheduleBuffer(pcmBuffer) { [weak self] in
            // When this buffer finishes, try to schedule the next one
            // (This keeps the player continuously fed with new samples)
        }

        // Start playing if not already playing
        if !antiNoisePlayerNode.isPlaying {
            antiNoisePlayerNode.play()
        }

        antiNoiseSampleBuffer.removeAll()
    }

    func start() {
        do {
            // Ensure the audio engine is running
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            // Start playback nodes
            if !musicPlayerNode.isPlaying {
                musicPlayerNode.play()
            }
            print("Audio engine started")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        musicPlayerNode.stop()
        antiNoisePlayerNode.stop()
        audioEngine.stop()
        print("Audio engine stopped")
    }

    deinit {
        stop()
    }

    /// Load and play music or podcast audio from a file.
    /// Use this to add music playback that will be mixed with the ANC signal.
    func loadAudioFile(_ url: URL) {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            musicPlayerNode.scheduleFile(audioFile, at: nil)
            if !musicPlayerNode.isPlaying {
                musicPlayerNode.play()
            }
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
}
