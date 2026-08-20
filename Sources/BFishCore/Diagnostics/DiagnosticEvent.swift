import Foundation

public struct StageTiming: Codable, Equatable, Sendable {
    public let stage: String
    public let milliseconds: Double

    public init(stage: String, milliseconds: Double) {
        self.stage = stage
        self.milliseconds = milliseconds
    }
}

public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let event: String
    public let segmentID: UUID?
    public let timings: [StageTiming]
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        event: String,
        segmentID: UUID? = nil,
        timings: [StageTiming] = [],
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.event = event
        self.segmentID = segmentID
        self.timings = timings
        self.metadata = metadata
    }

    public func jsonLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
