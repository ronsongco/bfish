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
    public let checks: [DoctorCheck]

    public init(checks: [DoctorCheck]) {
        self.checks = checks
    }

    public var hasFailures: Bool {
        checks.contains { $0.status == .fail }
    }
}
