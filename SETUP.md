# Setup Instructions

## Prerequisites

- **Xcode 15+** (iOS 15+ support, SwiftUI)
- **Physical iPhone 12 or newer** (simulator won't work; CoreAudio I/O is restricted)
- **Wired headphones** (Lightning adapter or USB-C, depending on your phone)
  - AirPods/Bluetooth won't work (latency is ~200ms, useless for ANC)

## Step 1: Create the Xcode Project

1. **Open Xcode** → File → New → Project
2. **Choose iOS App template**
3. **Fill in project details**:
   - Product Name: `HeadphoneANC`
   - Team: (select your team or "None")
   - Organization ID: `com.headphoneANC`
   - Interface: SwiftUI
   - Language: Swift
4. **Create the project**

## Step 2: Replace Files

1. **Delete the default files**:
   - `ContentView.swift`
   - `HeadphoneANCApp.swift` (if it exists)
   - `Preview Content` folder

2. **Add the new files**:
   - Copy `HeadphoneANCApp.swift` → drag into Xcode
   - Copy `ContentView.swift` → drag into Xcode
   - Copy `AudioEngine.swift` → drag into Xcode
   - Check "Copy items if needed" and "Add to targets"

3. **Replace Info.plist**:
   - In Xcode, select the project → Info tab
   - Or: Delete the default `Info.plist` and drag in the provided one
   - Key requirements:
     - `NSMicrophoneUsageDescription` = "We need microphone access to capture ambient noise for active noise cancellation."
     - `UIBackgroundModes` = `[audio]`
     - `MinimumOSVersion` = 15.0

## Step 3: Configure Project Settings

1. **Select the project** in the Navigator
2. **Select the target** → General tab
3. **Deployment Info**:
   - Minimum Deployment: iOS 15.0 or higher
   - Supported Orientations: Portrait (Portrait Upside Down optional)

4. **Signing & Capabilities** tab:
   - Select your Team
   - Make sure provisioning profile is set

## Step 4: Build & Run

1. **Select your physical iPhone** as the run destination (not simulator)
2. **Build**: ⌘B (Cmd+B)
   - Fix any compilation errors (usually missing imports or typos)
3. **Run**: ⌘R (Cmd+R)
4. **Allow microphone permission** when prompted

## Step 5: Test

1. **Wear wired headphones**
2. **Toggle ANC On** in the app
3. **Watch the latency display** — note the round-trip latency and max cancellable frequency
4. **Test with a tone generator**:
   - Open Apple's Tone Generator app or go to https://www.szynalski.com/tone-generator/
   - Generate a 60 Hz tone
   - Toggle ANC on/off and listen for cancellation effect
5. **Test with speech** (should hear no effect since voices are >100 Hz)

## Troubleshooting

### Build Errors

**"AudioUnit not found"**
- Make sure you're importing the correct framework. Check line 1 of `AudioEngine.swift`:
  ```swift
  import AVFoundation
  import Accelerate
  ```

**"Cannot find 'renderCallback' in scope"**
- This is a global C function required for AudioUnit callbacks. Ensure the entire `AudioEngine.swift` file is present.

### Runtime Errors

**"Audio session error"** or **"Failed to create AudioUnit"**
- This usually means the device doesn't support the audio configuration
- Try a different iPhone model or check if audio is muted

**No sound from headphones**
- Ensure headphones are plugged in and working (test with Music app)
- Toggle ANC off and back on
- Restart the app

**Can't hear any cancellation effect**
- This is **normal and expected** for most noise
- Only frequencies below ~100 Hz will show effect
- Try a 60 Hz test tone generator
- If using Bluetooth, switch to wired headphones

### Microphone Permission

If you see "Microphone permission denied":
1. Go to iPhone Settings → HeadphoneANC → Microphone
2. Toggle it on

## Performance Notes

- **CPU usage**: Low. The render callback does 1–2 operations per sample (read, negate, write).
- **Battery**: Minimal impact (audio processing runs at thread priority on DSP, not main CPU).
- **Memory**: ~1 MB for buffers and AudioUnit state.

## Next Steps

Once it builds and runs:

1. **Measure real-world latency** on your device (displayed in the app)
2. **Test with airplane noise recordings** (YouTube has good ones)
3. **Adjust the gain slider** to find the sweet spot
4. **Consider the physics**: If your latency is >10 ms, expect limited effect above 50 Hz

Enjoy experimenting with low-frequency noise!
