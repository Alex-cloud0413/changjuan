import Foundation

enum CaptureConstants {
    static let sessionsDirectoryName = "CaptureSessions"
    static let manifestFileName = "manifest.json"
    static let latestStatusFileName = "latest-status.json"
    static let outputsDirectoryName = "Outputs"
    static let savedToPhotosMarkerName = ".saved-to-photos"
    static let framePrefix = "frame-"
    static let frameExtension = "jpg"
    static let safetyIdleStopSeconds: TimeInterval = 30
    static let minimumFramesBeforeAutoStop = 4
    static let systemControlTailTrimFrames = 8
    static let minimumRetainedFrames = 4
    static let frameInterval: TimeInterval = 0.25
    static let captureLeadInSeconds: TimeInterval = 1.6
    static let movementDifferenceThreshold = 3.2

    static var appGroupIdentifier: String {
        guard let identifier = Bundle.main.object(
            forInfoDictionaryKey: "LongShotAppGroupIdentifier"
        ) as? String,
        !identifier.isEmpty,
        !identifier.contains("$(") else {
            return "group.com.gaoyiming.longshot.private"
        }
        return identifier
    }

}

enum CaptureSessionState: String, Codable {
    case capturing
    case complete
    case failed
}

struct CaptureManifest: Codable, Equatable {
    let id: String
    let startedAt: Date
    var completedAt: Date?
    var frameCount: Int
    var state: CaptureSessionState
    var autoStopped: Bool
    var failureMessage: String?
    var acceptedFrameCount: Int? = nil
    var skippedFrameCount: Int? = nil
    var outputCount: Int? = nil
    var savedToPhotos: Bool? = nil
    var topCropRatio: Double? = nil
    var processingSeconds: Double? = nil
    var samplingSeconds: Double? = nil
    var selectionSeconds: Double? = nil
    var assemblySeconds: Double? = nil
    var renderingSeconds: Double? = nil
    // Raw-frame indices at which an explicitly resumed page begins. Optional
    // keeps every previously recorded manifest readable.
    var segmentStarts: [Int]? = nil
}
