import AVFoundation
import Accelerate

// Global reference to the current AudioEngine instance for the render callback
private var sharedAudioEngine: AudioEngine?

// C-style render callback that can be passed to AudioUnit
private let renderCallback: AURenderCallback = { (
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus in

    guard let engine = sharedAudioEngine else { return noErr }
    return engine.handleAudioRender(ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData)
}

class AudioEngine {
    private var audioUnit: AudioUnit?
    private var isRunning = false

    // ANC parameters
    var isEnabled = false
    var gain: Float = 1.0  // amplitude scaling for inverted signal

    // Latency tracking
    private(set) var roundTripLatencyMs: Double = 0.0

    init() {
        sharedAudioEngine = self
        configureAudioSession()
        setupAudioUnit()
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
            // This is the minimum iOS typically honors
            try session.setPreferredIOBufferDuration(64.0 / 48000.0)

            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Measure actual round-trip latency
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

    private func setupAudioUnit() {
        var audioComponentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let audioComponent = AudioComponentFindNext(nil, &audioComponentDesc) else {
            print("Failed to find RemoteIO AudioUnit")
            return
        }

        var tempAudioUnit: AudioUnit?
        let status = AudioComponentInstanceNew(audioComponent, &tempAudioUnit)
        guard status == noErr, let au = tempAudioUnit else {
            print("Failed to create AudioUnit: \(status)")
            return
        }

        self.audioUnit = au

        // Enable input on bus 1 (microphone)
        var enableInput: UInt32 = 1
        AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )

        // Set up audio format: 48 kHz, mono
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        // Apply to both input and output
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,  // input bus
            &audioFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,  // output bus
            &audioFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        // Install render callback on output bus
        var renderCallbackStruct = AURenderCallbackStruct(
            inputProc: renderCallback,
            inputProcRefCon: UnsafeMutableRawPointer(bitPattern: 1)
        )
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Global,
            0,
            &renderCallbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        // Initialize the audio unit
        let initStatus = AudioUnitInitialize(au)
        if initStatus != noErr {
            print("Failed to initialize AudioUnit: \(initStatus)")
        }
    }

    // The actual real-time audio processing callback
    fileprivate func handleAudioRender(
        _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
        _ inBusNumber: UInt32,
        _ inNumberFrames: UInt32,
        _ ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {

        guard let ioData = ioData, isEnabled, let au = audioUnit else { return noErr }

        // Pull audio data from the microphone input (bus 1)
        var inputBuffer = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        )

        var inputStatus = AudioUnitRender(
            au,
            ioActionFlags,
            inTimeStamp,
            1,  // input bus
            inNumberFrames,
            &inputBuffer
        )

        guard inputStatus == noErr, let inputData = inputBuffer.mBuffers.mData else {
            return inputStatus
        }

        // Get the output buffer
        let outputBuffer = UnsafeMutableAudioBufferListPointer(ioData)[0]
        guard let outputData = outputBuffer.mData else { return noErr }

        // Cast to float pointers for DSP
        let input = inputData.assumingMemoryBound(to: Float.self)
        let output = outputData.assumingMemoryBound(to: Float.self)

        // Phase inversion: multiply each sample by -gain
        // This creates the anti-noise signal that cancels incoming noise
        let frames = Int(inNumberFrames)
        vDSP_vsmul(input, 1, [-gain], output, 1, vDSP_Length(frames))

        return noErr
    }

    func start() {
        guard let au = audioUnit else { return }

        let status = AudioOutputUnitStart(au)
        if status == noErr {
            isRunning = true
            print("Audio engine started")
        } else {
            print("Failed to start audio engine: \(status)")
        }
    }

    func stop() {
        guard let au = audioUnit else { return }

        let status = AudioOutputUnitStop(au)
        if status == noErr {
            isRunning = false
            print("Audio engine stopped")
        } else {
            print("Failed to stop audio engine: \(status)")
        }
    }

    deinit {
        stop()
        if let au = audioUnit {
            AudioUnitUninitialize(au)
        }
        sharedAudioEngine = nil
    }
}
