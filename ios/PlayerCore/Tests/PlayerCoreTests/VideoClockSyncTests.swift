import XCTest
@testable import PlayerCore

final class VideoClockSyncTests: XCTestCase {
    func testTargetRateKeepsNominalRateInsideDeadbandAndUsesSteadySlewRates() {
        XCTAssertEqual(VideoClockSync.targetRate(forDrift: 0), 1.0)
        XCTAssertEqual(VideoClockSync.targetRate(forDrift: 0.015), 1.0)
        XCTAssertEqual(VideoClockSync.targetRate(forDrift: -0.018), 1.0)
        XCTAssertEqual(VideoClockSync.targetRate(forDrift: .nan), 1.0)

        XCTAssertEqual(VideoClockSync.targetRate(forDrift: 0.100), VideoClockSync.maxRate)
        XCTAssertEqual(VideoClockSync.targetRate(forDrift: 0.700), VideoClockSync.maxRate)
        XCTAssertEqual(VideoClockSync.targetRate(forDrift: -0.100), VideoClockSync.minRate)
        XCTAssertEqual(VideoClockSync.targetRate(forDrift: -0.700), VideoClockSync.minRate)
    }

    func testShouldApplyRateUsesHysteresisAndAlwaysSnapsBackToNominal() {
        XCTAssertFalse(VideoClockSync.shouldApplyRate(1.0, current: 1.0))
        XCTAssertTrue(VideoClockSync.shouldApplyRate(1.0, current: VideoClockSync.maxRate))
        XCTAssertFalse(VideoClockSync.shouldApplyRate(VideoClockSync.maxRate, current: VideoClockSync.maxRate))
        XCTAssertTrue(VideoClockSync.shouldApplyRate(VideoClockSync.maxRate, current: 1.0))
        XCTAssertTrue(VideoClockSync.shouldApplyRate(1.0, current: 0))
    }

    func testPlayingDriftInsideWindowRateMatchesWithTwoStepHysteresis() {
        // Normal ±35 ms jitter while locked at 1.0x keeps nominal 1.0x without rate churn.
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.00, audioPosition: 10.035,
            currentRate: 1.0, isPlaying: true, isStopped: false, force: false), .adjustRate(1.0))

        // While already catching up, 35 ms keeps holding steady catch-up rate down into ±18 ms.
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.00, audioPosition: 10.035,
            currentRate: VideoClockSync.maxRate, isPlaying: true, isStopped: false, force: false),
            .adjustRate(VideoClockSync.maxRate))

        // Once inside ±18 ms, snap cleanly back to 1.0x.
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.00, audioPosition: 10.015,
            currentRate: VideoClockSync.maxRate, isPlaying: true, isStopped: false, force: false),
            .adjustRate(1.0))

        // 220 ms behind audio (e.g., after a real hardware seek) speeds up smoothly, never seeks.
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.00, audioPosition: 10.22,
            isPlaying: true, isStopped: false, force: false), .adjustRate(VideoClockSync.maxRate))

        // 55 ms ahead of audio slows down smoothly, never seeks.
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.055, audioPosition: 10.00,
            isPlaying: true, isStopped: false, force: false), .adjustRate(VideoClockSync.minRate))

        // Exceeding the 750 ms window or a stopped/forced decoder still seeks.
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.0, audioPosition: 10.85,
            isPlaying: true, isStopped: false, force: false), .seek(10.85))
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.0, audioPosition: 10.10,
            isPlaying: true, isStopped: true, force: false), .seek(10.10))
        XCTAssertEqual(VideoClockSync.action(videoPosition: 10.0, audioPosition: 10.05,
            isPlaying: true, isStopped: false, force: true), .seek(10.05))
    }

    func testPausedDriftPreservesSeekPolicy() {
        XCTAssertNil(VideoClockSync.action(videoPosition: 5.0, audioPosition: 5.05,
            isPlaying: false, isStopped: false, force: false))
        XCTAssertEqual(VideoClockSync.action(videoPosition: 5.0, audioPosition: 5.20,
            isPlaying: false, isStopped: false, force: false), .seek(5.20))
    }

    func testPostSeekStartNeverDoubleSeeksForNormalHardwareSeekLatency() {
        // Near-exact landing (within ±45 ms): play immediately at 1.0x without any rate transition.
        XCTAssertEqual(VideoClockSync.postSeekStart(soughtPosition: 4.0, audioPosition: 4.03),
            .playImmediately(rate: 1.0))
        XCTAssertEqual(VideoClockSync.postSeekStart(soughtPosition: 4.03, audioPosition: 4.0),
            .playImmediately(rate: 1.0))

        // Seek took 280 ms on real H.264/HEVC hardware: resume immediately with steady catch-up rate, ZERO second seek.
        XCTAssertEqual(VideoClockSync.postSeekStart(soughtPosition: 4.0, audioPosition: 4.28),
            .playImmediately(rate: VideoClockSync.maxRate))

        // Video landed 120 ms ahead of audio (e.g. AirPods latency): hold until future host time, ZERO second seek.
        if case .scheduleAtFutureHost(let delay) = VideoClockSync.postSeekStart(soughtPosition: 4.12, audioPosition: 4.0) {
            XCTAssertEqual(delay, 0.12, accuracy: 1e-9)
        } else {
            XCTFail("Expected scheduleAtFutureHost for ahead video")
        }

        // Extreme stall (> 750 ms): fall back to synchronized resync.
        XCTAssertEqual(VideoClockSync.postSeekStart(soughtPosition: 4.0, audioPosition: 5.10),
            .resyncToAudio(5.10))
    }
}
