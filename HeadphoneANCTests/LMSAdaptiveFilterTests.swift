import XCTest
@testable import HeadphoneANC

class LMSAdaptiveFilterTests: XCTestCase {
    var filter: LMSAdaptiveFilter!

    override func setUp() {
        super.setUp()
        // Create a filter with modest parameters for testing
        filter = LMSAdaptiveFilter(
            filterOrder: 128,
            learningRate: 0.001,
            regularization: 1e-6
        )
    }

    override func tearDown() {
        filter = nil
        super.tearDown()
    }

    /// Test that the filter processes a sample without crashing
    func testProcessSampleBasic() {
        let sample: Float = 0.5
        let output = filter.processSample(sample)

        // Initially (no learning yet), output should be close to zero
        XCTAssertEqual(output, 0.0, accuracy: 0.0001)
    }

    /// Test that filter adapts to a constant input
    func testFilterAdaptationToConstant() {
        let constantInput: Float = 1.0
        var outputs: [Float] = []

        // Feed the same value repeatedly
        for _ in 0..<1000 {
            let output = filter.processSample(constantInput)
            outputs.append(output)
        }

        // After learning, the filter should start producing output
        // (it learns to estimate the constant signal)
        let earlyOutput = abs(outputs[0])
        let lateOutput = abs(outputs[999])

        XCTAssertGreaterThan(lateOutput, earlyOutput,
            "Filter should adapt and produce larger magnitude output over time")
    }

    /// Test that filter processes alternating signal
    func testAlternatingSignal() {
        let altSignal: [Float] = [1.0, -1.0, 1.0, -1.0]
        var outputs: [Float] = []

        // Feed alternating signal multiple times
        for _ in 0..<100 {
            for sample in altSignal {
                let output = filter.processSample(sample)
                outputs.append(output)
            }
        }

        // Check that we have 400 outputs (100 cycles * 4 samples)
        XCTAssertEqual(outputs.count, 400)

        // All outputs should be finite (no NaN or infinity)
        XCTAssertTrue(outputs.allSatisfy { !$0.isNaN && !$0.isInfinite })
    }

    /// Test that filter reset works
    func testReset() {
        // Feed some samples to let filter learn
        for _ in 0..<100 {
            _ = filter.processSample(0.5)
        }

        // Reset the filter
        filter.reset()

        // After reset, processing a sample should give zero output (fresh state)
        let outputAfterReset = filter.processSample(0.5)
        XCTAssertEqual(outputAfterReset, 0.0, accuracy: 0.0001)
    }

    /// Test with white noise (random signal)
    func testNoiseSignal() {
        var outputs: [Float] = []

        // Feed random noise
        for _ in 0..<500 {
            let noise = Float.random(in: -1.0...1.0)
            let output = filter.processSample(noise)
            outputs.append(output)
        }

        // Verify all outputs are valid numbers
        XCTAssertTrue(outputs.allSatisfy { !$0.isNaN && !$0.isInfinite })

        // Outputs should have reasonable magnitude
        let maxOutput = outputs.map(abs).max() ?? 0
        XCTAssertLessThan(maxOutput, 100.0, "Output magnitude should be reasonable")
    }

    /// Test filter stability with extreme values
    func testStabilityWithExtremeValues() {
        let extremeValues: [Float] = [0.0, 1.0, -1.0, 0.1, -0.1]

        for value in extremeValues {
            filter.reset()
            var hasError = false

            // Feed the value 100 times
            for _ in 0..<100 {
                let output = filter.processSample(value)
                if output.isNaN || output.isInfinite {
                    hasError = true
                    break
                }
            }

            XCTAssertFalse(hasError, "Filter should remain stable with value: \(value)")
        }
    }

    /// Test that learning rate affects adaptation speed
    func testLearningRateEffect() {
        let fastFilter = LMSAdaptiveFilter(filterOrder: 128, learningRate: 0.01, regularization: 1e-6)
        let slowFilter = LMSAdaptiveFilter(filterOrder: 128, learningRate: 0.0001, regularization: 1e-6)

        let testSignal: Float = 0.5

        // Get output after 50 iterations for each
        for _ in 0..<50 {
            _ = fastFilter.processSample(testSignal)
            _ = slowFilter.processSample(testSignal)
        }

        let fastOutput = abs(fastFilter.processSample(testSignal))
        let slowOutput = abs(slowFilter.processSample(testSignal))

        // Fast learning rate should have adapted more
        XCTAssertGreaterThan(fastOutput, slowOutput,
            "Higher learning rate should produce larger adaptation")
    }
}
