import Foundation

/// Smooth synchronization policy for a muted video decoder following an independent
/// authoritative audio clock. Recoverable drift is absorbed via a steady, imperceptible
/// muted playback rate adjustment instead of destructive exact-zero seeks or rapid
/// per-tick rate changes that stall hardware H.264/HEVC pipelines.
public enum VideoClockSync {
    /// Inside ±18 ms (~half a 30 fps frame), release an active rate adjustment back to 1.0x.
    public static let deadbandSeconds = 0.018
    /// Ignore normal steady-state frame jitter up to ±45 ms when already locked at 1.0x
    /// so healthy 60 fps playback never disturbs AVPlayer.rate.
    public static let engageDriftSeconds = 0.045
    /// Drift up to 750 ms is smoothly absorbed by muted playback rate (0.90x / 1.12x)
    /// without seeking, flushing the display layer, or discarding decoded frames.
    public static let maxRateSyncDriftSeconds = 0.750
    /// Steady gentle catch-up / slow-down rates so each correction makes at most two
    /// clean AVPlayer rate transitions (1.0x -> slew -> 1.0x).
    public static let minRate: Float = 0.90
    public static let maxRate: Float = 1.12
    /// Ignore tiny rate deltas so steady playback does not churn AVPlayer.rate.
    public static let rateHysteresis: Float = 0.015

    public enum Action: Equatable, Sendable {
        /// Keep playing smoothly; update muted playback rate when outside hysteresis.
        case adjustRate(Float)
        /// Drift exceeds smooth rate-sync bounds, or the decoder is stopped/forced.
        case seek(Double)
    }

    public enum PostSeekStart: Equatable, Sendable {
        /// Begin immediately from the already-decoded seek target at `rate` (no second seek).
        case playImmediately(rate: Float)
        /// Video landed ahead of audio; hold on the decoded frame until `delaySeconds` later.
        case scheduleAtFutureHost(delaySeconds: Double)
        /// Audio moved beyond recoverable rate-sync while the seek ran; resync to `Double`.
        case resyncToAudio(Double)
    }

    /// Desired muted video rate for `drift = audioPosition - videoPosition`.
    /// Positive drift means video is behind audio (speed up); negative means ahead (slow down).
    public static func targetRate(forDrift drift: Double) -> Float {
        guard drift.isFinite else { return 1.0 }
        if abs(drift) <= deadbandSeconds { return 1.0 }
        return drift > 0 ? maxRate : minRate
    }

    public static func shouldApplyRate(_ desired: Float, current: Float) -> Bool {
        guard desired.isFinite, desired > 0, current.isFinite else { return false }
        if current <= 0 { return true }
        if desired == 1.0 && current != 1.0 { return true }
        return abs(desired - current) >= rateHysteresis
    }

    /// Choose smooth rate adjustment or a hard seek for muted video following audio.
    public static func action(videoPosition: Double, audioPosition: Double,
                              currentRate: Float = 1.0,
                              isPlaying: Bool, isStopped: Bool, force: Bool) -> Action? {
        guard audioPosition.isFinite, audioPosition >= 0 else { return nil }
        if force || isStopped { return .seek(audioPosition) }
        guard videoPosition.isFinite, videoPosition >= 0 else { return nil }
        let drift = audioPosition - videoPosition
        if !isPlaying {
            return abs(drift) > 0.080 ? .seek(audioPosition) : nil
        }
        if abs(drift) > maxRateSyncDriftSeconds {
            return .seek(audioPosition)
        }
        if currentRate == 1.0 && abs(drift) <= engageDriftSeconds {
            return .adjustRate(1.0)
        }
        return .adjustRate(targetRate(forDrift: drift))
    }

    /// Choose how to resume muted playback after a seek to `soughtPosition` finishes
    /// while live audio has advanced to `audioPosition`. Avoids issuing a second exact
    /// seek for normal hardware seek latency (up to `maxRateSyncDriftSeconds`).
    public static func postSeekStart(soughtPosition: Double, audioPosition: Double) -> PostSeekStart {
        guard soughtPosition.isFinite, soughtPosition >= 0,
              audioPosition.isFinite, audioPosition >= 0 else {
            return .playImmediately(rate: 1.0)
        }
        let drift = audioPosition - soughtPosition
        if drift < -engageDriftSeconds && drift >= -0.500 {
            return .scheduleAtFutureHost(delaySeconds: -drift)
        }
        if abs(drift) <= engageDriftSeconds {
            return .playImmediately(rate: 1.0)
        }
        if drift > engageDriftSeconds && drift <= maxRateSyncDriftSeconds {
            return .playImmediately(rate: maxRate)
        }
        return .resyncToAudio(audioPosition)
    }
}
