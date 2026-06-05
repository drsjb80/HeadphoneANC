import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngineViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Text("Headphone ANC")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 20)

            // Main toggle
            Toggle("ANC Enabled", isOn: $audioEngine.isEnabled)
                .font(.headline)
                .padding(.horizontal, 20)
                .onChange(of: audioEngine.isEnabled) { _, newValue in
                    if newValue {
                        audioEngine.startANC()
                    } else {
                        audioEngine.stopANC()
                    }
                }

            Divider()
                .padding(.horizontal, 20)

            // Mode selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Noise Profile")
                    .font(.headline)
                    .padding(.horizontal, 20)

                Picker("Profile", selection: $audioEngine.selectedMode) {
                    ForEach(NoiseProfile.allCases, id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .disabled(audioEngine.isEnabled)

                // Mode description
                Text(audioEngine.selectedMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            }

            Divider()
                .padding(.horizontal, 20)

            // Latency info
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Latency")
                    .font(.headline)
                    .padding(.horizontal, 20)

                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Round-trip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f ms", audioEngine.latencyMs))
                            .font(.body)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading) {
                        Text("Max frequency")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "~%.0f Hz", audioEngine.maxCancellableFrequency))
                            .font(.body)
                            .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)

                Text("Lower frequencies cancel better. Voices & traffic are above the cancellable range.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            }

            Divider()
                .padding(.horizontal, 20)

            // Gain slider
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Anti-noise Gain")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.1f", audioEngine.gain))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Slider(value: $audioEngine.gain, in: 0...2.0, step: 0.1)
                    .padding(.horizontal, 20)
                    .disabled(!audioEngine.isEnabled)

                Text("Higher = more aggressive cancellation (may cause flutter/artifacts)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            }

            Spacer()

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(audioEngine.isEnabled ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)

                Text(audioEngine.isEnabled ? "ANC Active" : "ANC Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - ViewModel

class AudioEngineViewModel: NSObject, ObservableObject {
    @Published var isEnabled = false
    @Published var selectedMode: NoiseProfile = .airplane
    @Published var gain: Float = 1.0
    @Published var latencyMs: Double = 0.0

    private var engine: AudioEngine?

    override init() {
        super.init()
        engine = AudioEngine()
        latencyMs = engine?.roundTripLatencyMs ?? 0
    }

    var maxCancellableFrequency: Double {
        // Formula: max_freq ≈ 1 / (2 * latency_in_seconds)
        if latencyMs > 0 {
            return 1.0 / (2.0 * (latencyMs / 1000.0))
        }
        return 0
    }

    func startANC() {
        engine?.isEnabled = true
        engine?.start()
    }

    func stopANC() {
        engine?.isEnabled = false
        engine?.stop()
    }
}

// MARK: - Noise Profiles

enum NoiseProfile: Hashable, CaseIterable {
    case airplane
    case hvac
    case general

    var displayName: String {
        switch self {
        case .airplane:
            return "Airplane"
        case .hvac:
            return "HVAC/Hum"
        case .general:
            return "General Drone"
        }
    }

    var description: String {
        switch self {
        case .airplane:
            return "Optimized for aircraft cabin noise (60–150 Hz). Most effective for low-frequency rumble."
        case .hvac:
            return "Targets building HVAC systems, fans, and hum (50–120 Hz)."
        case .general:
            return "Generic low-frequency drone cancellation (below 100 Hz)."
        }
    }

    // Target frequency range for each profile
    var targetFrequencyRange: (min: Float, max: Float) {
        switch self {
        case .airplane:
            return (60, 150)
        case .hvac:
            return (50, 120)
        case .general:
            return (20, 100)
        }
    }
}

#Preview {
    ContentView()
}
