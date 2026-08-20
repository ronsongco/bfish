public enum DoctorCheckStatus: String, Codable, Sendable {
    case pass
    case warning
    case fail
}

public struct DoctorCheck: Codable, Equatable, Sendable {
    public let name: String
    public let status: DoctorCheckStatus
    public let detail: String

    public init(name: String, status: DoctorCheckStatus, detail: String) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let checks: [DoctorCheck]

    public init(schemaVersion: Int = DoctorReport.currentSchemaVersion, checks: [DoctorCheck]) {
        self.schemaVersion = schemaVersion
        self.checks = checks
    }

    public var hasFailures: Bool {
        checks.contains { $0.status == .fail }
    }
}
