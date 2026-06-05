# Headphone ANC

An iPhone app that implements software-based Active Noise Cancellation using phase inversion. Captures background noise via the microphone, inverts it, and plays it back through your headphones to cancel ambient noise.

## What It Does

- **Real-time phase inversion**: Reads from the microphone, inverts the waveform (multiply by -1.0), and outputs to headphones
- **Latency-aware**: Displays your device's actual round-trip audio latency and the theoretical maximum cancellable frequency
- **Multiple noise profiles**: Choose between airplane, HVAC, or general drone profiles (affects UI descriptions; actual DSP is the same)
- **Gain control**: Adjust anti-noise amplitude to balance cancellation vs. artifacts

## Why It (Mostly) Doesn't Work for Real-World Noise

ANC requires the anti-noise signal to arrive at your ear **in sync** with the noise it cancels. On iOS:

| Scenario | Latency | Max Cancellable Frequency |
|---|---|---|
| Best case (iPad Pro, wired, measurement mode) | ~5 ms | ~100 Hz |
| Typical iPhone (wired) | 15–25 ms | ~25–50 Hz |
| Bluetooth (AirPods, etc.) | 155–220 ms | Unusable |

**At 5 ms latency, you can only cancel frequencies below ~100 Hz.** Most annoying noise is above that:
- Voices: 100–3000 Hz ✗
- Traffic: 500 Hz–2 kHz ✗
- Office chatter: 200 Hz–4 kHz ✗
- Airplane cabin rumble: 60–150 Hz ✓ (partly)
- HVAC drone: 50–120 Hz ✓

## When It Works

This app can provide **noticeable cancellation for**:
- Airplane cabin low-frequency rumble and vibration
- HVAC hum and constant drone
- Washing machine, subwoofer bleed
- Other sub-100 Hz stationary noise sources

**Use with wired headphones only.** Bluetooth latency (155+ ms) makes ANC impossible.

## How to Build

1. **Create a new Xcode iOS app project** (SwiftUI, iOS 15+)
2. **Copy these files** into the project:
   - `HeadphoneANCApp.swift`
   - `ContentView.swift`
   - `AudioEngine.swift`
3. **Replace the default Info.plist** with the provided `Info.plist`
4. **Request permissions**: Xcode will prompt for microphone permission (info.plist key is included)
5. **Run on a physical device** (simulator audio is restricted)

## Usage

1. **Toggle ANC On**
2. **Select a noise profile** (optional; currently cosmetic)
3. **Wear wired headphones**
4. **Adjust gain** until you hear some cancellation effect
5. **Watch the latency display** to understand why cancellation is limited to low frequencies

## Architecture

```
iPhone Microphone
        ↓ (ADC)
    [AudioUnit Input Bus 1]
        ↓
    [Render Callback]
        ├─ Read mic input
        ├─ Phase invert: output[n] = -gain * input[n]
        ├─ Apply gain scaling
        ↓
    [AudioUnit Output Bus 0]
        ↓ (DAC)
   Headphone Output
```

- **Framework**: CoreAudio RemoteIO AudioUnit (lowest-latency iOS audio path)
- **Session Mode**: `AVAudioSessionModeMeasurement` (disables AGC/noise suppression)
- **Buffer**: 64 frames @ 48 kHz (~1.33 ms)
- **DSP**: Accelerate framework (`vDSP_vsmul` for gain scaling)

## Latency Measurement

The app displays:
- **Round-trip latency**: Sum of input latency + output latency + buffer delay
- **Max cancellable frequency**: ~1 / (2 × latency_in_seconds)

These are measured from `AVAudioSession` properties at startup. Actual latency may vary slightly based on device load.

## Potential Artifacts

- **Flutter/comb filtering**: If gain is too high, you may hear a wavering effect (sign that latency is limiting cancellation)
- **Phase mismatch**: Real-world noise is never purely sinusoidal; the inverted signal won't perfectly align
- **Feedback**: Mic catching speaker output in very quiet environments (use wired headphones with mic shielding)

## Limitations (Fundamental to iOS)

1. **iOS round-trip latency is 100–1000x too high** for true wideband ANC
2. **No error microphone**: Hardware ANC headphones have a second mic to measure residual noise and adapt. This app has no feedback mechanism.
3. **No frequency-dependent filtering**: A real ANC headset uses adaptive filters (LMS/FxLMS) that model the acoustic path. This app does simple gain scaling.
4. **Bluetooth is useless**: AirPods latency (~200 ms) is far too high for any ANC.

## What You're Actually Doing

This is a **low-frequency noise suppression system**, not ANC in the hardware sense. You're creating a crude "comfort noise" or **anti-noise channel** that plays 180° inverted ambient sound. It works for stationary, low-frequency sources (planes, fans, hum) because those components are below the latency ceiling. Everything else is untouched.

## Testing

1. **Use a 60 Hz tone generator** (Apple's Tone Generator app or web-based)
   - You should hear some cancellation when ANC is on
2. **Try speech** (play a podcast or voice memo)
   - You should hear **no effect** (speech is >100 Hz)
3. **Monitor latency** at startup
   - If > 20 ms on your device, expect very limited cancellation even for bass

## References

- [Apple CoreAudio & RemoteIO](https://developer.apple.com/documentation/coreaudio)
- [iOS Audio Latency Measurement](https://superpowered.com/latency)
- [ANC Physics & Latency Requirements](https://dsprelated.com/thread/17752/active-noise-cancellation-anc-in-headphones)
- [Samsung Patent: Latency-Compensated ANC](https://uspto.report/patent/grant/10878796)

## License

Educational/experimental. Use at your own risk.
