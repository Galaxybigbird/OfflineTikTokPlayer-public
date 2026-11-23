import Foundation

/// Qualification for the unscaled video range; this never edits either track.
public enum NativeVideoCoverage {
    public static func allowsNativePresentation(start: Double, end: Double,
        assetDuration: Double, frameDuration: Double) -> Bool {
        guard start.isFinite, end.isFinite, assetDuration.isFinite,
              start == 0, end > 0, assetDuration >= end else { return false }
        let tail = assetDuration - end
        if tail == 0 { return true }
        guard frameDuration.isFinite, frameDuration > 0 else { return false }
        // AAC/container rounding and mastered-audio priming can leave up to a few
        // audio frames (<= 80 ms) past the last video frame even on 30/60 fps clips.
        // Preserve both tracks; never stretch/trim video or admit a long empty tail.
        let rounding = max(1, max(abs(end), abs(assetDuration))) * Double.ulpOfOne * 8
        return tail <= 0.080 + rounding
    }
}
