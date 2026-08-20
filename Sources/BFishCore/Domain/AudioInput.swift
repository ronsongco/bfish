import Foundation

public enum AudioInput: Equatable, Sendable {
    case file(URL)
    case device(uid: String)
    case system
    case application(bundleIdentifier: String)
}

public struct AudioFrame: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int

    public init(samples: [Float], sampleRate: Double, channelCount: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}
