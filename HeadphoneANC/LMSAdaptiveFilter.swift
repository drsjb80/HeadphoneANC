import Accelerate

/// Normalized Least Mean Squares (NLMS) adaptive filter for active noise cancellation.
///
/// The filter maintains an array of coefficients that are continuously updated
/// to estimate the noise signal. By outputting the negative of this estimate,
/// we create anti-noise that destructively interferes with the incoming noise.
/// With a slow learning rate, the filter characterizes steady-state noise (like
/// airplane cabin) over ~30 seconds and adapts to cancellation accordingly.
class LMSAdaptiveFilter {
    private let filterOrder: Int
    private let learningRate: Float
    private let regularization: Float

    // Filter state
    private var coefficients: [Float]
    private var inputBuffer: [Float]
    private var bufferIndex: Int = 0

    init(filterOrder: Int, learningRate: Float, regularization: Float) {
        self.filterOrder = filterOrder
        self.learningRate = learningRate
        self.regularization = regularization

        // Initialize coefficients to zero (filter starts inactive)
        self.coefficients = Array(repeating: 0.0, count: filterOrder)

        // Circular buffer to store recent input samples
        self.inputBuffer = Array(repeating: 0.0, count: filterOrder)
    }

    /// Process one audio sample through the filter.
    /// Returns the estimated anti-noise signal (negative of noise estimate).
    func processSample(_ inputSample: Float) -> Float {
        // Store the input sample in the circular buffer
        inputBuffer[bufferIndex] = inputSample
        bufferIndex = (bufferIndex + 1) % filterOrder

        // Compute filter output: sum(w[i] * x[i]) where w are coefficients,
        // x are recent input samples. This is our estimate of the noise signal.
        var estimate: Float = 0.0
        for i in 0..<filterOrder {
            let bufIdx = (bufferIndex + i) % filterOrder
            estimate += coefficients[i] * inputBuffer[bufIdx]
        }

        // The error signal is the part we couldn't cancel.
        // We want to drive this to zero by adjusting our coefficients.
        let error = inputSample - estimate

        // Update filter coefficients using NLMS rule.
        // This is the "learning" step: we adjust each coefficient based on how
        // much it contributed to the error, with a step size controlled by learning rate.
        //
        // NLMS normalizes by the input signal power to stabilize learning,
        // preventing the filter from oscillating or diverging.
        var inputPower: Float = 0.0
        for i in 0..<filterOrder {
            let bufIdx = (bufferIndex + i) % filterOrder
            let x = inputBuffer[bufIdx]
            inputPower += x * x
        }

        let divisor = inputPower + regularization
        let adaptationGain = learningRate / divisor

        for i in 0..<filterOrder {
            let bufIdx = (bufferIndex + i) % filterOrder
            coefficients[i] += adaptationGain * error * inputBuffer[bufIdx]
        }

        // Return negative of estimate: this is the anti-noise signal
        // that will be played back to cancel the incoming noise
        return -estimate
    }

    /// Reset filter to initial state (for testing or manual reset)
    func reset() {
        coefficients = Array(repeating: 0.0, count: filterOrder)
        inputBuffer = Array(repeating: 0.0, count: filterOrder)
        bufferIndex = 0
    }
}
